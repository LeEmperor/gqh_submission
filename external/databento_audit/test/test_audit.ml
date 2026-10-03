open Databento_audit_lib
module C = Trade_contract
module V = Validator
module G = Generator
module J = Yojson.Safe.Util

let passed = ref 0
let failed = ref 0
let current = ref ""

let check name cond =
  if cond then incr passed
  else begin
    incr failed;
    Printf.printf "FAIL [%s] %s\n%!" !current name
  end

let section name f =
  current := name;
  let before = !failed in
  (try f ()
   with e ->
     incr failed;
     Printf.printf "FAIL [%s] raised %s\n%!" name (Printexc.to_string e));
  Printf.printf "%s %s\n%!" (if !failed = before then "ok  " else "FAIL") name

let exe = ref ""
let fixtures = ref ""

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let read_file p = In_channel.with_open_bin p In_channel.input_all
let write_file p s = Out_channel.with_open_bin p (fun oc -> output_string oc s)

let tmp_counter = ref 0

let tmp_dir () =
  incr tmp_counter;
  let d =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "databento_audit_test_%d_%d" (Unix.getpid ()) !tmp_counter)
  in
  Unix.mkdir d 0o755;
  d

let rm_rf d = ignore (Sys.command ("rm -rf " ^ Filename.quote d))

let run_cli args =
  let cmd =
    String.concat " " (List.map Filename.quote (!exe :: args)) ^ " >/dev/null 2>&1"
  in
  Sys.command cmd

let cfg ?(quantum = C.default_quantum_nanos) ?(max_line_bytes = 65536) () =
  { V.symbol_a = "AAPL"; symbol_b = "MSFT"; quantum; max_line_bytes }

let collect ?(config = cfg ()) csv =
  let rows = ref [] in
  let r = V.run_string ~on_request:(fun q -> rows := q :: !rows) config csv in
  (r, List.rev !rows)

let category r = Option.map (fun (f : V.failure) -> V.category_name f.category) r.V.failure
let req = G.req

(* ---------- exact arithmetic ---------- *)

let test_price_parsing () =
  let ok s v = check ("price " ^ s) (C.parse_price s = Ok v) in
  let err s e = check ("price error " ^ s) (C.parse_price s = Error e) in
  ok "0" 0L;
  ok "200000000000" 200000000000L;
  ok "000123" 123L;
  ok "9007199254740993" 9007199254740993L;
  ok "9223372036854775806" 9223372036854775806L;
  err "9223372036854775807" C.Undefined_price;
  err "9223372036854775808" C.Int64_overflow;
  err "18446744073709551616" C.Int64_overflow;
  err "99999999999999999999999" C.Int64_overflow;
  err "" C.Missing_price;
  err "-1" C.Negative_price;
  err "-0" C.Negative_price;
  err "-9999999999999999999999" C.Negative_price;
  List.iter (fun s -> err s C.Invalid_number)
    [ "-"; "+1"; "1.5"; "12a"; " 1"; "1 "; "1e9"; "0x10"; "--1"; "١" ]

let test_wire_conversion () =
  let q = C.default_quantum_nanos in
  let w ?(quantum = q) p expect = check (Printf.sprintf "wire %Ld/%Ld" p quantum)
      (C.to_wire ~quantum p = expect) in
  w 0L (Ok 0);
  w 9999999L (Ok 0);
  w 10000000L (Ok 1);
  w 19999999L (Ok 1);
  w 200000000000L (Ok 20000);
  w 655359999999L (Ok 65535);
  w 655360000000L (Error 65536L);
  w Int64.(sub max_int 1L) (Error 922337203685L);
  let big = 281474976710656L in
  w ~quantum:big 9007199254740993L (Ok 32);
  w ~quantum:big 9223372036854775806L (Ok 32767);
  w ~quantum:big 281474976710655L (Ok 0);
  w ~quantum:1L 65535L (Ok 65535);
  w ~quantum:1L 65536L (Error 65536L);
  w ~quantum:3L 8L (Ok 2);
  (* The case a float path gets wrong. *)
  let as_float = Int64.of_float (Int64.to_float 9223372036854775806L /. Int64.to_float big) in
  check "float path would differ" (as_float <> 32767L);
  check "2^53+1 not float exact"
    (Int64.of_float (Int64.to_float 9007199254740993L) <> 9007199254740993L);
  let q s ok = check ("quantum " ^ s) (Result.is_ok (C.parse_quantum s) = ok) in
  q "1" true; q "10000000" true; q "9223372036854775807" true;
  q "0" false; q "-1" false; q "" false; q "1.0" false; q "9223372036854775808" false

