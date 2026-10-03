let cell s = "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""
let write ch columns = output_string ch (String.concat "," (List.map cell columns)); output_char ch '\n'; flush ch
let hex b =
  let out = Buffer.create (Bytes.length b * 2) in
  Bytes.iter (fun c -> Buffer.add_string out (Printf.sprintf "%02x" (Char.code c))) b;
  Buffer.contents out
let open_new path =
  let fd = Unix.openfile path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL; Unix.O_CLOEXEC] 0o600 in
  Unix.out_channel_of_descr fd
let header ch = write ch ["session_id";"source";"seed";"build_id";"index";"item1";"price1";"item2";"price2";"symbol_a";"symbol_b";"ts_a";"ts_b";"nanos_a";"nanos_b";"quantum_nanos";"request_hex";"response_hex";"expected_action1";"expected_action2";"actual_action1";"actual_action2";"elapsed_ms";"scored";"status";"error"]
