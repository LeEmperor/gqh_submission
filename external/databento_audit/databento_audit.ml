open Databento_audit_lib
module C = Trade_contract
module V = Validator

let exit_ok = 0
let exit_invalid = 1
let exit_usage = 2
let exit_io = 3

let usage =
  "usage:\n\
  \  databento_audit generate --output-dir DIR [--seed N] [--pairs N] [--overwrite]\n\
  \  databento_audit validate --input FILE|- --symbol-a SYM --symbol-b SYM\n\
  \                           [--quantum-nanos N] [--max-line-bytes N]\n\
  \                           [--report FILE] [--requests-out FILE] [--overwrite]\n\
  \  databento_audit verify --fixtures-dir DIR\n\
   exit codes: 0 ok, 1 invalid data or fixture mismatch, 2 usage error, 3 output/IO error"

exception Usage of string

let parse cmd specs args =
  let argv = Array.of_list (("databento_audit " ^ cmd) :: args) in
  try Arg.parse_argv ~current:(ref 0) argv specs (fun a -> raise (Usage ("unexpected argument " ^ a))) usage
  with
  | Arg.Bad m -> raise (Usage (List.hd (String.split_on_char '\n' m)))
  | Arg.Help m -> print_string m; exit exit_ok

let required name = function Some v -> v | None -> raise (Usage ("missing " ^ name))

let generate args =
  let out = ref None and seed = ref Generator.default_seed in
  let pairs = ref Generator.default_pairs and overwrite = ref false in
  parse "generate"
    [ ("--output-dir", Arg.String (fun s -> out := Some s), "DIR output directory");
      ("--seed", Arg.Set_int seed, "N seed (default 42)");
      ("--pairs", Arg.Set_int pairs, "N requests in 01_alternating (default 100)");
      ("--overwrite", Arg.Set overwrite, " replace existing files") ]
    args;
  let out = required "--output-dir" !out in
  if !pairs < 1 || !pairs > C.max_requests then
    raise (Usage (Printf.sprintf "--pairs must be in 1..%d" C.max_requests));
  let files = Generator.files ~seed:!seed ~pairs:!pairs in
  let targets = List.map (fun (rel, data) -> (Filename.concat out rel, data)) files in
  (match List.find_opt (fun (p, _) -> Safe_output.exists p) targets with
   | Some (p, _) when not !overwrite ->
       Printf.eprintf "refusing to overwrite %s (pass --overwrite); nothing written\n" p;
       exit exit_io
   | _ -> ());
  List.iter (fun (p, data) -> Safe_output.write_file ~overwrite:!overwrite p data) targets;
  Printf.printf "wrote %d files under %s (seed %d, pairs %d)\n" (List.length targets) out !seed
    !pairs;
  exit_ok

