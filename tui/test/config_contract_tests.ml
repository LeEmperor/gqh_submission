open! Core
open Tickweave_tui
open Model_adapter
let state () = Mock_backend.create ~scenario:Enabled ~seed:42 ~rate_hz:4. |> Or_error.ok_exn |> Mock_backend.state
let%expect_test "proposal checks are declared logical fields and ACK based" =
  let s = state () in
  let check ?(connected_build = "m01") ?(active_version = Some 12) ?(reachable = true) proposal =
    let result = validate_proposal ~manifest:s.manifest ~connected_build ~active_version
        ~engine_reachable:reachable proposal in
    printf "can apply %b; errors %s\n" result.can_apply (String.concat ~sep:", " result.errors) in
  check s.proposal;
  check { s.proposal with base_version = 11 };
  check ~connected_build:"other" s.proposal;
  check { s.proposal with changes = [ "quantity", 6 ] };
  check { s.proposal with changes = [ "undeclared", 1 ] };
  check ~reachable:false s.proposal;
  check { s.proposal with deployment_class = Rebuild_required };
  [%expect {|
    can apply true; errors
    can apply false; errors base version match
    can apply false; errors build match
    can apply false; errors every field in range
    can apply false; errors every field in range
    can apply false; errors engine reachable
    can apply false; errors REBUILD_REQUIRED
  |}]