let test_ts_event () =
  let t s ok = check ("ts " ^ s) (Result.is_ok (C.check_ts_event s) = ok) in
  t "0" true; t "1790982000000000000" true; t "18446744073709551615" true;
  t "0018446744073709551615" true;
  t "18446744073709551616" false; t "99999999999999999999" false;
  t "" false; t "-1" false; t "1e9" false; t "1.0" false;
  check "ts compare length" (C.compare_ts_event "9" "10" < 0);
  check "ts compare zeros" (C.compare_ts_event "0010" "10" = 0)

(* ---------- CSV parsing ---------- *)

let parse_all ?(max = 65536) s =
  let path = Filename.temp_file "csv" ".csv" in
  write_file path s;
  let ic = open_in_bin path in
  let t = Csv_stream.create ~max_record_bytes:max ic in
  let rec go acc =
    match Csv_stream.next t with
    | Ok None -> Ok (List.rev acc)
    | Ok (Some r) -> go ((r.Csv_stream.line, Array.to_list r.fields) :: acc)
    | Error e -> Error e
  in
  let r = go [] in
  close_in ic;
  Sys.remove path;
  r

let test_csv () =
  check "quoted, embedded quotes, CRLF"
    (parse_all "a,\"b,c\",\"d\"\"e\"\r\nx,,\n"
    = Ok [ (1, [ "a"; "b,c"; "d\"e" ]); (2, [ "x"; ""; "" ]) ]);
  check "newline inside quotes, no final newline"
    (parse_all "\"multi\nline\",z\nnext,1" = Ok [ (1, [ "multi\nline"; "z" ]); (3, [ "next"; "1" ]) ]);
  check "CRLF inside quotes preserved"
    (parse_all "\"a\r\nb\"\r\n" = Ok [ (1, [ "a\r\nb" ]) ]);
  check "empty input" (parse_all "" = Ok []);
  check "trailing empty field" (parse_all "a,\n" = Ok [ (1, [ "a"; "" ]) ]);
  check "blank line is a record" (parse_all "a\n\nb\n" = Ok [ (1, [ "a" ]); (2, [ "" ]); (3, [ "b" ]) ]);
  check "quoted empty" (parse_all "\"\",x\n" = Ok [ (1, [ ""; "x" ]) ]);
  let err s kind_ok =
    match parse_all s with Error e -> kind_ok e | Ok _ -> false
  in
  check "unterminated quote"
    (err "h\n\"abc" (fun e -> e.kind = Csv_stream.Unterminated_quote && e.line = 2));
  check "quote inside unquoted"
    (err "ab\"c,1\n" (function { kind = Csv_stream.Malformed_quote _; _ } -> true | _ -> false));
  check "junk after closing quote"
    (err "\"ab\"c,1\n" (function { kind = Csv_stream.Malformed_quote _; _ } -> true | _ -> false));
  check "bare CR" (err "a\rb\n" (fun e -> e.kind = Csv_stream.Bare_carriage_return));
  check "record exactly at limit" (parse_all ~max:10 "abcdefghi\n" = Ok [ (1, [ "abcdefghi" ]) ])

let test_csv_limit () =
  match parse_all ~max:10 "abcdefghij\n" with
  | Error e -> check "record over limit" (e.kind = Csv_stream.Record_too_long 10)
  | Ok _ -> check "record over limit" false

(* ---------- hand-derived pairing ---------- *)