let validate args =
  let input = ref None and sa = ref None and sb = ref None in
  let quantum = ref (Int64.to_string C.default_quantum_nanos) in
  let max_line = ref Csv_stream.default_max_record_bytes in
  let report = ref None and requests_out = ref None and overwrite = ref false in
  parse "validate"
    [ ("--input", Arg.String (fun s -> input := Some s), "FILE capture CSV, or - for stdin");
      ("--symbol-a", Arg.String (fun s -> sa := Some s), "SYM symbol mapped to item 17");
      ("--symbol-b", Arg.String (fun s -> sb := Some s), "SYM symbol mapped to item 34");
      ("--quantum-nanos", Arg.Set_string quantum, "N nanodollars per wire unit (default 10000000)");
      ("--max-line-bytes", Arg.Set_int max_line, "N maximum bytes per CSV record (default 65536)");
      ("--report", Arg.String (fun s -> report := Some s), "FILE write JSON report here (default stdout)");
      ("--requests-out", Arg.String (fun s -> requests_out := Some s),
       "FILE write derived request CSV (only if the capture is valid)");
      ("--overwrite", Arg.Set overwrite, " replace existing report/request files") ]
    args;
  let input = required "--input" !input in
  let quantum =
    match C.parse_quantum !quantum with Ok q -> q | Error m -> raise (Usage m)
  in
  let config =
    { V.symbol_a = required "--symbol-a" !sa; symbol_b = required "--symbol-b" !sb; quantum;
      max_line_bytes = !max_line }
  in
  (match V.check_config config with Ok () -> () | Error m -> raise (Usage m));
  let outputs = List.filter_map Fun.id [ !report; !requests_out ] in
  (match outputs with
   | [ a; b ] when a = b -> raise (Usage "--report and --requests-out must differ")
   | _ -> ());
  List.iter
    (fun p ->
      if input <> "-" && Safe_output.same_file p input then
        raise (Usage (p ^ " is the input file"));
      if (not !overwrite) && Safe_output.exists p then begin
        Printf.eprintf "refusing to overwrite %s (pass --overwrite)\n" p;
        exit exit_io
      end)
    outputs;
  let ic =
    if input = "-" then (set_binary_mode_in stdin true; stdin)
    else
      try open_in_bin input
      with Sys_error m -> Printf.eprintf "cannot open input: %s\n" m; exit exit_io
  in
  let req_tmp, on_request =
    match !requests_out with
    | None -> (None, fun _ -> ())
    | Some p ->
        Safe_output.mkdir_p (Filename.dirname p);
        let tmp = Safe_output.temp_sibling p "partial" in
        let oc = open_out_bin tmp in
        output_string oc (C.request_header ^ "\n");
        (Some (tmp, p, oc), fun r -> output_string oc (C.request_line r ^ "\n"))
  in
  let result = V.run ~on_request config ic in
  if input <> "-" then close_in_noerr ic;
  (match req_tmp with
   | None -> ()
   | Some (tmp, p, oc) ->
       close_out oc;
       if V.is_valid result then Safe_output.commit ~overwrite:!overwrite tmp p
       else Sys.remove tmp);
  let text = Report.to_string ~input result in
  (match !report with
   | None -> print_string text
   | Some p -> Safe_output.write_file ~overwrite:!overwrite p text);
  (match result.failure with
   | None ->
       Printf.eprintf "valid: %d records, %d requests\n" result.counts.data_records
         result.counts.requests;
       exit_ok
   | Some f ->
       Printf.eprintf "invalid: %s at line %d%s: %s\n" (V.category_name f.category) f.line
         (match f.field with Some x -> " field " ^ x | None -> "")
         f.message;
       exit_invalid)

let verify args =
  let dir = ref None in
  parse "verify" [ ("--fixtures-dir", Arg.String (fun s -> dir := Some s), "DIR fixture root") ] args;
  let outcomes = Fixture_check.check_dir (required "--fixtures-dir" !dir) in
  let failed = List.filter (fun (o : Fixture_check.outcome) -> o.problems <> []) outcomes in
  List.iter
    (fun (o : Fixture_check.outcome) ->
      Printf.printf "%s %s (%s)\n" (if o.problems = [] then "PASS" else "FAIL") o.name o.kind;
      List.iter (Printf.printf "    %s\n") o.problems)
    outcomes;
  Printf.printf "%d fixtures, %d failed\n" (List.length outcomes) (List.length failed);
  if failed = [] then exit_ok else exit_invalid

let () =
  let code =
    try
      match Array.to_list Sys.argv with
      | _ :: "generate" :: rest -> generate rest
      | _ :: "validate" :: rest -> validate rest
      | _ :: "verify" :: rest -> verify rest
      | _ :: ("help" | "--help" | "-help") :: _ -> print_endline usage; exit_ok
      | _ -> prerr_endline usage; exit_usage
    with
    | Usage m -> Printf.eprintf "error: %s\n%s\n" m usage; exit_usage
    | Safe_output.Output_exists p ->
        Printf.eprintf "refusing to overwrite %s (pass --overwrite)\n" p;
        exit_io
    | Sys_error m | Unix.Unix_error (_, _, m) ->
        Printf.eprintf "I/O error: %s\n" m;
        exit_io
  in
  exit code
