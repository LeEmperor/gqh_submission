// Derived from the user's Gowin-generated gowin_rpll.v (2026-10-04 07:17:18).
// Gowin V1.9.11.03 Education, GW2AR-LV18QN88C8/I7, GW2AR-18C.
// Frequency/primitive settings preserved; module renamed and LOCK exported.
// 27 MHz input -> 81 MHz CLKOUT; internal VCO = 648 MHz.
module Gowin_rPLL_81 (output clkout, output locked, input clkin);
    wire clkoutp_o, clkoutd_o, clkoutd3_o;
    rPLL rpll_inst (
        .CLKOUT(clkout), .LOCK(locked), .CLKOUTP(clkoutp_o),
        .CLKOUTD(clkoutd_o), .CLKOUTD3(clkoutd3_o),
        .RESET(1'b0), .RESET_P(1'b0), .CLKIN(clkin), .CLKFB(1'b0),
        .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
        .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0)
    );
    defparam rpll_inst.FCLKIN = "27";
    defparam rpll_inst.DYN_IDIV_SEL = "false";
    defparam rpll_inst.IDIV_SEL = 0;
    defparam rpll_inst.DYN_FBDIV_SEL = "false";
    defparam rpll_inst.FBDIV_SEL = 2;
    defparam rpll_inst.DYN_ODIV_SEL = "false";
    defparam rpll_inst.ODIV_SEL = 8;
    defparam rpll_inst.PSDA_SEL = "0000";
    defparam rpll_inst.DYN_DA_EN = "true";
    defparam rpll_inst.DUTYDA_SEL = "1000";
    defparam rpll_inst.CLKOUT_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUTP_FT_DIR = 1'b1;
    defparam rpll_inst.CLKOUT_DLY_STEP = 0;
    defparam rpll_inst.CLKOUTP_DLY_STEP = 0;
    defparam rpll_inst.CLKFB_SEL = "internal";
    defparam rpll_inst.CLKOUT_BYPASS = "false";
    defparam rpll_inst.CLKOUTP_BYPASS = "false";
    defparam rpll_inst.CLKOUTD_BYPASS = "false";
    defparam rpll_inst.DYN_SDIV_SEL = 2;
    defparam rpll_inst.CLKOUTD_SRC = "CLKOUT";
    defparam rpll_inst.CLKOUTD3_SRC = "CLKOUT";
    defparam rpll_inst.DEVICE = "GW2AR-18C";
endmodule
