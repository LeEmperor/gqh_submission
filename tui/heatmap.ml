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
  let t = { t with stride } in
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
  | Some marker, Some id when same_run -> { t with markers = Map.set t.markers ~key:(slot t id) ~data:marker }
  | _ -> t

include Market_heat_paint

(* ---- Geometry ---- *)

let mid_price column =
  match column.best_bid, column.best_ask with
  | Some bid, Some ask -> Some (bid + ((ask - bid) / 2))
  | Some price, None | None, Some price -> Some price
  | None, None -> None

let blank =
  { snapshot_id = None; valid = false; best_bid = None; best_ask = None
  ; prices = [||]; sizes = [||] }

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
  Array.iteri columns ~f:(fun x column ->
    Array.iteri column.prices ~f:(fun i price ->
      if in_window price then (
        let row = grid.(top - price) in
        let before = if x = 0 then 0 else bucket_of row.(x - 1) in
        row.(x) <- settle ~before ~maximum column.sizes.(i))));
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
    Array.iteri column.prices ~f:(fun i price ->
      let size = column.sizes.(i) in
      if price >= bottom && price <= top && size > 0 then (
        let bin = bin_of size in
        counts.(bin) <- counts.(bin) + 1;
        incr total)));
  scale_of counts ~total:!total

(* ---- Chrome ---- *)

(* The scale is never cut. The two price-line keys come next, since the glyphs alone do not
   say which is which; the scale then says how it was found, and the decision keys follow,
   each whole or not at all, as far as there is room. *)
let legend theme cache ~maximum ~width =
  let muted = Theme.attrs theme Muted in
  let key attrs glyph label =
    View.hcat [ View.text ~attrs glyph; View.text ~attrs:muted (" " ^ label ^ "  ") ] in
  let swatch = row_view ~style cache
      (Array.init 8 ~f:(fun step -> code Clear ~bucket:(Int.max 1 (step * (buckets - 1) / 7)))) in
  let lines = [ key (Theme.attrs theme Ask) "━" "ask"; key (Theme.attrs theme Bid) "═" "bid" ] in
  let decisions = [ key (chip theme Bid) "▲" "admitted"; key (chip theme Ask) "✗" "blocked" ] in
  let widths views = List.sum (module Int) views ~f:View.width in
  let room = width - 6 - View.width swatch - widths lines in
  let short = sprintf " %d u  " maximum in
  let wording = List.find
      [ sprintf " %d u = max(p95, %d×median), γ%.1f; white above %.1f×  " maximum contrast gamma saturation
      ; sprintf " %d u (γ%.1f, white >%.1f×)  " maximum gamma saturation
      ; sprintf " %d u (γ%.1f)  " maximum gamma ]
      ~f:(fun text -> View.width (View.text text) <= room) in
  let scale = View.hcat
      [ View.text ~attrs:muted "qty 0 "; swatch; View.text ~attrs:muted (Option.value wording ~default:short) ] in
  let kept, _ = List.fold (lines @ decisions) ~init:([], View.width scale) ~f:(fun (kept, used) key ->
      if used + View.width key <= width then key :: kept, used + View.width key
      else kept, width + 1) in
  View.hcat (scale :: List.rev kept)

let span_text seconds =
  if Float.(seconds < 1.) then sprintf "%.0f ms" (seconds *. 1000.) else sprintf "%.1f s" seconds

(* The longest wording that fits, from "← older … N columns · T each · newest →" down to
   a bare count. A book that is invalid always says so first. *)
let axis theme ~width ~count ~valid ~column_seconds =
  let used text = View.width (View.text text) in
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
let rail_cache theme = function
  | 1 -> "▲", chip theme Bid
  | 2 -> "✗", chip theme Ask
  | _ -> " ", []
let rail_codes heatmap columns =
  Array.map columns ~f:(fun column ->
    match Option.bind column.snapshot_id ~f:(fun id -> Map.find heatmap.markers (slot heatmap id)) with
    | Some Admitted -> 1 | Some Blocked -> 2 | None -> 0)

let digits value = String.length (Int.to_string value)

let view ~theme ~focus ~heatmap ~(state : application_state) ~width ~height =
  let snapshot = state.market in
  let inner = Int.max 0 (width - 4) in
  (* The legend, the decision rail and the axis take three rows of the body. *)
  let rows = Int.max 1 (height - 5) in
  let provisional = visible heatmap ~count:(inner - 5) in
  let scale_used, body =
    match Array.rev provisional |> Array.find_map ~f:mid_price with
    | None -> None, View.text ~attrs:(Theme.attrs theme Muted) "no liquidity observed yet"
    | Some center ->
      let bottom, top = fit ~rows ~center in
      let price_width = Int.max 4 (Int.max (digits top) (digits bottom)) in
      let columns = visible heatmap ~count:(inner - price_width - 1) in
      let maximum = scale columns ~bottom ~top in
      let threshold = Market_panel.threshold state in
      let cells = grid columns ~bottom ~top ~maximum ~threshold in
      let palette = palette theme in
      let memo = Array.create ~len:(inks * buckets) None in
      let cache cell = match memo.(cell) with
        | Some painted -> painted
        | None -> let painted = paint theme palette cell in memo.(cell) <- Some painted; painted in
      let newest = Option.some_if (not (Array.is_empty columns)) (Array.last_exn columns) in
      let valid = Option.for_all newest ~f:(fun column -> column.valid) in
      (* Until the map has a column for every cell, the left of the row is nothing resting. *)
      let padding = Array.create ~len:(Int.max 0 (inner - price_width - 1 - Array.length columns)) 0 in
      let muted = Theme.attrs theme Muted in
      let gutter ~label ~role =
        let attrs = Option.value_map role ~default:muted ~f:(Theme.attrs theme) in
        Runs.view [ attrs, String.make (Int.max 0 (price_width - String.length label)) ' ' ^ label
                  ; muted, if Option.is_some role then "┤" else "│" ] in
      let price_gutter price =
        let role = match newest with
          | Some column when Option.equal Int.equal column.best_ask (Some price) -> Some Theme.Ask
          | Some column when Option.equal Int.equal column.best_bid (Some price) -> Some Bid
          | _ -> if Option.equal Int.equal threshold (Some price) then Some Warn
            else if Int.(price % 4 = 0) then Some Muted else None in
        gutter ~label:(Option.value_map role ~default:"" ~f:(fun _ -> Int.to_string price)) ~role in
      let row ?(style = style) gutter cells cache =
        View.hcat [ gutter; row_view ~style cache (Array.append padding cells) ] in
      let heat = List.init rows ~f:(fun index -> row (price_gutter (top - index)) cells.(index) cache) in
      let rail = row ~style:Fn.id (gutter ~label:"dec" ~role:(Some Theme.Muted)) (rail_codes heatmap columns) (rail_cache theme) in
      let column_seconds = Float.of_int heatmap.stride /. state.rate_hz in
      Some maximum,
      View.vcat
        ((legend theme cache ~maximum ~width:inner :: heat)
         @ [ rail; axis theme ~width:inner ~count:(Array.length columns) ~valid ~column_seconds ]) in
  let scale = Option.value_map scale_used ~default:"—" ~f:Int.to_string in
  Panel.frame ~muted:(not snapshot.valid) ~theme ~focus ~panel:Heatmap
    ~title:(sprintf "Heatmap · %s · %s · scale %s u" snapshot.instrument
              (Status_bar.mode_name state.mode) scale)
    ~width ~height body

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
