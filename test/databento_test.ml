open Tickweave
let dummy_key = "dummy_api_key_12345678901234567890"
let contains text part =
  let rec loop i = i + String.length part <= String.length text && (String.sub text i (String.length part) = part || loop (i+1)) in loop 0
let fake_curl () =
  assert (not (Array.exists (fun a -> contains a dummy_key) Sys.argv));
  let config = Buffer.create 1024 in
  (try while true do Buffer.add_string config (input_line stdin);Buffer.add_char config '\n' done with End_of_file -> ());
  let config = Buffer.contents config in
  List.iter (fun field -> assert (contains config field))
    [dummy_key ^ ":";"schema=trades";"encoding=csv";"compression=none";"pretty_px=false";"pretty_ts=false";"map_symbols=true";"limit=10"];
  let status = Option.value (Sys.getenv_opt "TICKWEAVE_FAKE_HTTP_STATUS") ~default:"200" in
  Printf.printf "HTTP/2 %s\r\nContent-Type: text/csv\r\n\r\n" status;
  print_string "ts_event,rtype,instrument_id,price,symbol\n1790982000000000000,0,1,9007199254740993,AAPL\n";
  flush stdout;
  if Sys.getenv_opt "TICKWEAVE_FAKE_CURL_FAIL" = Some "1" then exit 22 else exit 0
let raises f = try ignore (f ());false with _ -> true
let with_file text f =
  let path = Filename.temp_file "tickweave-source-" ".csv" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () -> let ch = open_out_bin path in output_string ch text;close_out ch;f path)
let mock_live ~mode f =
  let server = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in Unix.set_close_on_exec server;
  Unix.bind server (Unix.ADDR_INET (Unix.inet_addr_loopback,0));Unix.listen server 1;
  let port = match Unix.getsockname server with Unix.ADDR_INET (_,p) -> p | _ -> assert false in
  let pid = Unix.fork () in
  if pid = 0 then (
    Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
    (try
      let fd,_ = Unix.accept server in Unix.close server;
      let ch = Unix.in_channel_of_descr fd in
      let send text = Databento.write fd text in
      send "lsg_ver"; ignore (Unix.select [] [] [] 0.001);send "sion=1\ncram=challenge\n";
      let auth = input_line ch in
      assert (contains auth "auth=8a1ccb725714559af3278a3848bac0c9f97d0e73efebc10f455cb4f7882ae549-67890");
      assert (contains auth "pretty_px=0" && contains auth "pretty_ts=0" && contains auth "slow_reader_behavior=warn");
      if mode = "auth-fail" then send ("success=0|error=dataset access denied; key=" ^ dummy_key ^ "\n")
      else (
        send "success=1|session_id=42\n";
        assert (input_line ch = "schema=trades|stype_in=raw_symbol|symbols=AAPL,MSFT");
        assert (input_line ch = "start_session=1");
        send "{\"hd\":{\"rtype\":22,\"instrument_id\":7},\"stype_in_symbol\":\"AAPL\",\"stype_out_symbol\":\"AAPL\"}\n";
        if mode = "control" then (
          for _ = 1 to 100 do send "{\"hd\":{\"rtype\":23},\"msg\":\"Heartbeat\"}\n";ignore (Unix.select [] [] [] 0.01) done)
        else if mode = "error" then send "{\"hd\":{\"rtype\":21},\"err\":\"unresolved symbol\"}\n"
        else (
          send "{\"hd\":{\"rtype\":23},\"msg\":\"Heartbeat\"}\n";
          send "{\"hd\":{\"rtype\":0,\"instrument_id\":7,\"ts_event\":\"1790982000000000001\"},\"pri";
          ignore (Unix.select [] [] [] 0.001);
          send "ce\":\"9007199254740993\"}\n"));
      close_in ch;Unix._exit 0
    with _ -> Unix._exit 1))
  else (
    Unix.close server;
    Fun.protect ~finally:(fun () -> (try Unix.kill pid Sys.sigterm with _ -> ());ignore (Unix.waitpid [] pid)) (fun () -> f port))
