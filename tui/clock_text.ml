open! Core

(* The UTC time of day as text, "13:37:00.123" and "13:37:00", straight from the nanoseconds.
   The same strings as [Time_ns.Ofday.to_millisecond_string] and [to_sec_string] of
   [Time_ns.to_ofday ~zone:Timezone.utc], which look the zone up and format through
   [Int63]; a table of rows asks for one per row on every frame. Fractions are cut, not
   rounded, as there. *)

let nanoseconds_per_day = 86_400_000_000_000

let digits bytes ~pos value =
  Stdlib.Bytes.unsafe_set bytes pos (Char.unsafe_of_int (Char.to_int '0' + (value / 10)));
  Stdlib.Bytes.unsafe_set bytes (pos + 1) (Char.unsafe_of_int (Char.to_int '0' + (value % 10)))

let utc time ~fraction =
  let milliseconds = Time_ns.to_int_ns_since_epoch time % nanoseconds_per_day / 1_000_000 in
  let bytes = Stdlib.Bytes.create (if fraction then 12 else 8) in
  digits bytes ~pos:0 (milliseconds / 3_600_000);
  Stdlib.Bytes.unsafe_set bytes 2 ':';
  digits bytes ~pos:3 (milliseconds / 60_000 % 60);
  Stdlib.Bytes.unsafe_set bytes 5 ':';
  digits bytes ~pos:6 (milliseconds / 1000 % 60);
  if fraction then (
    Stdlib.Bytes.unsafe_set bytes 8 '.';
    let millis = milliseconds % 1000 in
    digits bytes ~pos:9 (millis / 10);
    Stdlib.Bytes.unsafe_set bytes 11 (Char.unsafe_of_int (Char.to_int '0' + (millis % 10))));
  Stdlib.Bytes.unsafe_to_string bytes

let utc_millis time = utc time ~fraction:true
let utc_seconds time = utc time ~fraction:false
