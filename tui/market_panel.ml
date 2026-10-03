open! Core
open Bonsai_term
open Model_adapter

let quantity_bar ~quantity ~maximum ~width =
  let width = Int.max 0 width in
  if quantity <= 0 || maximum <= 0 then String.make width ' '
  else (
    let eighths = Float.of_int quantity /. Float.of_int maximum *. Float.of_int (width * 8)
        |> Float.to_int |> Int.max 1 |> Int.min (width * 8) in
    let full = eighths / 8 and part = eighths mod 8 in
    let fractions = [| ""; "▏"; "▎"; "▍"; "▌"; "▋"; "▊"; "▉" |] in
    String.concat (List.init full ~f:(fun _ -> "█")) ^ fractions.(part)
    ^ String.make (Int.max 0 (width - full - (if part = 0 then 0 else 1))) ' ')

let metrics (snapshot : snapshot) =
  match List.hd snapshot.bids, List.hd snapshot.asks with
  | Some bid, Some ask when snapshot.valid ->
    (* Two OCaml ints sum/differ exactly in int64; this is display arithmetic,
       not an inferred wire width. Preserve integer ticks above float precision. *)
    let module I = Stdlib.Int64 in
    let spread = I.sub (I.of_int ask.price_ticks) (I.of_int bid.price_ticks) |> I.to_string in
    let mid = Market_motion.mid_text ~bid:bid.price_ticks ~ask:ask.price_ticks in
    let total = Float.of_int bid.quantity_units +. Float.of_int ask.quantity_units in
    let imbalance = if Float.(total <= 0.) then None else
        Some ((Float.of_int bid.quantity_units -. Float.of_int ask.quantity_units) /. total) in
    sprintf "spread %s t   mid %s t" spread mid,
    Option.value_map imbalance ~default:"imbalance —" ~f:(fun value ->
      sprintf "imbalance %+.2f %s" value (if Float.(value > 0.) then "▲" else if Float.(value < 0.) then "▼" else "·"))
  | _ -> "spread —   mid —", "imbalance —"

(* Running totals from the best level outward. Saturating, so absurd quantities cannot wrap. *)
let running_totals levels =
  List.folding_map levels ~init:0 ~f:(fun total (level : level) ->
    let total = if level.quantity_units > Int.max_value - total then Int.max_value
      else total + level.quantity_units in
    total, total)

(* The enabled rule's maximum_price, only when the engine state is known and the rule really
   carries the parameter. There is no default: absent means nothing is drawn. *)
let threshold (state : application_state) =
  if equal_engine state.engine Engine_unknown then None
  else List.find_map state.rules ~f:(fun rule ->
    if not rule.enabled then None
    else List.find_map rule.parameters ~f:(fun (name, value, _) ->
        Option.some_if (String.equal name "maximum_price") value))

let dashes count = String.concat (List.init (Int.max 0 count) ~f:(fun _ -> "╌"))
let threshold_row theme ~width maximum =
  let label = sprintf " maximum_price %d t " maximum in
  let attrs = Theme.attrs theme Warn in
  let label_width = View.width (View.text label) in
  if label_width + 4 > width then View.text ~attrs (dashes width)
  else View.text ~attrs (dashes (width - label_width - 2) ^ label ^ dashes 2)

(* A chart needs its legend, its time axis and at least three rows of plot. *)
let min_chart_rows = 5

(* Room for a sign and four digits, plus the gap to the quantity column. *)
let delta_width = 6
let delta_text change =
  let sign = if change > 0 then "+" else "−" in
  let digits = String.chop_prefix_if_exists (Int.to_string change) ~prefix:"-" in
  if String.length digits <= 4 then sign ^ digits else sign ^ "…"
let delta_rgb theme ~change ~intensity =
  let role = if change > 0 then Theme.Bid else Ask in
  Theme.blend (Theme.role_rgb theme Bg) (Theme.role_rgb theme role) intensity
(* The delta column as one run of text [delta_width] cells wide. With nothing to show it takes
   [fill], the attributes of the run beside it, so that the two are one text node. *)
let delta_segment theme ~now ~bid ~live ~fill motion (level : level option) =
  let blank = fill, String.make delta_width ' ' in
  let delta = Option.bind level ~f:(fun level ->
      if live then Market_motion.delta motion ~bid level.price_ticks else None) in
  match delta with
  | None -> blank
  | Some delta ->
    let intensity = Market_motion.delta_intensity ~now delta in
    if Float.(intensity <= 0.) then blank
    else (
      let attrs = match Theme.rgb_color theme (delta_rgb theme ~change:delta.change ~intensity) with
        | Some color -> [ Attr.fg color ]
        | None -> if Float.(intensity > 0.5) then [ Attr.bold ] else [] in
      let text = delta_text delta.change in
      let room = String.make (delta_width - 1 - Braille_chart.display_width text) ' ' in
      attrs, if bid then room ^ text ^ " " else " " ^ text ^ room)

