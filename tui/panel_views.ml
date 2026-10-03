open! Core
open Bonsai_term
open Bonsai.Let_syntax
open Model_adapter

(* One Bonsai node per panel. Each node reads only what its panel draws and its own
   rectangle, so a change recomputes the panels it concerns and no others: a clock tick
   recomputes Market, and nothing else unless that panel animates; a stream tick recomputes
   the market-data panels, not Rules, Latency, Configuration or the header; a focus move
   recomputes the two panels it moves between.

   [compute] is a test hook, called with the panel's name each time its node runs. *)

(* A panel only asks whether it is the focused one. Handing it another panel's id instead of
   the real focus keeps its inputs, and so its node, unchanged while focus moves elsewhere. *)
let seen_focus panel ~focused = if focused then panel else Keymap.next panel

(* What each cold panel draws from the application state, and nothing else. A panel reads a
   state cut off on its own dependencies, so the book and the counters that change on every
   stream tick leave it alone. The tests change every other field and require the same screen,
   so a panel that starts drawing a field outside its list fails there instead of going stale
   on the screen. *)
module Deps = struct
  type t = application_state -> application_state -> bool
  (* Rules draws the outcomes of the newest [Rules_panel.recent_limit] decisions, and nothing
     else of the log: comparing those, not the ring, keeps this cheap on a 10 000-entry log. *)
  let recent_outcomes (state : application_state) =
    Sequence.take (Map.to_sequence ~order:`Decreasing_key state.decisions.records)
      Rules_panel.recent_limit
    |> Sequence.map ~f:(fun (_, (decision : decision)) -> decision.rule_id, decision.outcome)
    |> Sequence.to_list
  let rules : t = fun a b ->
    [%equal: rule list] a.rules b.rules && equal_mode a.mode b.mode && equal_engine a.engine b.engine
    && equal_configuration a.configuration b.configuration && String.equal a.run_id b.run_id
    && Int.equal a.decisions.next_sequence b.decisions.next_sequence
    && Int.equal a.decisions.first_sequence b.decisions.first_sequence
    && [%equal: (string * decision_outcome) list] (recent_outcomes a) (recent_outcomes b)
  let latency : t = fun a b -> equal_mode a.mode b.mode
  let configuration : t = fun a b ->
    equal_mode a.mode b.mode && String.equal a.build_id b.build_id && Bool.equal a.connected b.connected
    && equal_engine a.engine b.engine && equal_configuration a.configuration b.configuration
    && equal_manifest a.manifest b.manifest && equal_proposal a.proposal b.proposal
    && [%equal: apply_progress option] a.config_apply b.config_apply
    && [%equal: config_event list] a.config_events b.config_events
end

let tile rect build =
  match (rect : Ui_types.rect option) with
  | None -> View.none
  | Some { width; height; _ } -> Panel.fit (build ~width ~height) ~width ~height

(* Metrics moves a pixel at a time, about every 0.6 s. *)
let metrics_step = Time_ns.Span.of_sec 0.5
(* A print fades over [Tape_panel.fade]; the margin is the rounding of the slow clock that takes
   over, so the age it reads is already past the fade. From then on the tape moves only as its
   60 s summary window slides, in steps no finer than [metrics_step]. *)
let print_horizon = Time_ns.Span.(Tape_panel.fade + metrics_step)

let component ~compute ~theme ~state ~focus ~selected ~cumulative ~tiling ~history ~motion
    ~heatmap ~tape ~metrics ~now (local_ graph) =
  let projected deps = Bonsai.cutoff state ~equal:deps in
  let rect panel =
    Bonsai.cutoff ~equal:[%equal: Ui_types.rect option]
      (let%arr tiling in Layout.rect_of tiling panel) in
  let focused panel = let%arr focus in Keymap.equal_focus focus panel in
  let name panel = Keymap.name panel in
  let market =
    let%arr rect = rect Market and focused = focused Market and theme and state and motion
    and now and cumulative in
    compute (name Market);
    tile rect (fun ~width ~height ->
      Market_panel.view ~cumulative ~motion ~now ~theme ~focus:(seen_focus Market ~focused)
        ~state ~width ~height) in
  let heatmap_view =
    let%arr rect = rect Heatmap and focused = focused Heatmap and theme and state and heatmap in
    compute (name Heatmap);
    tile rect (fun ~width ~height ->
      Heatmap.view ~theme ~focus:(seen_focus Heatmap ~focused) ~heatmap ~state ~width ~height) in
  let tape_now =
    Anim_clock.windowed ~slow:metrics_step ~now ~within:print_horizon
      ~since:(let%arr tape in Option.map (List.hd (Tape_panel.prints tape)) ~f:(fun (print : Tape_panel.print) -> print.time))
      () in
  let tape_view =
    let%arr rect = rect Tape and focused = focused Tape and theme and tape and now = tape_now in
    compute (name Tape);
    tile rect (fun ~width ~height ->
      Tape_panel.view ~theme ~focus:(seen_focus Tape ~focused) ~tape ~now ~width ~height) in
  let metrics_now = Anim_clock.quantized ~now ~step:metrics_step in
  let metrics_view =
    let%arr rect = rect Metrics and focused = focused Metrics and theme
    and metrics and now = metrics_now in
    compute (name Metrics);
    tile rect (fun ~width ~height ->
      Metrics_panel.view ~theme ~focus:(seen_focus Metrics ~focused) ~metrics ~now ~width ~height) in
  let latency =
    let%arr rect = rect Latency and focused = focused Latency and theme
    and state = projected Deps.latency in
    compute (name Latency);
    tile rect (fun ~width ~height ->
      Latency_panel.view ~theme ~focus:(seen_focus Latency ~focused) ~state ~width ~height) in
  let rules =
    let%arr rect = rect Rules and focused = focused Rules and theme
    and state = projected Deps.rules and selected in
    compute (name Rules);
    tile rect (fun ~width ~height ->
      Rules_panel.view ~theme ~focus:(seen_focus Rules ~focused) ~state ~selected ~width ~height) in
  let decisions =
    let%arr rect = rect Decisions and history in
    compute (name Decisions);
    tile rect (fun ~width:_ ~height:_ -> history.History_panel.view) in
  let inspected = Bonsai.cutoff ~equal:[%equal: decision option]
      (let%arr history in history.History_panel.model.inspected) in
  let mode = let%arr state in state.mode in
  let inspector =
    let%arr rect = rect Inspector and focused = focused Inspector and theme and mode
    and decision = inspected in
    compute (name Inspector);
    tile rect (fun ~width ~height ->
      Inspector.view ~theme ~focus:(seen_focus Inspector ~focused) ~mode ~decision ~width ~height) in
  let configuration =
    let%arr rect = rect Configuration and focused = focused Configuration and theme
    and state = projected Deps.configuration in
    compute (name Configuration);
    tile rect (fun ~width ~height ->
      Config_review.view ~theme ~focus:(seen_focus Configuration ~focused) ~state ~width ~height) in
  (* The tiling joins the panels' views by rows and columns, so every cell is drawn once. *)
  let%arr tiling and market and heatmap_view and tape_view and metrics_view and latency and rules
  and decisions and inspector and configuration in
  compute "body";
  Layout.fold tiling ~row:View.hcat ~column:View.vcat ~panel:(fun panel _ ->
    match (panel : Keymap.focus) with
    | Market -> market | Heatmap -> heatmap_view | Tape -> tape_view | Metrics -> metrics_view
    | Latency -> latency | Rules -> rules | Decisions -> decisions | Inspector -> inspector
    | Configuration -> configuration)
