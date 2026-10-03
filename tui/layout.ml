open! Core
open Ui_types

(* The terminal is a header row, the body and a footer row. [compute] places panels in
   the body only; everything here is pure so the renderer, focus cycling and mouse
   hit-testing all read one answer. *)
let header_rows = 1
let footer_rows = 1
let min_width = 100
let min_height = 30
let body_height ~height = Int.max 0 (height - header_rows - footer_rows)

(* From 160x45 up there is room to give the Decide preset a third column and Monitor a wider
   heatmap. *)
let wide ~width ~height = width >= 160 && height >= 45

type tree = Panel of panel_id | Row of (int * tree) list | Column of (int * tree) list
[@@deriving equal]

(* [split total weights] shares [total] cells in proportion to [weights]. Sizes always sum
   to [total], so tiles leave neither gaps nor overlaps. *)
let split total weights =
  let sum = List.sum (module Int) weights ~f:Fn.id in
  let edges = List.folding_map weights ~init:0 ~f:(fun acc weight ->
    let acc = acc + weight in
    acc, total * acc / sum) in
  List.map2_exn (0 :: List.drop_last_exn edges) edges ~f:(fun start stop -> stop - start)

(* The children of a Row or Column with the rectangle each one fills. *)
let children_rects children (r : rect) ~horizontal =
  let total = if horizontal then r.width else r.height in
  let sizes = split total (List.map children ~f:fst) in
  let starts = List.folding_map sizes ~init:0 ~f:(fun start size -> start + size, start) in
  List.map3_exn children sizes starts ~f:(fun (_, child) size start ->
    child, if horizontal then { r with col = r.col + start; width = size }
           else { r with row = r.row + start; height = size })

let rec place tree (r : rect) =
  match tree with
  | Panel panel -> [ panel, r ]
  | Row children ->
    List.concat_map (children_rects children r ~horizontal:true) ~f:(fun (child, r) -> place child r)
  | Column children ->
    List.concat_map (children_rects children r ~horizontal:false) ~f:(fun (child, r) -> place child r)

(* Monitor: the market on top, and under it one band that reads left to right as the
   system's own numbers (Metrics), its timing (Latency) and what the book printed (Tape). *)
let monitor ~wide ~(toggles : market_toggles) =
  let top = match toggles.heatmap, wide with
    | false, _ -> Panel Market
    | true, false -> Row [ 1, Panel Market; 1, Panel Heatmap ]
    | true, true -> Row [ 2, Panel Market; 3, Panel Heatmap ] in
  Column [ 3, top; 2, Row [ 5, Panel Metrics; 4, Panel Latency; 4, Panel Tape ] ]

(* Decisions is the widest panel from 120 columns: it gets 70 there, enough for the
   comparison and config columns of [Decision_row]. Under 120 the Inspector keeps the wider
   share it needs to show every frozen field without clipping. *)
let decide ~wide ~width =
  if wide then Row [ 44, Panel Decisions; 31, Panel Inspector; 25, Panel Rules ]
  else if width >= 120 then Row [ 7, Panel Decisions; 5, Column [ 3, Panel Inspector; 2, Panel Rules ] ]
  else Row [ 9, Panel Decisions; 11, Column [ 1, Panel Rules; 2, Panel Inspector ] ]

(* Configure: the rules and the configuration beside each other, each with a full column of
   room for its parameter bars, ACK timeline and rule statistics, and the live decisions under
   them, so a change applied above shows in the config version column of the rows below. *)
let configure ~wide =
  Column [ (if wide then 5 else 3), Row [ 1, Panel Rules; 1, Panel Configuration ]
         ; (if wide then 4 else 2), Panel Decisions ]

(* Every step of the judges' script on one screen: header (mode, build, armed state),
   Configuration (review, apply, ACK), Decisions and Inspector (candidate, admission,
   receipt, blocked reason), Rules, and Metrics with Latency (timing, trace loss). *)
let demo ~wide =
  if wide then
    Row [ 34, Column [ 4, Panel Market; 5, Panel Decisions ]
        ; 33, Column [ 5, Panel Inspector; 4, Panel Rules ]
        ; 33, Column [ 3, Panel Configuration; 4, Panel Metrics; 3, Panel Latency ] ]
  else
    Row [ 1, Column [ 7, Panel Market; 4, Panel Decisions; 3, Panel Metrics ]
        ; 1, Column [ 3, Panel Rules; 4, Panel Inspector; 3, Panel Configuration; 2, Panel Latency ] ]

let tree ~preset ~toggles ~wide ~width =
  match preset with
  | Monitor -> monitor ~wide ~toggles
  | Decide -> decide ~wide ~width
  | Configure -> configure ~wide
  | Demo -> demo ~wide

(* A tiling of the body. Layout is a pure function of the preset, zoom, toggles and size,
   so the reducer, the renderer and mouse hit-testing cannot disagree about it, and a
   consumer can cut off on [equal] instead of re-deriving it. *)
type t = { tree : tree; body : rect } [@@deriving equal]

(* [width] and [height] are the body. Smaller than the minimum terminal's body there is no
   layout at all, and the caller shows the resize message. A zoom on a panel the preset
   does not show is ignored. *)
let create ~preset ~zoom ~toggles ~width ~height =
  if width < min_width || height < min_height - header_rows - footer_rows then None
  else (
    let body = { col = 0; row = 0; width; height } in
    let terminal_height = height + header_rows + footer_rows in
    let tree = tree ~preset ~toggles ~wide:(wide ~width ~height:terminal_height) ~width in
    match zoom with
    | Some panel when List.Assoc.mem (place tree body) panel ~equal:equal_panel_id ->
      Some { tree = Panel panel; body }
    | Some _ | None -> Some { tree; body })

let panels = function None -> [] | Some { tree; body } -> place tree body
let compute ~preset ~zoom ~toggles ~width ~height =
  panels (create ~preset ~zoom ~toggles ~width ~height)

let rect_of t panel = List.Assoc.find (panels t) panel ~equal:equal_panel_id

(* Rebuild a tiling from one piece per panel: [panel] makes a tile from its rectangle, [row]
   and [column] join neighbours. Joining pieces that already have their rectangle's size
   draws every cell once, where stacking full-size layers draws each cell once per panel. *)
let fold t ~panel ~row ~column =
  let rec go tree r = match tree with
    | Panel p -> panel p r
    | Row children ->
      row (List.map (children_rects children r ~horizontal:true) ~f:(fun (child, r) -> go child r))
    | Column children ->
      column (List.map (children_rects children r ~horizontal:false) ~f:(fun (child, r) -> go child r)) in
  Option.map t ~f:(fun { tree; body } -> go tree body)

(* The panel under a body cell, with its rectangle. *)
let panel_at panels ~col ~row =
  List.find panels ~f:(fun (_, r) ->
    col >= r.col && col < r.col + r.width && row >= r.row && row < r.row + r.height)
