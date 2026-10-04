module Payload = Types
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; byte_data : 'a [@bits 8]; byte_valid : 'a
    ; framing_error : 'a; update_ready : 'a; result_valid : 'a; action : 'a [@bits 2]
    ; tx_ready : 'a; tx_busy : 'a }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { update : 'a Payload.Update.t; update_valid : 'a; result_ready : 'a
    ; session_clear : 'a; tx_data : 'a [@bits 8]; tx_valid : 'a; protocol_fault : 'a }
  [@@deriving hardcaml]
end
module State = struct
  type t = Idle | Await_clear_idle | Clear | Read_id | Read_high | Read_low
         | Dispatch | Result | Echo_read | Send | Drain
  [@@deriving sexp_of, compare ~localize, enumerate]
end

(* An unreset 8x8 synchronous packet RAM owns all received bytes until the
   final TX stop bit drains. Idle accepts exactly eight bytes; reset aborts the
   partial packet before any read/dispatch, so stale RAM cannot become valid.
   RAM low-price output and high_price remain stable from Dispatch through
   Result. The engine may borrow the complete command through its result.
   Busy/framing faults latch without modifying a packet already in flight. *)
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let sm = State_machine.create (module State) spec in
  let position = Variable.reg spec ~width:3 in
  let position_value = position.value -- "packet_position" in
  let pointer = Variable.reg spec ~width:4 in
  let fault = Variable.reg spec ~width:1 in
  let high_zero = Variable.reg spec ~width:1 in
  let session = Variable.reg spec ~width:1 in
  let warmup = Variable.reg spec ~width:1 in
  let second = Variable.reg spec ~width:1 in
  let item = Variable.reg spec ~width:1 in
  let high_price = Variable.reg spec ~width:8 in
  let action1 = Variable.reg spec ~width:2 in
  let action2 = Variable.reg spec ~width:2 in
  let active = ~:(i.reset) in
  let receiving = (sm.is Idle &: ~:(fault.value)) -- "packet_receiving" in
  let write_enable = receiving &: i.byte_valid &: ~:(i.framing_error) &: active in
  let read_enable =
    (sm.is Read_id |: sm.is Read_high |: sm.is Read_low |: sm.is Echo_read) &: active in
  let echo_address = mux position_value
    [ zero 3; of_int_trunc ~width:3 1; of_int_trunc ~width:3 2; zero 3
    ; of_int_trunc ~width:3 5; zero 3; zero 3; zero 3 ] in
  let read_address = mux2 (sm.is Echo_read) echo_address
    (mux2 (sm.is Read_id)
       (mux2 second.value (of_int_trunc ~width:3 5) (of_int_trunc ~width:3 2))
       (mux2 (sm.is Read_high)
          (mux2 second.value (of_int_trunc ~width:3 6) (of_int_trunc ~width:3 3))
          (mux2 second.value (of_int_trunc ~width:3 7) (of_int_trunc ~width:3 4)))) in
  let data = Ram.create ~name:"request_packet" ~size:8
    ~attributes:[Rtl_attribute.create ~applies_to:[Rtl_attribute.Applies_to.Memories]
      ~value:(Rtl_attribute.Value.String "block_ram") "syn_ramstyle"]
    ~collision_mode:Ram.Collision_mode.Read_before_write
    ~write_ports:[| { Write_port.write_clock = i.clock; write_enable
      ; write_address = position_value; write_data = i.byte_data } |]
    ~read_ports:[| { Read_port.read_clock = i.clock; read_enable; read_address } |] ()
    |> fun q -> q.(0) in
  compile
    [ when_ i.framing_error
        [ fault <--. 1; when_ (sm.is Idle) [ position <--. 0 ] ]
    ; when_ (i.byte_valid &: ~:receiving) [ fault <--. 1 ]
    ; sm.switch
        [ Idle,
          [ when_ write_enable
              [ switch position_value
                  [ of_int_trunc ~width:3 0, [ high_zero <-- (i.byte_data ==:. 0) ]
                  ; of_int_trunc ~width:3 1,
                    [ session <-- (high_zero.value &: (i.byte_data ==:. 0))
                    ; warmup <-- (high_zero.value &: (i.byte_data <:. 16)) ] ]
              ; if_ (position_value ==:. 7)
                  [ second <--. 0; position <--. 0
                  ; if_ session.value
                      [ pointer <--. 0; sm.set_next Await_clear_idle ]
                      [ sm.set_next Read_id ] ]
                  [ position <-- position_value +:. 1 ] ] ]
        ; Await_clear_idle,
          [ when_ (i.update_ready &: ~:(i.result_valid)) [ sm.set_next Clear ] ]
        ; Clear, [ sm.set_next Read_id ]
        ; Read_id, [ sm.set_next Read_high ]
        ; Read_high, [ item <-- (data ==:. Payload.item_b); sm.set_next Read_low ]
        ; Read_low, [ high_price <-- data; sm.set_next Dispatch ]
        ; Dispatch, [ when_ i.update_ready [ sm.set_next Result ] ]
        ; Result,
          [ when_ i.result_valid
              [ if_ second.value
                  [ action2 <-- i.action; pointer <-- pointer.value +:. 1
                  ; sm.set_next Echo_read ]
                  [ action1 <-- i.action; second <--. 1; sm.set_next Read_id ] ] ]
        ; Echo_read, [ sm.set_next Send ]
        ; Send,
          [ when_ i.tx_ready
              [ if_ (position_value ==:. 7) [ sm.set_next Drain ]
                  [ position <-- position_value +:. 1; sm.set_next Echo_read ] ] ]
        ; Drain, [ when_ (~:(i.tx_busy)) [ position <--. 0; sm.set_next Idle ] ]
        ]
    ];
  { O.update =
      { Payload.Update.item_select = item.value
      ; price = concat_msb [ high_price.value; data ]
      ; window_position = pointer.value; warmup = warmup.value }
  ; update_valid = sm.is Dispatch &: active; result_ready = sm.is Result &: active
  ; session_clear = sm.is Clear &: active; protocol_fault = fault.value
  ; tx_valid = sm.is Send &: active
  ; tx_data = mux position_value
      [ data; data; data; uresize action1.value ~width:8
      ; data; uresize action2.value ~width:8; zero 8; zero 8 ] }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_packet_ram_controller" create i
