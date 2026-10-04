open! Hardcaml
module I = Top.I
module O = Top.O

(** Direct 27 MHz production board composition. Timing overrides are for local
    simulation/experiments; production defaults are 234 clocks/bit and zero extra
    gap. [half_period_cycles] is retained for call compatibility and ignored.
    RX synchronization and reset release match the diagnostic board top.
    LED0 is held high; LED1 is decoder sticky fault.
    The controller exclusively owns the engine and rearms only on final drain. *)
val create
  :  ?half_period_cycles:int
  -> ?cycles_per_bit:int
  -> ?extra_idle_cycles:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  :  ?instance:string
  -> ?half_period_cycles:int
  -> ?cycles_per_bit:int
  -> ?extra_idle_cycles:int
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
