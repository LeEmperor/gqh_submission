type tick = { symbol:string; ts_event:string; price:int64 }
type source = { next:unit -> tick option; close:unit -> unit }
let fail message = failwith ("Databento: " ^ message)
let decimal s = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s
let timestamp s =
  if not (decimal s) then fail "timestamp must be unsigned nanoseconds";
  let rec first i = if i < String.length s && s.[i] = '0' then first (i+1) else i in
  let start = first 0 in
  let digits = String.sub s start (String.length s-start) in
  if String.length digits > 20 || (String.length digits = 20 && String.compare digits "18446744073709551615" > 0)
  then fail "timestamp exceeds uint64 range";
  s
let price s =
  if not (decimal s) then fail "price must be nonnegative integer nanodollars";
  let n = try Int64.of_string s with _ -> fail "price exceeds int64 range" in
  if n = Int64.max_int then fail "undefined price"; n
let safe_atom name s =
  if s = "" || String.length s > 4096 || String.exists (fun c -> Char.code c < 32 || Char.code c > 126 || c = '|') s
  then fail ("invalid " ^ name)
let validate_symbols symbols =
  if symbols = [] then fail "at least one symbol is required";
  List.iter (fun s -> safe_atom "symbol" s; if String.contains s ',' || s = "ALL_SYMBOLS" then fail "invalid raw symbol") symbols;
  if List.length (List.sort_uniq String.compare symbols) <> List.length symbols then fail "duplicate configured symbol"
type reader = { fd:Unix.file_descr; pending:Buffer.t; mutable stash:string; mutable offset:int; mutable eof:bool; timeout:float option; max_record_bytes:int }
let reader ?timeout ?(max_record_bytes=1_048_576) fd =
  if max_record_bytes <= 0 then invalid_arg "max_record_bytes must be positive";
  {fd;pending=Buffer.create 256;stash="";offset=0;eof=false;timeout;max_record_bytes}
