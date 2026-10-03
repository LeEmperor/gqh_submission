let gettime = Core.Or_error.ok_exn Core_unix.Clock.gettime
let now () = Core.Int63.to_float (gettime Core_unix.Clock.Monotonic) /. 1_000_000_000.
