open! Core
open Bonsai_term
open Model_adapter

(* MOCK only. application_state carries no snapshot→candidate timestamps, so this panel
   plots a seeded synthetic distribution (a floor plus a lognormal tail, in ns) and says
   so. In SIM and HW modes it shows nothing rather than invent a measurement. *)

let seed = 42
let count = 2000

let samples ~seed ~count =
  let random = Stdlib.Random.State.make [| seed |] in
  let gaussian () =
    let u1 = 1. -. Stdlib.Random.State.float random 1. in
    let u2 = Stdlib.Random.State.float random 1. in
    Float.sqrt (-2. *. Float.log u1) *. Float.cos (2. *. Float.pi *. u2) in
  List.init count ~f:(fun _ ->
    180 + Float.iround_nearest_exn (Float.exp (4. +. 0.55 *. gaussian ())))

type histogram = { counts : int array; low : int; high : int }

(* The bin of [ns] among [bins] equal bins spanning [low, high]: the fastest sample is
   in the first bin, the slowest in the last. *)
let bin_of ~low ~high ~bins ns =
  let bin = if high <= low then 0 else (ns - low) * bins / (high - low) in
  Int.max 0 (Int.min (bins - 1) bin)

(* Bins span the fastest to the slowest sample, so p99 sits inside the chart and the tail
   is drawn to its right, not folded into the last bin. *)
let histogram ~bins samples =
  let low = Option.value_exn (List.min_elt samples ~compare:Int.compare)
  and high = Option.value_exn (List.max_elt samples ~compare:Int.compare) in
  let counts = Array.create ~len:bins 0 in
  List.iter samples ~f:(fun ns ->
    let bin = bin_of ~low ~high ~bins ns in
    counts.(bin) <- counts.(bin) + 1);
  { counts; low; high }

let blocks = [| " "; "▁"; "▂"; "▃"; "▄"; "▅"; "▆"; "▇"; "█" |]

(* [rows] lines of eighth-blocks, top first, one string per cell; a non-empty bin
   always shows at least ▁. *)
let chart_cells ~rows counts =
  let peak = Int.max 1 (Array.fold counts ~init:0 ~f:Int.max) in
  List.init rows ~f:(fun row ->
    Array.map counts ~f:(fun bin ->
      let eighths = (bin * rows * 8 + peak - 1) / peak in
      blocks.(Int.max 0 (Int.min 8 (eighths - 8 * (rows - 1 - row))))))
let chart ~rows counts = List.map (chart_cells ~rows counts) ~f:String.concat_array

let synthetic = samples ~seed ~count

let percentiles =
  let sorted = Array.of_list_map synthetic ~f:Float.of_int in
  Array.sort sorted ~compare:Float.compare;
  let at p = Float.to_int (Option.value_exn (Metrics_state.percentile sorted ~p)) in
  at 50., at 99., at 100.

(* What a cell shows: the body, the tail past p99, or a percentile marker. A marker
   recolours its bin's bar and rises above it as a dotted guide; a one-row chart has no
   room above the bar, so there the marker is a rule. *)
type mark = Body | Tail | P50 | P99 [@@deriving equal, sexp_of]

let marked ~rows ~p50 ~p99 counts =
  List.map (chart_cells ~rows counts) ~f:(fun glyphs ->
    Array.mapi glyphs ~f:(fun bin glyph ->
      let mark = if bin = p50 then P50 else if bin = p99 then P99 else if bin > p99 then Tail else Body in
      match mark with
      | (P50 | P99) when rows = 1 -> mark, "│"
      | (P50 | P99) when String.equal glyph " " -> mark, "╎"
      | Body | Tail | P50 | P99 -> mark, glyph))

type label = { variants : string list; start : int; role : Theme.role }
type placed = { text : string; column : int; colour : Theme.role }

(* Greedy and in priority order. A label takes the longest of its variants that fits at
   the nearest free column to its marker, trying the marker itself, then one cell right,
   one left, and so on; if nothing fits it is dropped, and its number is still in the
   title row when that fits. *)
let place ~width labels =
  List.fold labels ~init:[] ~f:(fun placed label ->
    let clear text column =
      let length = String.length text in
      column >= 0 && column + length <= width
      && List.for_all placed ~f:(fun other ->
        column >= other.column + String.length other.text + 1 || other.column >= column + length + 1) in
    let shifts = List.concat_map (List.range 0 12) ~f:(fun d -> if d = 0 then [ 0 ] else [ d; -d ]) in
    let found = List.find_map label.variants ~f:(fun text ->
        List.find_map shifts ~f:(fun shift ->
          Option.some_if (clear text (label.start + shift)) (text, label.start + shift))) in
    match found with
    | Some (text, column) -> { text; column; colour = label.role } :: placed
    | None -> placed)
  |> List.sort ~compare:(fun a b -> Int.compare a.column b.column)

let label_row ~theme ~width placed =
  let segments, used = List.fold placed ~init:([], 0) ~f:(fun (views, used) label ->
    views @ [ View.text (String.make (label.column - used) ' ')
            ; View.text ~attrs:(Theme.attrs theme label.colour) label.text ],
    label.column + String.length label.text) in
  View.hcat (segments @ [ View.text (String.make (Int.max 0 (width - used)) ' ') ])

let mark_attrs theme = function
  | Body -> Theme.attrs theme Info
  | Tail -> Braille_chart.fill_attrs theme Warn ~strength:0.7
  | P50 -> Theme.attrs theme Bid @ [ Attr.bold ]
  | P99 -> Theme.attrs theme Warn @ [ Attr.bold ]

