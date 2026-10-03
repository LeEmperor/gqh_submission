open! Core
open Bonsai_term

(* Paints are rationed to [frames_per_second], on the leading edge: a view that arrives when
   at least one interval has gone by since the last paint is painted at once, and one that
   arrives sooner waits for the end of the interval, and is then painted at its newest. So
   an idle application answers a key or a stream tick in the time it takes to compute the
   frame, a burst is painted once per interval, and nothing is ever painted twice inside
   one.

   It sits between the application and the driver, in [get_view_and_handler], and not in the
   Bonsai graph: there it is called once the frame's graph has settled, so it sees the final
   view. Inside the graph a release would have to be an action, and it could be applied
   between two of the frame's own waves of effects and paint a view that is half updated.

   A held view needs a frame at the end of its interval, and the driver would not run one
   before its own timer, so the throttle asks [Wake] for it. Nothing is asked for while
   there is nothing to hold, so an idle application runs no timer here. *)

let frames_per_second = 60.
let interval_of ~frames_per_second = Time_ns.Span.of_sec (1. /. frames_per_second)
let default_interval = interval_of ~frames_per_second

type t =
  { waker : Wake.t
  ; interval : Time_ns.Span.t
  ; now : unit -> Time_ns.t
  ; mutable shown : View.t          (* what the driver last painted, or View.none *)
  ; mutable released_at : Time_ns.t
  ; mutable wake : Time_ns.t option  (* the instant of the wake in flight for a held view *)
  ; mutable paints : int }

(* [now] is the clock; a test hands it a clock of its own. *)
let create ?(wake = Wake.off) ?(frames_per_second = frames_per_second) ?(now = Time_ns.now) () =
  { waker = wake; interval = interval_of ~frames_per_second; now; shown = View.none
  ; released_at = Time_ns.epoch; wake = None; paints = 0 }

(* How many views have been released: each is a paint. Observers compare it with the value
   they saw at their previous frame, so several of them can watch one throttle. *)
let paints t = t.paints

let hold t ~due ~current =
  (match t.wake with
   | Some at when Time_ns.(at >= due) && Time_ns.(at > current) -> ()
   | Some _ | None -> t.wake <- Some due; Wake.at t.waker due);
  t.shown

(* The view to hand the driver for the frame being computed: [view] if it is time to paint
   it, otherwise the view already on the screen, which the driver sees is unchanged and does
   not repaint. *)
let release t view =
  if phys_equal view t.shown then view
  else (
    let current = t.now () in
    let due = Time_ns.add t.released_at t.interval in
    (* A resize shows at once: a held view of the old size would leave the terminal
       showing a frame of the wrong shape for up to an interval. *)
    let resized = not (Dimensions.equal (View.dimensions view) (View.dimensions t.shown)) in
    if Time_ns.(current < due) && not resized then hold t ~due ~current
    else (
      t.shown <- view;
      t.released_at <- current;
      t.wake <- None;
      t.paints <- t.paints + 1;
      view))
