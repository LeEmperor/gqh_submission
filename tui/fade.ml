open! Core

(* Nothing in the console fades: a highlight is on at full strength for its time and then it
   is off. The terminal is sent every line that changes, across the panels side by side, so a
   colour that moves a little on each tick rewrites most of the screen on each tick. A binary
   highlight costs two paints, the one that shows it and the one that clears it, and nothing
   is computed or sent in between: the animation clock ticks once, at the expiry. *)

(* The level of an intensity in [0, 1]: all of it while any is left, none once the time is up.
   Callers still ask in terms of "1 at the start, falling to 0 at the end", so a fade that has
   not finished is never drawn as finished. *)
let level intensity = if Float.(intensity <= 0.) then 0. else 1.
