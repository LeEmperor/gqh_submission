open! Core
open Bonsai_term

(* The best bid, best ask and mid over the last 60 seconds, as a braille chart: a cell is
   2x4 dots, so the plot has four price rows to every text row. Time runs left to right and
   ends at [now]; the price scale is in ticks. A book that was invalid breaks the line
   rather than being bridged, and a price holds, as a book does, until its next change. *)

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
let pixel_of ~now ~pixels time =
  let step = bucket_seconds ~pixels in
  let age = Time_ns.diff now time in
  if Time_ns.Span.(age < zero || age > window) then None
  else (
    let x = pixels - 1 - (bucket ~step now - bucket ~step time) in
    Option.some_if (x >= 0) x)

(* One series as the dot row at each pixel column: [unset] where nothing was observed,
   [gap] where the book was invalid. [samples] are newest first, so the newest observation
   in a pixel column is the one kept. *)
let series ~samples ~now ~pixels ~row =
  let column = Array.create ~len:pixels unset in
  List.iter samples ~f:(fun (sample : Market_motion.sample) ->
    Option.iter (pixel_of ~now ~pixels sample.time) ~f:(fun x ->
      if column.(x) = unset then column.(x) <- Option.value (row sample) ~default:gap));
  column

(* Draws a series as a step line into [dots], a bit set per cell. Between observations the
   price holds; after the newest one it stops, so a stalled stream shows as a stub. *)
let draw dots ~width ~every column =
  let last = Array.foldi column ~init:(-1) ~f:(fun x last row -> if row <> unset then x else last) in
  let put x y =
    if x mod every = 0 then (
      let cell = (y / 4 * width) + (x / 2) in
      dots.(cell) <- dots.(cell) lor (1 lsl bits.(x mod 2).(y mod 4))) in
  ignore (Array.foldi column ~init:None ~f:(fun x held row ->
    if row = unset then (Option.iter held ~f:(fun y -> if x < last then put x y); held)
    else if row = gap then None
    else (
      (match held with
       | Some before when before <> row ->
         for y = Int.min before row to Int.max before row do put x y done
       | _ -> put x row);
      Some row)) : int option)

(* The smallest of 1, 2, 5, 10, 20, 50 ... ticks that leaves room for every label. *)
let tick_step ~span ~labels =
  let rec leading step = if step >= 10 then leading (step / 10) else step in
  let next step = match leading step with 2 -> step * 5 / 2 | _ -> step * 2 in
  let rec grow step =
    if Float.(span /. Float.of_int step <= Float.of_int labels) then step else grow (next step) in
  grow 1

let glyph bits =
  if bits = 0 then " "
  else (let buffer = Stdlib.Buffer.create 3 in
        Stdlib.Buffer.add_utf_8_uchar buffer (Stdlib.Uchar.of_int (0x2800 + bits));
        Stdlib.Buffer.contents buffer)

type owner = Nobody | Asks | Bids | Mids | Limit [@@deriving equal]

(* Prices beyond a quadrillion ticks are not charted: their scale cannot be labelled. *)
let plottable low high = Float.(abs (of_int low) < 1e15 && abs (of_int high) < 1e15)

