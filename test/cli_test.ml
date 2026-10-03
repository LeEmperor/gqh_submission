let contains haystack needle =
  let rec loop i = i + String.length needle <= String.length haystack &&
    (String.sub haystack i (String.length needle) = needle || loop (i + 1)) in
  loop 0
let read path = let ch = open_in_bin path in Fun.protect ~finally:(fun () -> close_in ch) (fun () -> really_input_string ch (in_channel_length ch))
let lines path = String.split_on_char '\n' (read path) |> List.filter (fun x -> x <> "")
let check_width path = List.iter (fun line -> assert (List.length (Tickweave.Databento.csv_fields line) = 26)) (lines path)
let () =
  let exe = Sys.argv.(1) in
  let paths = ref [] in
  let fresh () = let p = Filename.temp_file "tickweave-cli-" ".csv" in Sys.remove p; paths := p :: !paths; p in
  let execute args =
    let out = fresh () in let fd = Unix.openfile out [Unix.O_CREAT;Unix.O_WRONLY] 0o600 in
    let pid = Unix.create_process exe (Array.of_list (exe :: args)) Unix.stdin fd fd in
    Unix.close fd;
    let _, status = Unix.waitpid [] pid in status, read out in
  Fun.protect ~finally:(fun () -> List.iter (fun p -> if Sys.file_exists p then Sys.remove p) !paths) (fun () ->
    let log = fresh () in
    let status, text = execute ["--source";"synthetic";"--transport";"mock";"--sessions";"2";"--output";log] in
    assert (status = Unix.WEXITED 0);
    assert (contains text "scored packets=84/84");
    assert (List.length (lines log) = 201);check_width log;
    List.iter (fun fault ->
      let log = fresh () in
      let status, _ = execute ["--source";"synthetic";"--transport";"mock";"--mock-fault";fault;"--timeout";"0.05";"--output";log] in
      assert (status = Unix.WEXITED 1);
      assert (List.length (lines log) = 18);check_width log;
      let text = read log in
      if fault = "timeout" || fault = "partial" then assert (contains text "TIMEOUT")
      else if fault = "mismatch" then assert (contains text "MISMATCH")
      else assert (contains text "PROTOCOL_ERROR"))
      ["timeout";"partial";"wrong-index";"wrong-item";"reserved";"action";"mismatch";"extra"];
    let replay = fresh () in
    let ch = open_out replay in
    output_string ch "symbol,ts_event,price\nAAPL,1,200000000000\nMSFT,2,400000000000\nAAPL,3,201000000000\nMSFT,4,399000000000\n";close_out ch;
    let log = fresh () in
    let status, _ = execute ["--source";"replay";"--input";replay;"--symbol-a";"AAPL";"--symbol-b";"MSFT";"--packets";"2";"--sessions";"2";"--transport";"mock";"--output";log] in
    assert (status = Unix.WEXITED 0); assert (List.length (lines log) = 5);
    let short_log = fresh () in
    let status, _ = execute ["--source";"replay";"--input";replay;"--symbol-a";"AAPL";"--symbol-b";"MSFT";"--packets";"3";"--output";short_log] in
    assert (status = Unix.WEXITED 1); assert (contains (read short_log) "INCOMPLETE_SOURCE");check_width short_log;
    let before = read log in
    let status, _ = execute ["--source";"synthetic";"--output";log] in
    assert (status = Unix.WEXITED 1); assert (read log = before);
    let bad_input = fresh () in
    let ch = open_out bad_input in output_string ch "index,item1,price1,item2,price2\n0,17,65536,34,0\n";close_out ch;
    let status, _ = execute ["--source";"requests";"--input";bad_input;"--packets";"1";"--transport";"mock";"--output";fresh ()] in
    assert (status = Unix.WEXITED 1);
    let valid_input = fresh () in
    let ch = open_out valid_input in output_string ch "index,item1,price1,item2,price2\n0,17,100,34,200\n1,34,199,17,101\n";close_out ch;
    let log = fresh () in
    let status, _ = execute ["--source";"requests";"--input";valid_input;"--packets";"2";"--sessions";"2";"--transport";"mock";"--output";log] in
    assert (status = Unix.WEXITED 0); assert (List.length (lines log) = 5);check_width log;
    let capture = fresh () and log = fresh () in
    let status, _ = execute ["--source";"replay";"--input";replay;"--symbol-a";"AAPL";"--symbol-b";"MSFT";"--packets";"2";"--capture";capture;"--output";log] in
    assert (status = Unix.WEXITED 0);assert (List.length (lines capture) = 5);check_width log;
    let invalid_market = fresh () in
    let ch = open_out invalid_market in output_string ch "symbol,ts_event,price\nAAPL,1,-1\n";close_out ch;
    let log = fresh () in
    let status, _ = execute ["--source";"replay";"--input";invalid_market;"--symbol-a";"AAPL";"--symbol-b";"MSFT";"--packets";"1";"--output";log] in
    assert (status = Unix.WEXITED 1);assert (contains (read log) "SOURCE_ERROR");check_width log;
    print_endline "CLI integration: two sessions, replay, failure injection, log preservation, and input rejection passed")
