run 200 us

set core /soc_simple_tb/DUT/U_cpu/U_core
set axim /soc_simple_tb/DUT/U_cpu/U_aximaster

foreach signal {
    pc ifetch_req ifetch_valid if_req_valid front_stall
    if_id_valid if_id_pc if_id_inst
    id_ex_valid id_ex_pc id_ex_alu_op id_ex_is_mul_div
    ex_mem_valid ex_mem_pc ex_mem_ram_r_op ex_mem_ram_w_op
    mem_wb_valid mem_wb_pc mem_stall mul_div_stall
    if_id_hold id_ex_hold ex_mem_hold ex_mem_bubble
} {
    set object [get_objects ${core}/${signal}]
    puts "AB_STATE ${signal}=[get_value -radix hex $object]"
}

foreach signal {state rstate wstate ic_dev_rrdy dc_dev_rrdy dc_dev_wrdy} {
    set object [get_objects ${axim}/${signal}]
    if {[llength $object] > 0} {
        puts "AB_AXI_STATE ${signal}=[get_value -radix hex $object]"
    }
}

set mreq ${core}/U_MEM_REQ
foreach signal {
    valid ram_addr ram_rop ram_wop is_load is_store is_memory
    request_sent active_ram_rop active_ram_wop da_ren da_wen
    da_rvalid da_wresp response stall
} {
    set object [get_objects ${mreq}/${signal}]
    if {[llength $object] > 0} {
        puts "AB_MREQ_STATE ${signal}=[get_value -radix hex $object]"
    }
}

set dcache /soc_simple_tb/DUT/U_cpu/U_dcache
foreach signal {
    data_ren data_addr data_valid data_wen data_wresp
    cpu_ren cpu_raddr dev_rrdy dev_rvalid r_state r_nstat
} {
    set object [get_objects ${dcache}/${signal}]
    if {[llength $object] > 0} {
        puts "AB_DCACHE_STATE ${signal}=[get_value -radix hex $object]"
    }
}

quit
