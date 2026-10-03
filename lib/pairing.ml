type t = { symbol_a : string; symbol_b : string; quantum : int64;
           mutable a : Databento.tick option; mutable b : Databento.tick option;
           mutable dirty_a : bool; mutable dirty_b : bool }
type pair = { a : Databento.tick; b : Databento.tick; price_a : int; price_b : int }
let create ~symbol_a ~symbol_b ~quantum =
  if symbol_a = symbol_b then invalid_arg "Item A and B require different symbols";
  if quantum <= 0L then invalid_arg "Price quantum must be positive";
  { symbol_a; symbol_b; quantum; a = None; b = None; dirty_a = false; dirty_b = false }
let price ~quantum nanos =
  if quantum <= 0L then invalid_arg "Price quantum must be positive";
  if nanos < 0L || nanos = Int64.max_int then invalid_arg "Negative or undefined Databento price";
  let p = Int64.div nanos quantum in
  if p > 65535L then invalid_arg "Price exceeds UART uint16 range; increase --price-quantum-nanos";
  Int64.to_int p
let push t (tick : Databento.tick) =
  if tick.symbol = t.symbol_a || tick.symbol = t.symbol_b then ignore (price ~quantum:t.quantum tick.price);
  if tick.symbol = t.symbol_a then (t.a <- Some tick; t.dirty_a <- true)
  else if tick.symbol = t.symbol_b then (t.b <- Some tick; t.dirty_b <- true);
  match t.a, t.b with
  | Some a, Some b when t.dirty_a && t.dirty_b ->
    let price_a = price ~quantum:t.quantum a.price in
    let price_b = price ~quantum:t.quantum b.price in
    t.dirty_a <- false; t.dirty_b <- false;
    Some { a; b; price_a; price_b }
  | _ -> None
