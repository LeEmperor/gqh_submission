open! Core
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t = { clock : 'a; reset : 'a; rx : 'a } [@@deriving hardcaml]
end
module O = struct
  type 'a t =
    { byte_data : 'a [@bits 8]; byte_valid : 'a; framing_error : 'a }
  [@@deriving hardcaml]
end
module State = struct
  type t = Idle | Start | Data | Stop
  [@@deriving sexp_of, compare ~localize, enumerate]
end

(* Input must already be synchronized. Countdown N-1 expires after N edges.
   The edge detector also prevents a low break from continually restarting RX. *)
let create ?(factored_timer = false) ?state_encoding
  ?(cycles_per_bit = Config.cycles_per_bit) _scope (i : _ I.t) =
  if cycles_per_bit < 4 then invalid_arg "RX cycles_per_bit must be >= 4";
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let previous = reg spec ~clear_to:vdd ~initialize_to:Bits.vdd i.rx in
  let falling = previous &: ~:(i.rx) in
  let sm = match state_encoding with
    | None -> State_machine.create (module State) spec
    | Some encoding -> State_machine.create ~encoding ~attributes:[] (module State) spec in
  let timer = Variable.reg spec ~width:(Int.ceil_log2 cycles_per_bit) in
  let timer_set value = if factored_timer then [] else [ timer <-- value] in
  let timer_const n = timer_set (of_int_trunc ~width:(width timer.value) n) in
  let bit_index = Variable.reg spec ~width:3 in
  let data = Variable.reg spec ~width:8 in
  let valid = Variable.reg spec ~width:1 in
  let error = Variable.reg spec ~width:1 in
  let expire = timer.value ==:. 0 in
  let timer_logic = if not factored_timer then [] else (
    let start_load = sm.is Idle &: falling in
    let reload = expire &: ((sm.is Start &: ~:(i.rx)) |: sm.is Data) in
    [ when_ ((~:(sm.is Idle)) |: falling)
      [ timer <-- mux2 start_load (of_int_trunc ~width:(width timer.value) (cycles_per_bit / 2 - 1))
        (mux2 reload (of_int_trunc ~width:(width timer.value) (cycles_per_bit - 1))
          (timer.value -:. 1))] ]) in
  compile (timer_logic @
    [ valid <--. 0; error <--. 0
    ; sm.switch
        [ Idle, [ when_ falling
                    (timer_const (cycles_per_bit / 2 - 1) @ [ sm.set_next Start ]) ]
        ; Start,
          [ if_ expire
              [ if_ i.rx [ sm.set_next Idle ]
                  (timer_const (cycles_per_bit - 1) @ [bit_index <--. 0; sm.set_next Data]) ]
              (timer_set (timer.value -:. 1)) ]
        ; Data,
          [ if_ expire
              (timer_const (cycles_per_bit - 1) @ [ data <-- concat_msb [ i.rx; select data.value ~high:7 ~low:1 ]
              ; if_ (bit_index.value ==:. 7) [ sm.set_next Stop ]
                  [ bit_index <-- bit_index.value +:. 1 ] ])
              (timer_set (timer.value -:. 1)) ]
        ; Stop,
          [ if_ expire
              [ if_ i.rx [ valid <--. 1 ] [ error <--. 1 ]; sm.set_next Idle ]
              (timer_set (timer.value -:. 1)) ]
        ]
    ]);
  { O.byte_data = data.value; byte_valid = valid.value; framing_error = error.value }

let hierarchical ?instance ?factored_timer ?state_encoding ?cycles_per_bit scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_uart_rx" (create ?factored_timer ?state_encoding ?cycles_per_bit) i