let test_hand_pairing () =
  let csv =
    "symbol,ts_event,price\n\
     AAPL,1,100000000\n\
     MSFT,2,200000000\n\
     AAPL,3,110000000\n\
     AAPL,4,125555555\n\
     GOOG,5,999\n\
     MSFT,6,210000000\n\
     MSFT,7,220000000\n\
     AAPL,8,130000000\n\
     MSFT,9,230000000\n"
  in
  let r, rows = collect csv in
  check "valid" (V.is_valid r);
  check "rows"
    (rows = [ req 0 17 10 34 20; req 1 34 21 17 12; req 2 17 13 34 22 ]);
  check "records" (r.counts.data_records = 9);
  check "a count" (r.counts.symbol_a_trades = 4);
  check "b count" (r.counts.symbol_b_trades = 4);
  check "unrelated" (r.counts.unrelated_trades = 1);
  check "coalesced" (r.counts.coalesced_trades = 1);
  check "requests" (r.counts.requests = 3);
  check "pending a none" (r.pending_a = None);
  (match r.pending_b with
   | Some p ->
       check "pending b" (p.symbol = "MSFT" && p.p_line = 10 && p.p_record = 9
                          && p.price = 230000000L && p.wire = 23 && p.ts_event = "9")
   | None -> check "pending b present" false);
  check "incomplete" (V.incomplete_symbols r = [ "MSFT" ]);
  (* B first in arrival; slot order still alternates by index. *)
  let _, rows =
    collect "symbol,ts_event,price\nMSFT,1,400000000000\nAAPL,2,200000000000\n\
             MSFT,3,400100000000\nAAPL,4,200100000000\n"
  in
  check "reversed arrival" (rows = [ req 0 17 20000 34 40000; req 1 34 40010 17 20010 ]);
  (* No forward fill: second symbol never appears. *)
  let r, rows = collect "symbol,ts_event,price\nAAPL,1,1\nAAPL,2,2\nAAPL,3,3\n" in
  check "no pair without both" (rows = [] && V.incomplete_symbols r = [ "AAPL" ]);
  check "coalesced only-a" (r.counts.coalesced_trades = 2);
  (* Quoted symbols compare after unquoting; spaces and case are significant. *)
  let r, rows =
    collect "symbol,ts_event,price\n\"AAPL\",1,10000000\n\"AAPL \",2,1\naapl,3,1\n\"MSFT\",4,20000000\n"
  in
  check "quoted match" (rows = [ req 0 17 1 34 2 ] && r.counts.unrelated_trades = 2);
  (* Custom quantum with remainders. *)
  let _, rows =
    collect ~config:(cfg ~quantum:3L ()) "symbol,ts_event,price\nAAPL,1,8\nMSFT,2,9\n"
  in
  check "quantum 3" (rows = [ req 0 17 2 34 3 ])

let test_validator_errors () =
  let fails ?config csv cat line field =
    let r, _ = collect ?config csv in
    match r.failure with
    | Some f ->
        check (cat ^ " category") (V.category_name f.category = cat);
        check (cat ^ " line") (f.line = line);
        check (cat ^ " field") (f.field = field)
    | None -> check (cat ^ " should fail") false
  in
  let h = "symbol,ts_event,price\n" in
  fails "" "empty_input" 1 None;
  fails "price,ts_event,symbol,price\n" "duplicate_column" 1 (Some "price");
  fails "symbol,ts_event,Price\n" "missing_column" 1 (Some "price");
  fails (h ^ "AAPL,1,1,\n") "field_count" 2 None;
  fails (h ^ "AAPL,1,1\nMSFT,2,655360000000\n") "wire_out_of_range" 3 (Some "price");
  fails ~config:(cfg ~quantum:1L ()) (h ^ "GOOG,1,65536\nAAPL,2,65536\n") "wire_out_of_range" 3
    (Some "price");
  fails (h ^ "AAPL,18446744073709551616,1\n") "invalid_timestamp" 2 (Some "ts_event");
  (* Wide unrelated price is fine; wire range applies to configured symbols only. *)
  let r, _ = collect (h ^ "GOOG,1,9223372036854775806\n") in
  check "unrelated large price ok" (V.is_valid r);
  let r, _ = collect h in
  check "header only valid" (V.is_valid r && r.header_seen && r.counts.data_records = 0);
  check "header only status" (Report.status r = "valid_header_only");
  let r, _ = collect "symbol,ts_event,price" in
  check "header without newline" (V.is_valid r);
  let r, _ = collect "\"symbol\",\"ts_event\",\"price\"\r\n" in
  check "quoted crlf header" (V.is_valid r);
  let long = h ^ "AAPL,1," ^ String.make 5000 '9' ^ "\n" in
  let r, _ = collect ~config:(cfg ~max_line_bytes:1000 ()) long in
  check "long value clipped"
    (match r.failure with
     | Some { category = V.Line_too_long; value = Some v; line = 2; _ } -> String.length v <= 300
     | _ -> false);
  check "bad config rejected"
    (match V.run_string { (cfg ()) with symbol_b = "AAPL" } h with
     | exception Invalid_argument _ -> true
     | _ -> false)

