open! Core
open Bonsai_term

(* Decision rate, admit ratio and trace loss over the last 60 s, one braille area chart
   each. Wide panels set the three side by side, tall narrow ones stack them, short ones
   fall back to one inline sparkline per metric. Every layout fills the rect it is given. *)

type metric =
  { label : string; short : string; role : Theme.role; series : Metrics_state.series
  ; summary : Metrics_state.summary option  (* of [series], found once *)
  ; low : float; high : float
  ; number : float -> string  (* a value without its unit, for min/max and axes *)
  ; unit : string
  ; absent : string  (* why nothing is plotted *)
  ; connected : bool
  ; undefined : string  (* why the newest interval has no value, in a few words *)
  ; undefined_long : string }

let display_width = Braille_chart.display_width
let spaces = Braille_chart.spaces
let pad_right = Braille_chart.pad_right
let pad_left = Braille_chart.pad_left

let fit_parts = Braille_chart.fit_parts

let rate_number value =
  if Float.(value >= 10_000.) then sprintf "%.1fk" (value /. 1000.) else sprintf "%.1f" value

let metrics_of (t : Metrics_state.t) =
  let connected = Metrics_state.connected t in
  let collecting = if connected then "no data · collecting" else "no data · stream lost" in
  let rate ~label ~short ~role ~(summary : Metrics_state.summary option) series =
    let peak = Option.value_map summary ~default:1. ~f:(fun summary -> Float.max 1. summary.max) in
    (* A little headroom keeps a steady rate off the top edge; an idle series keeps 0..1. *)
    let high = if Float.(peak <= 1.) then 1. else Braille_chart.nice_ceiling (peak *. 1.1) in
    { label; short; role; series; summary; low = 0.; high
    ; number = rate_number; unit = "/s"; absent = collecting; connected
    ; undefined = (if connected then "no sample" else "stream lost")
    ; undefined_long = (if connected then "no sample in the newest interval" else "stream lost") } in
  let decisions = Metrics_state.decisions_per_second t and loss = Metrics_state.trace_loss_per_second t
  and ratio = Metrics_state.admit_ratio t in
  let loss_summary = Metrics_state.summarize loss in
  let lossy = Option.value_map loss_summary ~default:false ~f:(fun summary -> Float.(summary.max > 0.)) in
  let no_outcomes = connected && not (List.is_empty ratio) in
  [ rate ~label:"decisions/s" ~short:"dec/s" ~role:Info ~summary:(Metrics_state.summarize decisions) decisions
  ; { label = "admit ratio"; short = "admit"; role = Bid; series = ratio
    ; summary = Metrics_state.summarize ratio; low = 0.; high = 1.
    ; number = sprintf "%.2f"; unit = ""; connected
    ; absent = (if no_outcomes then "no data · no outcomes yet" else collecting)
    ; undefined = (if connected then "no outcomes" else "stream lost")
    ; undefined_long =
        (if connected
         then sprintf "no outcomes in the last %.0f s" (Time_ns.Span.to_sec Metrics_state.sample_period)
         else "stream lost") }
  ; rate ~label:"trace loss/s" ~short:"loss/s" ~role:(if lossy then Warn else Muted) ~summary:loss_summary loss ]

type current = Now of float | Undefined of string

let current metric =
  match metric.summary with
  | None -> Undefined metric.absent
  | Some { last = Some value; _ } -> Now value
  | Some { last = None; _ } -> Undefined metric.undefined

(* "now" is the newest one-second interval. When it has no value but older ones do, the
   value slot says why in a few words rather than a bare dash beside a known min and max. *)
let value_text metric = function
  | Now value -> metric.number value ^ metric.unit
  | Undefined _ ->
    if Option.is_some metric.summary then metric.undefined
    else if metric.connected then "—" else "unknown"

