(* File creation that never clobbers unless explicitly asked to. *)

exception Output_exists of string

let rec mkdir_p dir =
  if dir <> "" && dir <> "." && dir <> "/" && not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let exists path = Sys.file_exists path

let temp_sibling path tag =
  Printf.sprintf "%s.%s.%d" path tag (Unix.getpid ())

let write_all fd s =
  let b = Bytes.unsafe_of_string s in
  let rec go off =
    if off < Bytes.length b then go (off + Unix.write fd b off (Bytes.length b - off))
  in
  go 0

(* Moves [tmp] to [path]. Without [overwrite] this uses link(2), which fails
   atomically if [path] already exists. *)
let commit ~overwrite tmp path =
  if overwrite then Unix.rename tmp path
  else begin
    (try Unix.link tmp path
     with Unix.Unix_error (Unix.EEXIST, _, _) ->
       (try Unix.unlink tmp with Unix.Unix_error _ -> ());
       raise (Output_exists path));
    Unix.unlink tmp
  end

let write_file ~overwrite path contents =
  mkdir_p (Filename.dirname path);
  if (not overwrite) && exists path then raise (Output_exists path);
  let tmp = temp_sibling path "tmp" in
  let fd = Unix.openfile tmp [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC; Unix.O_CLOEXEC ] 0o644 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () -> write_all fd contents);
  commit ~overwrite tmp path

let same_file a b =
  match (Unix.stat a, Unix.stat b) with
  | sa, sb -> sa.Unix.st_dev = sb.Unix.st_dev && sa.Unix.st_ino = sb.Unix.st_ino
  | exception Unix.Unix_error _ -> false
