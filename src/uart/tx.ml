open! Core
open! Hardcaml
open! Signal
open! Always

module I = struct
  type 'a t =
    { clock : 'a; reset : 'a; tx_data : 'a [@bits 8]; tx_valid : 'a }
  [@@deriving hardcaml]
end
module O = struct
  type 'a t = { tx : 'a; tx_ready : 'a; tx_busy : 'a } [@@deriving hardcaml]
end
module State = struct
  type t = Idle | Start | Data | Stop | Gap
  [@@deriving sexp_of, compare ~localize, enumerate]
end

let create ?(cycles_per_bit = Config.cycles_per_bit)
  ?(extra_idle_cycles = Config.extra_idle_cycles) _scope (i : _ I.t) =
  if cycles_per_bit < 1 || extra_idle_cycles < 0 then invalid_arg "invalid TX timing";
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let sm = State_machine.create (module State) spec in
  let timer = Variable.reg spec
    ~width:(Int.max 1 (Int.ceil_log2 (Int.max cycles_per_bit extra_idle_cycles))) in
  let data = Variable.reg spec ~width:8 in
  let bit_index = Variable.reg spec ~width:3 in
  let expire = timer.value ==:. 0 in
  let ready = sm.is Idle &: ~:(i.reset) in
  (* On acceptance, load N-1. The output changes to Start at that edge and
     remains there for exactly N cycles, including the first cycle. *)
  compile
    [ sm.switch
        [ Idle,
          [ when_ i.tx_valid
              [ data <-- i.tx_data; timer <--. (cycles_per_bit - 1)
              ; bit_index <--. 0; sm.set_next Start ] ]
        ; Start,
          [ if_ expire [ timer <--. (cycles_per_bit - 1); sm.set_next Data ]
              [ timer <-- timer.value -:. 1 ] ]
        ; Data,
          [ if_ expire
              [ timer <--. (cycles_per_bit - 1)
              (* Shift the captured byte only after a complete data-bit period.
                 The first bit remains in place throughout Start and caller
                 changes cannot affect any accepted byte. *)
              ; data <-- concat_msb [ gnd; select data.value ~high:7 ~low:1 ]
              ; if_ (bit_index.value ==:. 7) [ sm.set_next Stop ]
                  [ bit_index <-- bit_index.value +:. 1 ] ]
              [ timer <-- timer.value -:. 1 ] ]
        ; Stop,
          [ if_ expire
              (if extra_idle_cycles = 0 then [ sm.set_next Idle ] else
                 [ timer <--. (extra_idle_cycles - 1); sm.set_next Gap ])
              [ timer <-- timer.value -:. 1 ] ]
        ; Gap,
          [ if_ expire [ sm.set_next Idle ] [ timer <-- timer.value -:. 1 ] ]
        ]
    ];
  { O.tx = mux2 i.reset vdd
      (mux2 (sm.is Start) gnd (mux2 (sm.is Data) (lsb data.value) vdd))
  ; tx_ready = ready
  ; tx_busy = ~:(sm.is Idle)
  }

let hierarchical ?instance ?cycles_per_bit ?extra_idle_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_uart_tx"
    (create ?cycles_per_bit ?extra_idle_cycles) i
