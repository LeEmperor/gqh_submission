module C = Trade_contract
module V = Validator

let report_version = 1

let scope =
  "Offline contract check of a local normalized trade CSV. This is not an FPGA, UART or \
   hardware acceptance result and does not establish Databento API completeness."

let units =
  `Assoc
    [ ("price", `String "int64 nanodollars, 1 USD = 1000000000; emitted as decimal strings");
      ("ts_event", `String "unsigned decimal nanoseconds since the UNIX epoch, preserved as text");
      ("quantum_nanos", `String "nanodollars per wire price unit");
      ("wire_price", `String "floor(price / quantum_nanos), unsigned 16-bit") ]

let opt f = function None -> `Null | Some x -> f x

let pending_json (p : V.pending) =
  `Assoc
    [ ("symbol", `String p.symbol); ("line", `Int p.p_line); ("record", `Int p.p_record);
      ("ts_event", `String p.ts_event); ("price_nanos", `String (Int64.to_string p.price));
      ("wire_price", `Int p.wire) ]

let failure_json (f : V.failure) =
  `Assoc
    [ ("category", `String (V.category_name f.category)); ("message", `String f.message);
      ("line", `Int f.line); ("record", opt (fun i -> `Int i) f.record);
      ("field", opt (fun s -> `String s) f.field);
      ("value", opt (fun s -> `String s) f.value) ]

let status (r : V.result) =
  match r.failure with
  | Some _ -> "invalid"
  | None -> if r.counts.data_records = 0 then "valid_header_only" else "valid"

let to_json ~input (r : V.result) : Yojson.Safe.t =
  let c = r.counts in
  let pending = List.filter_map Fun.id [ r.pending_a; r.pending_b ] in
  `Assoc
    [ ("tool", `String "databento-audit"); ("report_version", `Int report_version);
      ("scope", `String scope); ("input", `String input); ("status", `String (status r));
      ( "config",
        `Assoc
          [ ("symbol_a", `String r.config.symbol_a); ("item_a", `Int C.item_a);
            ("symbol_b", `String r.config.symbol_b); ("item_b", `Int C.item_b);
            ("quantum_nanos", `String (Int64.to_string r.config.quantum));
            ("max_line_bytes", `Int r.config.max_line_bytes);
            ("slot_order", `String "alternating: even index puts item_a in slot 1, odd index puts item_b in slot 1");
            ("max_requests", `Int C.max_requests) ] );
      ("units", units);
      ( "unrelated_symbol_policy",
        `String
          "rows for other symbols are fully parsed and validated (including price sign and \
           int64 range), counted in unrelated_trades, and ignored for pairing; wire range is \
           only checked for configured symbols" );
      ( "counts",
        `Assoc
          [ ("data_records", `Int c.data_records); ("symbol_a_trades", `Int c.symbol_a_trades);
            ("symbol_b_trades", `Int c.symbol_b_trades);
            ("unrelated_trades", `Int c.unrelated_trades);
            ("coalesced_trades", `Int c.coalesced_trades); ("requests", `Int c.requests);
            ("ts_event_regressions", `Int c.ts_event_regressions) ] );
      ( "counts_note",
        `String "counts cover records accepted before the first failure, if any" );
      ("incomplete_pair", `Bool (pending <> []));
      ("unmatched_trailing", `List (List.map pending_json pending));
      ("error", opt failure_json r.failure) ]

let to_string ~input r = Yojson.Safe.pretty_to_string (to_json ~input r) ^ "\n"
