# Portable project definition for the selected serial_lfsr submission.
# Run with Gowin V1.9.11.03 Education: gw_sh submission/gowin/build.tcl
cd [file dirname [file normalize [info script]]]
set inputs [file normalize ../../serial_adder_approach]
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
source [file join $inputs options.tcl]
set_option -top_module gqh_competition_top
set_option -output_base_name gqh_serial
add_file [file join $inputs gqh_serial_top.v]
add_file [file join $inputs 19_tang_nano_20k.cst]
add_file [file join $inputs tang_nano_20k.sdc]
saveto -all_options resolved-settings.tcl
run all
puts "SUBMISSION_BUILD_COMPLETED"
exit
