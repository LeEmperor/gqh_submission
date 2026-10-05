// Tang Nano 20K blinky: 27 MHz clock, six onboard LEDs (active low).
// LEDs show a 6-bit counter that ticks ~4 times per second.
module blinky (
    input  wire       clk,  // 27 MHz oscillator, pin 4
    output wire [5:0] led   // LED0..LED5, pins 15..20, active low
);
    localparam CLK_HZ  = 27_000_000;
    localparam TICK_HZ = 4;
    localparam DIV     = CLK_HZ / TICK_HZ;

    reg [$clog2(DIV)-1:0] div_cnt = 0;
    reg [5:0]             count   = 0;

    always @(posedge clk) begin
        if (div_cnt == DIV - 1) begin
            div_cnt <= 0;
            count   <= count + 1'b1;
        end else begin
            div_cnt <= div_cnt + 1'b1;
        end
    end

    assign led = ~count;
endmodule
