set script_dir [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]

open_project [file join $project_dir miniLA.xpr]
reset_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

set run_status [get_property STATUS [get_runs impl_1]]
puts "FIXED_IMPL_STATUS=$run_status"
if {![string match "*write_bitstream Complete*" $run_status]} {
    error "Fixed bitstream generation did not complete: $run_status"
}

set bit_file [file join $project_dir miniLA.runs impl_1 miniLA_SoC.bit]
if {![file exists $bit_file]} {
    error "Expected bitstream was not generated: $bit_file"
}
puts "FIXED_BITSTREAM=$bit_file"
close_project
