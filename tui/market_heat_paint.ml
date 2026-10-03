open! Core
open Bonsai_term

(* How the heatmap turns resting size into cells: the colour ramp and its power law, the
   percentile scale, the heat buckets under at most one ink each, and how a row of them
   becomes text nodes. Pure, and free of the heatmap's own state. *)

(* ---- Colour ---- *)

(* dark -> deep blue -> cyan -> amber -> white. The ends follow the theme background and
   accent; the blues and white are fixed so the ramp keeps its hue order on every scheme. *)
let stops theme =
  [| Theme.role_rgb theme Bg; (0x12, 0x2C, 0x7A); (0x2B, 0xC4, 0xD8)
   ; Theme.role_rgb theme Focus; (0xFF, 0xFF, 0xFF) |]

let ramp_rgb theme intensity =
  let stops = stops theme in
  let scaled = Float.clamp_exn intensity ~min:0. ~max:1. *. Float.of_int (Array.length stops - 1) in
  let index = Int.min (Array.length stops - 2) (Float.to_int scaled) in
  Theme.blend stops.(index) stops.(index + 1) (scaled -. Float.of_int index)
let ramp_color theme intensity = Theme.rgb_color theme (ramp_rgb theme intensity)

(* A power law a little above 1 keeps small sizes dim without hiding them: a level at a fifth
   of the scale shows at about a seventh of the ramp, so mid-sized liquidity reads. The scale
   is not the end of the ramp. White is reserved for a size above [saturation] times the scale,
   well beyond anything the book ordinarily shows, so a flat white cell always means "off the
   scale" and a wall that merely reaches the scale is amber, not white. *)
let gamma = 1.2
let saturation = 1.5
let intensity ~quantity ~maximum =
  if quantity <= 0 || maximum <= 0 then 0.
  else Float.min 1. ((Float.of_int quantity /. (saturation *. Float.of_int maximum)) ** gamma)

let density_glyph intensity =
  if Float.(intensity <= 0.) then " "
  else if Float.(intensity < 0.25) then "░"
  else if Float.(intensity < 0.5) then "▒"
  else if Float.(intensity < 0.75) then "▓" else "█"

(* ---- Scale ---- *)

(* The colour scale is the 95th percentile of the resting sizes in view, not the largest:
   one wall must not turn every other level to black. It is never less than [contrast] times
   the median size either, so a book with no walls does not stretch its ordinary noise across
   the whole ramp: a level has to stand well above its neighbours to glow. Sizes are counted
   in bins of eight a power of two, so a percentile is found in one pass and fixed space, to
   within 9%. *)
let contrast = 3
let bins = 480
let bin_of size =
  if size < 16 then Int.max 0 size
  else (let log = Int.floor_log2 size in (8 * (log - 2)) + ((size lsr (log - 3)) land 7))
let bin_ceiling bin =
  if bin < 16 then bin else (((8 + (bin mod 8) + 1) lsl ((bin / 8) + 2 - 3)) - 1)
let percentile counts ~total ~percent =
  let want = ((total * percent) + 99) / 100 in
  let rec find bin seen =
    if bin >= bins - 1 then bin
    else (let seen = seen + counts.(bin) in if seen >= want then bin else find (bin + 1) seen) in
  if total = 0 then 0 else bin_ceiling (find 0 0)
let scale_of counts ~total =
  let median = percentile counts ~total ~percent:50 in
  let floor = if median > Int.max_value / contrast then Int.max_value else median * contrast in
  Int.max 1 (Int.max (percentile counts ~total ~percent:95) floor)

(* ---- Cells ---- *)

(* A cell is a heat bucket under at most one ink: a best-price line glyph or the threshold
   dash. The code [ink * buckets + bucket] indexes everything a cell can look like. Bucket 0
   is nothing resting. Bucket 1 is a faint tint for the thinnest sizes, so the extent of the
   book shows. Buckets 2 to [buckets - 2] climb the ramp in even steps of ramp position, from
   [ordinary] to [top_shade]. The last bucket is the saturation zone, white, and nothing
   below [saturation] times the scale reaches it. Long flat runs are what keeps a frame small
   on the wire, so the ramp is a dozen steps, not a continuum. *)
let buckets = 12
let ordinary = 0.12
let top_shade = 0.85
type line = Horizontal | Vertical | Down_right | Down_left | Up_right | Up_left
type ink = Clear | Threshold | Bid_line of line | Ask_line of line
let line_index = function
  | Horizontal -> 0 | Vertical -> 1 | Down_right -> 2 | Down_left -> 3 | Up_right -> 4 | Up_left -> 5
let ink_index = function
  | Clear -> 0 | Threshold -> 1 | Bid_line line -> 2 + line_index line | Ask_line line -> 8 + line_index line
let inks = 14
let code ink ~bucket = (ink_index ink * buckets) + bucket
let bucket_of code = code mod buckets
let ink_of code = code / buckets
let steps = buckets - 4  (* between the first and the last bucket of the climb *)

(* Where a size falls on the climb, in steps from the first climbing bucket: 0 to [steps], with
   the fraction between two buckets. [None] below the climb (nothing, or the faint tint) and above
   it (white). *)
let climb ~maximum quantity =
  if quantity <= 0 || maximum <= 0 then None
  else (
    let heat = intensity ~quantity ~maximum in
    if Float.(heat >= 1. || heat < ordinary) then None
    else Some ((heat -. ordinary) /. (top_shade -. ordinary) *. Float.of_int steps))

let bucket_for ~maximum quantity =
  if quantity <= 0 || maximum <= 0 then 0
  else if Float.(intensity ~quantity ~maximum >= 1.) then buckets - 1
  else (
    match climb ~maximum quantity with
    | None -> 1
    | Some position -> 2 + Int.min steps (Float.iround_nearest_exn position))

(* Sizes jitter around the edge between two buckets, and a row that draws every crossing is a
   confetti of runs: each is a full colour sequence on the wire, and each scroll resends the row.
   A cell keeps the bucket of the column before it, at the same price, unless its size is clear
   of that bucket by more than [hold] of a step: the edge is drawn where the size has really
   moved, not where it touches. [hold] 0.5 is no hysteresis at all. *)
let hold = 0.75
let settle ~before ~maximum quantity =
  let bucket = bucket_for ~maximum quantity in
  let near position = Float.compare (Float.abs (position -. Float.of_int (before - 2))) hold < 0 in
  match climb ~maximum quantity with
  | Some position when before >= 2 && before <= 2 + steps && near position -> before
  | Some _ | None -> bucket

(* The ramp position a bucket stands for. Bucket 1 is a tint, a twentieth of the ramp. *)
let faint = 0.05
let bucket_intensity bucket =
  if bucket <= 0 then 0.
  else if bucket = 1 then faint
  else if bucket = buckets - 1 then 1.
  else ordinary +. ((top_shade -. ordinary) *. Float.of_int (bucket - 2) /. Float.of_int steps)

(* The ask is a heavy line and the bid a double line, so they differ without colour. *)
let ask_glyphs = [| "━"; "┃"; "┏"; "┓"; "┗"; "┛" |]
let bid_glyphs = [| "═"; "║"; "╔"; "╗"; "╚"; "╝" |]

(* A dark glyph on a solid chip, so a decision stands out from anything behind it. *)
let chip theme role =
  match Theme.rgb_color theme (Theme.role_rgb theme Bg) with
  | None -> [ Attr.bold ]
  | Some dark -> [ Attr.bold; Attr.fg dark; Attr.bg (Theme.color theme role) ]

(* Bucket 0, nothing resting, is the background itself and carries no attributes at all, so a
   run of it is the same text node as the blanks beside it. *)
let palette theme =
  Array.init buckets ~f:(fun bucket ->
    if bucket = 0 then None else Theme.rgb_color theme (ramp_rgb theme (bucket_intensity bucket)))

(* Heat is a background colour; without colour it is a density glyph instead. A price line
   is bold ink on the terminal's own background, a dark channel through whatever is behind
   it: brighter than any heat, and every cell of it the same attributes. *)
let paint theme palette code =
  let bucket = bucket_of code in
  let behind = Option.value_map palette.(bucket) ~default:[] ~f:(fun color -> [ Attr.bg color ]) in
  let stroke glyphs index role = glyphs.(index), Attr.bold :: Theme.attrs theme role in
  match ink_of code with
  | 0 ->
    if Option.is_some palette.(bucket) then " ", behind
    else density_glyph (bucket_intensity bucket), []
  | 1 -> "╌", Theme.attrs theme Warn @ behind
  | ink when ink < 8 -> stroke bid_glyphs (ink - 2) Bid
  | ink -> stroke ask_glyphs (ink - 8) Ask

(* Which cells may share a text node, whatever their glyphs: those drawn with the same
   attributes. Every price-line glyph of a side is drawn alike, so a run of line cells is
   one node and one escape sequence, not one per cell. *)
let style code =
  match ink_of code with
  | 0 -> bucket_of code
  | 1 -> buckets + bucket_of code
  | ink when ink < 8 -> 2 * buckets
  | _ -> (2 * buckets) + 1

(* One text node per run of cells that share a style. *)
let row_view ~style cache row =
  if Array.is_empty row then View.none
  else (
    let buffer = Stdlib.Buffer.create 64 in
    let flush attrs = View.text ~attrs (Stdlib.Buffer.contents buffer) in
    let views, last, attrs = Array.fold row ~init:([], style row.(0), snd (cache row.(0)))
        ~f:(fun (views, current, attrs) cell ->
          let glyph, cell_attrs = cache cell in
          let cell_style = style cell in
          if cell_style = current then (Stdlib.Buffer.add_string buffer glyph; views, current, attrs)
          else (
            let views = flush attrs :: views in
            Stdlib.Buffer.clear buffer;
            Stdlib.Buffer.add_string buffer glyph;
            views, cell_style, cell_attrs)) in
    ignore (last : int);
    View.hcat (List.rev (flush attrs :: views)))
