open! Core
open Ui_types

let name = function
  | Monitor -> "Monitor" | Decide -> "Decide" | Configure -> "Configure" | Demo -> "Demo"

(* The preset that brings [panel] on screen, for keys that jump to a hidden panel. *)
let showing : Ui_types.panel_id -> preset = function
  | Market | Heatmap | Tape | Metrics | Latency -> Monitor
  | Rules | Decisions | Inspector -> Decide
  | Configuration -> Configure

(* The last preset survives restarts in [$XDG_STATE_HOME/tickweave-tui/last-preset]
   ([~/.local/state] when unset). [TICKWEAVE_STATE_DIR] replaces the whole directory,
   which is how tests avoid the operator's real state. *)
let directory ~getenv =
  let set name = Option.filter (getenv name) ~f:(Fn.non String.is_empty) in
  match set "TICKWEAVE_STATE_DIR" with
  | Some directory -> Some directory
  | None ->
    let state_home = match set "XDG_STATE_HOME" with
      | Some home -> Some home
      | None -> Option.map (set "HOME") ~f:(fun home -> Filename.concat home ".local/state") in
    Option.map state_home ~f:(fun home -> Filename.concat home "tickweave-tui")

let file ~getenv =
  Or_error.of_option (directory ~getenv)
    ~error:(Error.of_string "no TICKWEAVE_STATE_DIR, XDG_STATE_HOME or HOME")
  |> Or_error.map ~f:(fun directory -> Filename.concat directory "last-preset")

(* [Sys_error] already carries a readable "path: reason"; keep it free of sexp quoting. *)
let attempt f =
  try Ok (f ()) with
  | Sys_error message -> Or_error.error_string message
  | exn -> Or_error.of_exn exn

let rec make_directory directory =
  if not (Stdlib.Sys.file_exists directory) then (
    make_directory (Filename.dirname directory);
    Stdlib.Sys.mkdir directory 0o755)

let read ~getenv =
  let%bind.Or_error file = file ~getenv in
  let%bind.Or_error text = attempt (fun () -> In_channel.read_all file) in
  let text = String.strip text in
  Or_error.of_option (List.find all_of_preset ~f:(fun preset -> String.equal (name preset) text))
    ~error:(Error.create_s [%message "unknown preset" (text : string)])

(* Anything unreadable is the first-run answer: Monitor. A preference must never stop the
   console from starting. *)
let load ?(getenv = Sys.getenv) () = Or_error.ok (read ~getenv) |> Option.value ~default:Monitor

(* The error is for tests and callers that care; the console ignores it, because losing
   a remembered layout must not interrupt an operator. *)
let save ?(getenv = Sys.getenv) preset =
  let%bind.Or_error file = file ~getenv in
  attempt (fun () ->
    make_directory (Filename.dirname file);
    Out_channel.write_all file ~data:(name preset ^ "\n"))
