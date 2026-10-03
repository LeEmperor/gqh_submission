(* Deterministic fixture builder.

   Seeded sessions are planned as rounds: a leader symbol updates one or more
   times, then the other symbol updates exactly once, which completes a pair.
   The expected request for a round is taken from that plan (the leader's last
   planned wire price and the follower's wire price). Each nanodollar price is
   built as [wire * quantum + remainder] with [remainder < quantum], so expected
   rows never depend on the validator's division or pairing code. *)

module C = Trade_contract

type kind = Valid_session | Expected_failure

type expected_error = {
  category : string;
  line : int;
  field : string option;
  value : string option;
}

type spec = {
  name : string;
  kind : kind;
  description : string;
  seed : int option;
  quantum : int64;
  symbol_a : string;
  symbol_b : string;
  max_line_bytes : int;
  trades_csv : string;
  input_records : int;
  expected_requests : C.request list;
  request_count : int;
  expected_incomplete : string list;
  expected_error : expected_error option;
  notes : string list;
}

let base_ts = 1790982000000000000L
let header = "symbol,ts_event,price\n"

(* SplitMix64, implemented here so output does not depend on Stdlib.Random. *)
type rng = { mutable state : int64 }

let next64 r =
  r.state <- Int64.add r.state 0x9E3779B97F4A7C15L;
  let z = r.state in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 30)) 0xBF58476D1CE4E5B9L in
  let z = Int64.mul (Int64.logxor z (Int64.shift_right_logical z 27)) 0x94D049BB133111EBL in
  Int64.logxor z (Int64.shift_right_logical z 31)

let below r n = Int64.to_int (Int64.unsigned_rem (next64 r) (Int64.of_int n))
let range r lo hi = lo + below r (hi - lo + 1)

let fnv1a s =
  let h = ref 0xcbf29ce484222325L in
  String.iter
    (fun c -> h := Int64.mul (Int64.logxor !h (Int64.of_int (Char.code c))) 0x100000001b3L)
    s;
  !h

let rng_for ~seed name = { state = Int64.logxor (Int64.of_int seed) (fnv1a name) }

type side = A | B

type session = {
  rng : rng;
  sa : string;
  sb : string;
  quantum : int64;
  rows : Buffer.t;
  mutable ts : int64;
  mutable records : int;
  mutable walk_a : int;
  mutable walk_b : int;
  mutable pairs : (int * int) list;
}

let session ~seed ~name ~sa ~sb =
  { rng = rng_for ~seed name; sa; sb; quantum = C.default_quantum_nanos;
    rows = Buffer.create 4096; ts = base_ts; records = 0; walk_a = 20000;
    walk_b = 40000; pairs = [] }

let emit s symbol nanos =
  s.ts <- Int64.add s.ts (Int64.of_int (range s.rng 1 2_000_000));
  Buffer.add_string s.rows
    (Printf.sprintf "%s,%s,%s\n" (Csv_stream.quote_field symbol) (Int64.to_string s.ts)
       (Int64.to_string nanos));
  s.records <- s.records + 1

let nanos_of_wire s wire =
  Int64.add (Int64.mul (Int64.of_int wire) s.quantum)
    (Int64.of_int (below s.rng (Int64.to_int s.quantum)))

let next_wire s side =
  let move w = max 1000 (min 60000 (w + range s.rng (-25) 25)) in
  match side with
  | A -> s.walk_a <- move s.walk_a; s.walk_a
  | B -> s.walk_b <- move s.walk_b; s.walk_b

let symbol_of s = function A -> s.sa | B -> s.sb
let other = function A -> B | B -> A

let trade s side =
  let w = next_wire s side in
  emit s (symbol_of s side) (nanos_of_wire s w);
  w

let unrelated_symbols = [| "GOOG"; "TSLA"; "aapl"; "MSFT.X"; "NVDA" |]

let unrelated s =
  let sym = unrelated_symbols.(below s.rng (Array.length unrelated_symbols)) in
  emit s sym (nanos_of_wire s (range s.rng 100 60000))

(* One completed pair. [noise] inserts at least one unrelated record before the
   follower and randomly between leader updates. *)
let round ?(noise = false) s ~leader ~updates =
  let last = ref 0 in
  for _ = 1 to updates do
    last := trade s leader;
    if noise && below s.rng 2 = 0 then unrelated s
  done;
  if noise then unrelated s;
  let f = trade s (other leader) in
  let pair = match leader with A -> (!last, f) | B -> (f, !last) in
  s.pairs <- pair :: s.pairs