(* "min 3.0 · max 14.8", then the full reason the newest value is missing, if it is. *)
let stats_parts metric =
  Option.value_map metric.summary ~default:[] ~f:(fun { min; max; _ } ->
    [ "min " ^ metric.number min; "max " ^ metric.number max ]
    @ match current metric with Undefined _ -> [ "now: " ^ metric.undefined_long ] | Now _ -> [])

let text theme role value = View.text ~attrs:(Theme.attrs theme role) value
let bold theme role value = View.text ~attrs:(Theme.attrs theme role @ [ Attr.bold ]) value

let plot ~theme ~anchor ?gutter ~width ~height metric =
  let no_data =
    if Option.is_some metric.summary then "no data" else metric.absent in
  Braille_chart.plot ~theme ~role:metric.role ~now:anchor ?gutter ~no_data ~width ~height
    ~low:metric.low ~high:metric.high ~format:Braille_chart.compact metric.series

(* Label left, bold value right; the stats below. Two rows, [width] wide. *)
let header ~theme ~width metric =
  let now = current metric in
  let value = value_text metric now in
  let label = if display_width metric.label + display_width value + 1 <= width then metric.label else metric.short in
  let gap = width - display_width label - display_width value in
  [ View.hcat [ text theme Text label; text theme Text (spaces gap)
              ; (match now with Now _ -> bold theme metric.role value | Undefined _ -> text theme Muted value) ]
  ; text theme Muted (fit_parts ~width (stats_parts metric)) ]

let notes ~theme ~connected ~width ~rows =
  let window = "60 s window · sampled 1 Hz" and definition = "admit ratio = admitted ÷ (admitted + blocked)" in
  let first = if connected then text theme Muted window else text theme Warn "no stream: rates unknown" in
  if rows <= 0 then []
  else if rows = 1 then
    [ (if connected && width >= display_width (window ^ " · " ^ definition)
       then text theme Muted (window ^ " · " ^ definition) else first) ]
  else [ first; text theme Muted definition ]

let side_by_side ~theme ~anchor ~metrics ~width ~height ~connected =
  let column_width = (width - 4) / 3 in
  let widths = [ column_width; column_width; width - 4 - (2 * column_width) ] in
  let note_rows = if height - 4 >= 6 then 1 else 0 in
  let plot_rows = height - 3 - note_rows in
  let column metric ~width =
    let gutter = Braille_chart.gutter ~width ~height:plot_rows ~low:metric.low ~high:metric.high
        ~format:Braille_chart.compact in
    View.vcat (header ~theme ~width metric
               @ [ plot ~theme ~anchor ~gutter ~width ~height:plot_rows metric
                 ; Braille_chart.time_axis ~theme ~gutter ~width () ]) in
  let columns = List.map2_exn metrics widths ~f:(fun metric width -> column metric ~width) in
  [ View.hcat (List.mapi columns ~f:(fun i view -> if i = 0 then view else View.pad ~l:2 view)) ]
  @ notes ~theme ~connected ~width ~rows:note_rows

let stacked ~theme ~anchor ~metrics ~width ~height ~connected =
  let note_rows = if height >= 14 then 2 else if height >= 12 then 1 else 0 in
  let available = height - 3 - 1 - note_rows in
  let heights = List.init 3 ~f:(fun i -> (available / 3) + if i < available mod 3 then 1 else 0) in
  let gutter = List.fold2_exn metrics heights ~init:0 ~f:(fun gutter metric height ->
      Int.max gutter (Braille_chart.gutter ~width ~height ~low:metric.low ~high:metric.high ~format:Braille_chart.compact)) in
  let blocks = List.map2_exn metrics heights ~f:(fun metric plot_height ->
      let now = current metric in
      let head = View.hcat
          [ text theme Text (metric.label ^ " ")
          ; (match now with Now _ -> bold theme metric.role (value_text metric now)
                          | Undefined _ -> text theme Muted (value_text metric now))
          ; text theme Muted (let used = display_width metric.label + 1 + display_width (value_text metric now) in
                              let parts = fit_parts ~width:(width - used - 3) (stats_parts metric) in
                              if String.is_empty parts then "" else "  " ^ parts) ] in
      View.vcat [ head; plot ~theme ~anchor ~gutter ~width ~height:plot_height metric ]) in
  blocks @ [ Braille_chart.time_axis ~theme ~gutter ~width () ]
  @ notes ~theme ~connected ~width ~rows:note_rows

