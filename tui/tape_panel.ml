open! Core
open Bonsai_term
open Model_adapter
open Bonsai.Let_syntax

(* Time & sales. The contracts carry no executed trades, so every print here is inferred
   from a top-of-book quantity decrease at an unchanged best price between consecutive valid
   snapshots: fewer units resting at the bid reads as a sell, at the ask as a buy. This is
   MOCK evidence about the book, never an execution, and the panel title says so. *)

let capacity = 128

type print = { time : Time_ns.t; side : side; price_ticks : int; quantity_units : int }
type t =
  { identity : identity option; mode : mode option
  ; top : (level option * level option) option  (* last valid best bid and ask *)
  ; prints : print Age_deque.t  (* newest first, at most [capacity] *) }

let empty = { identity = None; mode = None; top = None; prints = Age_deque.empty }

(* The prints, newest first, as a list: a copy of all of them, for a reader that wants the whole
   tape (the tests). The panel and the animation clock read the deque where it is. *)
let prints t =
  let newest_first = ref [] in
  Age_deque.iter_while t.prints ~f:(fun print -> newest_first := print :: !newest_first; true);
  List.rev !newest_first

let newest t = Age_deque.newest t.prints

(* The first [count] prints, newest first, and no more are visited. *)
let take t count =
  let taken = ref [] and left = ref count in
  Age_deque.iter_while t.prints ~f:(fun print ->
    if !left <= 0 then false else (taken := print :: !taken; decr left; true));
  List.rev !taken

(* Units that left a level whose price did not move, if any. *)
let consumed ~before ~after =
  match before, after with
  | Some (before : level), Some (after : level)
    when before.price_ticks = after.price_ticks && after.quantity_units < before.quantity_units ->
    Some (before.price_ticks, before.quantity_units - after.quantity_units)
  | _ -> None

let observe t ~now ~(snapshot : snapshot) =
  let reset = Option.exists t.identity ~f:(fun id ->
      not (String.equal id.run_id snapshot.identity.run_id)) in
  let t = if reset then empty else t in
  let top = if snapshot.valid then Some (List.hd snapshot.bids, List.hd snapshot.asks) else None in
  let inferred = match t.top, top with
    | Some (bid_before, ask_before), Some (bid_after, ask_after) ->
      List.filter_map
        [ Sell, consumed ~before:bid_before ~after:bid_after
        ; Buy, consumed ~before:ask_before ~after:ask_after ]
        ~f:(fun (side, consumed) ->
          Option.map consumed ~f:(fun (price_ticks, quantity_units) ->
            { time = now; side; price_ticks; quantity_units }))
    | _ -> [] in
  let prints = List.fold inferred ~init:t.prints ~f:(fun prints print ->
      Age_deque.trim (Age_deque.push prints print) ~keep:(fun ~length _ -> length <= capacity)) in
  { identity = Some snapshot.identity; mode = Some snapshot.mode; top; prints }

(* ---- View ---- *)

type clock = Millis | Seconds
type side = Word | Arrow
let clock ~style time =
  match style with Millis -> Clock_text.utc_millis time | Seconds -> Clock_text.utc_seconds time
let side_name ~style side = match style, side with
  | Word, Buy -> "▲ BUY " | Word, Sell -> "▼ SELL" | Arrow, Buy -> "▲" | Arrow, Sell -> "▼"

(* Columns are: time, side, price, quantity. A narrow panel gives up what it can spare, in
   this order: a space between columns, the milliseconds, the word beside the side's arrow,
   and the quantity header's unit. The time column keeps its header's width, so "time (UTC)"
   always fits. *)
