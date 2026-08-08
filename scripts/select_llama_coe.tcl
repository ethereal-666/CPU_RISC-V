set script_dir  [file dirname [file normalize [info script]]]
set project_dir [file normalize [file join $script_dir ..]]
set project_xpr [file join $project_dir miniLA.xpr]
set llama_dst   [file normalize [file join $project_dir src coe llama.coe]]
set bundled_src [file normalize [file join $project_dir software llama main.coe]]
set legacy_src  [file normalize [file join $project_dir .. 5_llama2.c main.coe]]

# Prefer a freshly compiled in-repository image, retain compatibility with the
# historical sibling directory, and finally fall back to the committed COE.
set llama_src ""
foreach candidate [list $bundled_src $legacy_src $llama_dst] {
    if {[file exists $candidate]} {
        set llama_src $candidate
        break
    }
}

if {$llama_src eq ""} {
    error "LLaMA COE not found in software/llama, ../5_llama2.c, or src/coe"
}

if {[current_project -quiet] eq ""} {
    open_project $project_xpr
}

file mkdir [file dirname $llama_dst]
if {$llama_src ne $llama_dst} {
    file copy -force $llama_src $llama_dst
}

# Remove stale COE entries inherited from the original lab directory. Vivado
# adds every registered COE to the synthesis command, even if no active IP uses
# it, so one missing historical test file is enough to abort synthesis.
set removed_coe {}
foreach f [get_files -all -quiet] {
    set file_name [get_property NAME $f]
    if {![string equal -nocase [file extension $file_name] ".coe"]} {
        continue
    }

    set normalized_name [file normalize $file_name]
    if {![file exists $normalized_name] ||
        ($llama_src ne $llama_dst && $normalized_name eq $llama_src)} {
        lappend removed_coe $file_name
        remove_files -quiet $f
    }
}

if {[llength [get_files -all -quiet $llama_dst]] == 0} {
    add_files -norecurse $llama_dst
}

set bram_ip [get_ips -quiet bram_axi]
if {[llength $bram_ip] != 1} {
    error "Expected exactly one bram_axi IP, found [llength $bram_ip]"
}

set_property CONFIG.Load_Init_File true $bram_ip
set_property CONFIG.Coe_File $llama_dst $bram_ip

reset_target all $bram_ip
generate_target all $bram_ip
export_ip_user_files -of_objects $bram_ip -no_script -sync -force -quiet

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

if {[llength [get_runs -quiet synth_1]] == 1} {
    reset_run synth_1
}

puts "LLAMA_COE_SELECTED=$llama_dst"
puts "LLAMA_COE_SOURCE=$llama_src"
puts "REMOVED_STALE_COE_COUNT=[llength $removed_coe]"
foreach f $removed_coe {
    puts "REMOVED_STALE_COE=$f"
}
puts "LLaMA COE selection is fixed. Generate Bitstream can now be launched again."
