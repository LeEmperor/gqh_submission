(* Frozen field and wire contracts. All arithmetic is exact int64; no floats. *)

let nanos_per_dollar = 1_000_000_000L
let default_quantum_nanos = 10_000_000L
let undefined_price = Int64.max_int
let max_wire_price = 65535
let max_requests = 65536
let item_a = 17
let item_b = 34
let required_columns = [ "symbol"; "ts_event"; "price" ]
let u64_max_text = "18446744073709551615"

type price_error =
  | Missing_price
  | Negative_price
  | Undefined_price
  | Int64_overflow
  | Invalid_number

let is_digit c = c >= '0' && c <= '9'

let all_digits s ~from =
  let n = String.length s in
  let rec go i = i >= n || (is_digit s.[i] && go (i + 1)) in
  from < n && go from

(* Non-negative decimal integer, digits only, with an overflow check before
   every multiply-add. *)
let parse_nonneg_int64 s =
  if not (all_digits s ~from:0) then None
  else begin
    let n = String.length s in
    let rec go i acc =
      if i = n then Some acc
      else begin
        let d = Int64.of_int (Char.code s.[i] - Char.code '0') in
        if Int64.compare acc (Int64.div (Int64.sub Int64.max_int d) 10L) > 0 then None
        else go (i + 1) (Int64.add (Int64.mul acc 10L) d)
      end
    in
    go 0 0L
  end

let parse_price s =
  let n = String.length s in
  if n = 0 then Error Missing_price
  else if s.[0] = '-' then
    if all_digits s ~from:1 then Error Negative_price else Error Invalid_number
  else if not (all_digits s ~from:0) then Error Invalid_number
  else
    match parse_nonneg_int64 s with
    | None -> Error Int64_overflow
    | Some v when Int64.equal v undefined_price -> Error Undefined_price
    | Some v -> Ok v

let price_error_to_string = function
  | Missing_price -> "missing_price"
  | Negative_price -> "negative_price"
  | Undefined_price -> "undefined_price"
  | Int64_overflow -> "int64_overflow"
  | Invalid_number -> "invalid_number"

let strip_leading_zeros s =
  let n = String.length s in
  let rec go i = if i < n - 1 && s.[i] = '0' then go (i + 1) else i in
  let i = go 0 in
  String.sub s i (n - i)

(* ts_event is kept as text. It must be an unsigned decimal that fits uint64. *)
let check_ts_event s =
  if s = "" then Error "missing ts_event"
  else if not (all_digits s ~from:0) then Error "ts_event is not an unsigned decimal"
  else begin
    let core = strip_leading_zeros s in
    let len = String.length core in
    if len > 20 || (len = 20 && String.compare core u64_max_text > 0) then
      Error "ts_event exceeds uint64"
    else Ok ()
  end

(* Ordering for already-validated ts_event text. *)
let compare_ts_event a b =
  let a = strip_leading_zeros a and b = strip_leading_zeros b in
  match Int.compare (String.length a) (String.length b) with
  | 0 -> String.compare a b
  | c -> c

let parse_quantum s =
  match parse_nonneg_int64 s with
  | None -> Error (Printf.sprintf "quantum_nanos %S is not a positive int64 decimal" s)
  | Some q when Int64.compare q 0L <= 0 ->
      Error (Printf.sprintf "quantum_nanos must be positive, got %S" s)
  | Some q -> Ok q

(* wire = floor(price / quantum). Both operands are non-negative so Int64.div
   truncation equals floor. Returns the unclamped quotient on failure. *)
let to_wire ~quantum price =
  if Int64.compare quantum 0L <= 0 then invalid_arg "to_wire: quantum must be positive";
  if Int64.compare price 0L < 0 then invalid_arg "to_wire: price must be non-negative";
  let w = Int64.div price quantum in
  if Int64.compare w (Int64.of_int max_wire_price) > 0 then Error w else Ok (Int64.to_int w)

type request = { index : int; item1 : int; price1 : int; item2 : int; price2 : int }

let request_header = "index,item1,price1,item2,price2"

let request_line r =
  Printf.sprintf "%d,%d,%d,%d,%d" r.index r.item1 r.price1 r.item2 r.price2

(* Slot order alternates by session index: even indices put item A first. *)
let make_request ~index ~wire_a ~wire_b =
  if index mod 2 = 0 then
    { index; item1 = item_a; price1 = wire_a; item2 = item_b; price2 = wire_b }
  else { index; item1 = item_b; price1 = wire_b; item2 = item_a; price2 = wire_a }

let requests_csv rows =
  String.concat "" (List.map (fun l -> l ^ "\n") (request_header :: List.map request_line rows))
