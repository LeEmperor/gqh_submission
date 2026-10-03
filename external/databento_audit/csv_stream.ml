(* Incremental RFC 4180 style reader. Only the current record is buffered, and
   a record is rejected as soon as it exceeds [max_record_bytes]. *)

type error_kind =
  | Unterminated_quote
  | Malformed_quote of string
  | Bare_carriage_return
  | Record_too_long of int

type error = {
  kind : error_kind;
  line : int;  (** Physical line on which the failing record starts. *)
  at_line : int;  (** Physical line on which the problem was detected. *)
  partial : string;  (** Prefix of the field being read, at most 256 bytes. *)
}

type record = { fields : string array; line : int }

type t = {
  ic : in_channel;
  max_record_bytes : int;
  field : Buffer.t;
  mutable peeked : char option;
  mutable line : int;
  mutable finished : bool;
}

let default_max_record_bytes = 65536

let create ?(max_record_bytes = default_max_record_bytes) ic =
  if max_record_bytes < 1 then invalid_arg "Csv_stream.create: max_record_bytes";
  { ic; max_record_bytes; field = Buffer.create 128; peeked = None; line = 1;
    finished = false }

let current_line t = t.line

exception Fail of error_kind

let error_kind_to_string = function
  | Unterminated_quote -> "end of input inside a quoted field"
  | Malformed_quote why -> why
  | Bare_carriage_return -> "carriage return not followed by line feed"
  | Record_too_long n -> Printf.sprintf "record exceeds %d bytes" n

let partial_of t =
  let s = Buffer.contents t.field in
  if String.length s <= 256 then s else String.sub s 0 256

let next t =
  if t.finished then Ok None
  else begin
    let start_line = t.line in
    let fields = ref [] in
    let consumed = ref 0 in
    Buffer.clear t.field;
    let read () =
      let c =
        match t.peeked with
        | Some c -> t.peeked <- None; Some c
        | None -> ( match input_char t.ic with
            | c -> Some c
            | exception End_of_file -> None)
      in
      (match c with
       | Some _ ->
           incr consumed;
           if !consumed > t.max_record_bytes then
             raise (Fail (Record_too_long t.max_record_bytes))
       | None -> ());
      c
    in
    let peek () =
      match t.peeked with
      | Some c -> Some c
      | None -> (
          match input_char t.ic with
          | c -> t.peeked <- Some c; Some c
          | exception End_of_file -> None)
    in
    let push () =
      fields := Buffer.contents t.field :: !fields;
      Buffer.clear t.field
    in
    let end_line () = push (); t.line <- t.line + 1; `Record in
    let crlf () =
      match read () with
      | Some '\n' -> end_line ()
      | _ -> raise (Fail Bare_carriage_return)
    in
    let rec start_field () =
      match read () with
      | None -> if !fields = [] && !consumed = 0 then `Eof else (push (); `Record)
      | Some '"' -> quoted ()
      | Some c -> unquoted_char c
    and unquoted_char = function
      | ',' -> push (); start_field ()
      | '\n' -> end_line ()
      | '\r' -> crlf ()
      | '"' -> raise (Fail (Malformed_quote "quote character inside an unquoted field"))
      | c -> Buffer.add_char t.field c; unquoted ()
    and unquoted () =
      match read () with
      | None -> push (); `Record
      | Some c -> unquoted_char c
    and quoted () =
      match read () with
      | None -> raise (Fail Unterminated_quote)
      | Some '"' -> (
          match peek () with
          | Some '"' -> ignore (read ()); Buffer.add_char t.field '"'; quoted ()
          | _ -> after_quoted ())
      | Some c ->
          if c = '\n' then t.line <- t.line + 1;
          Buffer.add_char t.field c;
          quoted ()
    and after_quoted () =
      match read () with
      | None -> push (); `Record
      | Some ',' -> push (); start_field ()
      | Some '\n' -> end_line ()
      | Some '\r' -> crlf ()
      | Some _ ->
          raise (Fail (Malformed_quote "unexpected character after closing quote"))
    in
    match start_field () with
    | `Eof -> t.finished <- true; Ok None
    | `Record ->
        Ok (Some { fields = Array.of_list (List.rev !fields); line = start_line })
    | exception Fail kind ->
        t.finished <- true;
        Error { kind; line = start_line; at_line = t.line; partial = partial_of t }
  end

let quote_field s =
  let needs =
    String.exists (function ',' | '"' | '\r' | '\n' -> true | _ -> false) s
  in
  if not needs then s
  else begin
    let b = Buffer.create (String.length s + 8) in
    Buffer.add_char b '"';
    String.iter (fun c -> if c = '"' then Buffer.add_string b "\"\"" else Buffer.add_char b c) s;
    Buffer.add_char b '"';
    Buffer.contents b
  end
