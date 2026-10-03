open! Core
open Bonsai_term
open Tickweave_tui
open Model_adapter

(* What one rebuild of each panel's view costs, at the rectangle the Monitor, Decide and
   Configure presets give it. MOCK fixture data throughout: the book comes from the seeded
   mock backend stepped at the bench's 1000 Hz and sampled at 60 frames a second, so every
   rolling window (the market samples, the heatmap ring, the tape, the metrics) is full, and
   each render is of the next frame's inputs, as the app's is.

   A "render" is what the app does to a panel when its inputs change: build the view, fit it to
   its tile, put the backdrop under it and build the terminal image. The nanoseconds and the
   minor words are medians over many renders. Nanoseconds depend on the machine and are only
   printed (set TICKWEAVE_VIEW_COST=1); the words do not, so budgets on them are tested. *)

let frame_rate = 60.
let stream_hz = 1000.
let history = 3600  (* a minute of painted frames: every window is full *)
let kept = 120  (* the frames whose inputs are rendered, the last of the history *)
let steps_per_frame = Float.to_int (stream_hz /. frame_rate)
let epoch = Time_ns.add Time_ns.epoch (Time_ns.Span.of_sec 50_000.)
let at frame = Time_ns.add epoch (Time_ns.Span.of_sec (Float.of_int frame /. frame_rate))

