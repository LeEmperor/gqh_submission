`timescale 1ns/1ps
module pll_reset_tb;
  reg sys_clk = 0, reset_btn = 0, uart_rx_i = 1;
  always #(1000.0/27.0/2.0) sys_clk = ~sys_clk;
  wire uart_tx_o, led0_n, led1_n;
  gqh_competition_pll_top dut(.*);
  localparam real BIT_TIME = 1000000000.0/115200.0;
  task send_byte(input [7:0] b);
    begin
      uart_rx_i=0; #(BIT_TIME);
      for (integer i=0;i<8;i=i+1) begin uart_rx_i=b[i]; #(BIT_TIME); end
      uart_rx_i=1; #(BIT_TIME);
    end
  endtask
  task request;
    reg [63:0] packet;
    begin
      packet=64'h00001100642200c8;
      for (integer i=0;i<8;i=i+1) send_byte(packet[63-8*i -:8]);
    end
  endtask
  task response;
    reg [63:0] expected;
    reg [7:0] got;
    begin
      expected=64'h0000110022000000;
      for (integer i=0;i<8;i=i+1) begin
        @(negedge uart_tx_o);
        #(BIT_TIME/2.0);
        if (uart_tx_o !== 0) $fatal(1,"bad start");
        for (integer b=0;b<8;b=b+1) begin #(BIT_TIME); got[b]=uart_tx_o; end
        #(BIT_TIME);
        if (uart_tx_o !== 1 || got !== expected[63-8*i -:8])
          $fatal(1,"PLL serial byte %0d got %h",i,got);
      end
      #(2*BIT_TIME);
    end
  endtask
  task transaction;
    fork request(); response(); join
  endtask
  task check_release;
    begin
      @(posedge dut.core_clk); #0.1;
      if (dut.reset_release.reset !== 1) $fatal(1,"reset released on first edge");
      @(posedge dut.core_clk); #0.1;
      if (dut.reset_release.reset !== 0) $fatal(1,"reset failed to release on second edge");
      repeat(4) @(negedge dut.core_clk);
    end
  endtask
  initial begin
    #1;
    if (dut.reset_release.reset !== 1 || uart_tx_o !== 1) $fatal(1,"startup idle/reset");
    repeat(20) @(negedge sys_clk);
    if (dut.pll_locked !== 0 || dut.reset_release.reset !== 1 || uart_tx_o !== 1)
      $fatal(1,"release before PLL lock");
    wait(dut.pll_locked === 1);
    check_release();
    transaction();
    // Loss of lock during an active response, with the core clock stopped.
    fork
      request();
      begin
        @(negedge uart_tx_o);
        #(BIT_TIME/4.0);
        @(negedge dut.core_clk);
        dut.pll.run_clock=0;
        dut.pll.locked=0;
        #1;
        if (dut.reset_release.reset !== 1 || uart_tx_o !== 1)
          $fatal(1,"unlock did not assert reset/TX idle without clock");
        #(2*BIT_TIME);
        if (dut.core_clk !== 0 || uart_tx_o !== 1) $fatal(1,"stopped-clock idle");
        dut.pll.locked=1;
        #100;
        if (dut.reset_release.reset !== 1) $fatal(1,"reset released without edges");
        dut.pll.run_clock=1;
        check_release();
      end
    join
    #(2*BIT_TIME);
    transaction();
    // Button reset also asserts asynchronously while the locked clock is stopped.
    @(negedge dut.core_clk); dut.pll.run_clock=0; reset_btn=1;
    #1;
    if (dut.reset_release.reset !== 1 || uart_tx_o !== 1) $fatal(1,"button assertion");
    reset_btn=0; #100;
    if (dut.reset_release.reset !== 1) $fatal(1,"button release without edges");
    dut.pll.run_clock=1; check_release();
    transaction();
    if (led0_n !== 1 || led1_n !== 1) $fatal(1,"LEDs");
    $display("PASS PLL reset: delayed lock, two-edge release, stopped-clock lock loss during TX, relock and button recovery");
    $finish;
  end
  initial begin #10000000; $fatal(1,"PLL reset watchdog"); end
endmodule