let expected_of s =
  List.mapi (fun index (wire_a, wire_b) -> C.make_request ~index ~wire_a ~wire_b)
    (List.rev s.pairs)

let finish ?(incomplete = []) ?(notes = []) s ~name ~seed ~description =
  { name; kind = Valid_session; description; seed = Some seed; quantum = s.quantum;
    symbol_a = s.sa; symbol_b = s.sb; max_line_bytes = Csv_stream.default_max_record_bytes;
    trades_csv = header ^ Buffer.contents s.rows; input_records = s.records;
    expected_requests = expected_of s; request_count = List.length s.pairs;
    expected_incomplete = incomplete;
    expected_error = None; notes }

let alternating ~seed ~pairs =
  let name = "01_alternating" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  for _ = 1 to pairs do round s ~leader:A ~updates:1 done;
  finish s ~name ~seed
    ~description:
      (Printf.sprintf "Strictly alternating AAPL/MSFT trades producing a %d-request session." pairs)

let faster_a ~seed =
  let name = "02_faster_symbol_a" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  for _ = 1 to 12 do round s ~leader:A ~updates:(range s.rng 2 5) done;
  finish s ~name ~seed
    ~description:
      "AAPL trades 2-5 times before each MSFT trade; each request uses the last AAPL price."

let faster_b ~seed =
  let name = "03_faster_symbol_b_reversed_first" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  for _ = 1 to 12 do round s ~leader:B ~updates:(range s.rng 2 5) done;
  finish s ~name ~seed
    ~description:
      "MSFT arrives first and trades 2-5 times before each AAPL trade; slot order still \
       follows the request index, not arrival order."

let unrelated_interleaved ~seed =
  let name = "04_unrelated_symbol_interleaved" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  for _ = 1 to 15 do
    let leader = if below s.rng 2 = 0 then A else B in
    round ~noise:true s ~leader ~updates:(range s.rng 1 3)
  done;
  finish s ~name ~seed
    ~description:
      "Unrelated symbols (GOOG, TSLA, aapl, MSFT.X, NVDA) appear between relevant updates \
       and never supply a price."
    ~notes:[ "symbol matching is exact and case-sensitive: aapl and MSFT.X are unrelated" ]

let late_second_trailing ~seed =
  let name = "05_late_second_symbol_trailing" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  round s ~leader:A ~updates:6;
  for i = 1 to 4 do round s ~leader:(if i mod 2 = 0 then A else B) ~updates:(range s.rng 1 2) done;
  for _ = 1 to 3 do ignore (trade s A) done;
  finish s ~name ~seed ~incomplete:[ "AAPL" ]
    ~description:
      "Six AAPL trades before the first MSFT trade (no forward fill), then three trailing \
       AAPL trades that never pair; expect one incomplete AAPL tick."

let single_symbol ~seed =
  let name = "05b_single_symbol_only" in
  let s = session ~seed ~name ~sa:"AAPL" ~sb:"MSFT" in
  for _ = 1 to 8 do ignore (trade s B) done;
  finish s ~name ~seed ~incomplete:[ "MSFT" ]
    ~description:"Only MSFT trades; no request is possible and one MSFT tick stays pending."

let req index item1 price1 item2 price2 = { C.index; item1; price1; item2; price2 }

let fixed ?(quantum = C.default_quantum_nanos) ?(incomplete = []) ?(notes = []) ~name
    ~description ~records ~requests csv =
  { name; kind = Valid_session; description; seed = None; quantum; symbol_a = "AAPL";
    symbol_b = "MSFT"; max_line_bytes = Csv_stream.default_max_record_bytes; trades_csv = csv;
    input_records = records; expected_requests = requests;
    request_count = List.length requests; expected_incomplete = incomplete;
    expected_error = None; notes }

(* Expected rows below are worked out by hand. *)
let precision_cents =
  fixed ~name:"06a_precision_cent_boundaries" ~records:8
    ~description:
      "Default one-cent quantum: zero price, fractional remainders that must floor, and the \
       largest accepted wire price 65535 (655359999999 nanodollars)."
    ~notes:[ "first rejected value 655360000000 is expected_failure/wire_out_of_range" ]
    ~requests:
      [ req 0 17 0 34 65535; req 1 34 0 17 65535; req 2 17 1 34 1; req 3 34 40000 17 20000 ]
    (header
   ^ "AAPL,1790982000000000000,0\n\
      MSFT,1790982000000000001,655359999999\n\
      MSFT,1790982000000000002,9999999\n\
      AAPL,1790982000000000003,655350000000\n\
      AAPL,1790982000000000004,19999999\n\
      MSFT,1790982000000000005,10000000\n\
      AAPL,1790982000000000006,200009999999\n\
      MSFT,1790982000000000007,400000000001\n")

