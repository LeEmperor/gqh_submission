open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

type overlay = Closed | Help | Quit_confirmation [@@deriving equal, sexp]

type ui_state =
  { focus : Keymap.focus; overlay : overlay; selected : string option
  ; filter_open : bool; config_open : bool
  ; preset : Ui_types.preset; zoom : bool; notice : string option
  ; toggles : Ui_types.market_toggles; scheme : Ui_types.scheme }
  [@@deriving equal, sexp]

(* Layout is a pure function of UI state and terminal size. The reducer (focus cycling,
   hit-testing) and the renderer both ask it, so they cannot disagree about what is shown.
   [zoomed:false] is the preset's own panel set, which Tab and the number keys walk. *)
let layout ui ~zoomed ~(dimensions : Dimensions.t) =
  Layout.compute ~preset:ui.preset ~zoom:(Option.some_if (zoomed && ui.zoom) ui.focus)
    ~toggles:ui.toggles ~width:dimensions.width
    ~height:(Layout.body_height ~height:dimensions.height)
let visible ui ~dimensions = List.map (layout ui ~zoomed:false ~dimensions) ~f:fst

(* A focus the layout no longer shows (a preset change, a resize) falls to its first panel. *)
let normalize ui ~dimensions =
  let visible = visible ui ~dimensions in
  if List.mem visible ui.focus ~equal:Keymap.equal_focus then ui
  else Option.value_map (List.hd visible) ~default:ui ~f:(fun focus -> { ui with focus })

(* Decisions keeps its size while hidden, as it would have in Decide, so switching presets
   does not resize its scroller. *)
let decisions_dimensions ui ~dimensions =
  let find ui = List.Assoc.find (layout ui ~zoomed:true ~dimensions) Decisions ~equal:Keymap.equal_focus in
  match Option.first_some (find ui) (find { ui with preset = Decide; zoom = false }) with
  | Some { width; height; _ } -> { Dimensions.width = Int.max 1 width; height = Int.max 3 height }
  | None -> { Dimensions.width = 1; height = 3 }

let too_small ~theme ~(dimensions : Dimensions.t) ~height =
  let line role text = View.text ~attrs:(Theme.attrs theme role) text in
  let lines = [ line Warn (sprintf "Resize to at least %d×%d" Layout.min_width Layout.min_height)
              ; line Muted (sprintf "now %d×%d · ? help · q quit" dimensions.width dimensions.height) ] in
  let width = List.fold lines ~init:0 ~f:(fun width view -> Int.max width (View.width view)) in
  View.center ~within:{ width = dimensions.width; height }
    (View.vcat (List.map lines ~f:(fun view -> View.center view ~within:{ width; height = 1 })))

(* The F12 box sits at the bottom right of the body: below the header row and above the
   footer row, so the status fields and key hints stay readable. *)
let meter_view ~theme ~stats ~(dimensions : Dimensions.t) =
  let box = Debug_overlay.view ~theme ~stats in
  let box = Theme.backdrop theme
      (View.zcat [ box; View.rectangle ~width:(View.width box) ~height:(View.height box) () ]) in
  View.pad box ~l:(Int.max 0 (dimensions.width - View.width box - 1))
    ~t:(Int.max Layout.header_rows (dimensions.height - Layout.footer_rows - View.height box))

type route =
  | Dashboard | History | Configuration | Persist of Ui_types.preset
  | Select_decision of int  (* row inside the Decisions frame *)

type action =
  | Input of Event.t | Initialize_selection | Filter_focus of bool | Config_focus of bool
  | Notice of string option

(* The reason is the text after the last colon: "preset not saved: Permission denied". *)
let save_notice error =
  let message = List.hd_exn (String.split_lines (Error.to_string_hum error ^ "\n")) in
  let reason = match String.rsplit2 message ~on:':' with
    | Some (_, reason) -> String.strip reason | None -> message in
  "preset not saved: " ^ reason

(* UI transitions that need no backend state and no effects. *)
let step ui ~dimensions : Keymap.action -> ui_state = function
  | Next -> { ui with focus = Keymap.cycle ~visible:(visible ui ~dimensions) ui.focus `Next }
  | Previous -> { ui with focus = Keymap.cycle ~visible:(visible ui ~dimensions) ui.focus `Previous }
  | Jump focus ->
    (* A hidden panel is reached by switching to the preset that shows it. Where the terminal is
       too small to show any panel nothing is "hidden" by the preset, so a jump changes nothing. *)
    let visible = visible ui ~dimensions in
    if List.is_empty visible then ui
    else if List.mem visible focus ~equal:Keymap.equal_focus then { ui with focus }
    else { ui with focus; preset = Presets.showing focus }
  | Preset preset -> normalize { ui with preset } ~dimensions
  | Zoom -> { ui with zoom = not ui.zoom }
  | Cycle_theme -> { ui with scheme = Theme.next_scheme ui.scheme }
  | Toggle_heatmap ->
    normalize { ui with toggles = { ui.toggles with heatmap = not ui.toggles.heatmap } } ~dimensions
  | Toggle_cumulative ->
    { ui with toggles = { ui.toggles with cumulative = not ui.toggles.cumulative } }
  | Toggle_meter  (* owned by [live], which holds the meter *)
  | Help | Close | Quit | Confirm_quit | Move_up | Move_down | First | Last | Ignore -> ui

(* A click focuses the panel under the pointer. The wheel acts on the panel under the
   pointer, not the focused one: Decisions scrolls through its own scroller, Rules steps. *)
let on_mouse ui ~dimensions ~(state : application_state) ~(kind : Event.mouse_kind)
    ~(position : Position.t) =
  let panels = layout ui ~zoomed:true ~dimensions in
  match Layout.panel_at panels ~col:position.x ~row:(position.y - Layout.header_rows), kind with
  | Some (Decisions, rect), Left ->
    { ui with focus = Decisions }, Select_decision (position.y - Layout.header_rows - rect.row - 1)
  | Some (panel, _), Left -> { ui with focus = panel }, Dashboard
  | Some (Decisions, _), Scroll _ -> ui, History
  | Some (Rules, _), Scroll direction ->
    let direction = match direction with `Up -> `Previous | `Down -> `Next in
    { ui with selected = Rules_panel.move_selection state.rules ~selected:ui.selected ~direction },
    Dashboard
  | _ -> ui, Dashboard

(* When each print of the tape that is still highlighted stops being. Prints are newest
   first, and one more than a highlight older than the newest is over before it begins. *)
let tape_expiries (tape : Tape_panel.t) =
  match Tape_panel.newest tape with
  | None -> []
  | Some newest ->
    let floor = Time_ns.sub newest.time Tape_panel.fade in
    let expiries = ref [] in
    Age_deque.iter_while tape.prints ~f:(fun print ->
      Time_ns.(print.time > floor)
      && (expiries := Time_ns.add print.time Tape_panel.fade :: !expiries; true));
    List.rev !expiries

(* [overlay] carries the frame meter's numbers while its box is open; [live] owns the meter.
   [on_compute] is a test hook: each node of the shell calls it with its name when it
   recomputes, so a test can count what an event really cost. *)
let component ?(overlay = Bonsai.return None) ?(initial_preset = Ui_types.Monitor)
    ?(on_preset = Bonsai.return (fun (_ : Ui_types.preset) -> Effect.return (Ok ())))
    ?(send_command = Bonsai.return (fun (_ : command) -> Effect.Ignore))
    ?(on_compute = ignore) ?wake
    ~(theme : Theme.t) ~state ~clock ~exit ~(dimensions : Dimensions.t Bonsai.t) (local_ graph) =
  (* The reducer sees the latest state for every queued key, even when several
     keys arrive before a redraw. A handler capturing focus/overlay would not. *)
  let input = let%arr state and dimensions in state, dimensions in
  let ui, inject =
    Bonsai.actor_with_input
      ~default_model:{ focus = Keymap.Market; overlay = Closed; selected = None
                     ; filter_open = false; config_open = false
                     ; preset = initial_preset; zoom = false; notice = None
                     ; toggles = { heatmap = true; cumulative = false }; scheme = theme.scheme }
      ~recv:(fun context input ui action ->
        match input with
        | Bonsai.Computation_status.Inactive -> ui, Dashboard
        | Active ((state : application_state), dimensions) ->
          match action with
          | Notice notice -> { ui with notice }, Dashboard
          | Filter_focus filter_open -> { ui with filter_open }, Dashboard
          | Config_focus config_open -> { ui with config_open }, Dashboard
          | Initialize_selection ->
            (if Option.is_some ui.selected then ui else
              { ui with selected = Option.map (List.hd state.rules) ~f:(fun rule -> rule.rule_id) }), Dashboard
          | Input event ->
            let ui = normalize ui ~dimensions in
            (* A notice lives until the next key press. *)
            let ui = match event with Key_press _ -> { ui with notice = None } | _ -> ui in
            if ui.filter_open then
              (match event with Key_press { key = Escape; _ } -> { ui with filter_open = false } | _ -> ui), History
            else if ui.config_open then
              (match event with Key_press { key = Escape; _ } -> { ui with config_open = false } | _ -> ui), Configuration
            else if equal_overlay ui.overlay Closed
                    && (match event with Key_press { key = ASCII 'c'; mods = [] } -> true | _ -> false)
            then { ui with config_open = true }, Configuration
            else if equal_overlay ui.overlay Closed
                    && (match event with Key_press { key = ASCII '/'; mods = [] } -> true | _ -> false)
            then { ui with focus = Decisions; filter_open = true }, History
            else (match event with
              | Mouse { kind; position; mods = [] } when equal_overlay ui.overlay Closed ->
                on_mouse ui ~dimensions ~state ~kind ~position
              | _ ->
                if equal_overlay ui.overlay Closed && Keymap.equal_focus ui.focus Decisions
                   && History_panel.is_history_event event then ui, History
                else (
                  let quit () =
                    match state.configuration.status with
                    | Applying _ -> { ui with overlay = Quit_confirmation }
                    | _ -> Bonsai.Apply_action_context.schedule_event context (exit ()); ui in
                  let before = ui in
                  let ui = match ui.overlay, Keymap.action event with
                    | _, Keymap.Close -> { ui with overlay = Closed }
                    | Quit_confirmation, (Confirm_quit | Quit) ->
                      Bonsai.Apply_action_context.schedule_event context (exit ()); ui
                    | Help, Help -> { ui with overlay = Closed }
                    | Help, Quit -> quit ()
                    | (Help | Quit_confirmation), _ -> ui
                    | Closed, Help -> { ui with overlay = Help }
                    | Closed, Quit -> quit ()
                    | Closed, (Move_up | Move_down | First | Last as action) ->
                      if not (Keymap.equal_focus ui.focus Rules) then ui else
                        let direction = match action with
                          | Move_up -> `Previous | Move_down -> `Next | First -> `First
                          | Last -> `Last | _ -> assert false in
                        { ui with selected = Rules_panel.move_selection state.rules ~selected:ui.selected ~direction }
                    | Closed, (Confirm_quit | Toggle_meter | Ignore) -> ui
                    | Closed, (Next | Previous | Jump _ | Preset _ | Zoom | Cycle_theme
                              | Toggle_heatmap | Toggle_cumulative as action) ->
                      step ui ~dimensions action in
                  ui, if Ui_types.equal_preset before.preset ui.preset then Dashboard
                      else Persist ui.preset)))
      input graph
  in
  let ids = let%arr state in List.map state.rules ~f:(fun rule -> rule.rule_id) in
  let callback = let%arr inject in fun _ -> let%map.Effect _ = inject Initialize_selection in () in
  Bonsai.Edge.on_change ~equal:[%equal: string list] ids ~callback graph;
  (* Everything below is a node of its own, reading only what it draws: see Panel_views. *)
  let ui = let%arr ui and dimensions in normalize ui ~dimensions in
  let focus = let%arr ui in ui.focus in
  let scheme = let%arr ui in ui.scheme in
  let log = let%arr state in state.decisions in
  let history_dimensions =
    Bonsai.cutoff ~equal:Dimensions.equal (let%arr ui and dimensions in decisions_dimensions ui ~dimensions) in
  let stepper_width = let%arr dimensions in Int.max 0 (Int.min 96 (dimensions.width - 4) - 4) in
  (* Components outside the panels follow the scheme through this Bonsai value. *)
  let themed = Bonsai.cutoff ~equal:Theme.equal (let%arr scheme in Theme.with_scheme theme scheme) in
  let stepper = Config_stepper.component ~theme:themed ~state ~width:stepper_width graph in
  let review = Config_review.component ~theme:themed ~state ~dimensions ~stepper graph in
  let dimmed = let%arr review in review.is_open in
  (* The modal dims the panels behind it, never the overlays above them. *)
  let panel_theme = let%arr themed and dimmed in if dimmed then Theme.dim themed else themed in
  let motion = Market_motion.component ~state graph in
  let heatmap = Heatmap.component ~state graph in
  let tape = Tape_panel.component ~state graph in
  let metrics = Metrics_state.component ?wake ~state graph in
  (* Animated views read this clock. It moves when the stream brings something and when a
     highlight is due to be taken off, and not otherwise: see Anim_clock. *)
  let activity = let%arr state in state.market, state.updates, state.decisions.next_sequence in
  let expiries = let%arr motion and tape in Market_motion.expiries motion @ tape_expiries tape in
  let now = Anim_clock.component ?wake ~activity ~equal:[%equal: snapshot * int * int] ~expiries
      ~after_touch:[ Decision_row.fresh_fade ] graph in
  let tiling = Bonsai.cutoff ~equal:[%equal: Layout.t option]
      (let%arr ui and dimensions in
       Layout.create ~preset:ui.preset ~zoom:(Option.some_if ui.zoom ui.focus) ~toggles:ui.toggles
         ~width:dimensions.width ~height:(Layout.body_height ~height:dimensions.height)) in
  (* The decisions are kept while their panel is not shown, and no row of them is built. *)
  let on_screen = Bonsai.cutoff ~equal:Bool.equal
      (let%arr tiling in Option.is_some (Layout.rect_of tiling Decisions)) in
  let history = History_panel.component ~theme:themed ~dimmed ~now ~on_screen
      ~focus:(let%arr focus in Panel_views.seen_focus Decisions ~focused:(Keymap.equal_focus focus Decisions))
      ~log ~dimensions:history_dimensions graph in
  let selected = let%arr ui in ui.selected in
  let cumulative = let%arr ui in ui.toggles.cumulative in
  let body = Panel_views.component ~compute:on_compute ~theme:panel_theme ~state ~focus ~selected
      ~cumulative ~tiling ~history ~motion ~heatmap ~tape ~metrics ~now graph in
  let width = let%arr dimensions in dimensions.width in
  let header =
    let%arr state = Bonsai.cutoff state ~equal:Status_bar.same_inputs and clock and width
    and theme = panel_theme in
    on_compute "header";
    Status_bar.view ~theme ~state ~clock ~width in
  let footer =
    let%arr focus and preset = (let%arr ui in ui.preset) and zoomed = (let%arr ui in ui.zoom)
    and scheme and notice = (let%arr ui in ui.notice) and width and theme = panel_theme in
    on_compute "footer";
    Footer.view ~theme ~focus ~preset ~zoomed ~scheme ~notice ~width in
  let base =
    let%arr header and body and footer and dimensions and theme = panel_theme in
    on_compute "frame";
    let body_height = Layout.body_height ~height:dimensions.height in
    let body = match body with
      | None -> too_small ~theme ~dimensions ~height:body_height
      | Some body -> Panel.fit body ~width:dimensions.width ~height:body_height in
    View.vcat [ header; body; footer ]
    |> Panel.fit ~width:dimensions.width ~height:dimensions.height
    |> Theme.backdrop theme in
  let help =
    let%arr overlay = (let%arr ui in ui.overlay) and theme = themed and dimensions in
    match overlay with
    | Closed -> None
    | Help | Quit_confirmation ->
      Some (Help_overlay.view ~theme ~dimensions ~quitting:(equal_overlay overlay Quit_confirmation)) in
  let modal = let%arr review in review.modal in
  let filter = let%arr history in history.History_panel.filter_view in
  let view =
    let%arr base and help and modal and filter and overlay and dimensions and theme = themed in
    let over view = View.zcat [ view; base ] in
    let view = match help, modal, filter with
      | Some help, _, _ -> over help |> Panel.fit ~width:dimensions.width ~height:dimensions.height
      | None, Some modal, _ -> over (View.center modal ~within:dimensions)
      | None, None, Some filter -> over (View.center filter ~within:dimensions)
      | None, None, None -> base in
    let view = match overlay with
      | Some stats -> View.zcat [ meter_view ~theme ~stats ~dimensions; view ]
      | None -> view in
    (* Only what floats above the base needs the default colours; the base brings its own. *)
    if phys_equal view base then view else Theme.backdrop theme view
  in
  let handler = let%arr inject and history and review and send_command and on_preset in fun event ->
    let open Effect.Let_syntax in
    let%bind route = inject (Input event) in
    match route with
    | Dashboard -> Effect.Ignore
    | Persist preset ->
      let%bind result = on_preset preset in
      let%map _ = inject (Notice (Result.error result |> Option.map ~f:save_notice)) in ()
    | Select_decision row -> history.click row
    | History ->
      let%bind filter_open = history.handler event in
      let%map _ = inject (Filter_focus filter_open) in ()
    | Configuration ->
      let%bind response = review.handler event in
      let%bind _ = inject (Config_focus response.is_open) in
      Option.value_map response.command ~default:Effect.Ignore ~f:send_command in
  ~view, ~handler

let frame = Live_poll.frame
let poll_margin = Live_poll.poll_margin
let poll_delay = Live_poll.poll_delay

(* [paints] counts the views the driver has been given to paint, for the frame meter; the
   runner owns the throttle that releases them, and counts them. Without it, as under test,
   the meter records nothing. *)
let live (type backend) ?(initial_preset = Presets.load ())
    ?(on_preset = Bonsai.return (fun preset -> Effect.of_sync_fun (fun preset -> Presets.save preset) preset))
    ?on_compute ?paints ?(wake = Wake.off)
    (module Backend : Backend_intf.S with type t = backend)
    ~theme ~(backend : backend) ~exit ~(dimensions : Dimensions.t Bonsai.t) (local_ graph) =
  let state, send_command = Live_poll.start ~wake (module Backend) ~backend graph in
  (* The header's one wall clock is UTC, like the tape's, to the second, read from a clock that
     ticks once a second on the second: a finer digit would be a guess. It is one of the two
     things an idle application runs (the other is the metrics sampler on the same tick), and
     it repaints the header once a second. *)
  let now = Anim_clock.each_second ~wake ~enabled:(Bonsai.return true) graph in
  let clock = Bonsai.cutoff ~equal:String.equal
      (let%arr now in Time_ns.to_ofday now ~zone:Timezone.utc |> Time_ns.Ofday.to_sec_string) in
  (* The meter and its F12 key wrap the whole component. It times the frames the driver really
     paints, which the throttle between the application and the driver decides. *)
  let debug, toggle_meter = Bonsai.toggle ~default_model:false graph in
  let meter = Frame_meter.probe ~enabled:debug ~updates:(let%arr state in state.updates)
      ~buffers:(let%arr state in Frame_meter.buffers_of_state state) graph in
  let overlay = let%arr debug and stats = meter.Frame_meter.stats in Option.some_if debug stats in
  let ~view, ~handler =
    component ~overlay ~initial_preset ~on_preset ~send_command ?on_compute ~wake ~theme ~state ~clock ~exit
      ~dimensions graph in
  let handler = let%arr handler and toggle_meter in fun event ->
    match Keymap.action event with Toggle_meter -> toggle_meter | _ -> handler event in
  Frame_meter.observe meter ?paints graph;
  ~view, ~handler
