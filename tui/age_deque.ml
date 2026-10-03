open! Core

(* A history that grows at its newest end and is trimmed at its oldest, as the market's
   samples are: every append and every trim costs O(1) amortised, and a walk from the newest
   stops where it is told to and allocates nothing.

   [Core.Fdeque] has the same shape and is no use here: its folds, [fold_until] included, copy
   the whole deque into a list first and always visit all of it, so a frame that wants the
   last minute would pay for every sample kept.

   [newer] holds the newest elements, newest first. [older] holds the rest, oldest first, in
   an array that is never written to once it is made; [first] is where the live part begins,
   so dropping the oldest is a move of an index. A walk from the newest goes down [newer] and
   then back down [older] from its end, and a walk that stops stops there: it reads only what
   it visits, with no recursion. When [older] runs out, the older half of [newer] becomes the
   next array, which is paid for by the drops it then serves. Every value is immutable, so a
   deque that has been pushed to or trimmed is still good. *)
type 'a t = { newer : 'a list; older : 'a array; first : int; length : int }

let empty = { newer = []; older = [||]; first = 0; length = 0 }
let length t = t.length
let push t x = { t with newer = x :: t.newer; length = t.length + 1 }

(* [of_list] takes the newest first. *)
let of_list newer = { empty with newer; length = List.length newer }

let newest t =
  match t.newer with
  | x :: _ -> Some x
  | [] -> if t.first < Array.length t.older then Some t.older.(Array.length t.older - 1) else None

(* Moves the older half of [newer] to [older], so that the oldest element is first. *)
let rebalance t =
  let #(newer, oldest_first) = List.split_n t.newer (t.length / 2) in
  { t with newer; older = Array.of_list_rev oldest_first; first = 0 }

(* Drops elements from the oldest while [keep] says they go: [keep] is given the oldest and the
   length. *)
let rec trim t ~keep =
  if t.length = 0 then t
  else if t.first >= Array.length t.older then trim (rebalance t) ~keep
  else if keep ~length:t.length t.older.(t.first) then t
  else trim { t with first = t.first + 1; length = t.length - 1 } ~keep

(* Calls [f] on the elements from the newest, for as long as it returns [true]. *)
let iter_while t ~f =
  if List.for_all t.newer ~f then (
    let i = ref (Array.length t.older - 1) in
    while !i >= t.first && f t.older.(!i) do decr i done)