(* [cumulative] is required, not optional: every other parameter is labelled, so an
   optional argument could never be erased by a total application. *)
let view ~cumulative ~(motion : Market_motion.t) ~now
    ~theme ~focus ~(state : application_state) ~width ~height =
  let inner = Int.max 0 (width - 4) in
  let bid_width = (inner - 1) / 2 and ask_width = inner - 1 - ((inner - 1) / 2) in
  let snapshot = state.market in
  let role side = if not snapshot.valid then Theme.Muted else side in
  let separator = View.text ~attrs:(Theme.attrs theme (if snapshot.valid then Border else Muted)) "│" in
  let combine bid ask = View.hcat [ Panel.fit bid ~width:bid_width ~height:1; separator
                                 ; Panel.fit ask ~width:ask_width ~height:1 ] in
  let threshold = if snapshot.valid && not (List.is_empty snapshot.asks) then threshold state else None in
  let max_rows = Int.max 1 (height - 8 - Bool.to_int (Option.is_some threshold)) in
  let depth = Int.min 10 (Int.min max_rows (Int.max 1 (Int.max (List.length snapshot.bids) (List.length snapshot.asks)))) in
  (* Each displayed level pairs with the quantity shown for it: its own, or the running total. *)
  let shown levels =
    let levels = List.take levels depth in
    List.zip_exn levels (if cumulative then running_totals levels
                         else List.map levels ~f:(fun (level : level) -> level.quantity_units)) in
  let bids = shown snapshot.bids and asks = shown snapshot.asks in
  let displayed = bids @ asks in
  let price_width = List.fold displayed ~init:5 ~f:(fun width ((level : level), _) ->
      Int.max width (String.length (Int.to_string level.price_ticks))) in
  let qty_width = List.fold displayed ~init:6 ~f:(fun width (_, quantity) ->
      Int.max width (String.length (Int.to_string quantity))) in
  let maximum = List.fold displayed ~init:0 ~f:(fun max (_, quantity) -> Int.max max quantity) in
  (* Deltas need a column of their own, and they come before the bars: a side keeps its
     delta column down to a bar of two cells, which is every panel at 100 columns or more. *)
  let spare = if bid_width - price_width - qty_width - 2 >= delta_width + 2 then delta_width else 0 in
  let delta_column ~bid ~fill level =
    if spare = 0 then []
    else [ delta_segment theme ~now ~bid ~live:snapshot.valid ~fill motion level ] in
  let column attrs size text =
    let view = View.text ~attrs text in
    View.pad ~l:(Int.max 0 (size - View.width view)) view in
  let padded size text = String.make (Int.max 0 (size - Braille_chart.display_width text)) ' ' ^ text in
  (* A side as runs: its blanks take the attributes of the ink beside them, so a quiet row is
     one text node a side, plus one for the delta while it fades and one for a price flash. *)
  let side ~bid ~size level ~best =
    let semantic = if bid then Theme.Bid else Ask in
    let attrs = Theme.attrs theme (role semantic) in
    let bar_width = Int.max 0 (size - price_width - qty_width - 2 - spare) in
    let run ~fill ~price ~bar ~quantity ~delta =
      if bid then delta @ [ fill, quantity ^ " " ^ bar ^ " "; price ]
      else [ price; fill, " " ^ bar ^ " " ^ quantity ] @ delta in
    match level with
    | _ when price_width + qty_width + 2 > size ->
      Runs.view [ Theme.attrs theme (role Warn), "VALUE TOO WIDE" ]
    | None ->
      let muted = Theme.attrs theme Muted in
      let price = muted, padded price_width "—" in
      Runs.view (run ~fill:muted ~price ~bar:(String.make bar_width ' ') ~quantity:(padded qty_width "—")
                   ~delta:(delta_column ~bid ~fill:muted None))
    | Some ((level : level), shown_quantity) ->
      let intensity = if not snapshot.valid || not best then 0. else
          Market_motion.flash_intensity ~now (if bid then motion.bid_changed_at else motion.ask_changed_at) in
      let price = attrs @ Theme.flash_attrs theme semantic ~intensity, padded price_width (Int.to_string level.price_ticks) in
      Runs.view (run ~fill:attrs ~price ~bar:(quantity_bar ~quantity:shown_quantity ~maximum ~width:bar_width)
                   ~quantity:(padded qty_width (Int.to_string shown_quantity))
                   ~delta:(delta_column ~bid ~fill:attrs (Some level))) in
  let header ~bid size =
    let attrs = Theme.attrs theme (role (if bid then Bid else Ask)) in
    let overflow = price_width + qty_width + 2 > size in
    let middle = Int.max 0 (size - price_width - qty_width - 2 - spare) in
    let qty = column attrs qty_width (if cumulative then "cum(u)" else "qty(u)")
    and px = column attrs price_width "px(t)" in
    let label = Panel.fit (View.text ~attrs (if bid then "BID" else "ASK")) ~width:middle ~height:1 in
    let outer = View.text (String.make spare ' ') in
    if overflow then View.text ~attrs "qty/px overflow"
    else if bid then View.hcat [ outer; qty; View.text " "; label; View.text " "; px ]
    else View.hcat [ px; View.text " "; label; View.text " "; qty; outer ] in
  let ladder = List.init depth ~f:(fun row ->
    combine (side ~bid:true ~size:bid_width (List.nth bids row) ~best:(row = 0))
      (side ~bid:false ~size:ask_width (List.nth asks row) ~best:(row = 0))) in
  (* The rule admits asks at or below the threshold: the line goes below the last such ask. *)
  let ladder = match threshold with
    | None -> ladder
    | Some maximum ->
      let buyable = List.take_while asks ~f:(fun ((level : level), _) -> level.price_ticks <= maximum) in
      let above = List.length buyable in
      List.take ladder above @ (threshold_row theme ~width:inner maximum :: List.drop ladder above) in
  let spread, imbalance = metrics snapshot in
  let spread = if View.width (View.text spread) <= inner then spread
      else "spread / mid exceed panel width" in
  let missing = match snapshot.bids, snapshot.asks with
    | [], [] -> "BOOK EMPTY" | [], _ -> "BID EMPTY" | _, [] -> "ASK EMPTY" | _ -> "" in
  let info = Theme.attrs theme Muted in
  (* The rows the ladder leaves free go to a price chart. Too few for one and the ask keeps
     its single sparkline row. *)
  let free = height - 2 - (2 + List.length ladder + 3) in
  let history =
    if free >= min_chart_rows then
      [ Market_chart.view ~theme ~samples:motion.samples ~now ~threshold ~width:inner ~height:free ]
    else (
      let spark = Sparkline.ask ~samples:motion.samples ~now ~width:(Int.max 0 (inner - 13)) in
      [ View.text ~attrs:(Theme.attrs theme (role Ask)) ("ask " ^ spark ^ " last 60s") ]) in
  let body = View.vcat
      ([ View.text ~attrs:info (if cumulative then "px (t) · cumulative qty (u)" else "px (t) · qty (u)")
       ; combine (header ~bid:true bid_width) (header ~bid:false ask_width) ]
       @ ladder
       @ [ View.text ~attrs:info (spread ^ if String.is_empty missing then "" else " · " ^ missing)
         ; View.text ~attrs:info imbalance ]
       @ history
       @ [ View.text ~attrs:info (sprintf "%s #%d  updates/s %.1f"
               (Status_bar.mode_name state.mode) state.updates (Market_motion.updates_per_second motion ~now)) ]) in
  let body = if snapshot.valid then body else
      let stamp_text = View.text ~attrs:(Theme.attrs theme Warn @ [ Attr.bold ])
          "BOOK INVALID — candidates suppressed" in
      let stamp_body = View.zcat
          [ View.center stamp_text ~within:{ width = Int.max 0 (inner - 2); height = 1 }
          ; View.rectangle ~width:(Int.max 0 (inner - 2)) ~height:1 () ] in
      let stamp = stamp_body |> Bonsai_term_border_box.view ~line_type:Round_corners
             ~attrs:(Theme.attrs theme Warn) ~left_padding:0 ~right_padding:0 in
      View.zcat [ View.center stamp ~within:{ width = inner; height = Int.max 0 (height - 2) }
                ; Panel.fit body ~width:inner ~height:(Int.max 0 (height - 2)) ] in
  Panel.frame ~muted:(not snapshot.valid) ~theme ~focus ~panel:Market
    ~title:("Market · " ^ snapshot.instrument) ~width ~height body