let tests () =
  assert (Sha256.digest "" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  assert (Sha256.digest "abc" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  assert (Sha256.digest "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq" = "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  assert (Databento.timestamp "18446744073709551615" = "18446744073709551615");
  assert (raises (fun () -> Databento.timestamp "18446744073709551616"));
  with_file "symbol,ts_event,price\r\n\"BRK\"\"B\",1790982000000000000,9007199254740993\r\n" (fun p ->
    let s = Databento.replay p in let t = Option.get (s.next ()) in
    assert (t.symbol = "BRK\"B" && t.price = 9007199254740993L && t.ts_event = "1790982000000000000");
    assert (s.next () = None);s.close ();s.close ();assert (s.next () = None));
  List.iter (fun text -> with_file text (fun p -> assert (raises (fun () -> let s = Databento.replay p in Fun.protect ~finally:s.close s.next))))
    ["";"symbol,ts_event,price,price\n";"symbol,price\n";"symbol,ts_event,price\nA,1,-1\n";"symbol,ts_event,price\nA,1,9223372036854775807\n";
     "symbol,ts_event,price\nA,1,9223372036854775808\n";"symbol,ts_event,price\nA,-1,1\n";"symbol,ts_event,price\nA,1\n";"symbol,ts_event,price\nA,1,1\r";"symbol,ts_event,price\n\"A,1,1\n"];
  let historical () = Databento.historical_with ~curl:Sys.executable_name ~api_key:dummy_key ~dataset:"XNAS.ITCH" ~symbols:["AAPL";"MSFT"] ~start:"2026-10-01" ~end_:"2026-10-02" ~limit:10 in
  let s = historical () in let tick = Option.get (s.next ()) in assert (tick.price = 9007199254740993L);
  assert (s.next () = None);s.close ();s.close ();assert (s.next () = None);
  List.iter (fun code -> Unix.putenv "TICKWEAVE_FAKE_HTTP_STATUS" code;assert (raises historical)) ["206";"401";"500"];
  Unix.putenv "TICKWEAVE_FAKE_HTTP_STATUS" "200";
  Unix.putenv "TICKWEAVE_FAKE_CURL_FAIL" "1";
  let s = historical () in ignore (s.next ());assert (raises s.next);s.close ();
  Unix.putenv "TICKWEAVE_FAKE_CURL_FAIL" "0";
  mock_live ~mode:"auth-fail" (fun port ->
    try ignore (Databento.live_at ~timeout:1. ~host:"127.0.0.1" ~port ~api_key:dummy_key ~dataset:"XNAS.ITCH" ~symbols:["AAPL";"MSFT"] ());assert false
    with Failure message ->
      assert (contains message "dataset access denied");
      assert (contains message "XNAS.ITCH");
      assert (contains message "[redacted]");
      assert (not (contains message dummy_key)));
  let token = String.make 64 'a' ^ "-67890" in
  (try Databento.authentication_failure ~api_key:dummy_key ~token ~dataset:"XNAS.ITCH" ["error", "key=" ^ dummy_key ^ "; auth=" ^ token ^ "\027[2J"]
   with Failure message -> assert (not (contains message dummy_key));assert (not (contains message token));assert (not (String.contains message '\027')));
  mock_live ~mode:"ok" (fun port ->
    let s = Databento.live_at ~timeout:1. ~host:"127.0.0.1" ~port ~api_key:dummy_key ~dataset:"XNAS.ITCH" ~symbols:["AAPL";"MSFT"] () in
    let tick = Option.get (s.next ()) in assert (tick.symbol = "AAPL" && tick.price = 9007199254740993L);
    s.close ();s.close ();assert (s.next () = None));
  List.iter (fun mode -> mock_live ~mode (fun port ->
    assert (raises (fun () -> let s = Databento.live_at ~timeout:0.2 ~host:"127.0.0.1" ~port ~api_key:dummy_key ~dataset:"XNAS.ITCH" ~symbols:["AAPL";"MSFT"] () in
      Fun.protect ~finally:s.close s.next)))) ["auth-fail";"error";"control"];
  let mappings = Hashtbl.create 1 in
  Hashtbl.add mappings "7" "AAPL";
  let parse json = Databento.json_tick ~symbols:["AAPL"] ~mappings (Yojson.Safe.from_string json) in
  let tick = Option.get (parse "{\"hd\":{\"rtype\":0,\"instrument_id\":7,\"ts_event\":1790982000000000000},\"price\":123456789012345678}") in
  assert (tick.price = 123456789012345678L);
  assert (raises (fun () -> parse "{\"hd\":{\"rtype\":0,\"instrument_id\":8,\"ts_event\":1},\"price\":1}"));
  assert (raises (fun () -> parse "{\"hd\":{\"rtype\":0,\"instrument_id\":7,\"ts_event\":1},\"price\":1.2}"));
  print_endline "Databento: SHA-256, quoted CSV, int64 precision, historical HTTP/status/cleanup, native live authentication/mapping/fragments/errors, and bounded control filtering passed"
let () = if Array.length Sys.argv > 1 && Sys.argv.(1) = "--disable" then fake_curl () else tests ()
