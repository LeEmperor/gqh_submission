(* Streaming capture validator. Memory use is bounded by the CSV record limit,
   the two pending ticks and a fixed set of counters. *)

module C = Trade_contract

type config = {
  symbol_a : string;
  symbol_b : string;
  quantum : int64;
  max_line_bytes : int;
}

let default_config ~symbol_a ~symbol_b =
  { symbol_a; symbol_b; quantum = C.default_quantum_nanos;
    max_line_bytes = Csv_stream.default_max_record_bytes }

type category =
  | Empty_input
  | Missing_column
  | Duplicate_column
  | Field_count
  | Unterminated_quote
  | Malformed_quote
  | Bare_carriage_return
  | Line_too_long
  | Empty_symbol
  | Invalid_timestamp
  | Missing_price
  | Negative_price
  | Undefined_price
  | Int64_overflow
  | Invalid_number
  | Wire_out_of_range
  | Request_limit

let category_name = function
  | Empty_input -> "empty_input"
  | Missing_column -> "missing_column"
  | Duplicate_column -> "duplicate_column"
  | Field_count -> "field_count"
  | Unterminated_quote -> "unterminated_quote"
  | Malformed_quote -> "malformed_quote"
  | Bare_carriage_return -> "bare_carriage_return"
  | Line_too_long -> "line_too_long"
  | Empty_symbol -> "empty_symbol"
  | Invalid_timestamp -> "invalid_timestamp"
  | Missing_price -> "missing_price"
  | Negative_price -> "negative_price"
  | Undefined_price -> "undefined_price"
  | Int64_overflow -> "int64_overflow"
  | Invalid_number -> "invalid_number"
  | Wire_out_of_range -> "wire_out_of_range"
  | Request_limit -> "request_limit"

type failure = {
  category : category;
  message : string;
  line : int;
  record : int option;  (** 1-based data record number; header is not counted. *)
  field : string option;
  value : string option;
}

type pending = {
  symbol : string;
  p_line : int;
  p_record : int;
  ts_event : string;
  price : int64;
  wire : int;
}

type counts = {
  mutable data_records : int;
  mutable symbol_a_trades : int;
  mutable symbol_b_trades : int;
  mutable unrelated_trades : int;
  mutable coalesced_trades : int;
  mutable requests : int;
  mutable ts_event_regressions : int;
}

type result = {
  config : config;
  counts : counts;
  header_seen : bool;
  pending_a : pending option;
  pending_b : pending option;
  failure : failure option;
}

let is_valid r = Option.is_none r.failure

exception Stop of failure

let max_reported_value = 256

let clip s =
  if String.length s <= max_reported_value then s
  else String.sub s 0 max_reported_value ^ "...[truncated]"

let fail ?record ?field ?value category line message =
  raise (Stop { category; message; line; record; field; value = Option.map clip value })

let check_config c =
  if c.symbol_a = "" || c.symbol_b = "" then Error "symbols must be non-empty"
  else if String.equal c.symbol_a c.symbol_b then Error "symbol_a and symbol_b must differ"
  else if Int64.compare c.quantum 0L <= 0 then Error "quantum_nanos must be positive"
  else if c.max_line_bytes < 16 then Error "max_line_bytes must be at least 16"
  else Ok ()

let locate_columns (r : Csv_stream.record) =
  let find name =
    let hits = ref [] in
    Array.iteri (fun i h -> if String.equal h name then hits := i :: !hits) r.fields;
    match !hits with
    | [ i ] -> i
    | [] ->
        fail ~field:name ~value:(String.concat "," (Array.to_list r.fields))
          Missing_column r.line (Printf.sprintf "header has no %S column" name)
    | _ ->
        fail ~field:name ~value:(String.concat "," (Array.to_list r.fields))
          Duplicate_column r.line (Printf.sprintf "header has more than one %S column" name)
  in
  let s = find "symbol" in
  let t = find "ts_event" in
  let p = find "price" in
  (s, t, p)

let csv_failure (e : Csv_stream.error) ~record =
  let category =
    match e.kind with
    | Csv_stream.Unterminated_quote -> Unterminated_quote
    | Malformed_quote _ -> Malformed_quote
    | Bare_carriage_return -> Bare_carriage_return
    | Record_too_long _ -> Line_too_long
  in
  { category; message = Csv_stream.error_kind_to_string e.kind; line = e.line;
    record; field = None; value = Some (clip e.partial) }

