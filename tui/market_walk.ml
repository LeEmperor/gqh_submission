open! Core
open Model_adapter

(* MOCK resting size, not a market model. Every price carries a size that reverts toward a
   depth profile (thin at the touch, thicker outward) with seeded noise, so a level keeps
   its identity from one snapshot to the next. A few "walls" of extra size build up, hold
   and decay at a price, and are pulled when the touch reaches them. The heatmap's bands
   come from this persistence: nothing here is hardware evidence. *)

let depth = 10
let touch_size = 30.
let size_per_level = 3.
let reversion_seconds = 2.5
let noise_share = 0.12           (* of a level's mean size, per root second *)
let wall_rate_hz = 0.12
let max_walls = 3
let update_hz = 1.5              (* size updates a second at each level, on average *)

type wall =
  { price : int; ask_side : bool; peak : float
  ; age : float; build : float; hold : float; fade : float }

type t =
  { sizes : float Int.Map.t  (* the walk's state at each price in the last book *)
  ; walls : wall list
  ; random : Stdlib.Random.State.t
  ; seed : int
  ; step : int }  (* snapshots so far *)

let mean level = touch_size +. (size_per_level *. Float.of_int level)

(* Rises smoothly over [build], holds for [hold], then falls linearly over [fade]. *)
let envelope wall =
  let smooth share = share *. share *. (3. -. (2. *. share)) in
  if Float.(wall.age < wall.build) then smooth (wall.age /. wall.build)
  else if Float.(wall.age < wall.build +. wall.hold) then 1.
  else Float.max 0. (1. -. ((wall.age -. wall.build -. wall.hold) /. wall.fade))
let alive wall = Float.(wall.age < wall.build +. wall.hold +. wall.fade)
let extra_at walls ~price ~ask_side =
  List.sum (module Float) walls ~f:(fun wall ->
    if wall.price = price && Bool.equal wall.ask_side ask_side then wall.peak *. envelope wall
    else 0.)

(* Irwin-Hall: four uniforms sum to a bell with variance 1/3; scaled to unit variance. *)
let gaussian random =
  let uniform () = Stdlib.Random.State.float random 1. in
  (uniform () +. uniform () +. uniform () +. uniform () -. 2.) *. Float.sqrt 3.

(* [uniform low width] is a draw in [low, low + width). Draws are named in order, so the stream
   does not depend on evaluation order. *)
let new_wall random ~bid ~ask ~age =
  let uniform low width = low +. Stdlib.Random.State.float random width in
  let ask_side = Stdlib.Random.State.bool random in
  let distance = 1 + Stdlib.Random.State.int random (depth - 1) in
  let peak = uniform 70. 60. in   (* 70 to 130 units above the level's ordinary size *)
  let build = uniform 2.5 2. in   (* seconds: 2.5 to 4.5 *)
  let hold = uniform 1. 2. in     (* 1 to 3 *)
  let fade = uniform 4. 3. in     (* 4 to 7: a wall lives at most 14.5 s of MOCK time *)
  { price = (if ask_side then ask + distance else bid - distance); ask_side; peak
  ; age; build; hold; fade }

let create ~seed ~bid ~spread =
  let random = Stdlib.Random.State.make [| seed; 0x77616c6c |] in
  (* Start mid-story: one wall already built and one still building. *)
  let ask = bid + spread in
  let walls = List.init 2 ~f:(fun index ->
      let wall = new_wall random ~bid ~ask ~age:0. in
      { wall with age = if index = 0 then wall.build +. 2. else wall.build *. 0.5 }) in
  { sizes = Int.Map.empty; walls; random; seed; step = 0 }

(* A wall is pulled once the touch has moved onto or past its price. *)
let still_resting ~bid ~ask wall =
  if wall.ask_side then wall.price > ask - 1 else wall.price < bid + 1

(* A level shows the size it last showed until an update reaches it, then the walk's current
   size. Updates arrive at each level at random, [update_hz] a second on average, so most levels
   are unchanged from one snapshot to the next and the ones that change are the walk's own
   moves. A frozen walk shows a frozen book. A level new to the book has no earlier size. *)
let displayed ~previous ~updated size =
  match previous with
  | Some (before : level) when not updated -> before.quantity_units
  | Some _ | None -> Int.max 1 (Float.iround_nearest_exn size)

(* Whether an update reaches the level at [price] in snapshot [step]. The draw is a function of
   its arguments alone, not of the walk's random stream, so it is deterministic by seed and
   adds nothing to the stream that the seeded size sequences came from. *)
let updated ~seed ~step ~price ~ask_side ~dt =
  let draw = Float.of_int (Stdlib.Hashtbl.hash (seed, step, price, ask_side) mod 1_000_000) /. 1e6 in
  Float.(draw < 1. -. Float.exp (-. update_hz *. dt))

(* [advance] moves the walk by [dt] seconds of MOCK time to the book at [bid] and [spread],
   and returns its ten levels a side. [previous] is the last book, which levels not updated keep. *)
let advance t ~dt ~bid ~spread ~previous:(old_bids, old_asks) =
  let random = Stdlib.Random.State.copy t.random in
  let ask = bid + spread in
  let walls = List.filter_map t.walls ~f:(fun wall ->
      let wall = { wall with age = wall.age +. dt } in
      Option.some_if (alive wall && still_resting ~bid ~ask wall) wall) in
  let spawn = Float.(Stdlib.Random.State.float random 1. < 1. -. Float.exp (-. wall_rate_hz *. dt)) in
  let walls =
    if not spawn || List.length walls >= max_walls then walls
    else (
      let wall = new_wall random ~bid ~ask ~age:0. in
      if List.exists walls ~f:(fun other -> other.price = wall.price) then walls else wall :: walls) in
  let pull = 1. -. Float.exp (-. dt /. reversion_seconds) in
  let step ~ask_side ~price level =
    let target = mean level +. extra_at walls ~price ~ask_side in
    let sigma = noise_share *. mean level in
    let before = match Map.find t.sizes price with
      | Some size -> size
      | None -> target +. (sigma *. Float.sqrt (reversion_seconds /. 2.) *. gaussian random) in
    Float.max 1. (before +. (pull *. (target -. before)) +. (sigma *. Float.sqrt dt *. gaussian random)) in
  let side ~ask_side old =
    let walk = List.init depth ~f:(fun level ->
        let price = if ask_side then ask + level else bid - level in
        price, step ~ask_side ~price level) in
    walk, List.map walk ~f:(fun (price_ticks, size) : level ->
      let previous = List.find old ~f:(fun (level : level) -> level.price_ticks = price_ticks) in
      let updated = updated ~seed:t.seed ~step:t.step ~price:price_ticks ~ask_side ~dt in
      { price_ticks; quantity_units = displayed ~previous ~updated size }) in
  let bid_walk, bids = side ~ask_side:false old_bids in
  let ask_walk, asks = side ~ask_side:true old_asks in
  { t with sizes = Int.Map.of_alist_reduce (bid_walk @ ask_walk) ~f:Float.max; walls; random
         ; step = t.step + 1 }, (bids, asks)
