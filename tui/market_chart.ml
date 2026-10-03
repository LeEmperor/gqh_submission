open! Core
open Bonsai_term

(* The best bid, best ask and mid over the last 60 seconds, as a braille chart: a cell is
   2x4 dots, so the plot has four price rows to every text row. Time runs left to right and
   ends at [now]; the price scale is in ticks. A book that was invalid breaks the line
   rather than being bridged, and a price holds, as a book does, until its next change.

   A frame is built from a history of thousands of samples, so the work here is in passes over
   that list that allocate nothing per sample, and in cells that are drawn straight into runs
   of text: a cell is never a string of its own. *)

let window = Time_ns.Span.of_sec 60.
let unset = -2
let gap = -1

(* Dot (x, y) of a cell as its braille bit: dots 1-3 and 7 are the left column, 4-6 and 8
   the right. *)
let bits = [| [| 0; 1; 2; 6 |]; [| 3; 4; 5; 7 |] |]

(* The number of ticks from [low] to [high], exact for any pair of ints. *)
let distance high low = Stdlib.Int64.(to_float (sub (of_int high) (of_int low)))

type scale = { low : int; high : int; span : float; dots : int }
let margin = 1  (* a dot of air above and below the extremes *)

(* The dot row of a price [offset] ticks above [low]. A flat range sits mid-plot. *)
let dot_row scale offset =
  let span = scale.span in
  if Float.(span <= 0.) then scale.dots / 2
  else (
    let used = Float.of_int (scale.dots - 1 - (2 * margin)) in
    margin + Int.clamp_exn ~min:0 ~max:(scale.dots - 1 - (2 * margin))
               (Float.iround_nearest_exn (used *. (span -. offset) /. span)))

(* The pixel column of a sample, or none when it is outside the window. Time is cut into
   buckets one pixel wide, anchored to absolute time rather than to [now]: between two
   bucket boundaries the chart does not move, so only its newest column changes from one
   frame to the next, and the terminal is not repainted for a scroll nobody can see. *)
let bucket_seconds ~pixels = Time_ns.Span.to_sec window /. Float.of_int pixels
let bucket ~step time =
  Float.iround_down_exn (Time_ns.Span.to_sec (Time_ns.to_span_since_epoch time) /. step)

(* Whether a sample is in the window, by integer nanoseconds: it is asked of every sample in a
   history of thousands, on every frame. *)
let window_ns = Time_ns.Span.to_int_ns window
let age_ns ~now time = Time_ns.to_int_ns_since_epoch now - Time_ns.to_int_ns_since_epoch time

(* Calls [f] on each sample in the window, newest first, and stops at the first that is older
   than it: the history is sorted, and the rest are older still. A frame touches the samples it
   draws, not the whole history. A sample after [now] is skipped. *)
let iter_window samples ~now ~f =
  Age_deque.iter_while samples ~f:(fun sample ->
    let age = age_ns ~now sample.Market_motion.time in
    age <= window_ns && ((if age >= 0 then f sample); true))

(* The newest book with both sides, and the lowest and highest price within the window, in
   one pass. [lowest > highest] when no price is in the window. *)
type extent = { latest : (int * int) option; lowest : int; highest : int }
let extent ~now (samples : Market_motion.sample Age_deque.t) =
  let low = ref Int.max_value and high = ref Int.min_value and latest = ref None in
  let widen price = if price < !low then low := price; if price > !high then high := price in
  (* Past the window only the latest book is still wanted, and the walk ends when it is found. *)
  Age_deque.iter_while samples ~f:(fun sample ->
    (match !latest, sample.bid, sample.ask with
     | None, Some bid, Some ask -> latest := Some (bid, ask)
     | _ -> ());
    let age = age_ns ~now sample.time in
    if age > window_ns then Option.is_none !latest
    else (
      if age >= 0 then (
        (match sample.bid with Some price -> widen price | None -> ());
        (match sample.ask with Some price -> widen price | None -> ()));
      true));
  { latest = !latest; lowest = !low; highest = !high }

