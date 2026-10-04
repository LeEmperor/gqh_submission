`timescale 1ns/1ps
// Elaborates the actual generated wrapper against Gowin's rPLL functional model.
module pll_vendor_tb;
  reg sys_clk = 0, reset_btn = 0, uart_rx_i = 1;
  always #(1000.0/27.0/2.0) sys_clk = ~sys_clk;
  wire uart_tx_o, led0_n, led1_n;
  gqh_competition_pll_top dut(.*);
  realtime before_edge, elapsed;
  initial begin
    #1;
    if (uart_tx_o !== 1 || dut.reset_release.reset !== 1) $fatal(1,"startup reset");
    wait(dut.pll_locked === 1);
    repeat(12) @(posedge dut.core_clk);
    #0.1;
    if (dut.reset_release.reset !== 0 || uart_tx_o !== 1) $fatal(1,"locked idle");
    @(posedge dut.core_clk); before_edge=$realtime;
    repeat(81) @(posedge dut.core_clk);
    elapsed=$realtime-before_edge;
    if (elapsed < 999.0 || elapsed > 1001.0) $fatal(1,"expected 81MHz, 81 cycles took %f ns",elapsed);
    if (led0_n !== 1 || led1_n !== 1) $fatal(1,"LED outputs");
    $display("PASS vendor rPLL model: lock, reset release, 81 cycles in %f ns",elapsed);
    $finish;
  end
  initial begin #1000000; $fatal(1,"vendor PLL watchdog"); end
endmodule