let precision_large =
  fixed ~name:"06b_precision_above_2_53" ~quantum:281474976710656L ~records:6
    ~description:
      "Prices above 2^53 with quantum 2^48 nanodollars. 9223372036854775806 must give 32767; \
       a float conversion rounds it to 2^63 and gives 32768."
    ~notes:
      [ "65536 * 2^48 overflows int64, so the uint16 limit is unreachable at this quantum" ]
    ~requests:[ req 0 17 32 34 32767; req 1 34 31 17 64; req 2 17 0 34 1 ]
    (header
   ^ "AAPL,1790982000000000000,9007199254740993\n\
      MSFT,1790982000000000001,9223372036854775806\n\
      MSFT,1790982000000000002,9007199254740991\n\
      AAPL,1790982000000000003,18014398509481984\n\
      AAPL,1790982000000000004,281474976710655\n\
      MSFT,1790982000000000005,281474976710656\n")

let quoted_crlf =
  fixed ~name:"07_quoted_crlf_long_timestamps" ~records:6
    ~description:
      "Quoted header and symbols, an unrelated symbol with embedded quotes and a comma, an \
       unrelated symbol containing CRLF inside quotes, CRLF line endings, and 19-20 digit \
       ts_event values beyond int64 preserved as text."
    ~notes:
      [ "ts_event values are intentionally non-monotonic; order is preserved, not sorted";
        "the quoted CRLF symbol spans physical lines 5-6" ]
    ~requests:[ req 0 17 20000 34 40000; req 1 34 39999 17 20100 ]
    "\"symbol\",\"ts_event\",\"price\"\r\n\
     \"AAPL\",1790982000123456789,\"200000000000\"\r\n\
     \"BRK \"\"B\"\", Class\",\"1790982000123456790\",500000000000\r\n\
     MSFT,18446744073709551614,400000000000\r\n\
     \"ZZ\r\nSPLIT\",1790982000123456791,1\r\n\
     \"MSFT\",\"18446744073709551613\",\"399990000000\"\r\n\
     \"AAPL\",9999999999999999999,201000000000\r\n"

let header_only =
  fixed ~name:"08_header_only" ~records:0 ~requests:[]
    ~description:"Header with no data rows: valid, zero records, zero requests." header

let extra_columns =
  fixed ~name:"09_extra_columns_reordered" ~records:4
    ~description:
      "Databento-style wider header with required columns in a different order; extra \
       columns are ignored but every row must have the header's field count."
    ~notes:[ "contract interpretation: extra columns are allowed (see REPORT.md questions)" ]
    ~requests:[ req 0 17 20000 34 40000; req 1 34 39990 17 20010 ]
    "ts_recv,ts_event,rtype,publisher_id,instrument_id,action,side,price,size,symbol\n\
     1790982000000000100,1790982000000000000,0,2,15144,T,B,200000000000,100,AAPL\n\
     1790982000000000101,1790982000000000001,0,2,10888,T,A,400000000000,50,MSFT\n\
     1790982000000000102,1790982000000000002,0,2,15144,T,N,200100000000,10,AAPL\n\
     1790982000000000103,1790982000000000003,0,2,10888,T,B,399900000000,5,MSFT\n"

let g1 = "AAPL,1790982000000000000,200000000000\n"
let g2 = "MSFT,1790982000000000001,400000000000\n"

let failing ?(max_line_bytes = Csv_stream.default_max_record_bytes) ?field ?value
    ?(records = 0) ?(requests = 0) ~name ~description ~category ~line csv =
  { name; kind = Expected_failure;
    description = "EXPECTED FAILURE, not a valid trading session. " ^ description;
    seed = None; quantum = C.default_quantum_nanos; symbol_a = "AAPL"; symbol_b = "MSFT";
    max_line_bytes; trades_csv = csv; input_records = records;
    expected_requests = []; request_count = requests;
    expected_incomplete = []; expected_error = Some { category; line; field; value };
    notes = [ "expected_input_records and expected_requests count what was accepted before the failure" ] }

