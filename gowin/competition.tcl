# Generated build.tcl sets stage and provides input/options Tcl lists.
# Syntax and all-options export verified with V1.9.11.03 Education.
cd $stage
set_device -name $device $part
foreach {key value} $options { set_option $key $value }
set_option -top_module $top
set_option -output_base_name competition
foreach path $inputs { add_file $path }
saveto -all_options resolved-settings.tcl
puts "GQH_INPUTS_CONFIGURED"
run all
puts "GQH_BUILD_COMPLETED"
exit
