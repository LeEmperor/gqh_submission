(* A local process on a socket pair exercises the real stop-and-wait transport. *)
let request b : Protocol.request =
  let u8 i = Char.code (Bytes.get b i) in
  let u16 i = (u8 i lsl 8) lor u8 (i + 1) in
  { index = u16 0; item1 = u8 2; price1 = u16 3; item2 = u8 5; price2 = u16 6 }
let response (r : Protocol.response) =
  let b = Bytes.make 8 '\000' in
  let put i n = Bytes.set b i (Char.chr n) in
  put 0 (r.index lsr 8); put 1 (r.index land 255);
  put 2 r.item1; put 3 r.action1; put 4 r.item2; put 5 r.action2; b
let rec read_exact fd b offset =
  if offset < Bytes.length b then (
    let n = Unix.read fd b offset (Bytes.length b - offset) in
    if n = 0 then raise End_of_file;
    read_exact fd b (offset + n))
let rec write_exact fd b offset length =
  if length > 0 then (
    let n = Unix.write fd b offset length in
    if n = 0 then raise End_of_file;
    write_exact fd b (offset + n) (length - n))
let faults = ["none"; "timeout"; "partial"; "wrong-index"; "wrong-item"; "reserved"; "action"; "mismatch"; "extra"]
let create ~fault =
  if not (List.mem fault faults) then invalid_arg "Unknown mock fault";
  let host, board = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  Unix.set_close_on_exec host; Unix.set_close_on_exec board;
  match Unix.fork () with
  | 0 ->
    Unix.close host;
    Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
    let model = Reference.create () in
    (try while true do
      let b = Bytes.create 8 in
      read_exact board b 0;
      let req = request b in
      let reply = response (Reference.process model req) in
      let inject = req.index = 16 in
      if inject then (match fault with
        | "wrong-index" -> Bytes.set reply 1 (Char.chr 17)
        | "wrong-item" -> Bytes.set reply 2 (Char.chr (if req.item1 = 17 then 34 else 17))
        | "reserved" -> Bytes.set reply 7 '\001'
        | "action" -> Bytes.set reply 3 '\003'
        | "mismatch" -> Bytes.set reply 3 (Char.chr ((Char.code (Bytes.get reply 3) + 1) mod 3))
        | _ -> ());
      if inject && fault = "timeout" then ignore (Unix.select [] [] [] 2.)
      else if inject && fault = "partial" then (
        write_exact board reply 0 7; ignore (Unix.select [] [] [] 2.))
      else if inject && fault = "extra" then (
        write_exact board (Bytes.cat reply (Bytes.of_string "x")) 0 9)
      else (
        write_exact board reply 0 1;
        ignore (Unix.select [] [] [] 0.001);
        write_exact board reply 1 2;
        ignore (Unix.select [] [] [] 0.001);
        write_exact board reply 3 5)
    done with _ -> ());
    Unix.close board; Unix._exit 0
  | pid ->
    Unix.close board;
    let t = Transport.of_fd ~close_fd:true host in
    let stop () =
      Transport.close t;
      (try Unix.kill pid Sys.sigterm with Unix.Unix_error (Unix.ESRCH, _, _) -> ());
      ignore (Unix.waitpid [] pid)
    in
    t, stop