let view ~theme ~(samples : Market_motion.sample list) ~now ~threshold ~width ~height =
  let muted = Theme.attrs theme Muted in
  let note text = View.text ~attrs:muted text in
  let rows = height - 2 in  (* the legend above and the time axis below *)
  let latest = List.find_map samples ~f:(fun (sample : Market_motion.sample) ->
      Option.both sample.bid sample.ask) in
  let in_window = List.filter samples ~f:(fun (sample : Market_motion.sample) ->
      let age = Time_ns.diff now sample.time in
      Time_ns.Span.(age >= zero && age <= window)) in
  let prices = List.concat_map in_window ~f:(fun sample -> List.filter_opt [ sample.bid; sample.ask ]) in
  match List.min_elt prices ~compare:Int.compare, List.max_elt prices ~compare:Int.compare with
  | Some low, Some high when rows >= 2 && width >= 12 && plottable low high ->
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
    let offset price = distance price low in
    let ask = series ~samples:in_window ~now ~pixels ~row:(fun sample ->
        Option.map sample.ask ~f:(fun price -> dot_row scale (offset price))) in
    let bid = series ~samples:in_window ~now ~pixels ~row:(fun sample ->
        Option.map sample.bid ~f:(fun price -> dot_row scale (offset price))) in
    let mid = series ~samples:in_window ~now ~pixels ~row:(fun sample ->
        Option.map (Option.both sample.bid sample.ask) ~f:(fun (bid, ask) ->
          dot_row scale ((offset bid +. offset ask) /. 2.))) in
    let cells = plot_width * rows in
    let layer ~every column = let dots = Array.create ~len:cells 0 in draw dots ~width:plot_width ~every column; dots in
    let ask_dots = layer ~every:1 ask and bid_dots = layer ~every:1 bid and mid_dots = layer ~every:2 mid in
    let threshold_row = Option.map threshold ~f:(fun price -> dot_row scale (offset price)) in
    let threshold_dots = Array.create ~len:cells 0 in
    Option.iter threshold_row ~f:(fun y ->
      for x = 0 to pixels - 1 do
        if x mod 4 < 2 then (
          let cell = (y / 4 * plot_width) + (x / 2) in
          threshold_dots.(cell) <- threshold_dots.(cell) lor (1 lsl bits.(x mod 2).(y mod 4)))
      done);
    (* A cell takes the colour of the series with most dots in it; the dots all show. *)
    let owner cell =
      let count dots = Int.popcount dots.(cell) in
      let pick = [ Asks, count ask_dots; Bids, count bid_dots; Mids, count mid_dots; Limit, count threshold_dots ] in
      match List.max_elt pick ~compare:(fun (_, a) (_, b) -> Int.compare a b) with
      | Some (owner, n) when n > 0 -> owner
      | _ -> Nobody in
    let attrs_of = function
      | Asks -> Theme.attrs theme Ask | Bids -> Theme.attrs theme Bid
      | Mids -> Theme.attrs theme Text | Limit -> Theme.attrs theme Warn | Nobody -> [] in
    (* Whole rows of one owner share a text node. *)
    let plot_row row =
      let first = row * plot_width in
      let runs = List.init plot_width ~f:(fun x ->
          let cell = first + x in
          owner cell, glyph (ask_dots.(cell) lor bid_dots.(cell) lor mid_dots.(cell) lor threshold_dots.(cell))) in
      (* A blank cell shows nothing, so it takes the colour of the run it is in: a dashed rule is
         one text node, not one per dash and gap. *)
      let merged = List.fold runs ~init:[] ~f:(fun acc (owner, text) ->
          match acc with
          | (previous, texts) :: rest when equal_owner previous owner || String.equal text " " ->
            (previous, text :: texts) :: rest
          | _ -> (owner, [ text ]) :: acc) in
      let runs = match List.rev merged with
        | (Nobody, blanks) :: (owner, texts) :: rest -> (owner, texts @ blanks) :: rest
        | runs -> runs in
      View.hcat (List.map runs ~f:(fun (owner, texts) ->
          View.text ~attrs:(attrs_of owner) (String.concat (List.rev texts)))) in
    (* Labels sit on round prices at their own rows; the threshold is always labelled. *)
    let step = tick_step ~span:scale.span ~labels:(Int.max 1 (rows / 2)) in
    let labelled = Int.Table.create () in
    let first_tick = Int.round_up low ~to_multiple_of:step in
    let rec ticks price = if price <= high then (
        Hashtbl.set labelled ~key:(dot_row scale (offset price) / 4) ~data:(price, Theme.Muted);
        ticks (price + step)) in
    ticks first_tick;
    Option.iter threshold ~f:(fun price ->
      let row = dot_row scale (offset price) / 4 in
      List.iter [ row - 1; row; row + 1 ] ~f:(Hashtbl.remove labelled);
      Hashtbl.set labelled ~key:row ~data:(price, Theme.Warn));
    let gutter row =
      match Hashtbl.find labelled row with
      | Some (price, role) ->
        let text = Int.to_string price in
        View.hcat [ View.pad ~l:(label_width - String.length text) (View.text ~attrs:(Theme.attrs theme role) text)
                  ; note "┤" ]
      | None -> View.hcat [ View.text (String.make label_width ' '); note "│" ] in
    let legend =
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
      (* Whole parts, in order, while they fit: a price is never clipped into another price. *)
      let rec fit used = function
        | [] -> []
        | (role, text) :: rest ->
          if used + Braille_chart.display_width (String.rstrip text) > width then []
          else View.text ~attrs:(Theme.attrs theme role) text :: fit (used + Braille_chart.display_width text) rest in
      fit 0 parts in
    let axis =
      (* "−" is one cell and three bytes: the marks are measured in cells. *)
      let cells = Braille_chart.display_width in
      let left, middle, right = "−60 s", "−30 s", "now" in
      let used = cells left + cells middle + cells right in
      if plot_width < used + 4 then
        String.make (label_width + 1) ' ' ^ String.concat (List.init (Int.max 0 (plot_width - 3)) ~f:(fun _ -> "─")) ^ "now"
      else (
        let gap_a = (plot_width / 2) - cells left - (cells middle / 2) in
        let gap_b = plot_width - cells left - gap_a - cells middle - cells right in
        let fill count = String.concat (List.init (Int.max 0 count) ~f:(fun _ -> "─")) in
        String.make (label_width + 1) ' ' ^ left ^ fill gap_a ^ middle ^ fill gap_b ^ right) in
    View.vcat
      (View.hcat legend
       :: List.init rows ~f:(fun row -> View.hcat [ gutter row; plot_row row ])
       @ [ note axis ])
  | _ ->
    let message = if rows < 2 || width < 12 then "" else "no price history yet" in
    View.vcat (note message :: List.init (Int.max 0 (height - 1)) ~f:(fun _ -> View.none))
