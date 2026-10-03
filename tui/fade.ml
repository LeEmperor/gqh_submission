open! Core

(* Every fade in the console steps, it does not slide. The terminal is sent every line that
   changes, across the panels side by side, so a colour that moves a little every 50 ms
   rewrites most of the screen twenty times a second. A fade here has [steps] levels and
   the animation clock ticks once per level, so a fading cell changes colour [steps] times a
   second, every fade changes on the same tick, and between ticks nothing is recomputed or
   sent. Eleven levels are still a smooth fade to the eye, with the colour itself still
   interpolated in RGB. *)
let steps = 11
let step = Time_ns.Span.of_sec (1. /. Float.of_int steps)

(* The level of an intensity in [0, 1], rounded up so that a fade that has not finished is
   never drawn as finished. *)
let level intensity =
  if Float.(intensity <= 0.) then 0.
  else Float.min 1. (Float.round_up (intensity *. Float.of_int steps) /. Float.of_int steps)