(* The dot row of ask, bid and mid at each pixel column: [unset] where nothing was observed,
   [gap] where the book was invalid. [samples] are newest first, so the newest observation in
   a pixel column is the one kept, and it decides all three series. *)
let series (samples : Market_motion.sample Age_deque.t) ~now ~pixels ~scale =
  let ask = Array.create ~len:pixels unset and bid = Array.create ~len:pixels unset
  and mid = Array.create ~len:pixels unset in
  let step = bucket_seconds ~pixels in
  let current = bucket ~step now in
  let offset price = distance price scale.low in
  iter_window samples ~now ~f:(fun sample ->
    let x = pixels - 1 - (current - bucket ~step sample.time) in
    if x >= 0 && ask.(x) = unset then (
      ask.(x) <- (match sample.ask with Some price -> dot_row scale (offset price) | None -> gap);
      bid.(x) <- (match sample.bid with Some price -> dot_row scale (offset price) | None -> gap);
      mid.(x) <- (match sample.bid, sample.ask with
        | Some bid, Some ask -> dot_row scale ((offset bid +. offset ask) /. 2.)
        | _ -> gap)));
  ask, bid, mid

(* A cell holds the dots of the four layers, a byte each: the asks, the bids, the mid and
   the rule. A cell takes the colour of the layer with most dots in it, the first on a tie;
   the dots all show. *)
type owner = Nobody | Asks | Bids | Mids | Limit [@@deriving equal]
let ask_layer = 0 and bid_layer = 8 and mid_layer = 16 and limit_layer = 24

let plot_dot cells ~width ~layer x y =
  let cell = ((y lsr 2) * width) + (x lsr 1) in
  cells.(cell) <- cells.(cell) lor (1 lsl (layer + bits.(x land 1).(y land 3)))

(* Draws a series as a step line into [cells]. Between observations the price holds; after the
   newest one it stops, so a stalled stream shows as a stub. *)
let draw cells ~width ~layer ~every column =
  let last = ref (-1) in
  Array.iteri column ~f:(fun x row -> if row <> unset then last := x);
  let held = ref gap in  (* the row being held, or [gap] once the line is broken *)
  let put x y = if x mod every = 0 then plot_dot cells ~width ~layer x y in
  Array.iteri column ~f:(fun x row ->
    if row = unset then (if !held <> gap && x < !last then put x !held)
    else if row = gap then held := gap
    else (
      if !held <> gap && !held <> row then
        for y = Int.min !held row to Int.max !held row do put x y done
      else put x row;
      held := row))

(* The smallest of 1, 2, 5, 10, 20, 50 ... ticks that leaves room for every label. *)
let tick_step ~span ~labels =
  let rec leading step = if step >= 10 then leading (step / 10) else step in
  let next step = match leading step with 2 -> step * 5 / 2 | _ -> step * 2 in
  let rec grow step =
    if Float.(span /. Float.of_int step <= Float.of_int labels) then step else grow (next step) in
  grow 1

(* Prices beyond a quadrillion ticks are not charted: their scale cannot be labelled. *)
let plottable low high = Float.(abs (of_int low) < 1e15 && abs (of_int high) < 1e15)

let owner_of cell =
  let count layer = Int.popcount ((cell lsr layer) land 0xFF) in
  let asks = count ask_layer and bids = count bid_layer and mids = count mid_layer
  and limit = count limit_layer in
  (* The first of the layers with most dots: the asks win a tie. *)
  if asks > 0 && asks >= bids && asks >= mids && asks >= limit then Asks
  else if bids > 0 && bids >= mids && bids >= limit then Bids
  else if mids > 0 && mids >= limit then Mids
  else if limit > 0 then Limit
  else Nobody

(* One row of the plot as runs of text. A blank cell shows nothing, so it takes the colour of
   the run it is in, and a row's leading blanks that of its first run: a dashed rule is one text
   node, not one per dash and gap. *)
