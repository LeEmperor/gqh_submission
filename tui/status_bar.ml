open! Core
open Bonsai_term
open Model_adapter

let mode_name = function Mock -> "MOCK" | Simulation -> "SIM" | Hardware -> "HW"
let numbered_step step =
  List.mem [ "1/6"; "2/6"; "3/6"; "4/6"; "5/6"; "6/6" ] step ~equal:String.equal

let configuration_label (configuration : configuration) =
  let last = Option.value_map configuration.last_acknowledged_version
      ~default:"none" ~f:(sprintf "v%d") in
  match configuration.status with
  | Active_acknowledged version -> sprintf "cfg ✓ACK v%d" version, Theme.Bid
  | Draft -> "cfg DRAFT last " ^ last, Warn
  | Validated -> "cfg VALIDATED last " ^ last, Warn
  | Applying step when numbered_step step ->
    "cfg " ^ (if Option.is_some configuration.last_acknowledged_version
              then "✓ACK " ^ last else "ACK none") ^ " ◐ APPLYING " ^ step, Warn
  | Applying step -> "cfg ◐APPLYING(" ^ step ^ ") last " ^ last, Warn
  | Failed _ -> "cfg ✗FAILED last " ^ last, Ask
  | Unknown -> "cfg ?UNKNOWN last " ^ last, Alarm

(* What the header reads, and nothing else. The app cuts the header off on this, so the market
   book and the update counter, which change on every stream tick, never rebuild it. A test
   changes every other field and requires the same header. *)
let same_inputs (a : application_state) (b : application_state) =
  equal_mode a.mode b.mode && Bool.equal a.connected b.connected
  && String.equal a.build_id b.build_id && String.equal a.run_id b.run_id
  && equal_configuration a.configuration b.configuration && equal_engine a.engine b.engine
  && Bool.equal a.market.valid b.market.valid && Int.equal a.trace_loss b.trace_loss

(* Compact lower-priority fields before ever clipping: clock, trace label,
   build/run labels, then build/run fields. Safety states retain words/glyphs. Each field is
   its segments, a run of text and the attributes it is drawn with. *)
let fields ~theme ~(state : application_state) ~clock ~tier =
  let config, config_role = configuration_label state.configuration in
  let config = if tier = 9 || tier >= 11 then
      match state.configuration.status with
      | Active_acknowledged _ -> "cfg ✓ACK [wide]"
      | Draft -> "cfg DRAFT last [wide]"
      | Validated -> "cfg VALIDATED last [wide]"
      | Applying step when numbered_step step -> "cfg ✓ACK [wide] ◐ APPLYING " ^ step
      | Applying _ -> "cfg ◐APPLYING last [wide]"
      | Failed _ -> "cfg ✗FAILED last [wide]"
      | Unknown -> "cfg ?UNKNOWN last [wide]"
    else if tier < 6 then config else
      match state.configuration.status with
      | Applying step when not (numbered_step step) ->
        "cfg ◐APPLYING last " ^ Option.value_map
          state.configuration.last_acknowledged_version ~default:"none" ~f:(sprintf "v%d")
      | _ -> config in
  let engine, engine_role = match state.engine with
    | Armed -> "● ARMED", Theme.Bid | Disarmed -> "○ DISARMED", Muted
    | Idle -> "○ IDLE", Muted | Engine_unknown -> "? UNKNOWN", Alarm in
  let mode_role = match state.mode with Mock -> Theme.Warn | Simulation -> Info | Hardware -> Bid in
  let text role value = Theme.attrs theme role, value in
  [ [ [ Attr.bold ], (if tier >= 8 then "" else if tier = 7 then "tw ▸ " else "tickweave ▸ ")
    ; text mode_role (mode_name state.mode)
    ; text (if state.connected then Muted else Alarm) (if state.connected then " UP" else " LOST") ] ]
  @ (if tier >= 4 then [] else [ [ [], (if tier >= 3 then "b " else "build ") ^ state.build_id ] ])
  @ (if tier >= 5 then [] else [ [ [], (if tier >= 3 then "r " else "run ") ^ state.run_id ] ])
  @ [ [ text config_role config ]
    ; [ text engine_role engine ]
    ; [ text (if state.market.valid then Bid else Warn)
          ((if tier >= 11 then "bk " else "book ") ^ (if state.market.valid then "✓VALID" else "✗INVALID")) ]
    ; [ text (if state.trace_loss = 0 then Muted else Warn)
          (if tier >= 10 then "loss TOO WIDE" else
             sprintf "%s %d" (if tier >= 2 then "loss" else "trace loss") state.trace_loss) ] ]
  @ (if tier = 0 then [ [ text Muted (clock ^ " UTC") ] ] else [])

(* [clock] is the UTC time of day; the header labels it once, here. The richest tier that fits
   is built, and the others are only measured as text. *)
let view ~theme ~state ~clock ~width =
  let separator = " │ " in
  let size fields =
    List.sum (module Int) fields ~f:(fun segments ->
      List.sum (module Int) segments ~f:(fun (_, text) -> Braille_chart.display_width text))
    + (Braille_chart.display_width separator * Int.max 0 (List.length fields - 1)) in
  let chosen = List.find_map (List.range 0 12) ~f:(fun tier ->
      let fields = fields ~theme ~state ~clock ~tier in
      Option.some_if (size fields <= width) fields) in
  let view = match chosen with
    | Some fields ->
      let segment (attrs, text) = View.text ~attrs text in
      List.intersperse (List.map fields ~f:(fun segments -> View.hcat (List.map segments ~f:segment)))
        ~sep:(View.text ~attrs:(Theme.attrs theme Border) separator)
      |> View.hcat
    | None -> View.text ~attrs:(Theme.attrs theme Warn) "status TOO WIDE" in
  Panel.fit view ~width:(Int.max 0 width) ~height:1 |> Theme.settle theme
