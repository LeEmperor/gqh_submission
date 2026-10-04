open! Hardcaml

module I : sig
  type 'a t =
    { clock : 'a
    ; reset : 'a
    ; session_clear : 'a
    ; update : 'a Protocol.Types.Update.t
    ; update_valid : 'a
    ; result_ready : 'a
    }
  [@@deriving hardcaml]
end

module O : sig
  type 'a t = { update_ready : 'a; result_valid : 'a; action : 'a [@bits 2] }
  [@@deriving hardcaml]
end

(** One outstanding command. Transfers occur at rising edges with valid and
    ready high. Capture at E0, synchronous history read at E1, exact-once commit
    and result publication at E2, earliest result acceptance at E3. Result and
    action hold through backpressure. Next command can transfer at E4 earliest.

    Active-high synchronous reset aborts processing/results and clears scalar
    and control state; RAM is not reset or initialized. Both handshake outputs
    are suppressed while reset is high. Caller must restart a complete warm-up.

    [session_clear] is legal only while idle with no pending result, takes
    priority over command acceptance, and clears both items' scalar state and
    the result action without touching RAM. It is ignored while busy. Reset
    has priority over clear. Deassert clear before presenting the first update.

    Caller owns item routing, warm-up classification and the shared pointer:
    overwrite positions 0..15 for each item before any steady-state command. *)
(** [borrow_command] defaults false. When enabled, the producer must hold all
    update fields from command acceptance through the commit edge E2 or reset.
    Fields may change once result_valid is asserted, including during stalls.
    [delta_arithmetic] defaults false and selects equivalent signed 17-bit price
    difference arithmetic with an exact 20-bit accumulated sum.
    [difference_relation] defaults false and derives both comparison flags from
    one signed 17-bit price-minus-average difference. *)
(** [records_in_bram] defaults false. When true, the exact 20-bit sum, two
    previous-relation flags and two held-action bits form one 24-bit BSRAM
    record per item. Reads occur in parallel with history at E1; both memories
    commit at E2. Reset/session_clear invalidate both records with two validity
    bits, so stale/poisoned RAM behaves as zero initial state. Neither RAM is
    reset nor initialized. The public schedule is unchanged. *)
val create : ?borrow_command:bool -> ?delta_arithmetic:bool -> ?difference_relation:bool
  -> ?records_in_bram:bool
  -> Scope.t -> Signal.t I.t -> Signal.t O.t
val hierarchical
  :  ?instance:string
  -> ?borrow_command:bool
  -> ?delta_arithmetic:bool
  -> ?difference_relation:bool
  -> ?records_in_bram:bool
  -> Scope.t
  -> Signal.t I.t
  -> Signal.t O.t
