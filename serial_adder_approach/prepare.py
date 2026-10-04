"""Copy standalone import constraints/settings and stage isolated Gowin builds."""
from pathlib import Path
import shutil

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
for name in ['19_tang_nano_20k.cst', 'tang_nano_20k.sdc']:
    shutil.copy2(ROOT / 'constraints' / name, HERE / name)
shutil.copy2(ROOT / 'gowin/manual_270/options.tcl', HERE / 'options.tcl')
for variant, rtl in [('serial_lfsr', 'gqh_serial_top.v'),
                     ('serial_engine_only', 'gqh_serial_engine_only_top.v')]:
    folder = HERE / 'builds' / variant
    folder.mkdir(parents=True, exist_ok=True)
    (folder / 'build.tcl').write_text('''cd [file dirname [file normalize [info script]]]
set_device -name GW2AR-18C GW2AR-LV18QN88C8/I7
source ../../options.tcl
set_option -top_module gqh_competition_top
set_option -output_base_name gqh_serial
add_file ../../''' + rtl + '''
add_file ../../19_tang_nano_20k.cst
add_file ../../tang_nano_20k.sdc
saveto -all_options resolved-settings.tcl
run all
puts "SERIAL_BUILD_COMPLETED"
exit
''')
print('Prepared constraints, options.tcl and builds/{serial_lfsr,serial_engine_only}/build.tcl')
