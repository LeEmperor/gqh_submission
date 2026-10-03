open Tickweave
open Yojson.Safe.Util
let json path = Yojson.Safe.from_file path
let int64 json = match json with `String s -> Int64.of_string s | `Int n -> Int64.of_int n | `Intlit s -> Int64.of_string s | _ -> failwith "invalid manifest int64"
let () =
  let root = Sys.argv.(1) in
  let index = json (Filename.concat root "index.json") in
  let fixtures = index |> member "fixtures" |> to_list in
  let passed = ref 0 in
  List.iter (fun entry ->
    let manifest_rel = match entry with `String s -> s | _ -> entry |> member "manifest" |> to_string in
    let path = Filename.concat root manifest_rel in
    let manifest = json path in
    let dir = Filename.dirname path in
    let field name = manifest |> member name in
    let symbol_a = field "symbol_a" |> to_string and symbol_b = field "symbol_b" |> to_string in
    let quantum = int64 (field "quantum_nanos") in
    let limit = field "max_line_bytes" |> to_int in
    let trades = manifest |> member "files" |> member "trades" |> to_string |> Filename.concat dir in
    let consume () =
      let source = Databento.replay ~max_record_bytes:limit trades in
      Fun.protect ~finally:source.close (fun () ->
        let pairer = Pairing.create ~symbol_a ~symbol_b ~quantum in
        let rec loop index requests = match source.next () with
          | None -> List.rev requests
          | Some tick -> match Pairing.push pairer tick with
            | None -> loop index requests
            | Some p ->
              let r : Protocol.request = if index mod 2 = 0 then {index;item1=17;price1=p.price_a;item2=34;price2=p.price_b}
                else {index;item1=34;price1=p.price_b;item2=17;price2=p.price_a} in
              ignore (Protocol.encode_request r);loop (index+1) (r::requests) in loop 0 []) in
    if field "expected_valid" |> to_bool then (
      let actual = consume () in
      let expected = manifest |> member "files" |> member "expected_requests" |> to_string |> Filename.concat dir |> Scenarios.replay in
      if actual <> expected then failwith ("streamer requests differ from independent fixture " ^ manifest_rel))
    else (
      let failed = try ignore (consume ());false with _ -> true in
      if not failed then failwith ("streamer accepted invalid fixture " ^ manifest_rel));
    incr passed) fixtures;
  Printf.printf "External integration: %d independent fixtures matched request rows or rejected invalid data\n" !passed
