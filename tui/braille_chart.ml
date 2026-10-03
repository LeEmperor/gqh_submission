open! Core
open Bonsai_term

(* A multi-row braille line and area chart. Each cell is 2x4 dots, so a chart of
   [width] x [height] cells has 2 * width time columns and 4 * height value levels.
   Geometry ([cells]) is pure and tested on its own; colour is applied afterwards,
   row by row, so a repaint costs O(cells) and never reads the clock. *)

type series = (Time_ns.t * float option) list
type kind = Blank | Fill | Line | No_data [@@deriving equal, sexp_of]
type cell = { bits : int; kind : kind } [@@deriving equal, sexp_of]
type fill = Solid | Stipple | Line_only [@@deriving equal, sexp_of]

let window = Time_ns.Span.of_sec 60.

(* Braille dot bit of (sub-column, row from the top of the cell). *)
let dot_bits = [| [| 0; 1; 2; 6 |]; [| 3; 4; 5; 7 |] |]
let dot_bit ~column ~row = dot_bits.(column).(row)

(* Value level: 0 is the bottom dot of the chart and [dots - 1] the top one. A flat
   scale (or a non-finite value) is never plotted above the baseline. *)
let level ~dots ~low ~high value =
  if Float.(high <= low) || not (Float.is_finite value) then 0
  else
    Int.clamp_exn ~min:0 ~max:(dots - 1)
      (Float.iround_nearest_exn ((value -. low) /. (high -. low) *. Float.of_int (dots - 1)))

let column ~cutoff ~window ~pixels time =
  let elapsed = Time_ns.diff time cutoff |> Time_ns.Span.to_sec in
  Int.clamp_exn ~min:0 ~max:(pixels - 1)
    (Float.to_int (elapsed /. Time_ns.Span.to_sec window *. Float.of_int (pixels - 1)))

(* The vertical span (low level, high level) the line covers in each time column, or
   [None] where nothing was observed. Consecutive observations are joined; a missing
   or non-finite value breaks the line, so a gap is never drawn as zero. *)
