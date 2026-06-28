
// ========================================================================================================================
// TIMING ANALYSIS- ".SDC FILE"
// ========================================================================================================================

create_clock -name CLOCK_50 -period 20.0 [get_ports {CLOCK_50}]
derive_clock_uncertainty
set_false_path -from [get_ports {GPIO1_COL[*]}]
set_false_path -to   [get_ports {GPIO1_ROW[*]}]