let line ?deadline ?(keep_cr=false) r =
  let deadline = match deadline with Some _ -> deadline | None -> Option.map (fun t -> Clock.now () +. t) r.timeout in
  let check () = Option.iter (fun stop -> if Clock.now () >= stop then fail "network read timed out") deadline in
  let rec refill () =
    check ();
    try
      (match deadline with None -> () | Some stop ->
        let ready,_,_ = Unix.select [r.fd] [] [] (max 0. (stop -. Clock.now ())) in
        if ready = [] then fail "network read timed out");
      let bytes = Bytes.create 4096 in
      let n = Unix.read r.fd bytes 0 4096 in
      if n = 0 then r.eof <- true else (r.stash <- Bytes.sub_string bytes 0 n; r.offset <- 0)
    with Unix.Unix_error ((Unix.EINTR|Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> refill () in
  let finish () =
    let s = Buffer.contents r.pending in Buffer.clear r.pending;
    let n = String.length s in if not keep_cr && n > 0 && s.[n-1] = '\r' then String.sub s 0 (n-1) else s in
  let rec loop () =
    check ();
    if r.offset < String.length r.stash then (
      let c = r.stash.[r.offset] in r.offset <- r.offset+1;
      if c = '\n' then Some (finish ()) else (
        if Buffer.length r.pending >= r.max_record_bytes then fail "record exceeds configured byte limit";
        Buffer.add_char r.pending c; loop ()))
    else if r.eof then (if Buffer.length r.pending = 0 then None else Some (finish ()))
    else (refill (); loop ()) in loop ()
let close_fd fd = try Unix.close fd with Unix.Unix_error _ -> ()
let write fd text =
  let deadline = Clock.now () +. 40. and bytes = Bytes.of_string text in
  let rec loop offset = if offset < Bytes.length bytes then (
    let remaining = deadline -. Clock.now () in if remaining <= 0. then fail "network write timed out";
    try
      let _,ready,_ = Unix.select [] [fd] [] remaining in if ready = [] then fail "network write timed out";
      let n = Unix.write fd bytes offset (Bytes.length bytes-offset) in
      if n = 0 then fail "network closed while writing";
      loop (offset+n)
    with Unix.Unix_error ((Unix.EINTR|Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> loop offset) in loop 0
let csv_fields text =
  let len = String.length text and field = Buffer.create 64 and fields = ref [] in
  let emit () = fields := Buffer.contents field :: !fields; Buffer.clear field in
  let rec unquoted i = if i = len then (emit (); List.rev !fields) else match text.[i] with
    | ',' -> emit (); start (i+1) | '"' -> fail "unexpected quote in CSV field"
    | '\r' | '\n' -> fail "unquoted line break in CSV field"
    | c -> Buffer.add_char field c; unquoted (i+1)
  and quoted i = if i = len then fail "unterminated quoted CSV field" else if text.[i] = '"' then
    if i+1 < len && text.[i+1] = '"' then (Buffer.add_char field '"'; quoted (i+2)) else after_quote (i+1)
    else (Buffer.add_char field text.[i]; quoted (i+1))
  and after_quote i = if i = len then (emit (); List.rev !fields) else if text.[i] = ',' then (emit (); start (i+1)) else fail "characters after closing CSV quote"
  and start i = if i < len && text.[i] = '"' then quoted (i+1) else unquoted i in start 0
(* Retain CRLF inside quoted fields while bounding the whole CSV record. *)
let csv_record r =
  let buffer = Buffer.create 256 and state = ref `Start in
  let scan text = String.iter (fun c ->
    state := (match !state,c with
      | `Start,'"' -> `Quoted
      | `Start,',' -> `Start
      | `Start,_ -> `Unquoted
      | `Unquoted,',' -> `Start
      | `Unquoted,_ -> `Unquoted
      | `Quoted,'"' -> `After_quote
      | `Quoted,_ -> `Quoted
      | `After_quote,'"' -> `Quoted
      | `After_quote,',' -> `Start
      | `After_quote,_ -> `Unquoted)) text in
  let rec consume () = match line ~keep_cr:true r with
    | None -> if Buffer.length buffer = 0 then None else fail "unterminated quoted CSV field"
    | Some raw ->
      if Buffer.length buffer + String.length raw > r.max_record_bytes then fail "record exceeds configured byte limit";
      scan raw;
      if !state = `Quoted then (
        Buffer.add_string buffer raw;Buffer.add_char buffer '\n';consume ())
      else (
        let n = String.length raw in
        let raw = if not r.eof && n > 0 && raw.[n-1] = '\r' then String.sub raw 0 (n-1) else raw in
        Buffer.add_string buffer raw;Some (Buffer.contents buffer))
  in consume ()
let csv_source r close =
  let closed = ref false in
  let close_once () = if not !closed then (closed := true; close ()) in
  let header = try match csv_record r with
    | None -> fail "CSV is empty"
    | Some s -> let fields = csv_fields s in
      if List.length fields <> List.length (List.sort_uniq String.compare fields) then fail "duplicate CSV header";
      fields
    with exn -> close_once (); raise exn in
  let index name =
    let rec find i = function [] -> close_once (); fail ("missing CSV column " ^ name)
      | x::xs -> if x = name then i else find (i+1) xs in find 0 header in
  let symbol_index = index "symbol" and timestamp_index = index "ts_event" and price_index = index "price" in
  let next () = if !closed then None else
    try match csv_record r with
    | None -> close_once (); None
    | Some s ->
      let fields = Array.of_list (csv_fields s) in
      if Array.length fields <> List.length header then fail "CSV row width mismatch";
      let symbol = fields.(symbol_index) in if symbol = "" then fail "empty CSV symbol";
      Some {symbol;ts_event=timestamp fields.(timestamp_index);price=price fields.(price_index)}
    with exn -> close_once (); raise exn in {next;close=close_once}
let replay ?(max_record_bytes=1_048_576) path =
  if max_record_bytes <= 0 then invalid_arg "max_record_bytes must be positive";
  let fd = Unix.openfile path [Unix.O_RDONLY;Unix.O_CLOEXEC] 0 in
  csv_source (reader ~max_record_bytes fd) (fun () -> close_fd fd)
let config_quote s =
  if String.exists (fun c -> c = '\n' || c = '\r' || c = '\000') s then fail "invalid HTTP configuration value";
  let b = Buffer.create (String.length s+2) in Buffer.add_char b '"';
  String.iter (fun c -> if c = '"' || c = '\\' then Buffer.add_char b '\\'; Buffer.add_char b c) s;
  Buffer.add_char b '"'; Buffer.contents b
let historical_with ~curl ~api_key ~dataset ~symbols ~start ~end_ ~limit =
  safe_atom "API key" api_key; safe_atom "dataset" dataset; validate_symbols symbols;
  if limit <= 0 then fail "limit must be positive";
  (* Validate configuration before allocating process resources. *)
  let cfg = ["url","https://hist.databento.com/v0/timeseries.get_range";"user",api_key ^ ":";"request","POST";
    "data-urlencode","dataset=" ^ dataset;"data-urlencode","schema=trades";"data-urlencode","symbols=" ^ String.concat "," symbols;
    "data-urlencode","stype_in=raw_symbol";"data-urlencode","start=" ^ start;"data-urlencode","end=" ^ end_;
    "data-urlencode","encoding=csv";"data-urlencode","compression=none";"data-urlencode","pretty_px=false";
    "data-urlencode","pretty_ts=false";"data-urlencode","map_symbols=true";"data-urlencode","limit=" ^ string_of_int limit] in
  let config = String.concat "\n" (List.map (fun (k,v) -> k ^ " = " ^ config_quote v) cfg) ^ "\n" in
  let cfg_read,cfg_write = Unix.pipe ~cloexec:true () in
  let out_read,out_write = Unix.pipe ~cloexec:true () in
  let devnull = Unix.openfile "/dev/null" [Unix.O_WRONLY;Unix.O_CLOEXEC] 0 in
  let pid = try Unix.create_process curl
    [|curl;"--disable";"--config";"-";"--silent";"--fail";"--no-buffer";"--include";"--suppress-connect-headers";"--connect-timeout";"20";"--max-time";"120"|]
    cfg_read out_write devnull
    with exn -> List.iter close_fd [cfg_read;cfg_write;out_read;out_write;devnull]; raise exn in
  List.iter close_fd [cfg_read;out_write;devnull]; Unix.set_nonblock cfg_write;
  let waited = ref false and released = ref false in
  let wait () = if !waited then None else (
    let rec reap () = try let status = snd (Unix.waitpid [] pid) in waited := true; Some status
      with Unix.Unix_error (Unix.EINTR,_,_) -> reap () in reap ()) in
  let release () = if not !released then (released := true; close_fd out_read) in
  let stop () = release (); if not !waited then ((try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());ignore (wait ())) in
  (try write cfg_write config; close_fd cfg_write with _ -> close_fd cfg_write; stop (); fail "historical request setup failed");
  let finish () = release (); match wait () with Some (Unix.WEXITED 0)|None -> () | Some _ -> fail "historical HTTP request failed" in
  let r = reader ~timeout:130. out_read in
  let rec headers () =
    let status = match line r with None -> fail "historical HTTP request failed" | Some s -> s in
    let fields = String.split_on_char ' ' status in
    let code = match fields with version::n::_ when String.starts_with ~prefix:"HTTP/" version ->
      (try int_of_string n with _ -> fail "invalid HTTP status") | _ -> fail "missing HTTP status" in
    let rec drain () = match line r with Some "" -> () | Some _ -> drain () | None -> fail "truncated HTTP headers" in
    drain ();
    if code >= 100 && code < 200 then headers ()
    else if code <> 200 then fail (Printf.sprintf "historical HTTP status %d (complete symbol resolution required)" code) in
  let src = try headers (); csv_source r finish with exn -> stop (); raise exn in
  {next=(fun () -> if !released then None else try
      match src.next () with
      | Some tick when not (List.mem tick.symbol symbols) -> stop (); fail "historical record has unexpected symbol"
      | result -> result
    with exn -> stop (); raise exn);close=stop}
let historical = historical_with ~curl:"curl"
let member name = function `Assoc fields -> (try List.assoc name fields with Not_found -> `Null) | _ -> `Null
let scalar = function `String s|`Intlit s -> s | `Int n -> string_of_int n | _ -> fail "expected integer or string JSON field"
let json_tick ~symbols ~mappings json =
  let hd = member "hd" json in
  match scalar (member "rtype" hd) with
  | "21" -> fail "live server returned an error record"
  | "23" -> None
  | "22" ->
    let input = scalar (member "stype_in_symbol" json) in
    let id = scalar (member "instrument_id" hd) in
    if List.mem input symbols then Hashtbl.replace mappings id input; None
  | "0" ->
    let id = scalar (member "instrument_id" hd) in
    let symbol = match Hashtbl.find_opt mappings id with Some s -> s | None -> fail "trade arrived without a configured symbol mapping" in
    Some {symbol;ts_event=timestamp (scalar (member "ts_event" hd));price=price (scalar (member "price" json))}
  | _ -> fail "unexpected record type in trades subscription"
let connect host port =
  let addresses = Unix.getaddrinfo host (string_of_int port) [Unix.AI_SOCKTYPE Unix.SOCK_STREAM] in
  let deadline = Clock.now () +. 40. in
  let rec attempt = function
    | [] -> fail "could not connect to live gateway"
    | address::rest ->
      let fd = Unix.socket ~cloexec:true address.Unix.ai_family Unix.SOCK_STREAM 0 in
      try
        Unix.set_nonblock fd;
        (try Unix.connect fd address.Unix.ai_addr with
         | Unix.Unix_error ((Unix.EINPROGRESS|Unix.EWOULDBLOCK|Unix.EAGAIN),_,_) ->
           let remaining = deadline -. Clock.now () in if remaining <= 0. then fail "live connection timed out";
           let _,ready,_ = Unix.select [] [fd] [] remaining in if ready = [] then fail "live connection timed out";
           match Unix.getsockopt_error fd with None -> () | Some _ -> fail "live connection failed"); fd
      with _ -> close_fd fd; attempt rest in attempt addresses
let protocol_fields text = List.filter_map (fun part -> match String.index_opt part '=' with None -> None
  | Some i -> Some (String.sub part 0 i,String.sub part (i+1) (String.length part-i-1))) (String.split_on_char '|' text)
let redact secrets text =
  let replace secret text =
    if secret = "" then text else
    let b = Buffer.create (String.length text) in
    let rec loop i =
      if i < String.length text then (
        if i + String.length secret <= String.length text && String.sub text i (String.length secret) = secret
        then (Buffer.add_string b "[redacted]";loop (i + String.length secret))
        else (Buffer.add_char b text.[i];loop (i+1)))
    in loop 0;Buffer.contents b in
  let text = List.fold_left (fun text secret -> replace secret text) text secrets in
  let text = String.map (fun c -> if Char.code c < 32 || Char.code c = 127 then ' ' else c) text in
  if String.length text > 512 then String.sub text 0 512 ^ "..." else text
let authentication_failure ~api_key ~token ~dataset response =
  let reason = Option.value (List.assoc_opt "error" response) ~default:"server returned no error description" in
  let digest = match String.index_opt token '-' with Some i -> String.sub token 0 i | None -> token in
  let reason = redact [api_key;token;digest] reason in
  fail ("live authentication failed for dataset " ^ dataset ^ ": " ^ reason)
let live_at ?(timeout=40.) ~host ~port ~api_key ~dataset ~symbols () =
  if not (Float.is_finite timeout) || timeout <= 0. then fail "invalid live read timeout";
  safe_atom "API key" api_key; if String.length api_key < 5 then fail "API key is too short";
  safe_atom "dataset" dataset; validate_symbols symbols;
  let fd = connect host port in let r = reader ~timeout fd and closed = ref false in
  let close () = if not !closed then (closed := true;close_fd fd) in
  let required_line ~deadline () = match line ~deadline r with Some text -> text | None -> fail "live gateway disconnected" in
  try
    let auth_deadline = Clock.now () +. timeout in
    let challenge = ref None in
    for _ = 1 to 2 do if !challenge = None then challenge := List.assoc_opt "cram" (protocol_fields (required_line ~deadline:auth_deadline ())) done;
    let challenge = match !challenge with Some v -> v | None -> fail "live authentication challenge missing" in
    let token = Sha256.digest (challenge ^ "|" ^ api_key) ^ "-" ^ String.sub api_key (String.length api_key-5) 5 in
    write fd ("auth=" ^ token ^ "|dataset=" ^ dataset ^ "|encoding=json|compression=none|pretty_px=0|pretty_ts=0|slow_reader_behavior=warn|ts_out=0\n");
    let response = protocol_fields (required_line ~deadline:auth_deadline ()) in
    if List.assoc_opt "success" response <> Some "1" then authentication_failure ~api_key ~token ~dataset response;
    write fd ("schema=trades|stype_in=raw_symbol|symbols=" ^ String.concat "," symbols ^ "\n"); write fd "start_session=1\n";
    let mappings = Hashtbl.create 16 in
    let next () = if !closed then None else
      let deadline = Clock.now () +. timeout in
      let rec consume () = match line ~deadline r with
        | None -> fail "live gateway disconnected"
        | Some text ->
          let json = try Yojson.Safe.from_string text with _ -> fail "invalid live JSON record" in
          match json_tick ~symbols ~mappings json with None -> consume () | Some tick -> Some tick in
      try consume () with exn -> close ();raise exn in {next;close}
  with exn -> close ();raise exn
let live ~api_key ~dataset ~symbols =
  let host = String.lowercase_ascii dataset |> String.map (fun c -> if c = '.' then '-' else c) in
  live_at ~host:(host ^ ".lsg.databento.com") ~port:13000 ~api_key ~dataset ~symbols ()
