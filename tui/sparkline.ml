open! Core

(* Each cell is 2×4 braille pixels. Horizontal position is time, not sample index.
   Only segments between real observations are drawn; missing/invalid values break
   the line. Storage is maintained by the caller, never by mutable globals. *)

let window = Time_ns.Span.of_sec 60.

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
    let dot x y =
      let bits = [| [| 0; 1; 2; 6 |]; [| 3; 4; 5; 7 |] |] in
      let index = x / 2 in
      cells.(index) <- cells.(index) lor (1 lsl bits.(x mod 2).(y)) in
    let column time =
      let elapsed = Time_ns.diff time cutoff |> Time_ns.Span.to_sec in
      Int.min (pixels - 1) (Int.max 0 (Float.to_int (elapsed /. 60. *. Float.of_int (pixels - 1)))) in
    ignore (List.fold points ~init:None ~f:(fun previous (time, row) ->
      match row with
      | None -> None
      | Some y ->
        let x = column time in
        (match previous with
         | None -> dot x y
         | Some (px, py) ->
           if x = px then
             for row = Int.min py y to Int.max py y do dot x row done
           else for column = px to x do
               let fraction = Float.of_int (column - px) /. Float.of_int (x - px) in
               dot column (Float.iround_nearest_exn (Float.of_int py +. fraction *. Float.of_int (y - py)))
             done);
        Some (x, y)) : (int * int) option);
    let buffer = Stdlib.Buffer.create (width * 3) in
    Array.iter cells ~f:(fun bits ->
      if bits = 0 then Stdlib.Buffer.add_char buffer ' '
      else Stdlib.Buffer.add_utf_8_uchar buffer (Stdlib.Uchar.of_int (0x2800 + bits)));
    Stdlib.Buffer.contents buffer)

(* The row of [value] on a scale from [high] (row 0) down to [low] (row 3).
   A flat scale puts the series on the baseline. *)
let row ~low ~high value =
  if Float.(high <= low) then 3
  else Int.max 0 (Int.min 3 (Float.iround_nearest_exn (3. *. (high -. value) /. (high -. low))))

(* [plot] is [braille] for float observations on a caller-chosen scale. *)
let plot ~now ~width ~low ~high points =
  braille ~now ~width
    (List.map points ~f:(fun (time, value) -> time, Option.map value ~f:(row ~low ~high)))

let ask ~samples ~now ~width =
  let cutoff = Time_ns.sub now window in
  let samples = List.filter samples ~f:(fun (s : Market_motion.sample) ->
      Time_ns.compare s.time cutoff >= 0 && Time_ns.compare s.time now <= 0) |> List.rev in
  let prices = List.filter_map samples ~f:(fun s -> s.ask) in
  match List.min_elt prices ~compare:Int.compare, List.max_elt prices ~compare:Int.compare with
  | Some low, Some high ->
    (* Integer ticks can exceed float precision; take the span in int64. *)
    let distance left right =
      Stdlib.Int64.sub (Stdlib.Int64.of_int left) (Stdlib.Int64.of_int right)
      |> Stdlib.Int64.to_float in
    let span = distance high low in
    let row price =
      if Float.(span = 0.) then 2
      else Int.max 0 (Int.min 3 (Float.iround_nearest_exn (3. *. (distance high price) /. span))) in
    braille ~now ~width (List.map samples ~f:(fun s -> s.time, Option.map s.ask ~f:row))
  | _ -> String.make (Int.max 0 width) ' '

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