let run ?(on_request = fun (_ : C.request) -> ()) config ic =
  (match check_config config with Ok () -> () | Error m -> invalid_arg m);
  let counts =
    { data_records = 0; symbol_a_trades = 0; symbol_b_trades = 0; unrelated_trades = 0;
      coalesced_trades = 0; requests = 0; ts_event_regressions = 0 }
  in
  let pending_a = ref None and pending_b = ref None in
  let header_seen = ref false in
  let last_ts = ref None in
  let reader = Csv_stream.create ~max_record_bytes:config.max_line_bytes ic in
  let next ~record =
    match Csv_stream.next reader with
    | Ok r -> r
    | Error e -> raise (Stop (csv_failure e ~record))
  in
  let process (si, ti, pi) width (r : Csv_stream.record) =
    let record = counts.data_records + 1 in
    let n = Array.length r.fields in
    if n <> width then
      fail ~record ~value:(string_of_int n) Field_count r.line
        (Printf.sprintf "expected %d fields, found %d" width n);
    let symbol = r.fields.(si) and ts = r.fields.(ti) and price_text = r.fields.(pi) in
    if symbol = "" then fail ~record ~field:"symbol" ~value:"" Empty_symbol r.line "empty symbol";
    (match C.check_ts_event ts with
     | Ok () -> ()
     | Error m -> fail ~record ~field:"ts_event" ~value:ts Invalid_timestamp r.line m);
    let price =
      match C.parse_price price_text with
      | Ok p -> p
      | Error e ->
          let category =
            match e with
            | C.Missing_price -> Missing_price
            | Negative_price -> Negative_price
            | Undefined_price -> Undefined_price
            | Int64_overflow -> Int64_overflow
            | Invalid_number -> Invalid_number
          in
          fail ~record ~field:"price" ~value:price_text category r.line
            (C.price_error_to_string e)
    in
    let side =
      if String.equal symbol config.symbol_a then `A
      else if String.equal symbol config.symbol_b then `B
      else `Unrelated
    in
    let wire () =
      match C.to_wire ~quantum:config.quantum price with
      | Ok w -> w
      | Error w ->
          fail ~record ~field:"price" ~value:price_text Wire_out_of_range r.line
            (Printf.sprintf "floor(%s / %Ld) = %Ld exceeds %d" price_text config.quantum w
               C.max_wire_price)
    in
    let tick w = { symbol; p_line = r.line; p_record = record; ts_event = ts; price; wire = w } in
    (match side with
     | `A ->
         let w = wire () in
         if Option.is_some !pending_a then counts.coalesced_trades <- counts.coalesced_trades + 1;
         pending_a := Some (tick w);
         counts.symbol_a_trades <- counts.symbol_a_trades + 1
     | `B ->
         let w = wire () in
         if Option.is_some !pending_b then counts.coalesced_trades <- counts.coalesced_trades + 1;
         pending_b := Some (tick w);
         counts.symbol_b_trades <- counts.symbol_b_trades + 1
     | `Unrelated -> counts.unrelated_trades <- counts.unrelated_trades + 1);
    (match !last_ts with
     | Some prev when C.compare_ts_event ts prev < 0 ->
         counts.ts_event_regressions <- counts.ts_event_regressions + 1
     | _ -> ());
    last_ts := Some ts;
    (match (!pending_a, !pending_b) with
     | Some a, Some b ->
         if counts.requests >= C.max_requests then
           fail ~record ~field:"symbol" ~value:symbol Request_limit r.line
             (Printf.sprintf "pair would be request %d; a session holds at most %d"
                (counts.requests + 1) C.max_requests);
         on_request (C.make_request ~index:counts.requests ~wire_a:a.wire ~wire_b:b.wire);
         counts.requests <- counts.requests + 1;
         pending_a := None;
         pending_b := None
     | _ -> ());
    counts.data_records <- record
  in
  let failure =
    try
      match next ~record:None with
      | None ->
          fail Empty_input 1 "input is empty; expected a header with symbol, ts_event, price"
      | Some header ->
          let cols = locate_columns header in
          header_seen := true;
          let width = Array.length header.fields in
          let rec loop () =
            match next ~record:(Some (counts.data_records + 1)) with
            | None -> ()
            | Some r -> process cols width r; loop ()
          in
          loop ();
          None
    with Stop f -> Some f
  in
  { config; counts; header_seen = !header_seen; pending_a = !pending_a;
    pending_b = !pending_b; failure }

let run_file ?on_request config path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> run ?on_request config ic)

let run_string ?on_request config s =
  let path = Filename.temp_file "databento_audit" ".csv" in
  Fun.protect
    ~finally:(fun () -> try Sys.remove path with Sys_error _ -> ())
    (fun () ->
      Out_channel.with_open_bin path (fun oc -> output_string oc s);
      run_file ?on_request config path)

let incomplete_symbols r =
  List.filter_map (fun p -> Option.map (fun t -> t.symbol) p) [ r.pending_a; r.pending_b ]
