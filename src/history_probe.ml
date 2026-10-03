open! Hardcaml

module I = struct
  type 'a t =
    { clock : 'a
    ; write_enable : 'a
    ; write_address : 'a [@bits 5]
    ; write_data : 'a [@bits 16]
    ; read_address : 'a [@bits 5]
    } [@@deriving hardcaml]
end
module O = struct
  type 'a t = { read_data : 'a [@bits 16] } [@@deriving hardcaml]
end

(* One rising-edge read latency; same-edge collision returns the OLD word.
   No RAM initialization/reset: unwritten addresses are unspecified. *)
let create _scope (i : _ I.t) =
  let q = Ram.create ~name:"history" ~size:32
    ~collision_mode:Ram.Collision_mode.Read_before_write
    ~write_ports:[| { Write_port.write_clock = i.clock
      ; write_enable = i.write_enable; write_address = i.write_address
      ; write_data = i.write_data } |]
    ~read_ports:[| { Read_port.read_clock = i.clock
      ; read_enable = Signal.vdd; read_address = i.read_address } |] () in
  { O.read_data = q.(0) }

let hierarchical ?instance scope i =
  let module H = Hierarchy.In_scope (I) (O) in
  H.hierarchical ?instance ~scope ~name:"history_probe" create i
