open Tickweave
let request = Bytes.make 8 '\000'
let with_peer board_fn host_fn =
  let host,peer = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  match Unix.fork () with
  | 0 -> Unix.close host; (try board_fn peer with _ -> ());Unix.close peer;Unix._exit 0
  | pid ->
    Unix.close peer;let t = Transport.of_fd host in
    Fun.protect ~finally:(fun () -> Transport.close t; (try Unix.kill pid Sys.sigterm with _ -> ()); ignore (Unix.waitpid [] pid)) (fun () -> host_fn t)
let () =
  let fragmented fd =
    let incoming = Bytes.create 8 in
    let rec read n = if n < 8 then let k = Unix.read fd incoming n (8-n) in if k > 0 then read (n+k) in read 0;
    List.iter (fun s -> ignore (Unix.write_substring fd s 0 (String.length s));ignore (Unix.select [] [] [] 0.005)) ["1";"23";"45678"];
    ignore (Unix.select [] [] [] 0.1) in
  with_peer fragmented (fun t -> assert (Transport.exchange t ~timeout:0.1 request = Bytes.of_string "12345678"));
  let drip fd =
    let b = Bytes.create 8 in ignore (Unix.read fd b 0 8);
    for _ = 1 to 8 do ignore (Unix.select [] [] [] 0.02); ignore (Unix.write_substring fd "x" 0 1) done in
  with_peer drip (fun t ->
    let start = Clock.now () in
    (try ignore (Transport.exchange t ~timeout:0.065 request);assert false with
      Transport.Timeout b -> assert (Bytes.length b >= 1 && Bytes.length b < 8));
    assert (Clock.now () -. start < 0.13);
    (try ignore (Transport.exchange t ~timeout:0.1 request);assert false with Transport.Error _ -> ()));
  let a,b = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in
  let t = Transport.of_fd a in
  Fun.protect ~finally:(fun () -> Transport.close t;Unix.close b) (fun () ->
    Unix.setsockopt_int a Unix.SO_SNDBUF 4096;
    let fill = Bytes.make 4096 'x' in
    let rec saturate () = try ignore (Unix.write a fill 0 4096);saturate () with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> () in
    saturate ();
    let start = Clock.now () in
    (try ignore (Transport.exchange t ~timeout:0.03 request);assert false with Transport.Timeout p -> assert (Bytes.length p = 0));
    assert (Clock.now () -. start < 0.1));
  let a,b = Unix.socketpair Unix.PF_UNIX Unix.SOCK_STREAM 0 in let t = Transport.of_fd a in
  Fun.protect ~finally:(fun () -> Transport.close t;Unix.close b) (fun () ->
    ignore (Unix.write_substring b "unexpected" 0 10);
    (try ignore (Transport.exchange t ~timeout:0.05 request);assert false with Transport.Error (_,raw) -> assert (Bytes.to_string raw = "unexpected")));
  print_endline "Transport: fragmented reads, absolute deadlines, poisoned connections, bounded writes, and unsolicited bytes passed"
