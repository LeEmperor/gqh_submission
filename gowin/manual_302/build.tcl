# Optional command-line reproduction: gw_sh build.tcl
cd [file dirname [file normalize [info script]]]
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
source options.tcl
set_option -top_module gqh_competition_top
set_option -output_base_name gqh_competition
add_file gqh_competition_bsram_top.v
add_file 19_tang_nano_20k.cst
add_file tang_nano_20k.sdc
saveto -all_options resolved-settings.tcl
run all
puts "REVIEW_BUILD_COMPLETED"
exit
