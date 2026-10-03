let max_packets = 65_536
let synthetic ~seed ~count =
  if count < 0 || count > max_packets then invalid_arg "packet count must be between 0 and 65536";
  let rng = Random.State.make [|seed|] in
  List.init count (fun index ->
    let a = Random.State.int rng 65536 and b = Random.State.int rng 65536 in
    if index mod 2 = 0 then ({index;item1=17;price1=a;item2=34;price2=b}:Protocol.request)
    else {index;item1=34;price1=b;item2=17;price2=a})
let fail line message = invalid_arg (Printf.sprintf "request CSV line %d: %s" line message)
let strip_cr s = let n = String.length s in if n > 0 && s.[n-1] = '\r' then String.sub s 0 (n-1) else s
let decimal ~line ~column text =
  if text = "" then fail line (column ^ " is empty");
  String.iter (fun c -> if c < '0' || c > '9' then fail line (column ^ " must contain decimal digits only")) text;
  let value = try int_of_string text with Failure _ -> fail line (column ^ " exceeds the integer range") in
  if value > 65535 then fail line (column ^ " must be between 0 and 65535"); value
let replay path =
  let ch = open_in path in
  Fun.protect ~finally:(fun () -> close_in_noerr ch) (fun () ->
    let header = try strip_cr (input_line ch) with End_of_file -> fail 1 "missing header" in
    if header <> "index,item1,price1,item2,price2" then fail 1 "expected header index,item1,price1,item2,price2";
    let rec read index acc = match input_line ch with
      | exception End_of_file -> List.rev acc
      | raw ->
        let line = index + 2 in
        if index >= max_packets then fail line "session exceeds 65536 packets";
        let r = match String.split_on_char ',' (strip_cr raw) with
          | [i;a;pa;b;pb] ->
            let actual = decimal ~line ~column:"index" i in
            let item1 = decimal ~line ~column:"item1" a and price1 = decimal ~line ~column:"price1" pa in
            let item2 = decimal ~line ~column:"item2" b and price2 = decimal ~line ~column:"price2" pb in
            if actual <> index then fail line (Printf.sprintf "expected sequential index %d" index);
            if not ((item1 = 17 && item2 = 34) || (item1 = 34 && item2 = 17)) then fail line "items must be distinct IDs 17 and 34";
            ({index;item1;price1;item2;price2}:Protocol.request)
          | _ -> fail line "expected exactly five columns" in
        read (index + 1) (r :: acc)
    in read 0 [])
