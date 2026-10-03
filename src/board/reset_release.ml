open! Hardcaml
open! Signal

module I = struct
  type 'a t = { clock : 'a; reset_btn : 'a } [@@deriving hardcaml]
end
module O = struct
  type 'a t = { reset : 'a } [@@deriving hardcaml]
end

(* Assumes button pressed = high (official CST pulls down).
   Initialization is intentional RTL, but Gowin power-up support must be checked.
   Both stages assert asynchronously and release only through clocked stages. *)
let create _scope (i : _ I.t) =
  let spec = Reg_spec.create ~clock:i.clock ~reset:i.reset_btn () in
  let stage1 = reg spec ~initialize_to:Bits.vdd ~reset_to:Bits.vdd gnd in
  let stage2 = reg spec ~initialize_to:Bits.vdd ~reset_to:Bits.vdd stage1 in
  { O.reset = stage2 }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"gqh_reset_release" create i