let bar_rows ~theme rows =
  List.map rows ~f:(fun cells ->
    let runs = Array.fold cells ~init:[] ~f:(fun runs (mark, glyph) ->
        match runs with
        | (previous, text) :: rest when equal_mark previous mark -> (mark, text ^ glyph) :: rest
        | _ -> (mark, glyph) :: runs) in
    View.hcat (List.rev_map runs ~f:(fun (mark, text) -> View.text ~attrs:(mark_attrs theme mark) text)))

(* A rule with ticks at both ends and a tick under each marker. *)
let ruler ~theme ~width ~p50 ~p99 =
  let cells = Array.init width ~f:(fun i ->
      if i = p50 then P50, "┴" else if i = p99 then P99, "┴"
      else if i = 0 then Body, "├" else if i = width - 1 then Body, "┤" else Body, "─") in
  let runs = Array.fold cells ~init:[] ~f:(fun runs (mark, glyph) ->
      match runs, mark with
      | (Body, text) :: rest, Body -> (Body, text ^ glyph) :: rest
      | _ -> (mark, glyph) :: runs) in
  View.hcat (List.rev_map runs ~f:(fun (mark, text) ->
    View.text ~attrs:(match mark with Body -> Theme.attrs theme Muted | mark -> mark_attrs theme mark) text))

(* The percentile summary, whole parts only, for the title row. *)
let summary ~width ~p50 ~p99 ~maximum =
  List.fold [ "snapshot→candidate latency, ns"; sprintf "n=%d" count; sprintf "p50 %d ns" p50
            ; sprintf "p99 %d ns" p99; sprintf "max %d ns" maximum ] ~init:"" ~f:(fun line part ->
    let joined = if String.is_empty line then part else line ^ " · " ^ part in
    if Braille_chart.display_width joined <= width then joined else line)

(* The disclaimer, whole when it fits. Narrower, it wraps if a row can be spared, and only
   then falls back to shorter wordings that still say synthetic and not hardware. *)
let mock_lines ~width ~rows =
  let full = sprintf "MOCK synthetic, seed %d: not a hardware measurement" seed in
  let fits text = String.length text <= width in
  if fits full then [ full ]
  else if rows >= 7 && fits "not a hardware measurement" then [ sprintf "MOCK synthetic, seed %d:" seed; "not a hardware measurement" ]
  else
    Option.value (List.find [ sprintf "MOCK synthetic, seed %d: not hardware" seed; "MOCK synthetic: not hardware"
                            ; "MOCK synthetic" ] ~f:fits) ~default:"MOCK"
    |> fun text -> [ text ]

let view ~theme ~focus ~(state : application_state) ~width ~height =
  let attrs role = Theme.attrs theme role in
  let frame ~muted ~title lines =
    Panel.frame ~muted ~theme ~focus ~panel:Latency ~title ~width ~height (View.vcat lines) in
  match state.mode with
  | Simulation | Hardware ->
    frame ~muted:true ~title:("Latency · " ^ Status_bar.mode_name state.mode)
      [ View.text ~attrs:(attrs Muted) "no timestamps: snapshot→candidate latency is not"
      ; View.text ~attrs:(attrs Muted) "carried by application_state, so none is shown." ]
  | Mock ->
    let inner = Int.max 0 (width - 4) and rows = Int.max 0 (height - 2) in
    let p50, p99, maximum = percentiles in
    (* From 6 rows: title, histogram, ruler, labels, MOCK line. Below that the ruler,
       then the title, then the labels go, until one line of histogram with its
       range at both ends is left beside the MOCK line. *)
    let with_title = rows >= 4 and with_ruler = rows >= 6 and with_labels = rows >= 3 in
    let mock = if rows >= 2 then mock_lines ~width:inner ~rows else [] in
    let chart_rows = Int.max 1 (rows - Bool.to_int with_title - Bool.to_int with_ruler
                                - Bool.to_int with_labels - List.length mock) in
    let ends_inline = not with_labels in
    let range_text value = sprintf "%d ns" value in
    let bins = if ends_inline then inner - 14 else inner in
    let { counts; low; high } = histogram ~bins:(Int.max 1 bins) synthetic in
    let bin value = bin_of ~low ~high ~bins:(Int.max 1 bins) value in
    let p50_bin = bin p50 and p99_bin = bin p99 in
    let bars = bar_rows ~theme (marked ~rows:chart_rows ~p50:p50_bin ~p99:p99_bin counts) in
    let bars =
      if ends_inline && bins >= 8 then
        List.mapi bars ~f:(fun i row ->
          if i = 0 then
            View.hcat [ View.text ~attrs:(attrs Muted) (range_text low ^ " "); row
                      ; View.text ~attrs:(attrs Muted) (" " ^ range_text high) ]
          else row)
      else bars in
    let labels =
      [ { variants = [ range_text low ]; start = 0; role = Muted }
      ; { variants = [ range_text high ]; start = inner - String.length (range_text high); role = Muted }
      ; { variants = [ sprintf "p99 %d ns" p99; sprintf "p99 %d" p99 ]; start = p99_bin; role = Warn }
      ; { variants = [ sprintf "p50 %d ns" p50; sprintf "p50 %d" p50 ]; start = p50_bin; role = Bid } ] in
    frame ~muted:false ~title:"Latency · MOCK synthetic"
      ((if with_title then [ View.text ~attrs:(attrs Text) (summary ~width:inner ~p50 ~p99 ~maximum) ] else [])
       @ bars
       @ (if with_ruler then [ ruler ~theme ~width:inner ~p50:p50_bin ~p99:p99_bin ] else [])
       @ (if with_labels then [ label_row ~theme ~width:inner (place ~width:inner labels) ] else [])
       @ List.map mock ~f:(View.text ~attrs:(attrs Warn)))
