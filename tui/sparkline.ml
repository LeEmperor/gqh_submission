open! Core

(* Each cell is 2×4 braille pixels. Horizontal position is time, not sample index.
   Only segments between real observations are drawn; missing/invalid values break
   the line. Storage is maintained by the caller, never by mutable globals. *)

let window = Time_ns.Span.of_sec 60.

(* Dot (x, y) of a cell as its braille bit: dots 1-3 and 7 are the left column, 4-6 and 8
   the right. *)
let bits = [| [| 0; 1; 2; 6 |]; [| 3; 4; 5; 7 |] |]

(* The braille text of [cells], a mask of dots each. *)
let text_of_cells cells =
  let buffer = Stdlib.Buffer.create (Array.length cells * 3) in
  Array.iter cells ~f:(fun dots ->
    if dots = 0 then Stdlib.Buffer.add_char buffer ' ' else Braille_chart.add_braille buffer dots);
  Stdlib.Buffer.contents buffer

(* The pixel column of [time] among [pixels], the window starting at [cutoff]. *)
let column ~pixels ~cutoff time =
  let elapsed = Time_ns.Span.to_sec (Time_ns.diff time cutoff) in
  Int.min (pixels - 1) (Int.max 0 (Float.to_int (elapsed /. 60. *. Float.of_int (pixels - 1))))

let dot cells x y =
  let index = x / 2 in
  cells.(index) <- cells.(index) lor (1 lsl bits.(x mod 2).(y))

(* Draws the line from the previous point, at pixel column [px] and row [py] ([px] negative
   when there is none), to the one at pixel column [x], row [y]. *)
let draw_to cells ~px ~py ~x ~y =
  if px < 0 then dot cells x y
  else if x = px then
    for row = Int.min py y to Int.max py y do dot cells x row done
  else for column = px to x do
      let fraction = Float.of_int (column - px) /. Float.of_int (x - px) in
      dot cells column (Float.iround_nearest_exn (Float.of_int py +. fraction *. Float.of_int (y - py)))
    done