type columns = { gap : int; clock : clock; side : side; qty_floor : int }
let columns_for ~inner ~price_digits ~qty_digits =
  let candidates =
    [ { gap = 2; clock = Millis; side = Word; qty_floor = 6 }
    ; { gap = 1; clock = Millis; side = Word; qty_floor = 6 }
    ; { gap = 1; clock = Seconds; side = Word; qty_floor = 6 }
    ; { gap = 1; clock = Seconds; side = Arrow; qty_floor = 6 }
    ; { gap = 1; clock = Seconds; side = Arrow; qty_floor = 3 } ] in
  let size c =
    (match c.clock with Millis -> 12 | Seconds -> 10) + c.gap
    + (match c.side with Word -> 6 | Arrow -> 4) + c.gap + Int.max 5 price_digits + c.gap
    + Int.max c.qty_floor qty_digits in
  Option.value (List.find candidates ~f:(fun candidate -> size candidate <= inner))
    ~default:(List.last_exn candidates)

let window = Time_ns.Span.of_sec 60.
let fade = Time_ns.Span.of_sec 1.

let add_saturating a b = if b > Int.max_value - a then Int.max_value else a + b

(* Units printed on each side in the last minute, and how many prints that was. *)
let summary t ~now =
  let buy = ref 0 and sell = ref 0 and count = ref 0 in
  (* Newest first, so the first print out of the window ends the walk. *)
  Age_deque.iter_while t.prints ~f:(fun print ->
    Time_ns.Span.(Time_ns.diff now print.time <= window)
    && (let units = Int.max 0 print.quantity_units in
        (match print.side with
         | Buy -> buy := add_saturating !buy units
         | Sell -> sell := add_saturating !sell units);
        incr count;
        true));
  !buy, !sell, !count

(* Buys fill from the left in the bid colour, sells the rest in the ask colour; the two
   use different glyphs, so the split reads without colour. *)
let share_bar theme ~buy ~sell ~width =
  let total = Float.of_int buy +. Float.of_int sell in
  if width < 6 || Float.(total <= 0.) then View.none
  else (
    let bought = Float.iround_nearest_exn (Float.of_int buy /. total *. Float.of_int width) in
    View.hcat [ View.text ~attrs:(Theme.attrs theme Bid) (Braille_chart.repeat "█" bought)
              ; View.text ~attrs:(Theme.attrs theme Ask) (Braille_chart.repeat "░" (width - bought)) ])

(* Weight by size: blend from muted toward the side's colour by share of the largest
   visible print, then toward the text colour for a second after it printed. Without
   colour, the larger half is bold and a fresh print is too. *)
let freshness ~now print =
  let age = Time_ns.diff now print.time in
  if Time_ns.Span.(age < zero || age >= fade) then 0.
  else Fade.level (1. -. (Time_ns.Span.to_sec age /. Time_ns.Span.to_sec fade))
let fresh ~now print = Float.(freshness ~now print >= 0.7)
let print_rgb theme ~now ~largest print =
  let share = if largest <= 0 then 0.
    else Float.min 1. (Float.of_int print.quantity_units /. Float.of_int largest) in
  let role = match print.side with Buy -> Theme.Bid | Sell -> Ask in
  let weighted = Theme.blend (Theme.role_rgb theme Muted) (Theme.role_rgb theme role) share in
  Theme.blend weighted (Theme.role_rgb theme Text) (0.7 *. freshness ~now print)

