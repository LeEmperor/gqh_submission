(* PROVISIONAL: replace with tickweave_types when C0 lands *)
open! Core

include Config_contract
type level = { price_ticks : int; quantity_units : int } [@@deriving equal, sexp]
type snapshot =
  { identity : identity; mode : mode; instrument : string
  ; bids : level list; asks : level list; valid : bool; source : string
  } [@@deriving equal, sexp]
type side = Buy | Sell [@@deriving equal, sexp]
type rule =
  { identity : identity; rule_id : string; name : string; predicate : string
  ; parameters : (string * int * string) list; enabled : bool
  ; slot : int; matched : int; admitted : int; blocked : int; last_block_reason : string option
  } [@@deriving equal, sexp]
type candidate =
  { identity : identity; mode : mode; rule_id : string; side : side
  ; price_ticks : int; quantity_units : int
  } [@@deriving equal, sexp]
(* Logical C0 adapter records: no inferred wire widths. Frozen inputs and
   configuration metadata travel with each decision, independently of live state. *)
type admission_bounds =
  { min_qty : int; max_qty : int; min_price_ticks : int; max_price_ticks : int }
  [@@deriving equal, sexp]
type decision_outcome = No_signal_result | Admitted_result | Blocked_result of string
  [@@deriving equal, sexp]
type decision =
  { identity : identity; mode : mode; rule_id : string; inputs : snapshot
  ; maximum_price_ticks : int; quantity_units : int; candidate : candidate option
  ; outcome : decision_outcome; occurred_at : Time_ns.t; receipt_at : Time_ns.t option
  ; build_id : string; slot : int; predicate_result : bool option
  ; bounds : admission_bounds }
  [@@deriving equal, sexp]
(* Persistent bounded ring: sequence keys are storage positions, never selection IDs. *)
type decision_log =
  { records : decision Int.Map.t; first_sequence : int; next_sequence : int }
  [@@deriving equal, sexp]
type event_kind =
  | Rule_matched of string | Candidate_created of candidate
  | Candidate_admitted | Candidate_blocked of string
  | Order_transmitted | Order_received | Connection of bool | Reset
  | Configuration_progress of string | Configuration_failed of string
  | Book_validity of bool | Trace_dropped of int
  [@@deriving equal, sexp]
type system_event =
  { identity : identity; schema_version : string; mode : mode; source : string
  ; event_sequence : int; kind : event_kind
  } [@@deriving equal, sexp]
type application_state =
  { mode : mode; connected : bool; build_id : string; run_id : string
  ; configuration : configuration; engine : engine; market : snapshot
  ; trace_loss : int; updates : int; rate_hz : float; rules : rule list
  ; latest_decision : decision option; decisions : decision_log
  ; manifest : manifest; proposal : proposal; config_apply : apply_progress option
  ; config_events : config_event list
  } [@@deriving equal, sexp]
