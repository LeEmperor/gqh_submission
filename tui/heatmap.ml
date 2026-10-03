open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

(* Bookmap-style liquidity heatmap: x is recent snapshots (newest at the right), y is price
   in ticks, cell colour is resting size. Each snapshot appends one column of resting levels
   to a bounded persistent ring. A frame composes only the columns in view, from those
   stored arrays, and never reads the clock, so it costs the same however long the run is. *)

let capacity = 256

(* Columns arrive at most this often, however fast the stream is, because a column scrolls
   the whole map and every cell of it is repainted to the terminal. *)
let column_hz = 5.

type column =
  { snapshot_id : int option; valid : bool
  ; best_bid : int option; best_ask : int option
  ; prices : int array      (* resting levels by price, ascending *)
  ; sizes : int array }     (* units at each of [prices] *)
type marker = Admitted | Blocked [@@deriving equal]
type t =
  { identity : identity option
  ; stride : int  (* snapshots per column *)
  ; columns : column Fdeque.t  (* oldest at the front *)
  ; markers : marker Int.Map.t }  (* column slot -> outcome *)

let empty = { identity = None; stride = 1; columns = Fdeque.empty; markers = Int.Map.empty }
let columns t = Fdeque.to_list t.columns

let column_of (snapshot : snapshot) =
  let book = if snapshot.valid then Market_motion.book (snapshot.bids @ snapshot.asks) else Int.Map.empty in
  let best levels = if snapshot.valid then Market_motion.best levels else None in
  { snapshot_id = snapshot.identity.snapshot_id; valid = snapshot.valid
  ; best_bid = best snapshot.bids; best_ask = best snapshot.asks
  ; prices = Array.of_list (Map.keys book); sizes = Array.of_list (Map.data book) }

(* The snapshot id that stands for a whole column: the first of its [stride] snapshots. *)
let slot t id = Int.round_down id ~to_multiple_of:t.stride

let observe t (snapshot : snapshot) =
  let reset = Option.exists t.identity ~f:(fun id ->
      not (String.equal id.run_id snapshot.identity.run_id)) in
  let t = if reset then { empty with stride = t.stride } else t in
  let columns = Fdeque.enqueue_back t.columns (column_of snapshot) in
  let columns, markers =
    if Fdeque.length columns <= capacity then columns, t.markers
    else (
      (* A marker older than the oldest column can never be drawn again. *)
      let columns = Fdeque.drop_front_exn columns in
      let oldest = Option.bind (Fdeque.peek_front columns) ~f:(fun column -> column.snapshot_id) in
      columns, Option.value_map oldest ~default:t.markers ~f:(fun oldest ->
        Map.filter_keys t.markers ~f:(fun id -> id >= slot t oldest))) in
  { t with identity = Some snapshot.identity; columns; markers }

(* [observe] for a stream of [rate_hz] snapshots a second: keeps the first snapshot of
   each [1 / column_hz] seconds and drops the rest, so the map scrolls at a bounded pace.
   At [column_hz] or slower every snapshot is a column. *)
let observe_sampled t ~rate_hz (snapshot : snapshot) =
  let stride = if Float.is_finite rate_hz && Float.(rate_hz > 0.)
    then Int.max 1 (Float.iround_nearest_exn (rate_hz /. column_hz)) else 1 in
  (* The same ring while nothing joins it: a node that reads the map is recomputed when the map
     is a new value, and the stream asks on every frame. *)
  let t = if t.stride = stride then t else { t with stride } in
  let same_run = Option.exists t.identity ~f:(fun id ->
      String.equal id.run_id snapshot.identity.run_id) in
  let newest = Option.bind (Fdeque.peek_back t.columns) ~f:(fun column -> column.snapshot_id) in
  match newest, snapshot.identity.snapshot_id with
  | Some newest, Some id when same_run && slot t newest = slot t id -> t
  | _ -> observe t snapshot

(* An admitted or blocked decision marks the column its snapshot falls in. No signal draws
   nothing. A later outcome in the same column replaces an earlier one. *)
let note_decision t (decision : decision) =
  let marker = match decision.outcome with
    | Admitted_result -> Some Admitted | Blocked_result _ -> Some Blocked | No_signal_result -> None in
  let same_run = Option.for_all t.identity ~f:(fun id ->
      String.equal id.run_id decision.identity.run_id) in
  match marker, decision.inputs.identity.snapshot_id with
  | Some marker, Some id when same_run ->
    let slot = slot t id in
    (* The same map when the column already shows this outcome: decisions arrive on every
       snapshot, and a node that reads the map is recomputed when it is a new value. *)
    if [%equal: marker option] (Map.find t.markers slot) (Some marker) then t
    else { t with markers = Map.set t.markers ~key:slot ~data:marker }
  | _ -> t

