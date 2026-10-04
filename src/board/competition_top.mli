open! Hardcaml
module I = Top.I
module O = Top.O

(** Direct 27 MHz production board composition. Timing overrides are for local
    simulation/experiments; production defaults are 234 clocks/bit, zero extra
    gap and a 13,500,000-clock heartbeat half-period. RX synchronization and
    reset release match the diagnostic board top. LED1 is decoder sticky fault.
    [diagnostics] defaults true; false omits the heartbeat and fault indication,
    driving both active-low LEDs high. Protocol fault lockout remains functional.
    The controller exclusively owns the engine and rearms only on final drain.
    Competition defaults borrow decoder request/controller response retention;
    set [borrow_request] or [borrow_response] false for independent measurements.
    All producers retain borrowed fields through final completion or shared reset.
    [packet_ram] defaults false and replaces the three protocol blocks with an
    8x8 synchronous packet RAM controller. The engine command stays stable
    through result transfer. Independent RX/TX timer factoring defaults false.
    [records_in_bram], [borrow_command], [delta_arithmetic] and
    [difference_relation] default false and select the documented engine
    experiments. Both protocol compositions retain engine fields through commit.
    Optional per-block state encoding and TX shift mode select experiments;
    omitted options preserve each module's existing implementation. *)
val create
  :  ?diagnostics:bool
  -> ?packet_ram:bool
  -> ?half_period_cycles:int
  -> ?cycles_per_bit:int
  -> ?extra_idle_cycles:int
  -> ?borrow_request:bool
  -> ?borrow_response:bool
  -> ?controller_encoding:Always.State_machine.Encoding.t
  -> ?sequencer_encoding:Always.State_machine.Encoding.t
  -> ?rx_encoding:Always.State_machine.Encoding.t
  -> ?tx_encoding:Always.State_machine.Encoding.t
  -> ?tx_shift_register:bool
  -> ?rx_factored_timer:bool
  -> ?tx_factored_timer:bool
  -> ?records_in_bram:bool
  -> ?borrow_command:bool
  -> ?delta_arithmetic:bool
  -> ?difference_relation:bool
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  :  ?instance:string
  -> ?diagnostics:bool
  -> ?packet_ram:bool
  -> ?half_period_cycles:int
  -> ?cycles_per_bit:int
  -> ?extra_idle_cycles:int
  -> ?borrow_request:bool
  -> ?borrow_response:bool
  -> ?controller_encoding:Always.State_machine.Encoding.t
  -> ?sequencer_encoding:Always.State_machine.Encoding.t
  -> ?rx_encoding:Always.State_machine.Encoding.t
  -> ?tx_encoding:Always.State_machine.Encoding.t
  -> ?tx_shift_register:bool
  -> ?rx_factored_timer:bool
  -> ?tx_factored_timer:bool
  -> ?records_in_bram:bool
  -> ?borrow_command:bool
  -> ?delta_arithmetic:bool
  -> ?difference_relation:bool
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