let plot_row ~attrs_of cells ~width ~row =
  let buffer = Stdlib.Buffer.create (3 * width) in
  let views = ref [] and run_owner = ref Nobody and started = ref false in
  let flush () =
    if !started then (
      views := View.text ~attrs:(attrs_of !run_owner) (Stdlib.Buffer.contents buffer) :: !views;
      Stdlib.Buffer.clear buffer) in
  for x = 0 to width - 1 do
    let cell = cells.((row * width) + x) in
    let dots = (cell lor (cell lsr 8) lor (cell lsr 16) lor (cell lsr 24)) land 0xFF in
    if dots = 0 then Stdlib.Buffer.add_char buffer ' '
    else (
      let owner = owner_of cell in
      if not !started then (started := true; run_owner := owner)
      else if not (equal_owner owner !run_owner) then (flush (); run_owner := owner);
      Braille_chart.add_braille buffer dots)
  done;
  if !started then flush ()
  else views := [ View.text (Stdlib.Buffer.contents buffer) ];
  List.rev !views

(* The legend above the plot: the newest book and the rule's threshold, whole parts in order
   while they fit, so a price is never clipped into another price. *)
let legend theme ~width ~label_width ~latest ~threshold ~limit =
  let value = function Some price -> Int.to_string price | None -> "—" in
  let bid_now, ask_now = match latest with
    | Some (bid, ask) -> Some bid, Some ask | None -> None, None in
  let mid_now = Option.map latest ~f:(fun (bid, ask) -> Market_motion.mid_text ~bid ~ask) in
  let parts =
    [ Theme.Muted, String.make (label_width - 1) ' ' ^ "t "
    ; Ask, "ask " ^ value ask_now ^ "  "
    ; Bid, "bid " ^ value bid_now ^ "  "
    ; Text, "mid " ^ Option.value mid_now ~default:"—" ^ " ┄  " ]
    @ (match threshold, limit with
        | Some price, _ -> [ Warn, sprintf "╌ maximum_price %d t  " price ]
        | None, Some price -> [ Warn, sprintf "maximum_price %d t off scale  " price ]
        | None, None -> []) in
  let rec fit used = function
    | [] -> []
    | (role, text) :: rest ->
      if used + Braille_chart.display_width (String.rstrip text) > width then []
      else View.text ~attrs:(Theme.attrs theme role) text :: fit (used + Braille_chart.display_width text) rest in
  View.hcat (fit 0 parts)

(* The time axis under the plot. "−" is one cell and three bytes: the marks are measured in
   cells. The right end is "now" while the stream is live. Once it has stopped, the chart does
   not run to the present, so the end says when the last sample was taken; the first of that
   and its shorter forms that fits is used, and the "−30 s" mark gives way before the time
   does. *)
let axis ~label_width ~plot_width ~stopped =
  let cells = Braille_chart.display_width in
  let left, middle = "−60 s", "−30 s" in
  let lead = String.make (label_width + 1) ' ' in
  let rules count = Braille_chart.repeat "─" count in
  let rights = match stopped with
    | None -> [ "now" ]
    | Some time -> [ sprintf "stopped %s UTC" (Clock_text.utc time ~fraction:false); "stopped" ] in
  (* Both marks, the middle one at the middle of the plot. *)
  let full right =
    let gap_a = (plot_width / 2) - cells left - (cells middle / 2) in
    let gap_b = plot_width - cells left - gap_a - cells middle - cells right in
    if plot_width >= cells left + cells middle + cells right + 4 && gap_a >= 1 && gap_b >= 1
    then Some (lead ^ left ^ rules gap_a ^ middle ^ rules gap_b ^ right) else None in
  let ends right =
    let gap = plot_width - cells left - cells right in
    Option.some_if (gap >= 1) (lead ^ left ^ rules gap ^ right) in
  let layouts = if Option.is_none stopped then [ full ] else [ full; ends ] in
  match List.find_map (List.cartesian_product rights layouts) ~f:(fun (right, layout) -> layout right) with
  | Some axis -> axis
  | None ->
    let right = Option.value (List.find rights ~f:(fun right -> plot_width >= cells right + 1))
        ~default:(List.last_exn rights) in
    lead ^ rules (Int.max 0 (plot_width - cells right)) ^ right

(* The price on each row that has one: labels sit on round prices at their own rows, and the
   threshold, always labelled, takes its row and the rows beside it. *)
