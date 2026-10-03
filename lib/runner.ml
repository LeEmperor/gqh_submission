type input = { request : Protocol.request; market : Pairing.pair option }
type summary = { mutable received : int; mutable correct_packets : int; mutable correct_actions : int;
                 mutable timeouts : int; mutable failures : int; mutable elapsed : float list }
let run_session ~session_id ~source_name ~seed ~build_id ~quantum ~count ~timeout ~transport ~log ~next =
  let stats = { received = 0; correct_packets = 0; correct_actions = 0; timeouts = 0; failures = 0; elapsed = [] } in
  let reference = Reference.create () in
  let row input request_bytes response_bytes expected actual elapsed status error =
    let r = input.request in
    let fields = match input.market with
      | None -> ["";"";"";"";"";""]
      | Some p -> [p.a.symbol;p.b.symbol;p.a.ts_event;p.b.ts_event;Int64.to_string p.a.price;Int64.to_string p.b.price] in
    let actual1, actual2 = match actual with None -> "", "" | Some (a : Protocol.response) -> string_of_int a.action1, string_of_int a.action2 in
    Log.write log ([session_id;source_name;seed;build_id;string_of_int r.index;string_of_int r.item1;string_of_int r.price1;string_of_int r.item2;string_of_int r.price2]
      @ fields @ [Int64.to_string quantum;Log.hex request_bytes;Log.hex response_bytes;string_of_int expected.Protocol.action1;string_of_int expected.action2;actual1;actual2;Printf.sprintf "%.6f" (elapsed *. 1000.);string_of_bool (r.index >= 16);status;error])
  in
  let source_failure index status error =
    stats.failures <- stats.failures + 1;
    Log.write log ([session_id;source_name;seed;build_id;string_of_int index]
      @ List.init 10 (fun _ -> "")
      @ [Int64.to_string quantum;"";"";"";"";"";"";"";string_of_bool (index >= 16);status;error]);
    Printf.eprintf "Session %s packet %d: %s: %s\n%!" session_id index status error
  in
  let rec loop index =
    if index < count then (
      match (try Ok (next index) with exn -> Error (Printexc.to_string exn)) with
      | Error error -> source_failure index "SOURCE_ERROR" error
      | Ok None -> source_failure index "INCOMPLETE_SOURCE" (Printf.sprintf "Input ended before %d requested packets" count)
      | Ok (Some input) ->
        let request = Protocol.encode_request input.request in
        let expected = Reference.process reference input.request in
        let began = Clock.now () in
        let raw = ref Bytes.empty and actual = ref None in
        let status, error =
          try match transport with
            | None -> "DRY_RUN", ""
            | Some t ->
              raw := Transport.exchange t ~timeout request;
              stats.received <- stats.received + 1;
              let response = Protocol.decode_response !raw in
              actual := Some response;
              Protocol.validate_response input.request response;
              if response.action1 = expected.action1 && response.action2 = expected.action2 then "OK", ""
              else "MISMATCH", "FPGA actions differ from reference"
          with
          | Transport.Timeout partial -> raw := partial; stats.timeouts <- stats.timeouts + 1; "TIMEOUT", "Transaction deadline expired; session stopped without resend"
          | Transport.Error (message, partial) -> raw := partial; "PROTOCOL_ERROR", message
          | exn -> "PROTOCOL_ERROR", Printexc.to_string exn
        in
        let elapsed = Clock.now () -. began in
        if status = "OK" || status = "MISMATCH" then stats.elapsed <- elapsed :: stats.elapsed;
        if input.request.index >= 16 then (
          if status = "OK" then stats.correct_packets <- stats.correct_packets + 1;
          match !actual with
          | Some a when status = "OK" || status = "MISMATCH" ->
            if a.action1 = expected.action1 then stats.correct_actions <- stats.correct_actions + 1;
            if a.action2 = expected.action2 then stats.correct_actions <- stats.correct_actions + 1
          | _ -> ());
        row input request !raw expected !actual elapsed status error;
        if status = "OK" || status = "DRY_RUN" then loop (index + 1)
        else (stats.failures <- stats.failures + 1; Printf.eprintf "Session %s packet %d: %s: %s\n%!" session_id index status error))
  in
  loop 0;
  let scored = max 0 (count - 16) in
  let avg_ms = match stats.elapsed with [] -> 0. | xs -> List.fold_left ( +. ) 0. xs /. float_of_int (List.length xs) *. 1000. in
  let mode = match transport with None -> "dry-run" | Some _ -> "verified responses" in
  Printf.printf "Session %s (%s): received=%d; scored packets=%d/%d; scored actions=%d/%d; timeouts=%d; failures=%d; mean round-trip=%.3f ms\n%!"
    session_id mode stats.received stats.correct_packets scored stats.correct_actions (scored * 2) stats.timeouts stats.failures avg_ms;
  stats.failures = 0
