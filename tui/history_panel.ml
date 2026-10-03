open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter
module Scroller = Bonsai_term_scroller
module Textbox = Bonsai_term_textbox

let offset ~count ~height = function
  | Scroller.Scroll_position.Top | All_visible -> 0
  | Bottom -> Int.max 0 (count - height)
  | Percentage pct -> Float.to_int (Float.round (Percent.to_mult pct *. Float.of_int (Int.max 0 (count - height))))
(* Plain d is the global depth toggle, so paging is Ctrl-d / Ctrl-u (or Page Up / Page Down). *)
let is_history_event = function
  | Event.Key_press { key = (ASCII ('j' | 'k' | 'g' | 'G' | '/' | ' ')
                           | Enter | Escape | Arrow (`Up | `Down) | Page (`Up | `Down)); mods = [] } -> true
  | Key_press { key = ASCII ('d' | 'D' | 'u' | 'U'); mods = [ Ctrl ] } -> true
  | Mouse { kind = Scroll _; _ } -> true
  | _ -> false
let direction = function
  | Event.Key_press { key = (ASCII 'k' | Arrow `Up); _ } -> Some History_state.Up
  | Key_press { key = (ASCII 'j' | Arrow `Down); _ } -> Some Down
  | Key_press { key = ASCII 'g'; _ } -> Some First
  | Key_press { key = Page `Up; _ } | Key_press { key = ASCII ('u' | 'U'); mods = [ Ctrl ] } -> Some Page_up
  | Key_press { key = Page `Down; _ } | Key_press { key = ASCII ('d' | 'D'); mods = [ Ctrl ] } -> Some Page_down
  | _ -> None

type action =
  | Receive of decision_log * Time_ns.t | Scrolled of int * bool | Key of Event.t * int * int
  | Click of int * int
let reduce (model : History_state.t) = function
  | Receive (log, now) -> History_state.receive ~now model log
  | Scrolled (offset, at_bottom) ->
    { model with offset; follow = at_bottom && Option.is_none model.selected }
  | Click (offset, row) -> History_state.click model ~offset ~row
  | Key (event, offset, height) ->
    if model.filter_open then (match event with
      | Event.Key_press { key = Escape; _ } -> { model with filter_open = false; filter_error = None }
      | Key_press { key = Enter; _ } -> History_state.set_filter model model.editor.text
      | _ -> { model with editor = Filter_editor.apply model.editor event })
    else match event with
      | Event.Key_press { key = ASCII '/'; mods = [] } ->
        { model with filter_open = true; filter_error = None
                   ; editor = Filter_editor.create (History_state.filter_name model.filter) }
      | Key_press { key = ASCII ' '; mods = [] } -> History_state.pause model
      | Key_press { key = Enter; mods = [] } -> History_state.inspect model
      | Key_press { key = Escape; mods = [] } -> History_state.clear_selection model
      | Key_press { key = ASCII 'G'; mods = [] } -> History_state.resume_live model
      | _ -> Option.value_map (direction event) ~default:model
          ~f:(History_state.navigate model ~height ~offset)

type t =
  { view : View.t; handler : Event.t -> bool Effect.t; click : int -> unit Effect.t
  ; model : History_state.t
  ; offset : int; visible : decision list; filter_view : View.t option }

(* [now] is the shared animation clock: new rows fade in against it, and it is read only while
   a fade runs, so an idle log is not recomputed. *)