(* One row per metric: label, bold value, inline sparkline, then min/max under a
   "min–max" caption on the time-axis row when there is a row for it. *)
let inline ~theme ~anchor ~metrics ~width ~height ~connected =
  let long = width >= 56 in
  let label metric = if long then metric.label else metric.short in
  let label_width = List.fold metrics ~init:0 ~f:(fun w metric -> Int.max w (display_width (label metric))) in
  let value_width = List.fold metrics ~init:0 ~f:(fun w metric ->
      Int.max w (display_width (value_text metric (current metric)))) in
  let range metric = match metric.summary with
    | None -> "" | Some { min; max; _ } ->
      if long then sprintf "min %s · max %s" (metric.number min) (metric.number max)
      else sprintf "%s–%s" (metric.number min) (metric.number max) in
  let range_width = List.fold metrics ~init:0 ~f:(fun w metric -> Int.max w (display_width (range metric))) in
  let prefix = label_width + 1 + value_width + 1 in
  let with_range = width - prefix - range_width - 1 >= 12 in
  let spark_width = Int.max 0 (width - prefix - if with_range then range_width + 1 else 0) in
  let rows = List.map metrics ~f:(fun metric ->
      let now = current metric in
      View.hcat
        ([ text theme Text (pad_right (label metric) ~width:label_width); text theme Text " "
         ; (match now with
             | Now _ -> bold theme metric.role (pad_left (value_text metric now) ~width:value_width)
             | Undefined _ -> text theme Muted (pad_left (value_text metric now) ~width:value_width))
         ; text theme Text " "; plot ~theme ~anchor ~width:spark_width ~height:1 metric ]
         @ if with_range then [ text theme Text " "; text theme Muted (range metric) ] else [])) in
  let axis =
    View.hcat ([ Braille_chart.time_axis ~theme ~gutter:prefix ~width:(prefix + spark_width) () ]
               @ if with_range then [ text theme Muted (" " ^ if long then "min · max" else "min–max") ] else []) in
  rows @ [ axis ] @ notes ~theme ~connected ~width ~rows:(height - 4)

type layout = Side_by_side | Stacked | Inline [@@deriving sexp_of]

(* Three charts across need 66 inner columns, which split 20, 20 and 22 around two 2-column
   gaps, and a few rows; three stacked need two rows each beside their headers; anything
   shorter gets one inline row per metric. *)
let layout_for ~width ~height =
  let inner_width = Int.max 0 (width - 4) and inner_height = Int.max 0 (height - 2) in
  if inner_width >= 66 && inner_height >= 6 then Side_by_side
  else if inner_height >= 10 then Stacked
  else Inline

let view ~theme ~focus ~(metrics : Metrics_state.t) ~now ~width ~height =
  let inner_width = Int.max 0 (width - 4) and inner_height = Int.max 0 (height - 2) in
  let connected = Metrics_state.connected metrics in
  (* The right edge is the newest sample while the stream is fresh, so the chart steps
     once a second rather than creeping; a stale stream falls back to the clock and
     shows its growing no-data stretch. *)
  let anchor = match Metrics_state.newest metrics with
    | Some newest when Time_ns.Span.(Time_ns.diff now newest <= of_sec 2.5) -> newest
    | Some _ | None -> now in
  let series = metrics_of metrics in
  let layout = match layout_for ~width ~height with
    | Side_by_side -> side_by_side | Stacked -> stacked | Inline -> inline in
  let body = layout ~theme ~anchor ~metrics:series ~width:inner_width ~height:inner_height ~connected in
  Panel.framed ~theme ~focus ~panel:Metrics ~title:("Metrics · " ^ Status_bar.mode_name metrics.mode)
    ~width ~height (View.vcat body)
