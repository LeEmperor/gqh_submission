`timescale 1ns/1ps
module bringup_tb;
  reg sys_clk = 0, reset_btn = 0, uart_rx_i = 0;
  wire uart_tx_o, led0_n, led1_n;
  gqh_top dut(.*);
  always #5 sys_clk = ~sys_clk;
  task check_idle;
    begin
      if (uart_tx_o !== 1'b1 || led1_n !== 1'b1) $fatal(1, "idle outputs");
    end
  endtask
  initial begin
    #1;
    if (led0_n !== 1'b1 || dut.reset_release.reset !== 1'b1)
      $fatal(1, "startup initialization missing");
    repeat (2) @(posedge sys_clk); #1;
    if (dut.reset_release.reset !== 1'b0) $fatal(1, "release latency");
    @(negedge sys_clk); reset_btn = 1; #1;
    if (dut.reset_release.reset !== 1'b1) $fatal(1, "async assertion");
    @(posedge sys_clk); #1;
    if (led0_n !== 1'b1) $fatal(1, "reset heartbeat");
    @(negedge sys_clk); reset_btn = 0;
    @(posedge sys_clk); #1;
    if (dut.reset_release.reset !== 1'b1) $fatal(1, "released too early");
    @(posedge sys_clk); #1;
    if (dut.reset_release.reset !== 1'b0) $fatal(1, "release failed");
    check_idle; uart_rx_i = 1;
    repeat (4) begin @(posedge sys_clk); #1; check_idle; end
    $display("PASS: emitted RTL initialization, async assertion, synchronized release, idle");
    $finish;
  end
endmodule