let labels ~scale ~rows ~threshold =
  let price = Array.create ~len:rows 0 and role = Array.create ~len:rows None in
  let row_of at = dot_row scale (distance at scale.low) / 4 in
  let step = tick_step ~span:scale.span ~labels:(Int.max 1 (rows / 2)) in
  let rec ticks at = if at <= scale.high then (
      let row = row_of at in
      price.(row) <- at; role.(row) <- Some Theme.Muted;
      ticks (at + step)) in
  ticks (Int.round_up scale.low ~to_multiple_of:step);
  Option.iter threshold ~f:(fun at ->
    let row = row_of at in
    List.iter [ row - 1; row; row + 1 ] ~f:(fun beside ->
      if beside >= 0 && beside < rows then role.(beside) <- None);
    price.(row) <- at; role.(row) <- Some Warn);
  price, role

let view ~theme ~(samples : Market_motion.sample Age_deque.t) ~now ~threshold ~width ~height =
  let muted = Theme.attrs theme Muted in
  let note text = View.text ~attrs:muted text in
  let rows = height - 2 in  (* the legend above and the time axis below *)
  let { latest; lowest = low; highest = high } = extent ~now samples in
  match low <= high with
  | true when rows >= 2 && width >= 12 && plottable low high ->
    (* The threshold joins the scale when it is within a span of the data, so a far-off
       rule does not squash the book. *)
    let reach = Float.max 3. (distance high low) in
    let limit = threshold in
    let threshold = Option.filter limit ~f:(fun price ->
        Float.(distance price high <= reach) && Float.(distance low price <= reach)) in
    let low = Option.value_map threshold ~default:low ~f:(Int.min low)
    and high = Option.value_map threshold ~default:high ~f:(Int.max high) in
    let label_width = Int.max 4 (Int.max (String.length (Int.to_string low)) (String.length (Int.to_string high))) in
    let plot_width = Int.max 1 (width - label_width - 1) in
    let pixels = plot_width * 2 in
    let scale = { low; high; span = distance high low; dots = rows * 4 } in
    let ask, bid, mid = series samples ~now ~pixels ~scale in
    let cells = Array.create ~len:(plot_width * rows) 0 in
    draw cells ~width:plot_width ~layer:ask_layer ~every:1 ask;
    draw cells ~width:plot_width ~layer:bid_layer ~every:1 bid;
    draw cells ~width:plot_width ~layer:mid_layer ~every:2 mid;
    Option.iter threshold ~f:(fun price ->
      let y = dot_row scale (distance price low) in
      for x = 0 to pixels - 1 do
        if x mod 4 < 2 then plot_dot cells ~width:plot_width ~layer:limit_layer x y
      done);
    let ask_attrs = Theme.attrs theme Ask and bid_attrs = Theme.attrs theme Bid
    and text_attrs = Theme.attrs theme Text and limit_attrs = Theme.attrs theme Warn in
    let attrs_of = function
      | Asks -> ask_attrs | Bids -> bid_attrs | Mids -> text_attrs | Limit -> limit_attrs
      | Nobody -> [] in
    let label_price, label_role = labels ~scale ~rows ~threshold in
    let blank_gutter = [ View.text (String.make label_width ' '); note "│" ] in
    let gutter row = match label_role.(row) with
      | Some role ->
        let text = Int.to_string label_price.(row) in
        [ View.pad ~l:(label_width - String.length text) (View.text ~attrs:(Theme.attrs theme role) text)
        ; note "┤" ]
      | None -> blank_gutter in
    View.vcat
      (legend theme ~width ~label_width ~latest ~threshold ~limit
       :: List.init rows ~f:(fun row -> View.hcat (gutter row @ plot_row ~attrs_of cells ~width:plot_width ~row))
       @ [ note (axis ~label_width ~plot_width ~stopped:(Market_motion.stopped_at samples ~now)) ])
  | _ ->
    let message = if rows < 2 || width < 12 then "" else "no price history yet" in
    View.vcat (note message :: List.init (Int.max 0 (height - 1)) ~f:(fun _ -> View.none))
