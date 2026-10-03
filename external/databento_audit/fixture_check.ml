(* Replays every fixture listed in index.json through the validator and checks
   the manifest's expectations, including byte equality of expected requests. *)

module V = Validator
module C = Trade_contract
module J = Yojson.Safe.Util

type outcome = { name : string; kind : string; problems : string list }

let read_file path = In_channel.with_open_bin path In_channel.input_all
let str_opt j = match j with `Null -> None | j -> Some (J.to_string j)

let check_manifest path =
  let m = Yojson.Safe.from_file path in
  let dir = Filename.dirname path in
  let name = J.(m |> member "name" |> to_string) in
  let kind = J.(m |> member "kind" |> to_string) in
  let problems = ref [] in
  let bad fmt = Printf.ksprintf (fun s -> problems := s :: !problems) fmt in
  let quantum =
    match C.parse_quantum J.(m |> member "quantum_nanos" |> to_string) with
    | Ok q -> q
    | Error e -> failwith e
  in
  let config =
    { V.symbol_a = J.(m |> member "symbol_a" |> to_string);
      symbol_b = J.(m |> member "symbol_b" |> to_string); quantum;
      max_line_bytes = J.(m |> member "max_line_bytes" |> to_int) }
  in
  let files = J.member "files" m in
  let trades = Filename.concat dir J.(files |> member "trades" |> to_string) in
  let out = Buffer.create 1024 in
  Buffer.add_string out (C.request_header ^ "\n");
  let r =
    V.run_file ~on_request:(fun q -> Buffer.add_string out (C.request_line q ^ "\n")) config trades
  in
  let expect_valid = J.(m |> member "expected_valid" |> to_bool) in
  if V.is_valid r <> expect_valid then
    bad "validity: expected %b, got %b" expect_valid (V.is_valid r);
  let int_field k = J.(m |> member k |> to_int) in
  if r.counts.data_records <> int_field "expected_input_records" then
    bad "input records: expected %d, got %d" (int_field "expected_input_records")
      r.counts.data_records;
  if r.counts.requests <> int_field "expected_requests" then
    bad "requests: expected %d, got %d" (int_field "expected_requests") r.counts.requests;
  let exp_incomplete =
    J.(m |> member "expected_incomplete_symbols" |> to_list |> List.map to_string)
  in
  if expect_valid
     && List.sort compare exp_incomplete <> List.sort compare (V.incomplete_symbols r)
  then
    bad "incomplete symbols: expected [%s], got [%s]" (String.concat ";" exp_incomplete)
      (String.concat ";" (V.incomplete_symbols r));
  (match (J.member "expected_error" m, r.failure) with
   | `Null, None -> ()
   | `Null, Some f -> bad "unexpected failure %s at line %d" (V.category_name f.category) f.line
   | _, None -> bad "expected a failure, input was accepted"
   | e, Some f ->
       let cat = J.(e |> member "category" |> to_string) in
       let line = J.(e |> member "line" |> to_int) in
       let field = str_opt (J.member "field" e) and value = str_opt (J.member "value" e) in
       if cat <> V.category_name f.category then
         bad "category: expected %s, got %s" cat (V.category_name f.category);
       if line <> f.line then bad "line: expected %d, got %d" line f.line;
       if field <> f.field then bad "field mismatch";
       if value <> f.value then bad "value mismatch");
  (match J.member "expected_requests" files with
   | `Null -> ()
   | j ->
       let expected = read_file (Filename.concat dir (J.to_string j)) in
       if expected <> Buffer.contents out then bad "request rows differ from expected_requests.csv");
  { name; kind; problems = List.rev !problems }

let check_dir dir =
  let idx = Yojson.Safe.from_file (Filename.concat dir "index.json") in
  J.(idx |> member "fixtures" |> to_list)
  |> List.map (fun entry ->
         let rel = J.(entry |> member "manifest" |> to_string) in
         try check_manifest (Filename.concat dir rel)
         with e ->
           { name = rel; kind = "?"; problems = [ "could not check: " ^ Printexc.to_string e ] })
