open! Core
open Model_adapter

(* Fixed MOCK policy, explicitly declared. Displayed liquidity is not a bound. *)
let mock_bounds = { min_qty = 1; max_qty = 5; min_price_ticks = 1001; max_price_ticks = 1005 }
let check ~engine ~book_valid ~bounds (candidate : candidate) =
  if not (equal_engine engine Armed) then Blocked_result "engine disarmed / unavailable"
  else if not book_valid then Blocked_result "book invalid"
  else if candidate.quantity_units < bounds.min_qty || candidate.quantity_units > bounds.max_qty
  then Blocked_result (sprintf "order qty %d u outside [%d, %d] u"
    candidate.quantity_units bounds.min_qty bounds.max_qty)
  else if candidate.price_ticks < bounds.min_price_ticks || candidate.price_ticks > bounds.max_price_ticks
  then Blocked_result (sprintf "price %d t outside [%d, %d] t"
    candidate.price_ticks bounds.min_price_ticks bounds.max_price_ticks)
  else Admitted_result
