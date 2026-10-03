type request = { index:int; item1:int; price1:int; item2:int; price2:int }
type response = { index:int; item1:int; action1:int; item2:int; action2:int }
let bound name maximum value = if value < 0 || value > maximum then invalid_arg (Printf.sprintf "%s must be in 0..%d" name maximum)
let validate_items a b = if not ((a = 17 && b = 34) || (a = 34 && b = 17)) then invalid_arg "item IDs must contain 0x11 and 0x22 exactly once"
let validate_request (r:request) = bound "index" 65535 r.index; validate_items r.item1 r.item2; bound "price1" 65535 r.price1; bound "price2" 65535 r.price2
let set_u16 b i n = Bytes.set b i (Char.chr (n lsr 8)); Bytes.set b (i+1) (Char.chr (n land 255))
let u8 b i = Char.code (Bytes.get b i)
let u16 b i = (u8 b i lsl 8) lor u8 b (i+1)
let encode_request (r:request) =
  validate_request r; let b = Bytes.create 8 in
  set_u16 b 0 r.index; Bytes.set b 2 (Char.chr r.item1); set_u16 b 3 r.price1;
  Bytes.set b 5 (Char.chr r.item2); set_u16 b 6 r.price2; b
let decode_response b : response =
  if Bytes.length b <> 8 then invalid_arg "response must contain exactly eight bytes";
  if u8 b 6 <> 0 || u8 b 7 <> 0 then invalid_arg "response reserved bytes must be zero";
  let r = {index=u16 b 0;item1=u8 b 2;action1=u8 b 3;item2=u8 b 4;action2=u8 b 5} in
  validate_items r.item1 r.item2; bound "action1" 2 r.action1; bound "action2" 2 r.action2; r
let validate_response (req:request) (r:response) =
  validate_request req; bound "response index" 65535 r.index; validate_items r.item1 r.item2;
  bound "action1" 2 r.action1; bound "action2" 2 r.action2;
  if req.index <> r.index then invalid_arg "response index does not match request";
  if req.item1 <> r.item1 || req.item2 <> r.item2 then invalid_arg "response item order does not match request"