let spans ~now ~window ~pixels ~dots ~low ~high (series : series) =
  let cutoff = Time_ns.sub now window in
  let spans = Array.create ~len:pixels None in
  let widen x lo hi =
    spans.(x) <- Some (match spans.(x) with
      | None -> lo, hi
      | Some (old_lo, old_hi) -> Int.min lo old_lo, Int.max hi old_hi) in
  let in_window = List.filter series ~f:(fun (time, _) ->
      Time_ns.compare time cutoff >= 0 && Time_ns.compare time now <= 0) in
  let _ : (int * int) option =
    List.fold in_window ~init:None ~f:(fun previous (time, value) ->
      match value with
      | Some value when Float.is_finite value ->
        let x = column ~cutoff ~window ~pixels time in
        let l = level ~dots ~low ~high value in
        (match previous with
         | None -> widen x l l
         | Some (px, pl) when x <= px -> widen x (Int.min l pl) (Int.max l pl)
         | Some (px, pl) ->
           let _ : int = List.fold (List.range (px + 1) x ~stop:`inclusive) ~init:pl
               ~f:(fun before c ->
                 let fraction = Float.of_int (c - px) /. Float.of_int (x - px) in
                 let here = pl + Float.iround_nearest_exn (fraction *. Float.of_int (l - pl)) in
                 widen c (Int.min before here) (Int.max before here);
                 here) in
           ());
        Some (x, l)
      | Some _ | None -> None) in
  spans

(* The dots one time column lights in the cell whose bottom dot is level [base], as
   (braille bits, whether any is on the line itself). [Solid] fills under the line,
   [Stipple] fills every other dot, [Line_only] draws the line alone. *)
let column_dots ~fill ~sub ~parity ~base = function
  | None -> 0, false
  | Some (lo, hi) ->
    let bits = ref 0 and on_line = ref false in
    for y = 0 to 3 do
      let d = base + (3 - y) in
      let line = d >= lo && d <= hi in
      let lit = match fill with
        | Line_only -> line
        | Solid -> d <= hi
        | Stipple -> line || (d < lo && (parity + d) land 1 = 0) in
      if lit then (
        bits := !bits lor (1 lsl dot_bit ~column:sub ~row:y);
        if line then on_line := true)
    done;
    !bits, !on_line

(* Cells top row first. [No_data] marks a cell whose two time columns saw no
   observation; it carries no dots. *)
let cells ~now ?(window = window) ~width ~height ~low ~high ~fill series =
  let width = Int.max 0 width and height = Int.max 0 height in
  let spans = spans ~now ~window ~pixels:(2 * width) ~dots:(4 * height) ~low ~high series in
  Array.init height ~f:(fun row ->
    let base = 4 * (height - 1 - row) in
    Array.init width ~f:(fun cx ->
      let left = spans.(2 * cx) and right = spans.((2 * cx) + 1) in
      if Option.is_none left && Option.is_none right then { bits = 0; kind = No_data }
      else (
        let left_bits, left_line = column_dots ~fill ~sub:0 ~parity:(2 * cx) ~base left
        and right_bits, right_line = column_dots ~fill ~sub:1 ~parity:((2 * cx) + 1) ~base right in
        let bits = left_bits lor right_bits in
        { bits; kind = if left_line || right_line then Line else if bits <> 0 then Fill else Blank })))

(* The 256 braille cells as strings, a blank for no dots at all. *)
let braille_glyphs =
  Array.init 256 ~f:(fun bits ->
    if bits = 0 then " "
    else (
      let buffer = Stdlib.Buffer.create 3 in
      Stdlib.Buffer.add_utf_8_uchar buffer (Stdlib.Uchar.of_int (0x2800 + bits));
      Stdlib.Buffer.contents buffer))

let glyph cell =
  match cell.kind with
  | No_data -> "·"
  | Blank -> " "
  | Fill | Line -> braille_glyphs.(cell.bits)

let to_strings cells =
  Array.to_list (Array.map cells ~f:(fun row -> String.concat_array (Array.map row ~f:glyph)))

(* Colour. The area fades from [strong] under the top row to [faint] at the baseline,
   an RGB blend of the surface towards the role colour. 16-colour terminals cannot
   interpolate, so the line takes the role colour and the area the muted grey; with no
   colour at all the area is stippled instead, so glyphs always carry the shape. *)
let strong = 0.55
let faint = 0.15

let strength ~height ~row =
  if height <= 1 then strong
  else faint +. ((strong -. faint) *. Float.of_int (height - 1 - row) /. Float.of_int (height - 1))

let shade theme role ~strength =
  Theme.rgb_color theme
    (Theme.blend (Theme.role_rgb theme Bg) (Theme.role_rgb theme role) strength)

let fill_attrs theme role ~strength =
  match theme.Theme.capability with
  | No_color -> []
  | Ansi16 -> Theme.attrs theme Muted
  | Truecolor | Ansi256 ->
    Option.value_map (shade theme role ~strength) ~default:[] ~f:(fun color -> [ Attr.fg color ])

let fill_style (theme : Theme.t) =
  match theme.capability with Truecolor | Ansi256 -> Solid | Ansi16 | No_color -> Stipple

let texture_attrs theme = fill_attrs theme Muted ~strength:0.5

(* Number formats for axes: short, and stable between frames. *)
let compact value =
  if Float.(abs value >= 1000.) then sprintf "%sk" (sprintf "%.3g" (value /. 1000.))
  else sprintf "%.3g" value

(* The least "round" bound at or above [value] (1, 1.2, 1.5, 1.8, 2, 2.5, 3, 4, 5, 6, 8
   times a power of ten), so an axis keeps clean labels while the data moves. *)
let nice_ceiling value =
  if not (Float.is_finite value) || Float.(value <= 0.) then 1.
  else (
    let magnitude = 10. ** Float.round_down (Float.log10 value) in
    let steps = [ 1.; 1.2; 1.5; 1.8; 2.; 2.5; 3.; 4.; 5.; 6.; 8.; 10. ] in
    let step = List.find steps ~f:(fun step -> Float.(step * magnitude >= value *. (1. -. 1e-9)))
      |> Option.value ~default:10. in
    step *. magnitude)

(* The cells [text] takes on screen, as [View.width (View.text text)] says, without building a
   view. Printable ASCII is a cell a byte. Other text is the sum of Notty's width of each code
   point; a control character, which the view rewrites, malformed UTF-8 and the variation
   selector that widens a cluster are left to the view itself. *)
let display_width text =
  let length = String.length text in
  let rec ascii index =
    index >= length
    || (let byte = Char.to_int (String.unsafe_get text index) in
        byte >= 0x20 && byte < 0x7F && ascii (index + 1)) in
  let rec cells index total =
    if index >= length then total
    else (
      let decoded = Stdlib.String.get_utf_8_uchar text index in
      let scalar = Stdlib.Uchar.to_int (Stdlib.Uchar.utf_decode_uchar decoded) in
      if (not (Stdlib.Uchar.utf_decode_is_valid decoded))
         || scalar < 0x20 || (scalar >= 0x7F && scalar < 0xA0) || scalar = 0xFE0F
      then View.width (View.text text)
      else cells (index + Stdlib.Uchar.utf_decode_length decoded)
             (total + View.uchar_tty_width (Stdlib.Uchar.utf_decode_uchar decoded))) in
  if ascii 0 then length else cells 0 0

(* The characters of [value] in decimal, a sign included: [String.length (Int.to_string value)]
   without the string. *)
let int_width value =
  let rec digits value count = if value > -10 then count else digits (value / 10) (count + 1) in
  (if value < 0 then 1 else 0) + digits (if value > 0 then -value else value) 1

(* [glyph] repeated [count] times (none for a count below one). *)
let repeat glyph count =
  let count = Int.max 0 count and size = String.length glyph in
  let bytes = Stdlib.Bytes.create (count * size) in
  for index = 0 to count - 1 do Stdlib.Bytes.blit_string glyph 0 bytes (index * size) size done;
  Stdlib.Bytes.unsafe_to_string bytes

(* The braille cell of [dots], a mask of its eight dots, as its UTF-8 bytes. *)
let add_braille buffer dots =
  Stdlib.Buffer.add_char buffer '\xE2';
  Stdlib.Buffer.add_char buffer (Char.unsafe_of_int (0xA0 lor (dots lsr 6)));
  Stdlib.Buffer.add_char buffer (Char.unsafe_of_int (0x80 lor (dots land 0x3F)))

(* Padding counts display cells, never bytes: "↑", "·" and "−" are one cell and several bytes. *)
let spaces count = String.make (Int.max 0 count) ' '
let pad_right text ~width = text ^ spaces (width - display_width text)
let pad_left text ~width = spaces (width - display_width text) ^ text

(* Joins the parts that fit, whole and in order, with " · "; never clips a word. *)
let fit_parts ~width parts =
  List.fold parts ~init:"" ~f:(fun line part ->
    let joined = if String.is_empty line then part else line ^ " · " ^ part in
    if display_width joined <= width then joined else line)

(* [text] cut to [width] cells with an ellipsis. One cell per code point, which is all
   the panels' own strings use. *)
let truncate ~width text =
  if display_width text <= width then text
  else if width <= 0 then ""
  else (
    (* A code point starts at any byte that is not a continuation byte. *)
    let rec cut index points =
      if index >= String.length text then index
      else if Char.to_int text.[index] land 0xC0 = 0x80 then cut (index + 1) points
      else if points = width - 1 then index
      else cut (index + 1) (points + 1) in
    String.prefix text (cut 0 0) ^ "…")

(* Y labels sit on the top and bottom rows, and in the middle from five rows up. *)
let y_labels ~height ~low ~high ~format =
  if height < 2 then []
  else
    [ 0, format high ]
    @ (if height >= 5 then [ (height - 1) / 2, format ((low +. high) /. 2.) ] else [])
    @ [ height - 1, format low ]

(* Label column plus the axis rule; 0 for a one-row sparkline or a chart too narrow
   to keep four plot columns beside its labels. *)
let gutter ~width ~height ~low ~high ~format =
  match y_labels ~height ~low ~high ~format with
  | [] -> 0
  | labels ->
    let gutter = 1 + List.fold labels ~init:0 ~f:(fun width (_, label) -> Int.max width (String.length label)) in
    if width - gutter < 4 then 0 else gutter

(* A cell is drawn by its kind, or is part of a label written over the texture. *)
type style = Cell of kind | Label [@@deriving equal]

let attrs_of theme role ~height ~row = function
  | Label -> Theme.attrs theme Text
  | Cell Line -> Theme.attrs theme role
  | Cell Fill -> fill_attrs theme role ~strength:(strength ~height ~row)
  | Cell No_data -> texture_attrs theme
  | Cell Blank -> []

(* One string per UTF-8 code point: a code point starts at any byte that is not a
   continuation byte. *)
let code_points text =
  String.fold text ~init:[] ~f:(fun points char ->
    if Char.to_int char land 0xC0 = 0x80 then
      (match points with last :: rest -> (last ^ String.of_char char) :: rest | [] -> [ String.of_char char ])
    else String.of_char char :: points)
  |> List.rev

(* Start and width of the widest run of No_data columns. *)
let widest_gap grid =
  if Array.is_empty grid then 0, 0
  else (
    let _, best, _ =
      Array.foldi grid.(0) ~init:(0, (0, 0), 0) ~f:(fun x (start, (best_start, best_width), width) cell ->
        if equal_kind cell.kind No_data then (
          let start, width = if width = 0 then x, 1 else start, width + 1 in
          start, (if width > best_width then (start, width) else (best_start, best_width)), width)
        else start, (best_start, best_width), 0) in
    best)

let centred ~width text =
  let left = (width - display_width text) / 2 in
  String.make (Int.max 0 left) ' ' ^ text ^ String.make (Int.max 0 (width - display_width text - left)) ' '

(* One row of the plot as runs of text, a run being the cells of one style. [styles] and
   [glyphs] hold the row a cell each. *)
let row_runs theme role ~height ~row styles glyphs =
  let buffer = Stdlib.Buffer.create (3 * Array.length styles) in
  let views = ref [] and current = ref None in
  let flush () =
    Option.iter !current ~f:(fun style ->
      views := View.text ~attrs:(attrs_of theme role ~height ~row style) (Stdlib.Buffer.contents buffer) :: !views;
      Stdlib.Buffer.clear buffer) in
  Array.iteri styles ~f:(fun x style ->
    if not ([%equal: style option] !current (Some style)) then (flush (); current := Some style);
    Stdlib.Buffer.add_string buffer glyphs.(x));
  flush ();
  List.rev !views

(* The plot proper, as rows. [no_data] says why an absent series is absent: a dashed
   box holding the reason from 3 rows up, a labelled stripe below that. A partly
   observed series labels its unobserved stretch "no data". *)
let plot_rows ~theme ~role ~now ~window ~width ~height ~low ~high ~no_data series =
  if width <= 0 || height <= 0 then []
  else (
    let fill = if height <= 1 then Line_only else fill_style theme in
    let grid = cells ~now ~window ~width ~height ~low ~high ~fill series in
    let texture = texture_attrs theme in
    let empty = Array.for_all grid ~f:(Array.for_all ~f:(fun cell -> equal_kind cell.kind No_data)) in
    let no_data = if display_width no_data <= width then no_data else "no data" in
    if empty && height >= 3 && width >= display_width no_data + 4 then
      List.init height ~f:(fun row ->
        let edge left fill_char right = View.text ~attrs:texture
            (left ^ repeat fill_char (width - 2) ^ right) in
        if row = 0 then edge "┌" "╌" "┐"
        else if row = height - 1 then edge "└" "╌" "┘"
        else if row = height / 2 then
          View.hcat [ View.text ~attrs:texture "╎"
                    ; View.text ~attrs:(Theme.attrs theme Text) (centred ~width:(width - 2) no_data)
                    ; View.text ~attrs:texture "╎" ]
        else edge "╎" " " "╎")
    else (
      (* The unobserved stretch is a sparse dot grid: present, but quieter than data. *)
      let styles = Array.map grid ~f:(Array.map ~f:(fun cell -> Cell cell.kind)) in
      let glyphs = Array.mapi grid ~f:(fun row cells -> Array.mapi cells ~f:(fun column cell ->
          match cell.kind with
          | No_data -> if (row + column) land 1 = 0 then "·" else " "
          | Blank | Fill | Line -> glyph cell)) in
      let start, gap = widest_gap grid in
      let label = if empty then no_data else "no data" in
      (* Breathing room each side of the label when the stretch is wide enough. *)
      let label = if gap >= display_width label + 4 then " " ^ label ^ " " else label in
      let size = display_width label in
      if gap >= size + 2 || (gap >= size && empty) then (
        let row = (height - 1) / 2 and column = start + ((gap - size) / 2) in
        List.iteri (code_points label) ~f:(fun i point ->
          styles.(row).(column + i) <- Label;
          glyphs.(row).(column + i) <- point));
      List.init height ~f:(fun row ->
        View.hcat (row_runs theme role ~height ~row styles.(row) glyphs.(row)))))

(* [width] x [height] cells in all: y labels and rule, then the plot. [gutter] lets
   stacked charts share one label column so their time axes line up. *)
let plot ~theme ~role ~now ?(window = window) ?(no_data = "no data") ?gutter:forced ~width ~height
    ~low ~high ~format series =
  let width = Int.max 0 width and height = Int.max 0 height in
  let gutter = Option.value forced ~default:(gutter ~width ~height ~low ~high ~format) in
  let gutter = if width - gutter < 4 || height < 2 then 0 else gutter in
  let labels = if gutter = 0 then [] else y_labels ~height ~low ~high ~format in
  let muted = Theme.attrs theme Muted in
  let rule row =
    match List.Assoc.find labels row ~equal:Int.equal with
    | Some label -> View.text ~attrs:muted (String.pad_left label ~len:(gutter - 1) ^ "┤")
    | None -> View.text ~attrs:muted (String.make (gutter - 1) ' ' ^ "│") in
  let body = plot_rows ~theme ~role ~now ~window ~width:(width - gutter) ~height ~low ~high ~no_data series in
  View.vcat (List.mapi body ~f:(fun row view ->
    if gutter = 0 then view else View.hcat [ rule row; view ]))

(* "-60s ──── -30s ──── now" under [width - gutter] plot columns; fewer labels as it narrows. *)
let time_axis ~theme ?(window = window) ~gutter ~width () =
  let width = Int.max 0 (width - gutter) in
  let seconds = Float.iround_nearest_exn (Time_ns.Span.to_sec window) in
  let oldest = sprintf "−%ds" seconds and middle = sprintf "−%ds" (seconds / 2) and newest = "now" in
  let wide text = display_width text in
  let rule n = repeat "─" n in
  let line =
    if width >= wide oldest + wide middle + wide newest + 8 then (
      let before = ((width - wide middle) / 2) - wide oldest - 2 in
      let after = width - wide oldest - 1 - before - 1 - wide middle - 1 - 1 - wide newest in
      oldest ^ " " ^ rule before ^ " " ^ middle ^ " " ^ rule after ^ " " ^ newest)
    else if width >= wide oldest + wide newest + 3 then
      oldest ^ " " ^ rule (width - wide oldest - wide newest - 2) ^ " " ^ newest
    else if width >= wide newest then rule (width - wide newest) ^ newest
    else rule width in
  let corner = if gutter = 0 then "" else String.make (gutter - 1) ' ' ^ "└" in
  View.text ~attrs:(Theme.attrs theme Muted) (corner ^ line)
