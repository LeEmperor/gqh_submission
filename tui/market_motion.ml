open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

type sample = { time : Time_ns.t; bid : int option; ask : int option; delta_updates : int }
(* The last quantity change at a price level. Levels that left the book are not tracked. *)
type delta = { change : int; at : Time_ns.t }
type t =
  { identity : identity option; bid : int option; ask : int option
  ; bid_changed_at : Time_ns.t option; ask_changed_at : Time_ns.t option
  ; samples : sample list; updates : int; started_at : Time_ns.t option
  ; bid_book : int Int.Map.t; ask_book : int Int.Map.t
  ; bid_deltas : delta Int.Map.t; ask_deltas : delta Int.Map.t }
let empty =
  { identity = None; bid = None; ask = None; bid_changed_at = None
  ; ask_changed_at = None; samples = []; updates = 0; started_at = None
  ; bid_book = Int.Map.empty; ask_book = Int.Map.empty
  ; bid_deltas = Int.Map.empty; ask_deltas = Int.Map.empty }
(* The mid of a best bid and ask in ticks, "1003.5". Summed in int64, so a price beyond float
   precision is still exact; display arithmetic, not an inferred wire width. *)
let mid_text ~bid ~ask =
  let module I = Stdlib.Int64 in
  let sum = I.add (I.of_int bid) (I.of_int ask) in
  let whole = I.div sum 2L in
  let fraction = if I.equal (I.rem sum 2L) 0L then ".0" else ".5" in
  let sign = if I.compare sum 0L < 0 && I.equal whole 0L then "-" else "" in
  sign ^ I.to_string whole ^ fraction
let best levels = Option.map (List.hd levels) ~f:(fun (level : level) -> level.price_ticks)

let delta_fade = Time_ns.Span.of_sec 1.
let book levels =
  Int.Map.of_alist_reduce ~f:( + )
    (List.map levels ~f:(fun (level : level) -> level.price_ticks, level.quantity_units))
(* Carry the deltas that are still visible, then add this snapshot's changes. *)
let update_deltas ~now ~previous ~current deltas =
  let fresh = Map.filter deltas ~f:(fun delta -> Time_ns.Span.(Time_ns.diff now delta.at < delta_fade)) in
  Map.fold current ~init:fresh ~f:(fun ~key:price ~data:quantity deltas ->
    let before = Option.value (Map.find previous price) ~default:0 in
    if before = quantity then deltas
    else Map.set deltas ~key:price ~data:{ change = quantity - before; at = now })
(* One side of the book: the last valid quantities by price, and what changed in them. An
   invalid book is no baseline, so recovery shows the real change since the last valid one;
   with no baseline yet (first book, new run) nothing is a change. *)
let track ~now ~valid levels (previous, deltas) =
  if not valid then previous, deltas
  else (
    let current = book levels in
    current, if Map.is_empty previous then deltas else update_deltas ~now ~previous ~current deltas)
let observe t ~now ~(snapshot : snapshot) ~updates =
  let reset = Option.value_map t.identity ~default:false
      ~f:(fun id -> not (String.equal id.run_id snapshot.identity.run_id)) in
  let t = if reset then empty else t in
  let bid = if snapshot.valid then best snapshot.bids else None in
  let ask = if snapshot.valid then best snapshot.asks else None in
  let changed old value previous =
    if Option.is_none t.identity || Option.is_none value then None
    else if Option.equal Int.equal old value then previous else Some now in
  let cutoff = Time_ns.sub now (Time_ns.Span.of_sec 60.) in
  let delta_updates = if Option.is_none t.identity then 0 else Int.max 0 (updates - t.updates) in
  (* Newest first, so one pass keeps the samples still in the window and stops at the cap. *)
  let samples = { time = now; bid; ask; delta_updates } :: t.samples
      |> List.filteri ~f:(fun index sample -> index < 3601 && Time_ns.(sample.time >= cutoff)) in
  let valid = snapshot.valid in
  let bid_book, bid_deltas = track ~now ~valid snapshot.bids (t.bid_book, t.bid_deltas) in
  let ask_book, ask_deltas = track ~now ~valid snapshot.asks (t.ask_book, t.ask_deltas) in
  { identity = Some snapshot.identity; bid; ask
  ; bid_changed_at = changed t.bid bid t.bid_changed_at
  ; ask_changed_at = changed t.ask ask t.ask_changed_at
  ; samples; updates; started_at = Some (Option.value t.started_at ~default:now)
  ; bid_book; ask_book; bid_deltas; ask_deltas }

let flash_intensity ~now changed_at =
  match changed_at with
  | None -> 0.
  | Some time ->
    let age = Time_ns.diff now time |> Time_ns.Span.to_sec in
    if Float.(age < 0. || age >= 0.3) then 0.
    else if Float.(age < 0.1) then 0.25
    else if Float.(age < 0.2) then 0.17 else 0.08

let delta t ~bid price = Map.find (if bid then t.bid_deltas else t.ask_deltas) price

(* 1 at the change, falling in [Fade.steps] steps to 0 after [delta_fade]. *)
let delta_intensity ~now delta =
  (* A clock a hair behind the change is the same instant, not a change from the future. *)
  let age = Time_ns.Span.max Time_ns.Span.zero (Time_ns.diff now delta.at) in
  if Time_ns.Span.(age >= delta_fade) then 0.
  else Fade.level (1. -. (Time_ns.Span.to_sec age /. Time_ns.Span.to_sec delta_fade))

let updates_per_second t ~now =
  let cutoff = Time_ns.sub now (Time_ns.Span.of_sec 1.) in
  let count = List.sum (module Int) t.samples
      ~f:(fun sample -> if Time_ns.(sample.time > cutoff) then sample.delta_updates else 0) in
  let elapsed = Option.value_map t.started_at ~default:0.
      ~f:(fun time -> Float.min 1. (Time_ns.diff now time |> Time_ns.Span.to_sec)) in
  if Float.(elapsed <= 0.) then 0. else Float.of_int count /. elapsed

let component ~state (local_ graph) =
  let motion, inject = Bonsai.state_machine ~default_model:empty
      ~apply_action:(fun _ motion (now, snapshot, updates) -> observe motion ~now ~snapshot ~updates)
      graph in
  let input = let%arr state in state.market, state.updates in
  let get_time = Bonsai.Clock.get_current_time graph in
  let callback =
    let%arr inject and get_time in
    fun (snapshot, updates) ->
      let open Effect.Let_syntax in
      let%bind now = get_time in
      inject (now, snapshot, updates) in
  Bonsai.Edge.on_change ~equal:[%equal: snapshot * int] input ~callback graph;
  motion
