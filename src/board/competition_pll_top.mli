open! Hardcaml
module I = Top.I
module O = Top.O

val reference_hz : int
val multiplier : int
val core_hz : int
val cycles_per_bit : int

(** 81 MHz LED-free BSRAM competition top. Requires Gowin_rPLL_81 external RTL.
    Reset asserts on button press or loss of PLL lock; release takes two core
    edges. The UART has the same physical bit duration as the 27 MHz parent. *)
val create : Scope.t -> Signal.t I.t -> Signal.t O.t
