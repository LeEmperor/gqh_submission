open Tickweave
let raises f = try ignore (f ()); false with _ -> true
let request index a b swap : Protocol.request = if swap then {index;item1=34;price1=b;item2=17;price2=a} else {index;item1=17;price1=a;item2=34;price2=b}
let () =
  let r = request 16 80 200 false in
  assert (Log.hex (Protocol.encode_request r) = "00101100502200c8");
  let out = Protocol.decode_response (Bytes.of_string "\000\016\017\001\034\002\000\000") in
  Protocol.validate_response r out;
  assert (out.action1 = 1 && out.action2 = 2);
  assert (raises (fun () -> Protocol.encode_request (request 65536 0 0 false)));
  assert (raises (fun () -> Protocol.encode_request (request 0 (-1) 0 false)));
  assert (raises (fun () -> Protocol.decode_response (Bytes.of_string "\000\016\017\001\034\002\000\001")));
  assert (raises (fun () -> Protocol.decode_response (Bytes.of_string "\000\016\017\003\034\002\000\000")));
  let t = Reference.create () in
  for i = 0 to 15 do let o = Reference.process t (request i 100 100 (i mod 2 = 1)) in assert (o.action1 = 0 && o.action2 = 0) done;
  let o = Reference.process t (request 16 101 98 false) in assert (o.action1 = 2 && o.action2 = 1);
  let o = Reference.process t (request 17 102 97 true) in assert (o.action1 = 1 && o.action2 = 2);
  let equality = Reference.create () in
  for i = 0 to 15 do ignore (Reference.process equality (request i 100 100 false)) done;
  let equal = Reference.process equality (request 16 99 100 false) in
  assert (equal.action1 = 0 && equal.action2 = 0);
  let o = Reference.process t (request 0 65535 0 true) in assert (o.action1 = 0 && o.action2 = 0);
  (* Independently recompute averages from complete lists rather than rolling sums. *)
  let slow () = ref [], ref 0, ref 0 in
  let a = slow () and b = slow () in
  let reset (w,p,held) = w := []; p := 0; held := 0 in
  let update (window,previous,held) price =
    let old = !window in
    if List.length old = 16 then (
      let old_average = List.fold_left ( + ) 0 old / 16 in
      let fresh = List.tl old @ [price] in
      let new_average = List.fold_left ( + ) 0 fresh / 16 in
      if !previous <= old_average && price > new_average then held := 2
      else if !previous >= old_average && price < new_average then held := 1;
      window := fresh)
    else window := old @ [price];
    previous := price; !held in
  List.iter (fun seed ->
    let model = Reference.create () in
    for session = 1 to 2 do
      ignore session; reset a; reset b;
      List.iter (fun (r : Protocol.request) ->
        let s id = if id = 17 then a else b in
        let expected1 = update (s r.item1) r.price1 in
        let expected2 = update (s r.item2) r.price2 in
        let o = Reference.process model r in
        assert (o.action1 = expected1 && o.action2 = expected2)) (Scenarios.synthetic ~seed ~count:300)
    done) [0;42;1000];
  assert (Scenarios.synthetic ~seed:42 ~count:100 = Scenarios.synthetic ~seed:42 ~count:100);
  let quantum = 10_000_000L in
  assert (Pairing.price ~quantum 655_359_999_999L = 65535);
  assert (raises (fun () -> Pairing.price ~quantum 655_360_000_000L));
  assert (raises (fun () -> Pairing.price ~quantum Int64.max_int));
  assert (raises (fun () -> Pairing.price ~quantum (-1L)));
  let pairing = Pairing.create ~symbol_a:"AAPL" ~symbol_b:"MSFT" ~quantum in
  let tick symbol price : Databento.tick = {symbol;ts_event="1";price} in
  assert (raises (fun () -> Pairing.push pairing (tick "AAPL" 655_360_000_000L)));
  assert (Pairing.push pairing (tick "AAPL" 100_000_000L) = None);
  assert (Pairing.push pairing (tick "AAPL" 110_000_000L) = None);
  assert (Pairing.push pairing (tick "OTHER" 120_000_000L) = None);
  let pair = Option.get (Pairing.push pairing (tick "MSFT" 200_000_000L)) in
  assert (pair.price_a = 11 && pair.price_b = 20);
  assert (Pairing.push pairing (tick "MSFT" 210_000_000L) = None);
  let pair = Option.get (Pairing.push pairing (tick "AAPL" 120_000_000L)) in
  assert (pair.price_a = 12 && pair.price_b = 21);
  print_endline "Core: codec, resets, held actions, slow independent oracle, seeded data, and exact pairing passed"
