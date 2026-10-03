open! Core
open Tickweave_tui

let console =
  Async.Command.async_or_error ~summary:"tickweave operator console (Phase 4)"
    (let%map_open.Command
       mode = flag "--mode" (optional_with_default "mock" string)
         ~doc:"MODE mock, simulation (alias sim), or hardware"
     and scenario = flag "--scenario" (optional_with_default "connected_disarmed" string)
         ~doc:"NAME deterministic MOCK fixture"
     and seed = flag "--seed" (optional_with_default 42 int) ~doc:"N mock random seed"
     and rate_hz = flag "--rate" (optional_with_default 4. float)
         ~doc:"HZ mock stream rate, in [0.1, 60]; up to 1000 with --bench"
     and bench = flag "--bench" no_arg
         ~doc:" run the app for 20 s in this terminal, then print frame-time statistics (mock only)"
     in
     fun () ->
       match mode with
       | _ when bench && not (String.equal mode "mock") ->
         Async.Deferred.return (Or_error.error_string "--bench needs --mode mock")
       | "simulation" | "sim" | "hardware" ->
         printf "%s: not yet connected\n" (if String.equal mode "hardware" then "HW" else "SIM");
         Async.Deferred.Or_error.return ()
       | "mock" ->
         let max_rate_hz = if bench then Bench.max_rate_hz else Mock_backend.max_rate_hz in
         (match Or_error.bind (Mock_backend.scenario_of_string scenario)
                  ~f:(fun scenario ->
                    Mock_backend.create_with_max_rate ~max_rate_hz ~scenario ~seed ~rate_hz) with
          | Error error -> Async.Deferred.return (Error error)
          | Ok backend when bench -> Bench.run ~theme:(Theme.detect ()) ~backend ~rate_hz
          | Ok backend ->
            (* Clicks and wheel, but not hover. *)
            Bonsai_term.start_with_exit ~mouse:All_mouse_events_except_hover
              (fun ~exit ~dimensions (local_ graph) ->
                 App.live (module Mock_backend) ~theme:(Theme.detect ()) ~backend ~exit
                   ~dimensions graph))
       | _ -> Async.Deferred.return
           (Or_error.error_string "--mode must be mock, simulation, sim, or hardware"))

let () = Command_unix.run (Command.group ~summary:"tickweave" [ "console", console ])