include Market_heat_paint

(* ---- Geometry ---- *)

let blank =
  { snapshot_id = None; valid = false; best_bid = None; best_ask = None
  ; prices = [||]; sizes = [||] }

let mid_price column =
  match column.best_bid, column.best_ask with
  | Some bid, Some ask -> Some (bid + ((ask - bid) / 2))
  | Some price, None | None, Some price -> Some price
  | None, None -> None

(* The last [count] columns, oldest first. Walks the ring once and allocates for the
   columns kept, not for the history. *)
let visible t ~count =
  let length = Fdeque.length t.columns in
  let kept = Int.min length (Int.max 0 count) in
  let out = Array.create ~len:kept blank in
  let index = ref 0 in
  Fdeque.iter t.columns ~f:(fun column ->
    if !index >= length - kept then out.(!index - (length - kept)) <- column;
    incr index);
  out

(* The mid of the newest of [columns] that has one, which centres the window. *)
let newest_mid columns =
  let rec from index =
    if index < 0 then None
    else (match mid_price columns.(index) with Some _ as mid -> mid | None -> from (index - 1)) in
  from (Array.length columns - 1)

(* The window of [rows] prices around the mid, which snaps to a coarse grid so the map holds
   still while the mid wanders a tick or two. Returns the lowest and highest price shown. *)
let fit ~rows ~center =
  let snap = Int.max 2 (rows / 8) in
  let bottom = Int.round_nearest center ~to_multiple_of:snap - ((rows - 1) / 2) in
  bottom, bottom + rows - 1

(* ---- Frame ---- *)

