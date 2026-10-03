module top (
    input  wire sys_clk,
    input  wire reset_btn,

    output wire clk_test,

    output wire led0_n,
    output wire led1_n,

    output wire uart_tx_o,
    input wire  uart_rx_i

);

    // Expected PLL output: 400 MHz
    wire clk_270m;

    Gowin_rPLL pll_inst (
        .clkout(clk_270m),
        .clkin (sys_clk)
    );

    // Using a counter here to ensure that the actual GPIO toggles at
    // 25MHz so that the DAD board can actually sample it properly
    // You can just use this clock directly, or regenerate the IP yourself
    // Only 4 bits needed.
    // counter[3] toggles every 8 input clock cycles.
    reg [3:0] counter = 4'd0;

    always @(posedge clk_270m) begin
        if (reset_btn)
            counter <= 4'd0;
        else
            counter <= counter + 1'b1;
    end

    // 400 MHz / 16 = 25 MHz output
    assign clk_test = counter[3];

    // Optional visible status
    assign led0_n = ~counter[3];
    assign led1_n = 1'b1;

endmodule