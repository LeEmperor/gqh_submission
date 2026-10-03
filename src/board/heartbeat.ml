open! Core
open! Hardcaml
open! Signal

module I = struct
  type 'a t = { clock : 'a; reset : 'a } [@@deriving hardcaml]
end
module O = struct
  type 'a t = { led_n : 'a } [@@deriving hardcaml]
end

let create ?(half_period_cycles = Config.heartbeat_half_period_cycles) _scope
  (i : _ I.t) =
  if half_period_cycles < 1 then invalid_arg "heartbeat half period must be positive";
  let width = Int.max 1 (Int.ceil_log2 half_period_cycles) in
  let spec = Reg_spec.create ~clock:i.clock ~clear:i.reset () in
  let count = reg_fb spec ~initialize_to:(Bits.zero width) ~width
    ~f:(fun count -> mux2 (count ==:. (half_period_cycles - 1))
      (zero width) (count +:. 1)) in
  let tick = count ==:. (half_period_cycles - 1) in
  let lit = reg_fb spec ~initialize_to:Bits.gnd ~width:1
    ~f:(fun lit -> mux2 tick (~:lit) lit) in
  { O.led_n = ~:lit }

let hierarchical ?instance ?half_period_cycles scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_heartbeat"
    (create ?half_period_cycles) i
