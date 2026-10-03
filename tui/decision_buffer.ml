open! Core
open Model_adapter

let capacity = 10_000
let empty = { records = Int.Map.empty; first_sequence = 0; next_sequence = 0 }
let append log decision =
  let records = Map.set log.records ~key:log.next_sequence ~data:decision in
  let first_sequence, records =
    if Map.length records > capacity
    then log.first_sequence + 1, Map.remove records log.first_sequence
    else log.first_sequence, records in
  { records; first_sequence; next_sequence = log.next_sequence + 1 }
let to_list log = Map.data log.records
