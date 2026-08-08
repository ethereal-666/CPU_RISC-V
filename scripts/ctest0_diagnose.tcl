set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]

open_project [file join $project_dir miniLA.xpr]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
launch_simulation -mode behavioral
source [file join $script_dir inspect_stall.tcl]

