open Tickweave
let () =
  let source = ref "live" and transport = ref "dry-run" and port = ref "" in
  let input = ref "" and output = ref "" and capture = ref "" in
  let dataset = ref "" and symbol_a = ref "" and symbol_b = ref "" in
  let start = ref "" and end_ = ref "" and limit = ref 100000 in
  let packets = ref 100 and sessions = ref 1 and seed = ref 42 in
  let quantum = ref 10_000_000L and timeout = ref 1. and interval_ms = ref 0. in
  let pair_timeout = ref 60. in
  let swap_slots = ref false and fault = ref "none" and build_id = ref "unknown" in
  let options = [
    "--source", Arg.Set_string source, "live|historical|replay|requests|synthetic";
    "--transport", Arg.Set_string transport, "dry-run|mock|serial";
    "--port", Arg.Set_string port, "Linux serial device (115200 8N1)";
    "--input", Arg.Set_string input, "Replay file: normalized Databento trades or integer requests";
    "--output", Arg.Set_string output, "New CSV transaction log (required; existing file is preserved)";
    "--capture", Arg.Set_string capture, "New normalized trade CSV for offline replay";
    "--dataset", Arg.Set_string dataset, "Databento dataset (required for API sources)";
    "--symbol-a", Arg.Set_string symbol_a, "Raw symbol mapped to Item A=17";
    "--symbol-b", Arg.Set_string symbol_b, "Raw symbol mapped to Item B=34";
    "--start", Arg.Set_string start, "Historical interval start (ISO 8601)";
    "--end", Arg.Set_string end_, "Historical interval end (exclusive)";
    "--record-limit", Arg.Set_int limit, "Maximum historical trade records (default 100000)";
    "--packets", Arg.Set_int packets, "Packets per session (default 100, maximum 65536)";
    "--sessions", Arg.Set_int sessions, "Sessions on one transport connection (default 1)";
    "--seed", Arg.Set_int seed, "Synthetic generator seed (default 42)";
    "--price-quantum-nanos", Arg.String (fun x -> quantum := Int64.of_string x), "Nanodollars per UART price unit (default 10000000 = one cent, floor)";
    "--timeout", Arg.Set_float timeout, "Total UART transaction deadline in seconds (default 1)";
    "--interval-ms", Arg.Set_float interval_ms, "Minimum spacing before next transaction (default 0)";
    "--pair-timeout", Arg.Set_float pair_timeout, "Maximum wait for a fresh two-symbol pair in seconds (default 60)";
    "--swap-slots", Arg.Set swap_slots, "Alternate A/B packet slots for market sources";
    "--mock-fault", Arg.Set_string fault, "none|timeout|partial|wrong-index|wrong-item|reserved|action|mismatch|extra (at packet 16)";
    "--build-id", Arg.Set_string build_id, "FPGA build/source identifier written to every log row"
  ] in
  let cleanup = ref [] in
  let register f = cleanup := f :: !cleanup in
  let close_all () = List.iter (fun f -> try f () with _ -> ()) !cleanup; cleanup := [] in
  try
    Sys.catch_break true;
    Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
    Arg.parse options (fun _ -> raise (Arg.Bad "Unexpected positional argument")) "Tickweave OCaml data streamer";
    let require condition message = if not condition then invalid_arg message in
    require (List.mem !source ["live";"historical";"replay";"requests";"synthetic"]) "Unknown --source";
    require (List.mem !transport ["dry-run";"mock";"serial"]) "Unknown --transport";
    require (!output <> "") "--output is required";
    require (!packets > 0 && !packets <= 65536) "--packets must be in 1..65536";
    require (!sessions > 0) "--sessions must be positive";
    require (Float.is_finite !timeout && !timeout > 0.) "--timeout must be finite and positive";
    require (Float.is_finite !interval_ms && !interval_ms >= 0.) "--interval-ms must be finite and nonnegative";
    require (Float.is_finite !pair_timeout && !pair_timeout > 0.) "--pair-timeout must be finite and positive";
    require (!quantum > 0L) "--price-quantum-nanos must be positive";
    require (!limit > 0) "--record-limit must be positive";
    require (List.mem !fault Mock.faults) "Unknown --mock-fault";
    require (!fault = "none" || !transport = "mock") "--mock-fault requires --transport mock";
    require (!transport <> "serial" || !port <> "") "--port is required for serial transport";
    let market_source = List.mem !source ["live";"historical";"replay"] in
    require (not market_source || (!symbol_a <> "" && !symbol_b <> "" && !symbol_a <> !symbol_b)) "Market sources need distinct --symbol-a and --symbol-b";
    require (not (List.mem !source ["replay";"requests"]) || !input <> "") "Replay sources require --input";
    require (not (List.mem !source ["live";"historical"]) || !dataset <> "") "API sources require --dataset";
    require (!source <> "historical" || (!start <> "" && !end_ <> "")) "Historical source requires --start and --end";
    require (!capture = "" || market_source) "--capture is only supported with trade sources";
    let key = if List.mem !source ["live";"historical"] then
      match Sys.getenv_opt "DATABENTO_API_KEY" with Some x when x <> "" -> x | _ -> invalid_arg "Set DATABENTO_API_KEY in the environment"
      else "" in
    let log = Log.open_new !output in register (fun () -> close_out log); Log.header log;
    let capture_ch = if !capture = "" then None else (
      let c = Log.open_new !capture in register (fun () -> close_out c);
      Log.write c ["symbol";"ts_event";"price"]; Some c) in
    let t = match !transport with
      | "serial" -> let t = Transport.serial !port in register (fun () -> Transport.close t); Some t
      | "mock" -> let t, stop = Mock.create ~fault:!fault in register stop; Some t
      | _ -> None in
    let shared_source = match !source with
      | "live" -> Some (Databento.live ~api_key:key ~dataset:!dataset ~symbols:[!symbol_a;!symbol_b])
      | "historical" -> Some (Databento.historical ~api_key:key ~dataset:!dataset ~symbols:[!symbol_a;!symbol_b] ~start:!start ~end_:!end_ ~limit:!limit)
      | _ -> None in
    Option.iter (fun (s : Databento.source) -> register s.close) shared_source;
    let requests = if !source = "requests" then Some (Array.of_list (Scenarios.replay !input))
      else if !source = "synthetic" then Some (Array.of_list (Scenarios.synthetic ~seed:!seed ~count:!packets)) else None in
    Option.iter (fun rows -> require (Array.length rows = !packets) "Request replay must have exactly --packets rows") requests;
    let source_name = if !input <> "" then !source ^ ":" ^ !input else !source ^ ":" ^ !dataset in
    let run_id = Printf.sprintf "%.0f-%d" (Unix.gettimeofday () *. 1000.) (Unix.getpid ()) in
    let rec run session =
      if session <= !sessions then (
        let local_source = if !source = "replay" then Some (Databento.replay !input) else None in
        Option.iter (fun (s : Databento.source) -> register s.close) local_source;
        let market = match local_source with Some _ -> local_source | None -> shared_source in
        let pairing = if market_source then Some (Pairing.create ~symbol_a:!symbol_a ~symbol_b:!symbol_b ~quantum:!quantum) else None in
        let rec next_market deadline index (s : Databento.source) pairer =
          if Clock.now () >= deadline then failwith "Timed out waiting for a fresh two-symbol price pair";
          match s.next () with
          | None -> None
          | Some tick ->
            Option.iter (fun c -> Log.write c [tick.symbol;tick.ts_event;Int64.to_string tick.price]) capture_ch;
            match Pairing.push pairer tick with
            | None -> next_market deadline index s pairer
            | Some p ->
              let request : Protocol.request = if !swap_slots && index mod 2 = 1 then
                {index;item1=34;price1=p.price_b;item2=17;price2=p.price_a}
                else {index;item1=17;price1=p.price_a;item2=34;price2=p.price_b} in
              Some { Runner.request; market = Some p }
        in
        let next index =
          if index > 0 && !interval_ms > 0. then ignore (Unix.select [] [] [] (!interval_ms /. 1000.));
          match requests, market, pairing with
          | Some rows, _, _ -> Some { Runner.request = rows.(index); market = None }
          | _, Some s, Some p -> next_market (Clock.now () +. !pair_timeout) index s p
          | _ -> assert false in
        let ok = Runner.run_session ~session_id:(Printf.sprintf "%s-%d" run_id session) ~source_name
          ~seed:(if !source = "synthetic" then string_of_int !seed else "") ~build_id:!build_id
          ~quantum:!quantum ~count:!packets ~timeout:!timeout ~transport:t ~log ~next in
        Option.iter (fun (s : Databento.source) -> s.close ()) local_source;
        if ok then run (session + 1) else false)
      else true in
    let ok = run 1 in close_all (); if not ok then exit 1
  with exn -> close_all (); Printf.eprintf "Streamer failed: %s\n%!" (Printexc.to_string exn); exit 1
