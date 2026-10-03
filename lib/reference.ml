type item = { window : int array; mutable count : int; mutable sum : int;
              mutable previous : int; mutable action : int }
type t = { a : item; b : item }
let item () = { window = Array.make 16 0; count = 0; sum = 0; previous = 0; action = 0 }
let create () = { a = item (); b = item () }
let reset_item s = Array.fill s.window 0 16 0; s.count <- 0; s.sum <- 0; s.previous <- 0; s.action <- 0
let update s price =
  let slot = s.count mod 16 in
  if s.count < 16 then (s.window.(slot) <- price; s.sum <- s.sum + price)
  else (
    let old_average = s.sum / 16 in
    s.sum <- s.sum - s.window.(slot) + price;
    s.window.(slot) <- price;
    let new_average = s.sum / 16 in
    if s.previous <= old_average && price > new_average then s.action <- 2
    else if s.previous >= old_average && price < new_average then s.action <- 1);
  s.previous <- price;
  s.count <- s.count + 1;
  s.action
let process t (r : Protocol.request) : Protocol.response =
  ignore (Protocol.encode_request r);
  if r.index = 0 then (reset_item t.a; reset_item t.b);
  let state id = if id = 0x11 then t.a else t.b in
  let action1 = update (state r.item1) r.price1 in
  let action2 = update (state r.item2) r.price2 in
  { index = r.index; item1 = r.item1; action1; item2 = r.item2; action2 }