let malformed =
  [ failing ~name:"empty_file" ~description:"Zero-byte input." ~category:"empty_input" ~line:1 "";
    failing ~name:"missing_header" ~description:"Data row where the header should be."
      ~category:"missing_column" ~line:1 ~field:"symbol"
      ~value:"AAPL,1790982000000000000,200000000000" (g1 ^ g2);
    failing ~name:"missing_price_column" ~description:"Header lacks the price column."
      ~category:"missing_column" ~line:1 ~field:"price" ~value:"symbol,ts_event"
      "symbol,ts_event\nAAPL,1790982000000000000\n";
    failing ~name:"duplicate_header" ~description:"price column declared twice."
      ~category:"duplicate_column" ~line:1 ~field:"price" ~value:"symbol,ts_event,price,price"
      "symbol,ts_event,price,price\nAAPL,1790982000000000000,200000000000,200000000000\n";
    failing ~name:"field_count_extra" ~description:"Row with four fields under a three-column header."
      ~category:"field_count" ~line:3 ~value:"4" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001,400000000000,7\n");
    failing ~name:"field_count_short" ~description:"Row with two fields."
      ~category:"field_count" ~line:3 ~value:"2" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001\n");
    failing ~name:"blank_line" ~description:"Empty line between rows is a one-field record."
      ~category:"field_count" ~line:3 ~value:"1" ~records:1 (header ^ g1 ^ "\n" ^ g2);
    failing ~name:"truncated_quote" ~description:"Input ends inside a quoted price."
      ~category:"unterminated_quote" ~line:3 ~value:"400000000000\n" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001,\"400000000000\n");
    failing ~name:"malformed_quote" ~description:"Quote character inside an unquoted symbol."
      ~category:"malformed_quote" ~line:2 ~value:"AA"
      (header ^ "AA\"PL,1790982000000000000,200000000000\n");
    failing ~name:"bare_carriage_return" ~description:"Lone CR used as a line terminator."
      ~category:"bare_carriage_return" ~line:2 ~value:"200000000000"
      (header ^ "AAPL,1790982000000000000,200000000000\rMSFT,1790982000000000001,400000000000\n");
    failing ~name:"line_too_long" ~description:"300-byte symbol with max_line_bytes = 128."
      ~max_line_bytes:128 ~category:"line_too_long" ~line:2 ~value:(String.make 128 'X')
      (header ^ String.make 300 'X' ^ ",1790982000000000000,1\n");
    failing ~name:"invalid_number" ~description:"Decimal point in a nanodollar price."
      ~category:"invalid_number" ~line:3 ~field:"price" ~value:"400.5" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001,400.5\n");
    failing ~name:"missing_price" ~description:"Empty price field."
      ~category:"missing_price" ~line:3 ~field:"price" ~value:"" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001,\n");
    failing ~name:"negative_price" ~description:"Negative price for a configured symbol."
      ~category:"negative_price" ~line:3 ~field:"price" ~value:"-1" ~records:1
      (header ^ g1 ^ "MSFT,1790982000000000001,-1\n");
    failing ~name:"negative_price_unrelated_symbol"
      ~description:"Negative price on an unrelated symbol is still corruption."
      ~category:"negative_price" ~line:3 ~field:"price" ~value:"-5" ~records:1
      (header ^ g1 ^ "GOOG,1790982000000000001,-5\n" ^ g2);
    failing ~name:"undefined_price" ~description:"Databento UNDEF_PRICE after one good pair."
      ~category:"undefined_price" ~line:4 ~field:"price" ~value:"9223372036854775807"
      ~records:2 ~requests:1
      (header ^ g1 ^ g2 ^ "AAPL,1790982000000000002,9223372036854775807\n");
    failing ~name:"int64_overflow" ~description:"INT64_MAX + 1 after one good pair."
      ~category:"int64_overflow" ~line:4 ~field:"price" ~value:"9223372036854775808"
      ~records:2 ~requests:1
      (header ^ g1 ^ g2 ^ "AAPL,1790982000000000002,9223372036854775808\n");
    failing ~name:"wire_out_of_range"
      ~description:"655360000000 nanodollars is wire 65536, the first rejected value at one cent."
      ~category:"wire_out_of_range" ~line:2 ~field:"price" ~value:"655360000000"
      (header ^ "AAPL,1790982000000000000,655360000000\n" ^ g2);
    failing ~name:"invalid_timestamp" ~description:"Exponent notation in ts_event."
      ~category:"invalid_timestamp" ~line:3 ~field:"ts_event" ~value:"1790982e9" ~records:1
      (header ^ g1 ^ "MSFT,1790982e9,400000000000\n");
    failing ~name:"empty_symbol" ~description:"Empty symbol field."
      ~category:"empty_symbol" ~line:2 ~field:"symbol" ~value:""
      (header ^ ",1790982000000000000,200000000000\n") ]

