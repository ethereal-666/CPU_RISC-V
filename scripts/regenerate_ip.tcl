set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]

open_project [file join $project_dir miniLA.xpr]

set requested $argv
if {[llength $requested] == 0} {
    set ips [get_ips -quiet]
} else {
    set ips {}
    foreach name $requested {
        set ip [get_ips -quiet $name]
        if {[llength $ip] != 1} {
            error "Expected exactly one IP named '$name', found [llength $ip]"
        }
        lappend ips $ip
    }
}

foreach ip $ips {
    set ip_name [get_property NAME $ip]
    if {[get_property IS_LOCKED $ip]} {
        puts "UPGRADING_LOCKED_IP=$ip_name"
        upgrade_ip $ip
    }
    reset_target all $ip
    generate_target all $ip
    export_ip_user_files -of_objects $ip -no_script -sync -force -quiet
    puts "REGENERATED_IP=$ip_name"
}

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
close_project