(* ---------- committed fixtures ---------- *)

let test_fixtures () =
  let outcomes = Fixture_check.check_dir !fixtures in
  check "fixture count" (List.length outcomes = 31);
  List.iter
    (fun (o : Fixture_check.outcome) ->
      List.iter (fun p -> check (o.name ^ ": " ^ p) false) o.problems;
      check o.name (o.problems = []))
    outcomes;
  let m name =
    Yojson.Safe.from_file (Filename.concat !fixtures (Filename.concat name "manifest.json"))
  in
  let alt = m "valid/01_alternating" in
  check "alternating 100 requests" (J.(alt |> member "expected_requests" |> to_int) = 100);
  check "alternating 200 records" (J.(alt |> member "expected_input_records" |> to_int) = 200);
  check "alternating seed" (J.(alt |> member "generator" |> member "seed" |> to_int) = 42);
  let late = m "valid/05_late_second_symbol_trailing" in
  check "late incomplete"
    (J.(late |> member "expected_incomplete_symbols" |> to_list |> List.map to_string) = [ "AAPL" ]);
  let cats =
    List.filter_map
      (fun (s : G.spec) -> Option.map (fun (e : G.expected_error) -> e.category) s.expected_error)
      (G.all ~seed:42 ~pairs:100)
  in
  List.iter
    (fun c -> check ("malformed corpus has " ^ c) (List.mem c cats))
    [ "empty_input"; "missing_column"; "duplicate_column"; "field_count"; "unterminated_quote";
      "invalid_number"; "missing_price"; "negative_price"; "undefined_price"; "int64_overflow";
      "wire_out_of_range"; "invalid_timestamp"; "line_too_long" ];
  List.iter
    (fun (s : G.spec) ->
      if s.kind = G.Expected_failure then
        check (s.name ^ " labelled") (String.starts_with ~prefix:"EXPECTED FAILURE" s.description))
    (G.all ~seed:42 ~pairs:100);
  (* The pairs in 02 really are coalesced. *)
  let r = V.run_file (cfg ())
      (Filename.concat !fixtures "valid/02_faster_symbol_a/trades.csv") in
  check "02 coalesces" (r.counts.coalesced_trades > 0 && r.counts.symbol_b_trades = 12);
  let r = V.run_file (cfg ())
      (Filename.concat !fixtures "valid/04_unrelated_symbol_interleaved/trades.csv") in
  check "04 has unrelated" (r.counts.unrelated_trades >= 15)

(* ---------- reproducibility ---------- *)

let test_reproducible () =
  let a = G.files ~seed:42 ~pairs:100 and b = G.files ~seed:42 ~pairs:100 in
  check "same seed same files" (a = b);
  List.iter
    (fun (rel, data) ->
      let p = Filename.concat !fixtures rel in
      check ("committed matches " ^ rel) (Sys.file_exists p && read_file p = data))
    a;
  let c = G.files ~seed:43 ~pairs:100 in
  check "different seed differs"
    (List.assoc "valid/01_alternating/trades.csv" a <> List.assoc "valid/01_alternating/trades.csv" c);
  check "hand fixtures seed independent"
    (List.assoc "valid/06b_precision_above_2_53/trades.csv" a
    = List.assoc "valid/06b_precision_above_2_53/trades.csv" c);
  let d1 = tmp_dir () and d2 = tmp_dir () in
  check "cli gen 1" (run_cli [ "generate"; "--output-dir"; d1; "--seed"; "7"; "--pairs"; "33" ] = 0);
  check "cli gen 2" (run_cli [ "generate"; "--output-dir"; d2; "--seed"; "7"; "--pairs"; "33" ] = 0);
  List.iter
    (fun (rel, data) ->
      let x = read_file (Filename.concat d1 rel) and y = read_file (Filename.concat d2 rel) in
      check ("cli identical " ^ rel) (x = y && x = data))
    (G.files ~seed:7 ~pairs:33);
  check "pairs honoured"
    (Fixture_check.check_dir d1 |> List.for_all (fun (o : Fixture_check.outcome) -> o.problems = []));
  check "pairs out of range" (run_cli [ "generate"; "--output-dir"; d1; "--pairs"; "0"; "--overwrite" ] = 2);
  check "pairs above max" (run_cli [ "generate"; "--output-dir"; d1; "--pairs"; "65537"; "--overwrite" ] = 2);
  rm_rf d1;
  rm_rf d2

