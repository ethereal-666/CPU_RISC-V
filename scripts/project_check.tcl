set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]

open_project [file join $project_dir miniLA.xpr]
update_compile_order -fileset sources_1
report_ip_status
close_project
