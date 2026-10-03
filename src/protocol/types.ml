module Request = struct
  type 'a t =
    { index : 'a [@bits 16]
    ; slot1_id : 'a [@bits 8]
    ; slot1_price : 'a [@bits 16]
    ; slot2_id : 'a [@bits 8]
    ; slot2_price : 'a [@bits 16]
    }
  [@@deriving hardcaml]
end

module Response = struct
  type 'a t =
    { index : 'a [@bits 16]
    ; slot1_id : 'a [@bits 8]
    ; slot2_id : 'a [@bits 8]
    ; slot1_action : 'a [@bits 2]
    ; slot2_action : 'a [@bits 2]
    }
  [@@deriving hardcaml]
end

module Update = struct
  type 'a t =
    { item_select : 'a
    ; price : 'a [@bits 16]
    ; window_position : 'a [@bits 4]
    ; warmup : 'a
    }
  [@@deriving hardcaml]
end

let item_a = 0x11
let item_b = 0x22
let action_none = 0
let action_sell = 1
let action_buy = 2
let packet_bytes = 8
