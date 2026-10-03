(* Independent offline audit: uses only OCaml stdlib, never Tickweave modules.
   This reader handles single-line CSV records used in this captured run. *)
let require yes message = if not yes then failwith message
let csv text =
  let fields = ref [] and field = Buffer.create 32 in
  let emit () = fields := Buffer.contents field :: !fields; Buffer.clear field in
  let rec start i =
    if i < String.length text && text.[i] = '"' then quoted (i+1) else plain i
  and plain i =
    if i = String.length text then (emit (); List.rev !fields)
    else match text.[i] with
    | ',' -> emit (); start (i+1)
    | '"' -> failwith "unexpected CSV quote"
    | c -> Buffer.add_char field c; plain (i+1)
  and quoted i =
    require (i < String.length text) "unterminated CSV quote";
    if text.[i] <> '"' then (Buffer.add_char field text.[i]; quoted (i+1))
    else if i+1 < String.length text && text.[i+1] = '"' then
      (Buffer.add_char field '"'; quoted (i+2))
    else if i+1 = String.length text then (emit (); List.rev !fields)
    else (require (text.[i+1] = ',') "invalid CSV quote ending"; emit (); start (i+2))
  in start 0
let read path =
  let ic = open_in path in
  Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
    let line () = let s = input_line ic in
      let n = String.length s in
      csv (if n > 0 && s.[n-1] = '\r' then String.sub s 0 (n-1) else s) in
    let header = line () in
    let rec loop rows = match line () with
      | row -> require (List.length row = List.length header) "CSV field count";
               loop (List.combine header row :: rows)
      | exception End_of_file -> List.rev rows
    in loop [])
let get row name = List.assoc name row
let number row name = int_of_string (get row name)
let nanos row name = Int64.of_string (get row name)
let price_by_id row id =
  if number row "item1" = id then number row "price1"
  else (require (number row "item2" = id) "missing item"; number row "price2")
let digit = function
  | '0'..'9' as c -> Char.code c - Char.code '0'
  | 'a'..'f' as c -> Char.code c - Char.code 'a' + 10
  | 'A'..'F' as c -> Char.code c - Char.code 'A' + 10
  | _ -> failwith "non-hex request"
let bytes hex =
  require (String.length hex = 16) "request must have exactly eight bytes";
  Array.init 8 (fun i -> digit hex.[2*i]*16 + digit hex.[2*i+1])
let main () =
  require (Array.length Sys.argv = 4) "usage: LOG CAPTURE INDEPENDENT_REQUESTS";
  let logs = read Sys.argv.(1) and capture = read Sys.argv.(2)
  and expected = read Sys.argv.(3) in
  require (logs <> []) "no packets to verify";
  let first = List.hd logs in
  let sym_a = get first "symbol_a" and sym_b = get first "symbol_b" in
  let quantum = nanos first "quantum_nanos" in
  require (quantum > 0L) "nonpositive quantum";
  let wire p = require (p >= 0L && p < Int64.max_int) "invalid source price";
    let q = Int64.div p quantum in
    require (q <= 65535L) "wire price overflow"; Int64.to_int q in
  let a = ref None and b = ref None and pairs = ref [] in
  List.iter (fun tick ->
    let symbol = get tick "symbol" in
    if symbol = sym_a || symbol = sym_b then (
      ignore (wire (nanos tick "price"));
      if symbol = sym_a then a := Some tick else b := Some tick;
      match !a,!b with
      | Some x,Some y -> pairs := (x,y)::!pairs; a:=None; b:=None
      | _ -> ())) capture;
  let pairs = List.rev !pairs in
  require (List.length logs = List.length pairs && List.length logs = List.length expected)
    "capture / logged packet / independent request count mismatch";
  List.iteri (fun index (log,((a,b),expected)) ->
    let hex = get log "request_hex" in
    let raw = bytes hex in
    let u16 i = raw.(i)*256 + raw.(i+1) in
    let decoded = [u16 0;raw.(2);u16 3;raw.(5);u16 6] in
    let logged = List.map (number log) ["index";"item1";"price1";"item2";"price2"] in
    require (decoded = logged) (Printf.sprintf "packet %d bytes disagree with log" index);
    require (u16 0 = index && number expected "index" = index) "index sequence";
    require ((raw.(2)=17 && raw.(5)=34) || (raw.(2)=34 && raw.(5)=17)) "item IDs";
    require (get log "session_id" = get first "session_id") "audit expects one session";
    require (get log "symbol_a" = sym_a && get log "symbol_b" = sym_b && nanos log "quantum_nanos" = quantum)
      "configuration changed";
    List.iter (fun (id,tick,suffix) ->
      require (nanos log ("nanos_"^suffix) = nanos tick "price") "selected source price mismatch";
      require (get log ("ts_"^suffix) = get tick "ts_event") "source timestamp mismatch";
      let price = wire (nanos tick "price") in
      require (price_by_id log id = price) "incorrect scale / rounding";
      require (price_by_id expected id = price) "external validator disagreement")
      [17,a,"a";34,b,"b"];
    Printf.printf "PASS index=%d request_hex=%s A=%d B=%d\n" index hex
      (price_by_id log 17) (price_by_id log 34))
    (List.combine logs (List.combine pairs expected));
  Printf.printf "PASS: %d packets; %d captured trades; length, big-endian fields, IDs, indices, exact scaling, fresh pairing, timestamps, independent validator agreement.\n"
    (List.length logs) (List.length capture)
let () = try main () with exn -> Printf.eprintf "FAIL: %s\n" (Printexc.to_string exn); exit 1
