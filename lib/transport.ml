exception Timeout of bytes
exception Error of string * bytes
type t = { fd:Unix.file_descr; close_fd:bool; saved_termios:Unix.terminal_io option;
           mutable closed:bool; mutable busy:bool; mutable poisoned:bool }
let of_fd ?(close_fd=true) fd =
  Unix.set_nonblock fd; Unix.set_close_on_exec fd;
  {fd;close_fd;saved_termios=None;closed=false;busy=false;poisoned=false}
let serial path =
  let fd = Unix.openfile path [Unix.O_RDWR;Unix.O_NOCTTY;Unix.O_NONBLOCK;Unix.O_CLOEXEC] 0 in
  let saved = ref None in
  try
    let previous = Unix.tcgetattr fd in saved := Some previous;
    let configured = { previous with
      c_ignbrk=false;c_brkint=false;c_ignpar=false;c_parmrk=false;c_inpck=false;c_istrip=false;
      c_inlcr=false;c_igncr=false;c_icrnl=false;c_ixon=false;c_ixoff=false;c_opost=false;
      c_ibaud=115200;c_obaud=115200;c_csize=8;c_cstopb=1;c_cread=true;c_parenb=false;
      c_parodd=false;c_clocal=true;c_isig=false;c_icanon=false;c_echo=false;c_echoe=false;
      c_echok=false;c_echonl=false;c_vmin=1;c_vtime=0 } in
    Unix.tcsetattr fd Unix.TCSANOW configured;
    {fd;close_fd=true;saved_termios=Some previous;closed=false;busy=false;poisoned=false}
  with exn ->
    Option.iter (fun previous -> try Unix.tcsetattr fd Unix.TCSANOW previous with _ -> ()) !saved;
    (try Unix.close fd with _ -> ()); raise exn
let close t =
  if not t.closed then (
    t.closed <- true;
    let first_error = ref None in
    let attempt f = try f () with exn -> if !first_error = None then first_error := Some exn in
    Option.iter (fun previous -> attempt (fun () -> Unix.tcsetattr t.fd Unix.TCSANOW previous)) t.saved_termios;
    if t.close_fd then attempt (fun () -> Unix.close t.fd);
    Option.iter raise !first_error)
let exchange t ~timeout request =
  if Bytes.length request <> 8 then invalid_arg "request must contain exactly eight bytes";
  if timeout <= 0. || not (Float.is_finite timeout) then invalid_arg "timeout must be finite and positive";
  if t.closed then raise (Error ("transport is closed",Bytes.empty));
  if t.poisoned then raise (Error ("transport requires reconnect after an earlier failure",Bytes.empty));
  if t.busy then raise (Error ("an exchange is already in progress",Bytes.empty));
  t.busy <- true;
  let response = Bytes.create 8 and received = ref 0 in
  let partial () = Bytes.sub response 0 !received in
  let deadline = Clock.now () +. timeout in
  let remaining () = let s = deadline -. Clock.now () in if s <= 0. then raise (Timeout (partial ())); s in
  let rec wait ~reading =
    let seconds = remaining () in
    try
      let readers,writers,_ = Unix.select (if reading then [t.fd] else []) (if reading then [] else [t.fd]) [] seconds in
      if readers = [] && writers = [] then raise (Timeout (partial ()))
    with Unix.Unix_error (Unix.EINTR,_,_) -> wait ~reading in
  let rec write offset =
    if offset < 8 then (
      wait ~reading:false;
      let count = try ignore (remaining ()); Unix.write t.fd request offset (8-offset)
        with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK|Unix.EINTR),_,_) -> -1 in
      if count = 0 then raise (Error ("connection closed while writing",partial ()));
      write (if count < 0 then offset else offset + count)) in
  let rec read () =
    if !received < 8 then (
      wait ~reading:true;
      let count = try ignore (remaining ()); Unix.read t.fd response !received (8 - !received)
        with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK|Unix.EINTR),_,_) -> -1 in
      if count = 0 then raise (Error ("connection closed while reading",partial ()));
      if count > 0 then received := !received + count;
      read ()) in
  let rec check_surplus () =
    try
      let ready,_,_ = Unix.select [t.fd] [] [] 0. in
      if ready <> [] then (
        let extra = Bytes.create 4096 in
        let count = try Unix.read t.fd extra 0 (Bytes.length extra)
          with Unix.Unix_error ((Unix.EAGAIN|Unix.EWOULDBLOCK),_,_) -> -1 in
        if count > 0 then raise (Error ("received surplus response bytes",Bytes.cat (partial ()) (Bytes.sub extra 0 count)));
        if count = 0 then raise (Error ("connection closed after response",partial ())))
    with Unix.Unix_error (Unix.EINTR,_,_) -> check_surplus () in
  try
    check_surplus (); write 0; read (); ignore (remaining ()); check_surplus ();
    t.busy <- false; response
  with exn ->
    t.busy <- false; t.poisoned <- true;
    match exn with
    | Timeout _ | Error _ -> raise exn
    | Unix.Unix_error (code,operation,_) -> raise (Error (operation ^ ": " ^ Unix.error_message code,partial ()))
    | _ -> raise exn
