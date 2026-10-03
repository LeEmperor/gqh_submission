open! Core
open Model_adapter

(* Producers stamp newly committed inputs with the last observed ACK. Historical
   decisions retain their own snapshot and are never stamped again by the UI. *)
let stamp_snapshot ~(configuration : configuration) (snapshot : snapshot) =
  { snapshot with
    identity =
      { snapshot.identity with
        config_version = configuration.last_acknowledged_version } }