let component ?(dimmed = Bonsai.return false) ?(now = Bonsai.return Time_ns.epoch)
    ~(theme : Theme.t Bonsai.t) ~focus ~log ~(dimensions : Dimensions.t Bonsai.t) (local_ graph) =
  let model, inject = Bonsai.actor ~default_model:History_state.empty
      ~recv:(fun _context model action -> let next = reduce model action in next, (model, next)) graph in
  let get_time = Bonsai.Clock.get_current_time graph in
  let callback = let%arr inject and get_time in fun log ->
    let open Effect.Let_syntax in
    let%bind now = get_time in
    let%map _ = inject (Receive (log, now)) in () in
  Bonsai.Edge.on_change ~equal:(fun a b -> a.next_sequence = b.next_sequence
    && a.first_sequence = b.first_sequence
    && equal_decision_log a b) log ~callback graph;
  let fresh_at = let%arr model in model.fresh_at in
  let fade_now = Anim_clock.windowed ~now ~since:fresh_at ~within:Decision_row.fresh_fade () in
  let viewport = let%arr dimensions in
    { Dimensions.width = Int.max 1 (dimensions.width - 4)
    ; height = Int.max 1 (dimensions.height - 3) } in
  let window = let%arr model and viewport in
    let rows = History_state.rows model in
    let count = Array.length rows in
    let start = if model.follow then Int.max 0 (count - viewport.height)
      else Int.clamp_exn model.offset ~min:0 ~max:(Int.max 0 (count - viewport.height)) in
    let visible = Array.sub rows ~pos:start ~len:(Int.min viewport.height (count - start)) |> Array.to_list in
    start, count, visible in
  let canvas = let%arr window and model and viewport and dimmed and theme and fade_now in
    let theme = if dimmed then Theme.dim theme else theme in
    let start, count, visible = window in
    (* Only this viewport is converted to text views. The other <=10k rows are
       represented by two transparent spacers, then cropped by the real scroller. *)
    View.vcat
      [ View.transparent_rectangle ~width:viewport.width ~height:start
      ; View.vcat (List.map visible ~f:(fun decision -> Decision_row.view ~theme ~width:viewport.width
            ~fresh:(match model.fresh_at with
              | Some at when List.mem model.fresh_keys (History_state.key decision)
                               ~equal:[%equal: string * int option] ->
                Decision_row.fresh_intensity ~now:fade_now ~at
              | Some _ | None -> 0.)
            ~selected:(Option.value_map model.selected ~default:false
              ~f:(History_state.same_key decision)) decision))
      ; View.transparent_rectangle ~width:viewport.width ~height:(count - start - List.length visible) ] in
  let scroller = Scroller.component ~default_stuck_to_bottom:true ~crop_width_if_too_big:`Yes
      ~dimensions:viewport canvas graph in
  let position = let%arr scroller and window and viewport in
    let _, count, _ = window in
    let offset = offset ~count ~height:viewport.height scroller.scroll_position in
    offset, offset = Int.max 0 (count - viewport.height) in
  let callback = let%arr inject in fun (offset, bottom) ->
    let%map.Effect _ = inject (Scrolled (offset, bottom)) in () in
  Bonsai.Edge.on_change ~equal:[%equal: int * bool] position ~callback graph;
  let editing = let%arr model in model.filter_open in
  let textbox = Textbox.component ~default_model:"all" ~is_focused:editing
      ~text_attrs:(let%arr theme in Theme.attrs theme Text) graph in
  let handler = let%arr inject and scroller and textbox and viewport and position in fun event ->
    let open Effect.Let_syntax in
    (* One actor message decides and updates this entire key before yielding to
       textbox/scroller effects. Queued g+Enter and /+q cannot overtake each other. *)
    let%bind before, model = inject (Key (event, fst position, viewport.height)) in
    if before.filter_open then (
      match event with
      | Event.Key_press { key = Escape | Enter; _ } -> Effect.return model.filter_open
      | _ -> let%map () = textbox.handler event in model.filter_open)
    else match event with
    | Event.Key_press { key = ASCII '/'; mods = [] } ->
      let%map () = textbox.set model.editor.text in true
    | Key_press { key = ASCII (' '); mods = [] }
    | Key_press { key = Enter | Escape; mods = [] } -> Effect.return false
    | Key_press { key = ASCII 'G'; mods = [] } ->
      let%bind _ = scroller.less_keybindings_handler event in
      let%map () = scroller.inject Stick_to_bottom in false
    | _ ->
      let%bind _ = scroller.less_keybindings_handler event in
      (* The installed less handler uses gg; a second g implements single-g Top. *)
      let%bind () = match event with
        | Key_press { key = ASCII 'g'; mods = [] } ->
          let%map _ = scroller.less_keybindings_handler event in ()
        | _ -> Effect.Ignore in
      match direction event, History_state.selected_index model with
      | Some _, Some index ->
        let%map () = scroller.inject (Scroll_to { top = index; bottom = index }) in false
      | _ -> Effect.return false in
  (* [row] counts from the first row inside the frame. The scroller is told too, as a key would. *)
  let click = let%arr inject and scroller and window in fun row ->
    let start, _, visible = window in
    if row < 0 || row >= List.length visible then Effect.Ignore
    else (
      let open Effect.Let_syntax in
      let%bind _ = inject (Click (start, row)) in
      scroller.inject (Scroll_to { top = start + row; bottom = start + row })) in
  let%arr model and scroller and dimensions and focus and window and position and textbox and handler
      and dimmed and theme and click in
  let theme = if dimmed then Theme.dim theme else theme in
  let _, _, visible = window in
  let title = "Decisions · MOCK · " ^ History_state.filter_name model.filter
    ^ (if model.paused then " ⏸ PAUSED" else "") in
  let pill = if model.unseen > 0 then sprintf "↓ %d new%s" model.unseen
      (if model.paused then sprintf " (%d while paused)" model.paused_arrivals else "")
    else if Option.is_some model.selected then "Enter inspect · Esc deselect · G live"
    else "MOCK · G live · / filter · Space pause" in
  let body = View.vcat [ Panel.fit scroller.view ~width:(Int.max 0 (dimensions.width - 4))
                          ~height:(Int.max 0 (dimensions.height - 3)); View.text ~attrs:(Theme.attrs theme Muted) pill ] in
  let view = Panel.frame ~theme ~focus ~panel:Decisions ~title
      ~width:dimensions.width ~height:dimensions.height body in
  let filter_view = if not model.filter_open then None else
    let body = View.vcat
        [ View.text "all | match | admitted | blocked | received | errors"
        ; View.hcat [ View.text "/ "; textbox.view ]
        ; View.text ~attrs:(Theme.attrs theme Muted) "Enter apply · Esc close · input owns all keys"
        ; View.text ~attrs:(Theme.attrs theme Warn) (Option.value model.filter_error ~default:"") ] in
    let box = Bonsai_term_border_box.view ~title:"Decision filter" ~line_type:Round_corners
        ~attrs:(Theme.attrs theme Focus) ~left_padding:1 ~right_padding:1 body in
    Some (View.zcat [ box; View.rectangle ~width:(View.width box) ~height:(View.height box) () ]) in
  { view; handler; click; model; offset = fst position; visible; filter_view }
