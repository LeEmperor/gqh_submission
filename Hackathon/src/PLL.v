module PLL (
    // straight from .cst file
    input  wire sys_clk,
    input  wire reset_btn,

    output wire uart_tx_o,
    input wire  uart_rx_i,

    output wire led0_n,
    output wire led1_n

);

    // Expected PLL output: 108 MHz
    wire clk_108m; // change this if you wanna when copying

    // Here's how you actually instantiate it
    // you just need to copy this
    Gowin_rPLL pll_inst (
        .clkout(clk_108m),
        .clkin (sys_clk)
    );

    // maybe remove this below for your actual
    // have to assign PLL signal to something
    // so that the PLL itself isn't optimized away
    assign led1_n = clk_108m; 

endmodule