(* [braille] draws [points], oldest first, over the 60 seconds ending at [now].
   A point's row runs from 0 (top dot) to 3 (bottom dot); [None] breaks the line. *)
let braille ~now ~width points =
  let width = Int.max 0 width in
  let cutoff = Time_ns.sub now window in
  let points = List.filter points ~f:(fun (time, _) ->
      Time_ns.compare time cutoff >= 0 && Time_ns.compare time now <= 0) in
  if width = 0 || List.for_all points ~f:(fun (_, row) -> Option.is_none row)
  then String.make width ' '
  else (
    let pixels = width * 2 in
    let cells = Array.create ~len:width 0 in
    ignore (List.fold points ~init:None ~f:(fun previous (time, row) ->
      match row with
      | None -> None
      | Some y ->
        let x = column ~pixels ~cutoff time in
        (match previous with
         | None -> draw_to cells ~px:(-1) ~py:0 ~x ~y
         | Some (px, py) -> draw_to cells ~px ~py ~x ~y);
        Some (x, y)) : (int * int) option);
    text_of_cells cells)

(* The row of [value] on a scale from [high] (row 0) down to [low] (row 3).
   A flat scale puts the series on the baseline. *)
let row ~low ~high value =
  if Float.(high <= low) then 3
  else Int.max 0 (Int.min 3 (Float.iround_nearest_exn (3. *. (high -. value) /. (high -. low))))

(* [plot] is [braille] for float observations on a caller-chosen scale. *)
let plot ~now ~width ~low ~high points =
  braille ~now ~width
    (List.map points ~f:(fun (time, value) -> time, Option.map value ~f:(row ~low ~high)))

(* The ask over the last minute. The line is the union of the segments between neighbouring
   observations and a dot for one with no neighbour, so it can be drawn from the newest sample
   as well as from the oldest: the walk stops at the first sample outside the window, and
   allocates nothing. *)
let ask ~(samples : Market_motion.sample Age_deque.t) ~now ~width =
  let width = Int.max 0 width in
  let cutoff = Time_ns.sub now window in
  let cutoff_ns = Time_ns.to_int_ns_since_epoch cutoff and now_ns = Time_ns.to_int_ns_since_epoch now in
  (* Calls [f] on the samples in the window, newest first. *)
  let iter_window f =
    Age_deque.iter_while samples ~f:(fun (sample : Market_motion.sample) ->
      let at = Time_ns.to_int_ns_since_epoch sample.time in
      at >= cutoff_ns && ((if at <= now_ns then f sample); true)) in
  let low = ref Int.max_value and high = ref Int.min_value in
  iter_window (fun sample ->
    match sample.ask with
    | Some price ->
      if price < !low then low := price;
      if price > !high then high := price
    | None -> ());
  if width = 0 || !low > !high then String.make width ' '
  else (
    let low = !low and high = !high in
    (* Integer ticks can exceed float precision; take the span in int64. *)
    let span = Stdlib.Int64.(to_float (sub (of_int high) (of_int low))) in
    let row price =
      if Float.(span = 0.) then 2
      else (
        let below_high = Stdlib.Int64.(to_float (sub (of_int high) (of_int price))) in
        Int.max 0 (Int.min 3 (Float.iround_nearest_exn (3. *. below_high /. span)))) in
    let pixels = width * 2 in
    let cells = Array.create ~len:width 0 in
    (* The newer neighbour of the sample visited, if it has a price: its pixel column and row.
       Its segment is drawn when its older neighbour is met, and it is a dot of its own when
       that neighbour has no price or there is none. *)
    let px = ref (-1) and py = ref 0 in
    iter_window (fun sample ->
      match sample.ask with
      | None -> if !px >= 0 then dot cells !px !py; px := -1
      | Some price ->
        let x = column ~pixels ~cutoff sample.time and y = row price in
        if !px >= 0 then draw_to cells ~px:x ~py:y ~x:!px ~y:!py;
        px := x; py := y);
    if !px >= 0 then dot cells !px !py;
    text_of_cells cells)

(* Inline bars: a fraction of a width in eighths of a cell, and a value placed in
   its declared range. Both are pure, so the panels' rows are easy to pin down. *)
let eighths = [| ""; "▏"; "▎"; "▍"; "▌"; "▋"; "▊"; "▉" |]

type bar = { full : int; partial : string; empty : int }

(* [fraction] of [width] cells; out-of-range and non-finite fractions clamp. *)
let bar ~width ~fraction =
  let width = Int.max 0 width in
  let fraction = if Float.is_finite fraction then Float.clamp_exn fraction ~min:0. ~max:1. else 0. in
  let units = Float.iround_nearest_exn (fraction *. Float.of_int (width * 8)) in
  let full = units / 8 and partial = eighths.(units mod 8) in
  { full; partial; empty = width - full - (if String.is_empty partial then 0 else 1) }

type placement = Below | Inside of int | Above [@@deriving equal, sexp_of]

(* Where [value] sits among [width] cells spanning [low, high]; the ends are exact. *)
let placement ~low ~high ~value ~width =
  if value < low then Below
  else if value > high then Above
  else if high <= low || width <= 1 then Inside 0
  else
    Inside (Float.iround_nearest_exn
              ((Float.of_int value -. Float.of_int low) /. (Float.of_int high -. Float.of_int low)
               *. Float.of_int (width - 1)))

(* The track left of the marker, the marker, and the track right of it. A value outside
   its range pins to the nearer end with an arrow instead of a dot. *)
let range_bar ~low ~high ~value ~width =
  let width = Int.max 1 width in
  let track n = String.concat (List.init (Int.max 0 n) ~f:(fun _ -> "━")) in
  let rest n = String.concat (List.init (Int.max 0 n) ~f:(fun _ -> "─")) in
  match placement ~low ~high ~value ~width with
  | Inside at -> track at, "●", rest (width - at - 1)
  | Below -> "", "◀", rest (width - 1)
  | Above -> track (width - 1), "▶", ""
