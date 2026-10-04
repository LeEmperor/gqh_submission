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

let create ?(factored_timer = false) ?(shift_register = false) ?state_encoding
  ?(cycles_per_bit = Config.cycles_per_bit)
  ?(extra_idle_cycles = Config.extra_idle_cycles) _scope (i : _ I.t) =
  if cycles_per_bit < 1 || extra_idle_cycles < 0 then invalid_arg "invalid TX timing";
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let sm = match state_encoding with
    | None -> State_machine.create (module State) spec
    | Some encoding -> State_machine.create ~encoding ~attributes:[] (module State) spec in
  let timer = Variable.reg spec
    ~width:(Int.max 1 (Int.ceil_log2 (Int.max cycles_per_bit extra_idle_cycles))) in
  let timer_set value = if factored_timer then [] else [ timer <-- value] in
  let timer_const n = timer_set (of_int_trunc ~width:(width timer.value) n) in
  let data = Variable.reg spec ~width:8 in
  let bit_index = Variable.reg spec ~width:3 in
  let expire = timer.value ==:. 0 in
  let ready = sm.is Idle &: ~:(i.reset) in
  (* On acceptance, load N-1. The output changes to Start at that edge and
     remains there for exactly N cycles, including the first cycle. *)
  let timer_logic = if not factored_timer then [] else (
    let load = (sm.is Idle &: i.tx_valid) |: (expire &: (sm.is Start |: sm.is Data)) in
    let gap_load = expire &: sm.is Stop in
    let next = mux2 load (of_int_trunc ~width:(width timer.value) (cycles_per_bit - 1))
      (if extra_idle_cycles = 0 then timer.value -:. 1 else
        mux2 gap_load (of_int_trunc ~width:(width timer.value) (extra_idle_cycles - 1))
          (timer.value -:. 1)) in
    [ when_ ((~:(sm.is Idle)) |: i.tx_valid) [ timer <-- next] ]) in
  compile (timer_logic @
    [ sm.switch
        [ Idle,
          [ when_ i.tx_valid
              (timer_const (cycles_per_bit - 1) @ [data <-- i.tx_data; bit_index <--. 0; sm.set_next Start]) ]
        ; Start,
          [ if_ expire (timer_const (cycles_per_bit - 1) @ [sm.set_next Data])
              (timer_set (timer.value -:. 1)) ]
        ; Data,
          [ if_ expire
              ((if shift_register then
                  [data <-- concat_msb [gnd; select data.value ~high:7 ~low:1]] else [])
               @ timer_const (cycles_per_bit - 1) @ [ if_ (bit_index.value ==:. 7) [ sm.set_next Stop ]
                  [ bit_index <-- bit_index.value +:. 1 ] ])
              (timer_set (timer.value -:. 1)) ]
        ; Stop,
          [ if_ expire
              (if extra_idle_cycles = 0 then [ sm.set_next Idle ] else
                 (timer_const (extra_idle_cycles - 1) @ [sm.set_next Gap]))
              (timer_set (timer.value -:. 1)) ]
        ; Gap,
          [ if_ expire [ sm.set_next Idle ] (timer_set (timer.value -:. 1)) ]
        ]
    ]);
  let data_bit = if shift_register then bit data.value ~pos:0
    else mux bit_index.value (bits_lsb data.value) in
  { O.tx = mux2 i.reset vdd
      (mux2 (sm.is Start) gnd (mux2 (sm.is Data) data_bit vdd))
  ; tx_ready = ready
  ; tx_busy = ~:(sm.is Idle)
  }

let hierarchical ?instance ?factored_timer ?shift_register ?state_encoding ?cycles_per_bit ?extra_idle_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_uart_tx"
    (create ?factored_timer ?shift_register ?state_encoding ?cycles_per_bit ?extra_idle_cycles) i