(* Expected rows come from the generator's plan; the validator must agree for
   many seeds. *)
let test_cross_seed () =
  for seed = 0 to 40 do
    let pairs = 1 + (seed * 37 mod 300) in
    List.iter
      (fun (s : G.spec) ->
        if s.kind = G.Valid_session then begin
          let config = { (cfg ~quantum:s.quantum ()) with symbol_a = s.symbol_a; symbol_b = s.symbol_b } in
          let r, rows = collect ~config s.trades_csv in
          let tag = Printf.sprintf "seed %d %s" seed s.name in
          check (tag ^ " valid") (V.is_valid r);
          check (tag ^ " rows") (rows = s.expected_requests);
          check (tag ^ " records") (r.counts.data_records = s.input_records);
          check (tag ^ " incomplete") (V.incomplete_symbols r = s.expected_incomplete)
        end)
      (G.all ~seed ~pairs)
  done

(* ---------- CLI and output preservation ---------- *)

let test_cli () =
  let d = tmp_dir () in
  let fx rel = Filename.concat !fixtures rel in
  let valid = fx "valid/05_late_second_symbol_trailing/trades.csv" in
  let report = Filename.concat d "report.json" and reqs = Filename.concat d "requests.csv" in
  let base input = [ "validate"; "--input"; input; "--symbol-a"; "AAPL"; "--symbol-b"; "MSFT" ] in
  check "valid exit 0" (run_cli (base valid @ [ "--report"; report; "--requests-out"; reqs ]) = 0);
  let j = Yojson.Safe.from_file report in
  check "report status" (J.(j |> member "status" |> to_string) = "valid");
  check "report units" (J.(j |> member "units" |> member "price" |> to_string) <> "");
  check "report scope disclaims hardware"
    (let s = J.(j |> member "scope" |> to_string) in
     contains s "not an FPGA");
  check "report pending"
    (match J.(j |> member "unmatched_trailing" |> to_list) with
     | [ p ] -> J.(p |> member "symbol" |> to_string) = "AAPL"
                && (match J.member "price_nanos" p with `String _ -> true | _ -> false)
     | _ -> false);
  check "report incomplete flag" (J.(j |> member "incomplete_pair" |> to_bool));
  check "requests-out matches expected"
    (read_file reqs = read_file (fx "valid/05_late_second_symbol_trailing/expected_requests.csv"));
  (* Existing outputs are preserved unless --overwrite. *)
  write_file report "sentinel";
  check "existing report exit 3" (run_cli (base valid @ [ "--report"; report ]) = 3);
  check "existing report intact" (read_file report = "sentinel");
  write_file reqs "sentinel";
  check "existing requests exit 3" (run_cli (base valid @ [ "--requests-out"; reqs ]) = 3);
  check "existing requests intact" (read_file reqs = "sentinel");
  check "overwrite exit 0" (run_cli (base valid @ [ "--report"; report; "--overwrite" ]) = 0);
  check "overwritten" (read_file report <> "sentinel");
  (* Input is never clobbered, even with --overwrite. *)
  let copy = Filename.concat d "copy.csv" in
  write_file copy (read_file valid);
  check "report onto input exit 2" (run_cli (base copy @ [ "--report"; copy; "--overwrite" ]) = 2);
  check "input intact" (read_file copy = read_file valid);
  (* Invalid captures: exit 1, report written, no request file. *)
  let bad = fx "expected_failure/negative_price/trades.csv" in
  let report2 = Filename.concat d "bad.json" and reqs2 = Filename.concat d "bad_requests.csv" in
  check "invalid exit 1" (run_cli (base bad @ [ "--report"; report2; "--requests-out"; reqs2 ]) = 1);
  check "no requests on invalid" (not (Sys.file_exists reqs2));
  check "no partial left"
    (Array.for_all (fun f -> not (contains f ".partial.")) (Sys.readdir d));
  let j = Yojson.Safe.from_file report2 in
  check "error category" (J.(j |> member "error" |> member "category" |> to_string) = "negative_price");
  check "error line" (J.(j |> member "error" |> member "line" |> to_int) = 3);
  check "error field" (J.(j |> member "error" |> member "field" |> to_string) = "price");
  check "error value" (J.(j |> member "error" |> member "value" |> to_string) = "-1");
  check "status invalid" (J.(j |> member "status" |> to_string) = "invalid");
  List.iter
    (fun (s : G.spec) ->
      let p = fx (Filename.concat (G.dir_of s) "trades.csv") in
      let args = base p @ [ "--quantum-nanos"; Int64.to_string s.quantum;
                            "--max-line-bytes"; string_of_int s.max_line_bytes ] in
      let want = if s.kind = G.Valid_session then 0 else 1 in
      check ("exit code " ^ s.name) (run_cli args = want))
    (G.all ~seed:42 ~pairs:100);
  (* Usage and I/O errors. *)
  check "no args" (run_cli [] = 2);
  check "unknown command" (run_cli [ "frobnicate" ] = 2);
  check "missing symbol" (run_cli [ "validate"; "--input"; valid; "--symbol-a"; "AAPL" ] = 2);
  check "same symbols" (run_cli [ "validate"; "--input"; valid; "--symbol-a"; "X"; "--symbol-b"; "X" ] = 2);
  check "zero quantum" (run_cli (base valid @ [ "--quantum-nanos"; "0" ]) = 2);
  check "negative quantum" (run_cli (base valid @ [ "--quantum-nanos"; "-5" ]) = 2);
  check "float quantum" (run_cli (base valid @ [ "--quantum-nanos"; "1e7" ]) = 2);
  check "tiny max line" (run_cli (base valid @ [ "--max-line-bytes"; "1" ]) = 2);
  check "missing input exit 3" (run_cli (base (Filename.concat d "nope.csv")) = 3);
  check "stdin input"
    (Sys.command
       (Printf.sprintf "%s validate --input - --symbol-a AAPL --symbol-b MSFT < %s >/dev/null 2>&1"
          (Filename.quote !exe) (Filename.quote valid)) = 0);
  check "verify exit 0" (run_cli [ "verify"; "--fixtures-dir"; !fixtures ] = 0);
  (* Generate preserves existing files. *)
  let g = Filename.concat d "gen" in
  check "generate fresh" (run_cli [ "generate"; "--output-dir"; g ] = 0);
  let target = Filename.concat g "valid/01_alternating/trades.csv" in
  let other = Filename.concat g "index.json" in
  let original_other = read_file other in
  write_file target "sentinel";
  check "generate refuses" (run_cli [ "generate"; "--output-dir"; g ] = 3);
  check "generate left file" (read_file target = "sentinel");
  check "generate wrote nothing" (read_file other = original_other);
  check "generate overwrite" (run_cli [ "generate"; "--output-dir"; g; "--overwrite" ] = 0);
  check "generate restored"
    (read_file target = List.assoc "valid/01_alternating/trades.csv" (G.files ~seed:42 ~pairs:100));
  write_file (Filename.concat g "valid/01_alternating/expected_requests.csv") "tampered";
  check "verify detects tampering" (run_cli [ "verify"; "--fixtures-dir"; g ] = 1);
  rm_rf d

(* ---------- streaming and bounded memory ---------- *)

(* Runs [writer] in a child process feeding a pipe, so the capture is never a
   file and never fully resident in this process. *)
let with_pipe writer f =
  let rd, wr = Unix.pipe ~cloexec:true () in
  match Unix.fork () with
  | 0 ->
      Unix.close rd;
      let oc = Unix.out_channel_of_descr wr in
      (try writer oc; close_out oc with _ -> ());
      Unix._exit 0
  | pid ->
      Unix.close wr;
      let ic = Unix.in_channel_of_descr rd in
      let r = Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> f ic) in
      ignore (Unix.waitpid [] pid);
      r

let heap_growth_words f =
  Gc.compact ();
  let before = (Gc.quick_stat ()).heap_words in
  let peak = ref before in
  let r = f (fun () -> peak := max !peak (Gc.quick_stat ()).heap_words) in
  (r, !peak - before)

let test_streaming () =
  let retained, control =
    heap_growth_words (fun sample ->
        let l = List.init 100 (fun _ -> Bytes.create 100_000) in
        sample ();
        l)
  in
  check "heap probe detects 10 MB retained" (control > 1_000_000 && List.length retained = 100);
  let rows = 2_000_000 in
  let writer oc =
    output_string oc "symbol,ts_event,price\n";
    for i = 0 to rows - 1 do
      let sym = match i mod 40 with 0 -> "AAPL" | 1 -> "MSFT" | _ -> "NOISE" in
      Printf.fprintf oc "%s,%d,%d\n" sym (1790982000000000000 + i) (200000000000 + (i mod 977))
    done
  in
  let requests = ref 0 in
  let r, growth =
    heap_growth_words (fun sample ->
        with_pipe writer (fun ic ->
            V.run ~on_request:(fun _ -> incr requests; if !requests mod 1000 = 0 then sample ()) (cfg ()) ic))
  in
  Printf.printf "    streamed %d rows (~%d MB), heap growth %d words\n%!" rows
    (rows * 38 / 1_000_000) growth;
  check "stream valid" (V.is_valid r);
  check "stream records" (r.counts.data_records = rows);
  check "stream requests" (r.counts.requests = rows / 40 && !requests = rows / 40);
  check "stream unrelated" (r.counts.unrelated_trades = rows / 40 * 38);
  check "bounded heap (< 4 MiB growth)" (growth < 512 * 1024);
  (* A single 64 MiB line is rejected without buffering it. *)
  let chunk = String.make 65536 'A' in
  let r, growth =
    heap_growth_words (fun sample ->
        with_pipe
          (fun oc ->
            output_string oc "symbol,ts_event,price\n";
            for _ = 1 to 1024 do output_string oc chunk done)
          (fun ic -> let r = V.run (cfg ~max_line_bytes:4096 ()) ic in sample (); r))
  in
  check "long line rejected" (category r = Some "line_too_long");
  check "long line heap bounded" (growth < 512 * 1024)

let test_request_limit () =
  let alternating n oc =
    output_string oc "symbol,ts_event,price\n";
    for i = 0 to n - 1 do
      Printf.fprintf oc "%s,%d,%d\n" (if i mod 2 = 0 then "AAPL" else "MSFT") i 200000000000
    done
  in
  let last = ref None in
  let r = with_pipe (alternating (2 * 65536)) (fun ic ->
      V.run ~on_request:(fun q -> last := Some q) (cfg ()) ic) in
  check "65536 requests accepted" (V.is_valid r && r.counts.requests = 65536);
  check "last index 65535" (match !last with Some q -> q.index = 65535 | None -> false);
  let r = with_pipe (alternating ((2 * 65536) + 2)) (fun ic -> V.run (cfg ()) ic) in
  check "65537th rejected" (category r = Some "request_limit");
  check "limit line"
    (match r.failure with Some f -> f.line = (2 * 65536) + 3 | None -> false);
  check "limit counts" (r.counts.requests = 65536)

let () =
  (match Sys.argv with
   | [| _; e; f |] ->
       exe := if Filename.is_relative e then Filename.concat (Sys.getcwd ()) e else e;
       fixtures := f
   | _ -> prerr_endline "usage: test_audit EXE FIXTURES_DIR"; exit 2);
  section "price parsing" test_price_parsing;
  section "wire conversion" test_wire_conversion;
  section "ts_event" test_ts_event;
  section "csv parsing" test_csv;
  section "csv record limit" test_csv_limit;
  section "hand-derived pairing" test_hand_pairing;
  section "validator errors" test_validator_errors;
  section "committed fixtures" test_fixtures;
  section "reproducibility" test_reproducible;
  section "cross-seed generator/validator agreement" test_cross_seed;
  section "cli and output preservation" test_cli;
  section "streaming bounded memory" test_streaming;
  section "request limit" test_request_limit;
  Printf.printf "%d checks passed, %d failed\n" !passed !failed;
  if !failed > 0 then exit 1
