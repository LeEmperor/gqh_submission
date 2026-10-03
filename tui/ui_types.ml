open! Core

(* Phase 5 shared types, frozen by the lead. Read them; do not edit them. *)

type panel_id =
  | Market | Heatmap | Tape | Metrics | Latency
  | Rules | Decisions | Inspector | Configuration
[@@deriving equal, compare, sexp, enumerate]

type preset = Monitor | Decide | Configure | Demo [@@deriving equal, compare, sexp, enumerate]

type scheme = Tickweave_amber | Tokyo_night | Catppuccin_mocha
[@@deriving equal, compare, sexp, enumerate]

(* Cell rectangle within the body area; [col], [row] are 0-based offsets. *)
type rect = { col : int; row : int; width : int; height : int } [@@deriving equal, sexp]

(* Market display toggles held in app state: [h] heatmap, [d] cumulative depth. *)
type market_toggles = { heatmap : bool; cumulative : bool } [@@deriving equal, sexp]

(* Render instrumentation for the F12 overlay and [--bench]. Times in milliseconds. *)
type frame_stats =
  { last_ms : float; avg_ms : float; p50_ms : float; p99_ms : float; max_ms : float
  ; events_per_second : float; render_count : int; coalesced_frames : int
  ; buffer_sizes : (string * int) list }
[@@deriving equal, sexp]