(* "Inferred" is the panel's honesty label: it is the last thing a narrow title gives up. *)
let title ~mode ~width =
  let candidates = [ sprintf "Tape · %s · inferred from book deltas" mode; sprintf "Tape · %s · inferred" mode
                   ; "Tape · inferred" ] in
  Option.value (List.find candidates ~f:(fun text -> Braille_chart.display_width text <= width - 4))
    ~default:(List.last_exn candidates)

let view ~theme ~focus ~tape ~now ~width ~height =
  let inner = Int.max 0 (width - 4) in
  (* The summary and the column header take two rows of the body. *)
  let rows = Int.max 0 (height - 4) in
  let shown = take tape rows in
  let digits value = String.length (Int.to_string value) in
  let largest = List.fold shown ~init:0 ~f:(fun largest print ->
      Int.max largest print.quantity_units) in
  let muted = Theme.attrs theme Muted in
  let price_digits = List.fold shown ~init:0 ~f:(fun width print -> Int.max width (digits print.price_ticks))
  and qty_digits = List.fold shown ~init:0 ~f:(fun width print -> Int.max width (digits print.quantity_units)) in
  let columns = columns_for ~inner ~price_digits ~qty_digits in
  let price_width = Int.max 5 price_digits in
  let qty_width = Int.max columns.qty_floor qty_digits in
  let cells = Braille_chart.display_width in
  let right size text = Braille_chart.spaces (size - String.length text) ^ text in
  let spaces = String.make columns.gap ' ' in
  let clock_width = match columns.clock with Millis -> 12 | Seconds -> 10 in
  let side_width = match columns.side with Word -> 6 | Arrow -> 4 in
  let line ~time ~side ~price ~quantity =
    String.concat [ time; Braille_chart.spaces (clock_width - cells time); spaces
                  ; side; Braille_chart.spaces (side_width - cells side); spaces
                  ; right price_width price; spaces; right qty_width quantity ] in
  let bar_width = Int.max 0 (inner - cells (line ~time:"" ~side:"" ~price:"" ~quantity:"") - 2) in
  (* A row is one text node: its fields and its bar are drawn alike. *)
  let row (print : print) =
    let rgb = print_rgb theme ~now ~largest print in
    let attrs = match Theme.rgb_color theme rgb with
      | Some color -> [ Attr.fg color ]
      | None ->
        if Float.(of_int print.quantity_units >= 0.5 * of_int largest) || fresh ~now print then [ Attr.bold ] else [] in
    View.text ~attrs
      (line ~time:(clock ~style:columns.clock print.time)
         ~side:(side_name ~style:columns.side print.side)
         ~price:(Int.to_string print.price_ticks)
         ~quantity:(Int.to_string print.quantity_units)
       ^ " " ^ Market_panel.quantity_bar ~quantity:print.quantity_units ~maximum:largest ~width:bar_width) in
  let body =
    if Age_deque.length tape.prints = 0 then View.text ~attrs:muted "no prints inferred yet"
    else (
      let buy, sell, count = summary tape ~now in
      let totals = List.find
          [ sprintf "60 s: %d prints · buy %d u · sell %d u · net %+d u " count buy sell (buy - sell)
          ; sprintf "60 s: buy %d u · sell %d u · net %+d u " buy sell (buy - sell)
          ; sprintf "buy %d · sell %d · net %+d " buy sell (buy - sell) ]
          ~f:(fun text -> cells text <= inner) in
      let totals = Option.value totals ~default:(sprintf "net %+d u" (buy - sell)) in
      let bar = share_bar theme ~buy ~sell ~width:(inner - cells totals) in
      View.vcat
        (View.hcat [ View.text ~attrs:muted totals; bar ]
         :: View.text ~attrs:muted (line ~time:"time (UTC)" ~side:"side" ~price:"px(t)" ~quantity:(if qty_width >= 6 then "qty(u)" else "qty")
                                    ^ " size")
         :: List.map shown ~f:row)) in
  Panel.framed ~theme ~focus ~panel:Tape ~width ~height
    ~title:(title ~mode:(Option.value_map tape.mode ~default:"—" ~f:Status_bar.mode_name) ~width)
    body

(* What [view] reads of the tape, and nothing else: the prints and the mode. Each snapshot makes
   a new tape, and most leave the prints as they were, so a node that cuts the tape off on this
   is computed when a print arrives and not on every snapshot. *)
let same_inputs a b = phys_equal a.prints b.prints && [%equal: mode option] a.mode b.mode

(* ---- Component ---- *)

let component ~(state : application_state Bonsai.t) (local_ graph) =
  let tape, inject = Bonsai.state_machine ~default_model:empty
      ~apply_action:(fun _ tape (now, snapshot) -> observe tape ~now ~snapshot) graph in
  let market = let%arr state in state.market in
  let get_time = Bonsai.Clock.get_current_time graph in
  let callback =
    let%arr inject and get_time in
    fun snapshot ->
      let open Effect.Let_syntax in
      let%bind now = get_time in
      inject (now, snapshot) in
  Bonsai.Edge.on_change ~equal:[%equal: snapshot] market ~callback graph;
  tape