(* Everything a panel's view reads at one frame. *)
type frame =
  { state : application_state; now : Time_ns.t; motion : Market_motion.t; heatmap : Heatmap.t
  ; tape : Tape_panel.t; metrics : Metrics_state.t }

(* The last [kept] frames of a run of [history] frames, oldest first. *)
let run ~scenario =
  let backend = ref (Or_error.ok_exn
      (Mock_backend.create_with_max_rate ~max_rate_hz:stream_hz ~scenario ~seed:42 ~rate_hz:stream_hz)) in
  let motion = ref Market_motion.empty and heatmap = ref Heatmap.empty and tape = ref Tape_panel.empty
  and metrics = ref Metrics_state.empty in
  Array.init history ~f:(fun index ->
    let frame = index + 1 in
    for _ = 1 to steps_per_frame do backend := Mock_backend.advance !backend done;
    let state = Mock_backend.state !backend and now = at frame in
    motion := Market_motion.observe !motion ~now ~snapshot:state.market ~updates:state.updates;
    heatmap := Heatmap.observe_sampled !heatmap ~rate_hz:state.rate_hz state.market;
    Option.iter state.latest_decision ~f:(fun decision -> heatmap := Heatmap.note_decision !heatmap decision);
    tape := Tape_panel.observe !tape ~now ~snapshot:state.market;
    if frame % Float.to_int frame_rate = 0 then metrics := Metrics_state.observe !metrics ~now state;
    (* Only the frames that will be rendered are kept; the rest are the history they stand on. *)
    if index < history - kept then None
    else Some { state; now; motion = !motion; heatmap = !heatmap; tape = !tape; metrics = !metrics })
  |> Array.filter_opt

let quiet = lazy (run ~scenario:Connected_disarmed)
let busy = lazy (run ~scenario:Enabled)

let rect ~preset ~width ~height panel =
  let toggles = { Ui_types.heatmap = true; cumulative = false } in
  List.Assoc.find_exn
    (Layout.compute ~preset ~zoom:None ~toggles ~width ~height:(Layout.body_height ~height))
    panel ~equal:Ui_types.equal_panel_id

(* One panel as the app builds it: [Panel_views.tile], then the backdrop and the image. *)
let render ~theme (rect : Ui_types.rect) view =
  Panel.fit view ~width:rect.width ~height:rect.height
  |> Theme.backdrop theme |> View.Private.notty_image |> ignore

let median values =
  let sorted = Array.of_list values in
  Array.sort sorted ~compare:Float.compare;
  sorted.(Array.length sorted / 2)

(* The nanoseconds and minor words of each of [count] runs of [step], after a warm-up. [step]
   is told which of the runs it is, to pick that frame's inputs. *)
let samples ?(count = kept) step =
  for index = 0 to 4 do step index done;
  List.init count ~f:(fun index ->
    let words = Gc.minor_words () and start = Time_ns.now () in
    step index;
    let stop = Time_ns.now () in
    Time_ns.diff stop start |> Time_ns.Span.to_ns, Float.of_int (Gc.minor_words () - words))

(* The median nanoseconds and minor words. *)
let measure ?count step =
  let samples = samples ?count step in
  median (List.map samples ~f:fst), median (List.map samples ~f:snd)

let theme = Theme.create Truecolor
let focus = Keymap.Market

(* Every panel in the Monitor preset, plus the cold ones at the rectangle they have in the
   preset that shows them. A case builds the view of the frame it is told. *)
let cases ~width ~height =
  let quiet = Lazy.force quiet and busy = Lazy.force busy in
  let monitor = rect ~preset:Monitor ~width ~height in
  let decide = rect ~preset:Decide ~width ~height in
  let configure = rect ~preset:Configure ~width ~height in
  let in_frames frames build index ~width ~height =
    build frames.(index % Array.length frames) ~width ~height in
  (* The newest rows of each frame's log, found once: finding them is not what is measured. *)
  let rows = Array.map busy ~f:(fun frame -> List.take (List.rev (Decision_buffer.to_list frame.state.decisions)) 58) in
  [ "market", monitor Market, in_frames quiet (fun f ~width ~height ->
      Market_panel.view ~cumulative:false ~motion:f.motion ~now:f.now ~theme ~focus ~state:f.state ~width ~height)
  ; "heatmap", monitor Heatmap, in_frames quiet (fun f ~width ~height ->
      Heatmap.view ~theme ~focus ~heatmap:f.heatmap ~state:f.state ~width ~height)
  ; "tape", monitor Tape, in_frames quiet (fun f ~width ~height ->
      Tape_panel.view ~theme ~focus ~tape:f.tape ~now:f.now ~width ~height)
  ; "metrics", monitor Metrics, in_frames quiet (fun f ~width ~height ->
      Metrics_panel.view ~theme ~focus ~metrics:f.metrics ~now:f.now ~width ~height)
  ; "latency", monitor Latency, in_frames quiet (fun f ~width ~height ->
      Latency_panel.view ~theme ~focus ~state:f.state ~width ~height)
  ; "rules", decide Rules, in_frames busy (fun f ~width ~height ->
      let selected = Option.map (List.hd f.state.rules) ~f:(fun rule -> rule.rule_id) in
      Rules_panel.view ~theme ~focus ~state:f.state ~selected ~width ~height)
  ; "config", configure Configuration, in_frames busy (fun f ~width ~height ->
      Config_review.view ~theme ~focus ~state:f.state ~width ~height)
  ; "decision rows", decide Decisions, (fun index ~width ~height:_ ->
      View.vcat (List.map rows.(index % Array.length rows) ~f:(fun decision ->
        Decision_row.view ~theme ~width:(width - 4) ~selected:false ~fresh:0. decision)))
  ; "header", { col = 0; row = 0; width; height = 1 }, in_frames quiet (fun f ~width ~height:_ ->
      Status_bar.view ~theme ~state:f.state ~clock:"13:37:00" ~width)
  ; "footer", { col = 0; row = 0; width; height = 1 }, in_frames quiet (fun _ ~width ~height:_ ->
      Footer.view ~theme ~focus ~preset:Monitor ~zoomed:false ~scheme:Tickweave_amber ~notice:None ~width) ]

let table ~width ~height =
  List.map (cases ~width ~height) ~f:(fun (name, rect, build) ->
    let ns, words = measure (fun index -> render ~theme rect (build index ~width:rect.width ~height:rect.height)) in
    name, rect, ns, words)

let print_table ~width ~height =
  printf "%dx%d  %-14s %10s %10s %12s\n" width height "panel" "tile" "median us" "minor words";
  let total_words = ref 0. in
  List.iter (table ~width ~height) ~f:(fun (name, (rect : Ui_types.rect), ns, words) ->
    total_words := !total_words +. words;
    printf "         %-14s %4dx%-5d %10.1f %12.0f\n" name rect.width rect.height (ns /. 1000.) words);
  printf "         %-14s %10s %10s %12.0f\n" "total" "" "" !total_words

let%expect_test "per-panel cost table (printed only with TICKWEAVE_VIEW_COST=1)" =
  if [%equal: string option] (Sys.getenv "TICKWEAVE_VIEW_COST") (Some "1") then (
    print_table ~width:120 ~height:36;
    print_table ~width:200 ~height:60);
  [%expect {| |}]

(* ==== The optimized code, against what it replaced ==== *)

(* The fewest minor words of a render of [name] at [width] x [height], of one frame's inputs again
   and again: what the view's own code allocates, without the cost of text Notty has not seen
   before, which comes and goes with the collector. *)
let words_of name ~width ~height =
  let _, rect, build = List.find_exn (cases ~width ~height) ~f:(fun (n, _, _) -> String.equal n name) in
  samples (fun _ -> render ~theme rect (build 0 ~width:rect.width ~height:rect.height))
  |> List.map ~f:snd |> List.min_elt ~compare:Float.compare |> Option.value_exn

(* Budgets, in minor words a render may allocate, with room above what it takes today. Each
   is below what the view took before it was made to allocate little: a view that goes back to
   allocating a word for every sample, or a list for every cell, goes over. *)
let%expect_test "a panel's render stays within its allocation budget at 200x60" =
  let budgets =
    [ "market", 50_000          (* 281 000 before: a list and a boxed float for each of 3 600 samples, three times *)
    ; "heatmap", 165_000        (* 183 000 before; what is left is a text node for each run of one colour *)
    ; "tape", 13_000            (* 17 000 *)
    ; "metrics", 52_000         (* 63 000 *)
    ; "latency", 29_000         (* 36 000 *)
    ; "decision rows", 26_000   (* 41 000 *)
    ; "header", 3_500 ] in      (* 9 600: twelve candidate headers were built for each one shown *)
  List.iter budgets ~f:(fun (name, budget) ->
    let words = Float.to_int (words_of name ~width:200 ~height:60) in
    if words > budget then printf "%s: %d words, over its budget of %d\n" name words budget);
  printf "within budget\n";
  [%expect {| within budget |}]

let%expect_test "no panel raises at any size, down to none at all" =
  let busy = (Lazy.force busy).(0) and quiet = (Lazy.force quiet).(0) in
  let failures = ref [] in
  List.iter [ 0; 1; 2; 3; 4; 5; 11; 12; 13; 24; 47; 65; 100 ] ~f:(fun width ->
    List.iter [ 0; 1; 2; 3; 4; 5; 6; 10; 14; 30 ] ~f:(fun height ->
      let attempt name view =
        try ignore (View.width (view ()) : int)
        with exn -> failures := sprintf "%s %dx%d: %s" name width height (Exn.to_string exn) :: !failures in
      let selected = Option.map (List.hd busy.state.rules) ~f:(fun rule -> rule.rule_id) in
      attempt "market" (fun () ->
        Market_panel.view ~cumulative:false ~motion:quiet.motion ~now:quiet.now ~theme ~focus ~state:quiet.state ~width ~height);
      attempt "market, cumulative" (fun () ->
        Market_panel.view ~cumulative:true ~motion:busy.motion ~now:busy.now ~theme ~focus ~state:busy.state ~width ~height);
      attempt "heatmap" (fun () -> Heatmap.view ~theme ~focus ~heatmap:quiet.heatmap ~state:quiet.state ~width ~height);
      attempt "tape" (fun () -> Tape_panel.view ~theme ~focus ~tape:quiet.tape ~now:quiet.now ~width ~height);
      attempt "metrics" (fun () -> Metrics_panel.view ~theme ~focus ~metrics:quiet.metrics ~now:quiet.now ~width ~height);
      attempt "latency" (fun () -> Latency_panel.view ~theme ~focus ~state:quiet.state ~width ~height);
      attempt "rules" (fun () -> Rules_panel.view ~theme ~focus ~state:busy.state ~selected ~width ~height);
      attempt "config" (fun () -> Config_review.view ~theme ~focus ~state:busy.state ~width ~height);
      attempt "chart" (fun () ->
        Market_chart.view ~theme ~samples:quiet.motion.samples ~now:quiet.now ~threshold:(Some 1005) ~width ~height);
      attempt "sparkline" (fun () -> View.text (Sparkline.ask ~samples:quiet.motion.samples ~now:quiet.now ~width));
      attempt "header" (fun () -> Status_bar.view ~theme ~state:busy.state ~clock:"13:37:00" ~width);
      attempt "footer" (fun () ->
        Footer.view ~theme ~focus ~preset:Monitor ~zoomed:true ~scheme:Tokyo_night ~notice:(Some "notice") ~width);
      List.iter (List.take (List.rev (Decision_buffer.to_list busy.state.decisions)) 4) ~f:(fun decision ->
        attempt "decision row" (fun () -> Decision_row.view ~theme ~width ~selected:false ~fresh:0.5 decision))));
  printf "%d failures%s\n" (List.length !failures)
    (String.concat (List.map (List.take (List.rev !failures) 5) ~f:(fun failure -> "\n  " ^ failure)));
  [%expect {| 0 failures |}]

let%expect_test "the market's sparkline allocates nothing for the samples it walks" =
  let frame = (Lazy.force quiet).(0) in
  let samples = frame.motion.samples in
  let _, words = measure (fun _ -> ignore (Sparkline.ask ~samples:frame.motion.samples ~now:frame.now ~width:63 : string)) in
  printf "a minute of samples: %b, under 1000 words: %b\n" (Age_deque.length samples > 3000) Float.(words < 1000.);
  [%expect {| a minute of samples: true, under 1000 words: true |}]

let%expect_test "Clock_text is the UTC time of day Time_ns formats, to the millisecond and the second" =
  let random = Random.State.make [| 7 |] in
  let day = 86_400_000_000_000 in
  let times = List.init 20_000 ~f:(fun _ ->
      Time_ns.of_int_ns_since_epoch
        ((Random.State.int random 1_000_000 * day / 1_000_000) + (Random.State.int random 40_000 * day)))
    @ List.map [ 0; 1; 999_999; 1_000_000; 59_999_999_999; 86_399_999_999_999; 86_400_000_000_000; -1
               ; 1_700_000_000_123_456_789 ] ~f:Time_ns.of_int_ns_since_epoch in
  let wrong = List.filter times ~f:(fun time ->
      let ofday = Time_ns.to_ofday time ~zone:Timezone.utc in
      not (String.equal (Clock_text.utc_millis time) (Time_ns.Ofday.to_millisecond_string ofday)
           && String.equal (Clock_text.utc_seconds time) (Time_ns.Ofday.to_sec_string ofday))) in
  printf "%d times checked, %d differ\n" (List.length times) (List.length wrong);
  [%expect {| 20009 times checked, 0 differ |}]

let%expect_test "display_width is the width of the view the text becomes" =
  let texts =
    [ ""; "ask 1003"; "−60 s"; "━ ask  ═ bid"; "▲ admitted  ✗ blocked"; "⡖⢲ ⡖⡆⢰⠒⡆"; "γ1.2, white above 1.5×"
    ; "← older … 12 columns · 200 ms each · newest →"; "日本語 market"; "e\u{301}"; "tab\there"; "bell\007"
    ; "\u{0085}c1"; "emoji ✅ ok"; "vs16 \u{2764}\u{fe0f}"; "bad \255 utf8"; "µs · ticks · ±" ] in
  let wrong = List.filter texts ~f:(fun text ->
      Braille_chart.display_width text <> View.width (View.text text)) in
  printf "%d texts checked, differing: %s\n" (List.length texts)
    (String.concat ~sep:" | " (List.map wrong ~f:String.escaped));
  [%expect {| 17 texts checked, differing: |}]

let%expect_test "int_width and repeat are what they replaced" =
  let values = [ 0; 1; -1; 9; 10; -9; -10; 99; 100; 1003; -1003; 999_999_999; Int.max_value; Int.min_value ] in
  let wrong = List.filter values ~f:(fun value ->
      Braille_chart.int_width value <> String.length (Int.to_string value)) in
  let repeats = [ "─", 0; "─", 1; "─", 7; "╌", 3; "x", -2 ] in
  let wrong_repeats = List.filter repeats ~f:(fun (glyph, count) ->
      not (String.equal (Braille_chart.repeat glyph count)
             (String.concat (List.init (Int.max 0 count) ~f:(fun _ -> glyph))))) in
  printf "widths differing: %d; repeats differing: %d\n" (List.length wrong) (List.length wrong_repeats);
  [%expect {| widths differing: 0; repeats differing: 0 |}]

let%expect_test "the heatmap's settler agrees with settle for every size, bucket and scale" =
  let differing = ref 0 and checked = ref 0 in
  List.iter [ 0; 1; 7; 20; 100; 333; 1000 ] ~f:(fun maximum ->
    let settler = Heatmap.settler ~maximum in
    List.iter (List.range (-2) 2200) ~f:(fun quantity ->
      List.iter (List.range 0 Heatmap.buckets) ~f:(fun before ->
        incr checked;
        if settler ~before quantity <> Heatmap.settle ~before ~maximum quantity then incr differing)));
  printf "%d cases, %d differ\n" !checked !differing;
  [%expect {| 184968 cases, 0 differ |}]

(* [Sparkline.ask] as it was written, from [braille] and a list of rows. *)
let ask_by_braille ~(samples : Market_motion.sample list) ~now ~width =
  let cutoff = Time_ns.sub now Sparkline.window in
  let samples = List.filter samples ~f:(fun (s : Market_motion.sample) ->
      Time_ns.compare s.time cutoff >= 0 && Time_ns.compare s.time now <= 0) |> List.rev in
  let prices = List.filter_map samples ~f:(fun s -> s.ask) in
  match List.min_elt prices ~compare:Int.compare, List.max_elt prices ~compare:Int.compare with
  | Some low, Some high ->
    let distance left right =
      Stdlib.Int64.sub (Stdlib.Int64.of_int left) (Stdlib.Int64.of_int right) |> Stdlib.Int64.to_float in
    let span = distance high low in
    let row price =
      if Float.(span = 0.) then 2
      else Int.max 0 (Int.min 3 (Float.iround_nearest_exn (3. *. (distance high price) /. span))) in
    Sparkline.braille ~now ~width (List.map samples ~f:(fun s -> s.time, Option.map s.ask ~f:row))
  | _ -> String.make (Int.max 0 width) ' '

let%expect_test "the market's sparkline draws what braille draws from the same samples" =
  let random = Random.State.make [| 11 |] in
  let differing = ref 0 and checked = ref 0 in
  for _ = 1 to 400 do
    let count = Random.State.int random 60 in
    let width = Random.State.int random 40 in
    let now = Time_ns.add epoch (Time_ns.Span.of_sec 100.) in
    let spread = 1 + Random.State.int random 20 in
    (* Newest first, as the history is kept: each is a little older than the one before. *)
    let samples = List.folding_map (List.range 0 count) ~init:0. ~f:(fun age _ ->
        let age = age +. 0.2 +. Random.State.float random 2. in
        age, ({ time = Time_ns.sub now (Time_ns.Span.of_sec age)
        ; bid = Some 1000
        ; ask = (if Random.State.int random 6 = 0 then None else Some (1000 + Random.State.int random spread))
        ; delta_updates = 1 } : Market_motion.sample)) in
    incr checked;
    if not (String.equal (Sparkline.ask ~samples:(Age_deque.of_list samples) ~now ~width) (ask_by_braille ~samples ~now ~width))
    then incr differing
  done;
  printf "%d series, %d differ\n" !checked !differing;
  [%expect {| 400 series, 0 differ |}]

(* Decisions from the seeded mock stream, [count] of them from the [first]th, under [run_id]. *)
let decisions_of ~run_id ~first ~count : decision_log =
  let backend = ref (Or_error.ok_exn
      (Mock_backend.create_with_max_rate ~max_rate_hz:1000. ~scenario:Enabled ~seed:3 ~rate_hz:1000.)) in
  let decisions = ref [] in
  while List.length !decisions < first + count do
    backend := Mock_backend.advance !backend;
    Option.iter (Mock_backend.state !backend).latest_decision ~f:(fun decision ->
      decisions := { decision with identity = { decision.identity with run_id } } :: !decisions)
  done;
  List.fold (List.drop (List.rev !decisions) first) ~init:Decision_buffer.empty ~f:Decision_buffer.append

(* [History_state.receive]'s fresh keys as they were found, by a walk over every record. *)
let%expect_test "a log's new keys are the same when found by the difference between two logs" =
  let by_walking (before : decision_log) (after : decision_log) =
    Map.fold after.records ~init:[] ~f:(fun ~key:sequence ~data:decision keys ->
      let fresh = match Map.find before.records sequence with
        | None -> true | Some previous -> not (History_state.same_key previous decision) in
      if fresh then History_state.key decision :: keys else keys) in
  let first = decisions_of ~run_id:"a" ~first:0 ~count:30 and later = decisions_of ~run_id:"a" ~first:0 ~count:55
  and other = decisions_of ~run_id:"b" ~first:0 ~count:40 in
  List.iter [ "append", first, later; "nothing new", later, later; "another run", later, other
            ; "from nothing", Decision_buffer.empty, first ] ~f:(fun (name, before, after) ->
    let received = History_state.receive { History_state.empty with live = before; shown = before } after in
    printf "%s: %d new keys, as walking finds them: %b\n" name (List.length received.fresh_keys)
      ([%equal: (string * int option) list] received.fresh_keys (by_walking before after)));
  [%expect {|
    append: 25 new keys, as walking finds them: true
    nothing new: 0 new keys, as walking finds them: true
    another run: 40 new keys, as walking finds them: true
    from nothing: 30 new keys, as walking finds them: true
    |}]

(* The window the history panel shows, read by position, against the rows it replaced. *)
let%expect_test "the history window read by position is the window of the rows" =
  let log = decisions_of ~run_id:"run" ~first:0 ~count:300 in
  let model = History_state.receive History_state.empty log in
  let reference (model : History_state.t) ~height =
    let rows = History_state.rows model in
    let count = Array.length rows in
    let start = if model.follow then Int.max 0 (count - height)
      else Int.clamp_exn model.offset ~min:0 ~max:(Int.max 0 (count - height)) in
    start, count, Array.sub rows ~pos:start ~len:(Int.min height (count - start)) |> Array.to_list in
  let differing = ref 0 and checked = ref 0 in
  List.iter [ 1; 5; 30; 299; 300; 400 ] ~f:(fun height ->
    List.iter [ true, 0; false, 0; false, 7; false, 250; false, 299; false, 1000; false, -4 ] ~f:(fun (follow, offset) ->
      List.iter [ model; { model with live = Decision_buffer.empty; shown = Decision_buffer.empty } ] ~f:(fun model ->
        incr checked;
        let model = { model with follow; offset } in
        if not ([%equal: int * int * decision list] (History_panel.window_of model ~height) (reference model ~height))
        then incr differing)));
  printf "%d windows, %d differ\n" !checked !differing;
  [%expect {| 84 windows, 0 differ |}]
