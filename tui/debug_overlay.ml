open! Core
open Bonsai_term

(* How much of the frame budget the p99 uses, as ten cells. The fill runs from the Bid
   colour to Alarm as p99 approaches the budget, an RGB blend on colour terminals; on
   16 colours and none the words and the glyphs carry it. *)
let budget_bar ~theme ~p99_ms =
  let fraction = if Float.is_finite p99_ms then Float.clamp_exn (p99_ms /. Frame_meter.budget_ms) ~min:0. ~max:1. else 1. in
  let { Sparkline.full; partial; empty } = Sparkline.bar ~width:10 ~fraction in
  let fill_attrs = match theme.Theme.capability with
    | Truecolor | Ansi256 ->
      Option.value_map ~default:[] ~f:(fun color -> [ Attr.fg color ])
        (Theme.rgb_color theme (Theme.blend (Theme.role_rgb theme Bid) (Theme.role_rgb theme Alarm) fraction))
    | Ansi16 | No_color -> Theme.attrs theme (if Float.(fraction >= 1.) then Warn else Bid) in
  View.hcat [ View.text ~attrs:fill_attrs (String.concat (List.init full ~f:(fun _ -> "█")) ^ partial)
            ; View.text ~attrs:(Theme.attrs theme Muted) (String.concat (List.init empty ~f:(fun _ -> "░")) ^ " ") ]

(* A compact box for the F12 overlay. Each line says what it measures; see Frame_meter. *)
let view ~theme ~(stats : Ui_types.frame_stats) =
  let attrs role = Theme.attrs theme role in
  let line ?(role = Theme.Text) text = View.text ~attrs:(attrs role) text in
  let over = Float.(stats.p99_ms > Frame_meter.budget_ms) in
  let buffers = List.map stats.buffer_sizes ~f:(fun (name, size) -> sprintf "%s %d" name size) in
  let body =
    View.vcat
      ([ line ~role:Muted "frame work: flush+compute+paint"
       ; line (sprintf "last %.1f · avg %.1f ms" stats.last_ms stats.avg_ms)
       ; line (sprintf "p50 %.1f · p99 %.1f · max %.1f ms" stats.p50_ms stats.p99_ms stats.max_ms)
       ; View.hcat
           [ budget_bar ~theme ~p99_ms:stats.p99_ms
           ; (if over then line ~role:Warn (sprintf "p99 over budget (%.0f ms)" Frame_meter.budget_ms)
              else line ~role:Bid (sprintf "p99 within %.0f ms budget" Frame_meter.budget_ms)) ]
       ; line (sprintf "stream events %.0f/s" stats.events_per_second)
       ; line (sprintf "paints %d · coalesced events %d" stats.render_count stats.coalesced_frames) ]
       @ if List.is_empty buffers then [] else [ line ~role:Muted (String.concat ~sep:" · " buffers) ]) in
  Bonsai_term_border_box.view ~line_type:Round_corners ~attrs:(attrs Border)
    ~title_attrs:(attrs Focus) ~title:"Frame meter" ~left_padding:1 ~right_padding:1 body
