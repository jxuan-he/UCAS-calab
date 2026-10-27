# Reproducible exp14 SoC build. Usage: vivado -mode batch -source this.tcl
#   -tclargs create|sim|impl [seed=0x5501ff] [cpu_mhz=100]
# Source RTL and the supplied environment are never modified by this script.
set repo [file normalize [file join [file dirname [info script]] ..]]
set envroot [file normalize [file join $repo .. output exp14]]
set soc [file join $envroot soc_verify soc_hs_bram]
set work [file join $repo build exp14]
set mode [lindex $argv 0]
if {$mode eq ""} {set mode create}
set seed [lindex $argv 1]
if {$seed eq ""} {set seed 0x5501ff}
set mhz [lindex $argv 2]
if {$mhz eq ""} {set mhz 100}
file mkdir $work
file mkdir [file join $work generated]
file mkdir [file join $work reports]
proc read_text {path} {set f [open $path r]; set s [read $f]; close $f; return $s}
proc write_text {path s} {set f [open $path w]; puts -nonewline $f $s; close $f}

# Keep the vendor testbench, RAM wrapper, bridge and confreg behavior intact.
# Only make trace location absolute, select a reproducible seed, and add checks.
set conf [read_text [file join $soc rtl CONFREG confreg.v]]
regsub {`define RANDOM_SEED[^\n]*} $conf "`define RANDOM_SEED 23'h[format %06x $seed]" conf
write_text [file join $work generated confreg.v] $conf
set tb [read_text [file join $soc testbench mycpu_tb.v]]
regsub {`define TRACE_REF_FILE[^\n]*} $tb "`define TRACE_REF_FILE \"[file join $envroot gettrace golden_trace.txt]\"" tb
set tb [string map [list "module tb_top( );" "module tb_top( );\nexp14_bus_monitor bus_checks();"] $tb]
write_text [file join $work generated mycpu_tb.v] $tb

if {$mode eq "create"} {
    create_project exp14 [file join $work project] -part xc7a200tfbg676-1 -force
    set_property target_language Verilog [current_project]
    foreach f {mycpu_top.v IF_PC.v IDU.v CP0.v control.v regfile.v alu.v div_gen.v} {
        add_files [file join $repo $f]
    }
    add_files [file join $soc rtl soc_lite_top.v]
    add_files [glob [file join $soc rtl BRIDGE *.v]]
    add_files [glob [file join $soc rtl ram_wrap *.v]]
    add_files [file join $work generated confreg.v]
    add_files -fileset sim_1 [file join $work generated mycpu_tb.v]
    add_files -fileset sim_1 [file join $repo tests exp14_bus_monitor.sv]
    add_files -fileset constrs_1 [glob [file join $soc run_vivado constraints *.xdc]]
    foreach name {inst_ram data_ram} depth {262144 65536} {
        create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name $name
        set_property -dict [list CONFIG.Memory_Type {Single_Port_RAM} \
            CONFIG.Write_Width_A {32} CONFIG.Read_Width_A {32} \
            CONFIG.Write_Depth_A $depth CONFIG.Use_Byte_Write_Enable {true} \
            CONFIG.Byte_Size {8} CONFIG.Enable_A {Use_ENA_Pin} \
            CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
            CONFIG.Register_PortA_Output_of_Memory_Core {false} \
            CONFIG.Use_RSTA_Pin {false} CONFIG.Operating_Mode_A {WRITE_FIRST}] [get_ips $name]
        if {$name eq "inst_ram"} {
            set_property -dict [list CONFIG.Load_Init_File {true} \
                CONFIG.Coe_File [file join $envroot func obj inst_ram.coe]] [get_ips $name]
        }
    }
    create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name clk_pll
    set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $mhz CONFIG.CLKOUT2_USED {true} \
        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {100.000} \
        CONFIG.CLK_OUT1_PORT {cpu_clk} CONFIG.CLK_OUT2_PORT {timer_clk} \
        CONFIG.USE_RESET {false} CONFIG.USE_LOCKED {false}] [get_ips clk_pll]
    generate_target all [get_ips]
    set_property top soc_lite_top [get_filesets sources_1]
    set_property top tb_top [get_filesets sim_1]
    set_property xsim.simulate.runtime all [get_filesets sim_1]
    set_property xsim.simulate.log_all_signals false [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    close_project
    puts "EXP14_PROJECT_READY $work"
} else {
    open_project [file join $work project exp14.xpr]
    if {$mode eq "sim" || $mode eq "regress"} {
        if {$mode eq "regress"} {set seeds {0x5500ff 0x550001 0x551234 0x5527ff}} else {set seeds [list $seed]}
        foreach runseed $seeds {
            set conf [read_text [file join $soc rtl CONFREG confreg.v]]
            regsub {`define RANDOM_SEED[^\n]*} $conf "`define RANDOM_SEED 23'h[format %06x $runseed]" conf
            write_text [file join $work generated confreg.v] $conf
            set_property xsim.simulate.runtime all [get_filesets sim_1]
            launch_simulation -mode behavioral
            close_sim -quiet
            set simlog [file join $work project exp14.sim sim_1 behav xsim simulate.log]
            set result [read_text $simlog]
            write_text [file join $work reports sim_[format %06x $runseed].log] $result
            if {![string match {*----PASS!!!*} $result] || ![string match {*8'd58 Functional Test Point PASS*} $result] ||
                [string match {*Fatal:*} $result] || [string match {*Error!!!*} $result]} {
                error "exp14 functional verification failed seed=$runseed"
            }
            puts "EXP14_SIM_PASS seed=$runseed"
        }
    } elseif {$mode eq "impl"} {
        set_property CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $mhz [get_ips clk_pll]
        generate_target all [get_ips clk_pll]
        set_param general.maxThreads 8
        reset_run synth_1
        set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
        launch_runs synth_1 -jobs 8
        wait_on_run synth_1
        if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "synthesis failed"}
        set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]
        launch_runs impl_1 -to_step route_design -jobs 8
        wait_on_run impl_1
        if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "implementation failed"}
        open_run impl_1
        report_timing_summary -delay_type min_max -report_unconstrained -max_paths 10 \
            -file [file join $work reports timing_${mhz}MHz.rpt]
        report_utilization -file [file join $work reports utilization_${mhz}MHz.rpt]
        report_drc -file [file join $work reports drc_${mhz}MHz.rpt]
        report_clocks -file [file join $work reports clocks_${mhz}MHz.rpt]
        check_timing -verbose -file [file join $work reports check_timing_${mhz}MHz.rpt]
        set p [get_timing_paths -delay_type max -max_paths 1]
        puts "EXP14_ROUTE_WNS_MHZ=$mhz WNS=[get_property SLACK $p]"
    } else {error "unknown mode: $mode"}
    close_project
}