let default_seed = 42
let default_pairs = 100

let all ~seed ~pairs =
  if pairs < 1 || pairs > C.max_requests then
    invalid_arg (Printf.sprintf "pairs must be in 1..%d" C.max_requests);
  [ alternating ~seed ~pairs; faster_a ~seed; faster_b ~seed; unrelated_interleaved ~seed;
    late_second_trailing ~seed; single_symbol ~seed; precision_cents; precision_large;
    quoted_crlf; header_only; extra_columns ]
  @ malformed

let dir_of spec =
  match spec.kind with
  | Valid_session -> Filename.concat "valid" spec.name
  | Expected_failure -> Filename.concat "expected_failure" spec.name

let kind_name = function Valid_session -> "valid_session" | Expected_failure -> "expected_failure"

let opt_string = function None -> `Null | Some s -> `String s

let manifest ~pairs spec : Yojson.Safe.t =
  let valid = spec.kind = Valid_session in
  `Assoc
    [ ("name", `String spec.name); ("kind", `String (kind_name spec.kind));
      ("description", `String spec.description);
      ( "generator",
        `Assoc
          [ ("tool", `String "databento_audit generate");
            ("seed", match spec.seed with Some s -> `Int s | None -> `Null);
            ("pairs", if spec.name = "01_alternating" then `Int pairs else `Null);
            ("rng", `String (if spec.seed = None then "none (hand-written)" else "splitmix64 seeded with seed xor fnv1a64(name)")) ] );
      ("symbol_a", `String spec.symbol_a); ("item_a", `Int C.item_a);
      ("symbol_b", `String spec.symbol_b); ("item_b", `Int C.item_b);
      ("quantum_nanos", `String (Int64.to_string spec.quantum));
      ("max_line_bytes", `Int spec.max_line_bytes);
      ("slot_order", `String "alternating");
      ( "files",
        `Assoc
          [ ("trades", `String "trades.csv");
            ("expected_requests", if valid then `String "expected_requests.csv" else `Null) ] );
      ("expected_valid", `Bool valid);
      ("expected_input_records", `Int spec.input_records);
      ("expected_requests", `Int spec.request_count);
      ("expected_incomplete_symbols", `List (List.map (fun s -> `String s) spec.expected_incomplete));
      ( "expected_error",
        match spec.expected_error with
        | None -> `Null
        | Some e ->
            `Assoc
              [ ("category", `String e.category); ("line", `Int e.line);
                ("field", opt_string e.field); ("value", opt_string e.value) ] );
      ("notes", `List (List.map (fun s -> `String s) spec.notes)) ]

let json_text j = Yojson.Safe.pretty_to_string j ^ "\n"

(* Relative path and contents for every file the generator writes. *)
let files ~seed ~pairs =
  let specs = all ~seed ~pairs in
  let per_spec spec =
    let d = dir_of spec in
    let base =
      [ (Filename.concat d "trades.csv", spec.trades_csv);
        (Filename.concat d "manifest.json", json_text (manifest ~pairs spec)) ]
    in
    if spec.kind = Valid_session then
      base @ [ (Filename.concat d "expected_requests.csv", C.requests_csv spec.expected_requests) ]
    else base
  in
  let index =
    `Assoc
      [ ("generator", `String "databento_audit generate"); ("seed", `Int seed);
        ("pairs", `Int pairs);
        ( "note",
          `String
            "Synthetic local fixtures. expected_failure entries are malformed on purpose and \
             are not trading sessions. Not hardware results." );
        ( "fixtures",
          `List
            (List.map
               (fun s ->
                 `Assoc
                   [ ("name", `String s.name); ("kind", `String (kind_name s.kind));
                     ("manifest", `String (Filename.concat (dir_of s) "manifest.json")) ])
               specs) ) ]
  in
  List.concat_map per_spec specs @ [ ("index.json", json_text index) ]