(* The resting sizes in the window, as heat buckets, with the best bid and ask drawn over
   them as unbroken stepped lines and the rule's threshold as a dashed line. *)
let grid columns ~bottom ~top ~maximum ~threshold =
  let rows = top - bottom + 1 in
  let grid = Array.init rows ~f:(fun _ -> Array.create ~len:(Array.length columns) 0) in
  let in_window price = price >= bottom && price <= top in
  let settle = settler ~maximum in
  Array.iteri columns ~f:(fun x column ->
    for level = 0 to Array.length column.prices - 1 do
      let price = column.prices.(level) in
      if in_window price then (
        let row = grid.(top - price) in
        let before = if x = 0 then 0 else bucket_of row.(x - 1) in
        row.(x) <- settle ~before column.sizes.(level))
    done);
  let ink_over x price ink =
    if in_window price then (
      let row = grid.(top - price) in
      row.(x) <- code ink ~bucket:(bucket_of row.(x))) in
  (* A move draws its vertical stroke in the column it happens in, and a gap in the book
     breaks the line. *)
  let draw ~best ~ink =
    ignore (Array.foldi columns ~init:None ~f:(fun x before column ->
      match best column with
      | None -> None
      | Some price ->
        (match before with
         | Some before when before <> price ->
           let up = price > before in
           ink_over x before (ink (if up then Up_left else Down_left));
           for between = Int.max (Int.min before price + 1) bottom to Int.min (Int.max before price - 1) top do
             ink_over x between (ink Vertical)
           done;
           ink_over x price (ink (if up then Down_right else Up_right))
         | _ -> ink_over x price (ink Horizontal));
        Some price) : int option) in
  draw ~best:(fun column -> column.best_bid) ~ink:(fun line -> Bid_line line);
  draw ~best:(fun column -> column.best_ask) ~ink:(fun line -> Ask_line line);
  Option.iter threshold ~f:(fun price ->
    if in_window price then (
      let row = grid.(top - price) in
      Array.iteri row ~f:(fun x cell ->
        if ink_of cell = 0 then row.(x) <- code Threshold ~bucket:(bucket_of cell))));
  grid

(* The sizes in view, counted into [bins] bins, give the colour scale. *)
let scale columns ~bottom ~top =
  let counts = Array.create ~len:bins 0 in
  let total = ref 0 in
  Array.iter columns ~f:(fun column ->
    for level = 0 to Array.length column.prices - 1 do
      let price = column.prices.(level) and size = column.sizes.(level) in
      if price >= bottom && price <= top && size > 0 then (
        let bin = bin_of size in
        counts.(bin) <- counts.(bin) + 1;
        incr total)
    done);
  scale_of counts ~total:!total

(* ---- Chrome ---- *)

(* The scale is never cut. The two price-line keys come next, since the glyphs alone do not
   say which is which; the scale then says how it was found, and the decision keys follow,
   each whole or not at all, as far as there is room. *)
let legend theme painter ~shared ~buffer ~maximum ~width =
  let muted = Theme.attrs theme Muted in
  let cells = Braille_chart.display_width in
  (* A key is its glyph and its label, and takes [cells] of the row. *)
  let key attrs glyph label =
    let label = " " ^ label ^ "  " in
    View.hcat [ View.text ~attrs glyph; View.text ~attrs:muted label ], cells glyph + cells label in
  let swatch = heat_row_views painter ~shared ~buffer ~padding:0
      (Array.init 8 ~f:(fun step -> code Clear ~bucket:(Int.max 1 (step * (buckets - 1) / 7)))) in
  let swatch_width = 8 in  (* a cell each *)
  let lines = [ key (Theme.attrs theme Ask) "━" "ask"; key (Theme.attrs theme Bid) "═" "bid" ] in
  let decisions = [ key (chip theme Bid) "▲" "admitted"; key (chip theme Ask) "✗" "blocked" ] in
  let widths keys = List.sum (module Int) keys ~f:snd in
  let room = width - 6 - swatch_width - widths lines in
  let short = sprintf " %d u  " maximum in
  let wording = List.find
      [ sprintf " %d u = max(p95, %d×median), γ%.1f; white above %.1f×  " maximum contrast gamma saturation
      ; sprintf " %d u (γ%.1f, white >%.1f×)  " maximum gamma saturation
      ; sprintf " %d u (γ%.1f)  " maximum gamma ]
      ~f:(fun text -> cells text <= room) in
  let scale_width = 6 + swatch_width + cells (Option.value wording ~default:short) in
  let kept, _ = List.fold (lines @ decisions) ~init:([], scale_width) ~f:(fun (kept, used) (view, size) ->
      if used + size <= width then view :: kept, used + size else kept, width + 1) in
  View.hcat
    (View.text ~attrs:muted "qty 0 " :: swatch
     @ (View.text ~attrs:muted (Option.value wording ~default:short) :: List.rev kept))

let span_text seconds =
  if Float.(seconds < 1.) then sprintf "%.0f ms" (seconds *. 1000.) else sprintf "%.1f s" seconds

(* The longest wording that fits, from "← older … N columns · T each · newest →" down to
   a bare count. A book that is invalid always says so first. *)
let axis theme ~width ~count ~valid ~column_seconds =
  let used = Braille_chart.display_width in
  let flag = if valid then "" else "BOOK INVALID · " in
  let each = span_text column_seconds in
  let fits text = used text <= width in
  let newest = List.find
      [ sprintf "%s%d columns · %s each · newest →" flag count each
      ; sprintf "%s%d cols · %s each →" flag count each
      ; sprintf "%s%d cols →" flag count; String.strip flag ]
      ~f:fits in
  let newest = Option.value newest ~default:(String.prefix (flag ^ Int.to_string count) width) in
  let older = "← older" in
  let left = if used older + 1 + used newest <= width then older else "" in
  let gap = Int.max 0 (width - used left - used newest) in
  View.text ~attrs:(Theme.attrs theme (if valid then Muted else Warn))
    (left ^ String.make gap ' ' ^ newest)

(* One row of outcomes under the map, a glyph per column, so a decision never covers the
   price lines it was taken against. *)
let rail_codes heatmap columns =
  Array.map columns ~f:(fun column ->
    match Option.bind column.snapshot_id ~f:(fun id -> Map.find heatmap.markers (slot heatmap id)) with
    | Some Admitted -> 1 | Some Blocked -> 2 | None -> 0)

let digits value = String.length (Int.to_string value)

(* The map and what frames it, once the window is known. *)
let chart theme ~heatmap ~(state : application_state) ~inner ~rows ~center =
  let bottom, top = fit ~rows ~center in
  let price_width = Int.max 4 (Int.max (digits top) (digits bottom)) in
  let columns = visible heatmap ~count:(inner - price_width - 1) in
  let maximum = scale columns ~bottom ~top in
  let threshold = Market_panel.threshold state in
  let cells = grid columns ~bottom ~top ~maximum ~threshold in
  let painter = painter theme and buffer = Stdlib.Buffer.create 256 in
  let shared = Hashtbl.create (module Int) ~size:128 in
  let newest = Option.some_if (not (Array.is_empty columns)) (Array.last_exn columns) in
  let valid = Option.for_all newest ~f:(fun column -> column.valid) in
  (* Until the map has a column for every cell, the left of the row is nothing resting. *)
  let padding = Int.max 0 (inner - price_width - 1 - Array.length columns) in
  let muted = Theme.attrs theme Muted in
  (* A price gutter is the label and the axis rule beside it. Where the label has the colour of
     the rule they are one text node. *)
  let gutter ~label ~role =
    let attrs = Option.value_map role ~default:muted ~f:(Theme.attrs theme) in
    let label = String.make (Int.max 0 (price_width - String.length label)) ' ' ^ label in
    let rule = if Option.is_some role then "┤" else "│" in
    if [%equal: Attr.t list] attrs muted then [ View.text ~attrs:muted (label ^ rule) ]
    else [ View.text ~attrs label; View.text ~attrs:muted rule ] in
  let unlabelled = gutter ~label:"" ~role:None in
  let price_gutter price =
    let role = match newest with
      | Some column when Option.equal Int.equal column.best_ask (Some price) -> Some Theme.Ask
      | Some column when Option.equal Int.equal column.best_bid (Some price) -> Some Bid
      | _ -> if Option.equal Int.equal threshold (Some price) then Some Warn
        else if Int.(price % 4 = 0) then Some Muted else None in
    match role with
    | None -> unlabelled
    | Some _ -> gutter ~label:(Int.to_string price) ~role in
  let heat = List.init rows ~f:(fun index ->
      View.hcat (price_gutter (top - index) @ heat_row_views painter ~shared ~buffer ~padding cells.(index))) in
  let chip_bid = chip theme Bid and chip_ask = chip theme Ask in
  let rail =
    View.hcat
      (gutter ~label:"dec" ~role:(Some Theme.Muted)
       @ row_views ~shared:(Hashtbl.create (module Int) ~size:4) ~buffer ~padding ~style:Fn.id
           ~glyph:(function 1 -> "▲" | 2 -> "✗" | _ -> " ")
           ~attrs:(function 1 -> chip_bid | 2 -> chip_ask | _ -> [])
           (rail_codes heatmap columns)) in
  let column_seconds = Float.of_int heatmap.stride /. state.rate_hz in
  maximum,
  View.vcat
    ((legend theme painter ~shared ~buffer ~maximum ~width:inner :: heat)
     @ [ rail; axis theme ~width:inner ~count:(Array.length columns) ~valid ~column_seconds ])

let view ~theme ~focus ~heatmap ~(state : application_state) ~width ~height =
  let snapshot = state.market in
  let inner = Int.max 0 (width - 4) in
  (* The legend, the decision rail and the axis take three rows of the body. *)
  let rows = Int.max 1 (height - 5) in
  let scale_used, body =
    match newest_mid (visible heatmap ~count:(inner - 5)) with
    | None -> None, View.text ~attrs:(Theme.attrs theme Muted) "no liquidity observed yet"
    | Some center ->
      let maximum, body = chart theme ~heatmap ~state ~inner ~rows ~center in
      Some maximum, body in
  let scale = Option.value_map scale_used ~default:"—" ~f:Int.to_string in
  Panel.framed ~muted:(not snapshot.valid) ~theme ~focus ~panel:Heatmap
    ~title:(sprintf "Heatmap · %s · %s · scale %s u" snapshot.instrument
              (Status_bar.mode_name state.mode) scale)
    ~width ~height body

(* What [view] reads of the application state, and nothing else: a book valid or not, the
   instrument, the mode, the stream rate and the rule's threshold. The rest of the state, the
   book and the counters that change on every stream tick, leave the map alone, which changes
   only as a column joins its ring. A node that cuts the state off on this is computed when
   the map changes, not when the stream ticks. *)
let same_inputs (a : application_state) (b : application_state) =
  Bool.equal a.market.valid b.market.valid && String.equal a.market.instrument b.market.instrument
  && equal_mode a.mode b.mode && Float.equal a.rate_hz b.rate_hz
  && [%equal: int option] (Market_panel.threshold a) (Market_panel.threshold b)

(* ---- Component ---- *)

type action = Observe of snapshot * float | Note of decision

let component ~(state : application_state Bonsai.t) (local_ graph) =
  let heatmap, inject = Bonsai.state_machine ~default_model:empty
      ~apply_action:(fun _ heatmap -> function
        | Observe (snapshot, rate_hz) -> observe_sampled heatmap ~rate_hz snapshot
        | Note decision -> note_decision heatmap decision)
      graph in
  let market = let%arr state in state.market in
  let latest = let%arr state in state.latest_decision in
  let rate_hz = let%arr state in state.rate_hz in
  let on_snapshot = let%arr inject and rate_hz in fun snapshot -> inject (Observe (snapshot, rate_hz)) in
  let on_decision = let%arr inject in
    fun decision -> Option.value_map decision ~default:Effect.Ignore
                      ~f:(fun decision -> inject (Note decision)) in
  Bonsai.Edge.on_change ~equal:[%equal: snapshot] market ~callback:on_snapshot graph;
  Bonsai.Edge.on_change ~equal:[%equal: decision option] latest ~callback:on_decision graph;
  heatmap
