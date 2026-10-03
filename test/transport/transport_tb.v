`timescale 1ns/1ps
module transport_tb;
  localparam BIT = 234;
  reg sys_clk = 0;
  always #5 sys_clk = ~sys_clk;
  reg reset_btn = 0, uart_rx_i = 1;
  wire uart_tx_o, led0_n, led1_n;
  gqh_transport_top dut(.*);
  integer seen = 0;
  reg [7:0] received [0:255];
  reg [7:0] assembled;
  integer k;
  // Independent pin-level receiver at nominal baud. Sample bit centers.
  initial forever begin
    @(negedge uart_tx_o);
    repeat (BIT/2) @(posedge sys_clk);
    if (uart_tx_o !== 0) $fatal(1, "bad start");
    for (k=0;k<8;k=k+1) begin
      repeat (BIT) @(posedge sys_clk);
      assembled[k] = uart_tx_o;
    end
    repeat (BIT) @(posedge sys_clk);
    if (uart_tx_o !== 1) $fatal(1, "bad stop");
    received[seen] = assembled;
    seen = seen+1;
  end
  task hold(input integer clocks, input level);
    begin
      @(negedge sys_clk); uart_rx_i = level;
      repeat (clocks) @(negedge sys_clk);
    end
  endtask
  // Drive full independent periods, without waiting an extra cycle between bits.
  task send_byte(input [7:0] b, input stop);
    integer bitno;
    begin
      uart_rx_i = 0; repeat (BIT) @(negedge sys_clk);
      for (bitno=0;bitno<8;bitno=bitno+1) begin
        uart_rx_i = b[bitno]; repeat (BIT) @(negedge sys_clk);
      end
      uart_rx_i = stop; repeat (BIT) @(negedge sys_clk);
    end
  endtask
  task reset_board;
    begin
      reset_btn = 1; uart_rx_i = 1;
      repeat (5) @(negedge sys_clk);
      if (uart_tx_o !== 1) $fatal(1,"reset TX");
      reset_btn = 0; repeat (10) @(negedge sys_clk);
      if (led1_n !== 1) $fatal(1,"reset fault clear");
    end
  endtask
  task transaction(input [15:0] idx, input [7:0] id1, input [7:0] id2);
    integer base, j;
    begin
      base = seen;
      send_byte(idx[15:8],1); send_byte(idx[7:0],1);
      send_byte(id1,1); send_byte(8'h12,1); send_byte(8'h34,1);
      send_byte(id2,1); send_byte(8'hfe,1);
      if (seen != base || uart_tx_o !== 1) $fatal(1,"early response");
      // Legitimate host pauses must not abort a request.
      repeat (BIT*20) @(negedge sys_clk);
      send_byte(8'hdc,1);
      repeat (BIT*85) @(negedge sys_clk);
      if (seen != base+8) $fatal(1,"response count %0d",seen-base);
      if (received[base] !== idx[15:8] || received[base+1] !== idx[7:0] ||
          received[base+2] !== id1 || received[base+3] !== 0 ||
          received[base+4] !== id2 || received[base+5] !== 0 ||
          received[base+6] !== 0 || received[base+7] !== 0)
        $fatal(1,"response mismatch");
      if (led1_n !== 1) $fatal(1,"unexpected fault");
    end
  endtask
  initial begin
    repeat (10) @(negedge sys_clk);
    transaction(0,8'h11,8'h22);
    transaction(16'habcd,8'h22,8'h11);
    send_byte(8'hab,1); send_byte(8'hcd,1); reset_board();
    transaction(16'h1234,8'h11,8'h22);
    // Bad stop latches fault and prevents partial bytes becoming requests.
    send_byte(8'h42,0); hold(BIT*15,1);
    if (led1_n !== 0) $fatal(1,"missing framing fault");
    for (integer n=0;n<8;n=n+1) send_byte(0,1);
    repeat (BIT*85) @(negedge sys_clk);
    if (seen != 24) $fatal(1,"response after fault");
    reset_board(); transaction(16'hffff,8'h22,8'h11);
    // Unexpected input while responding faults, but the accepted response finishes.
    send_byte(0,1); send_byte(1,1); send_byte(8'h11,1); send_byte(0,1);
    send_byte(0,1); send_byte(8'h22,1); send_byte(0,1); send_byte(0,1);
    send_byte(8'h99,1);
    repeat (BIT*85) @(negedge sys_clk);
    if (led1_n !== 0 || seen != 40) $fatal(1,"busy input policy");
    reset_board(); transaction(2,8'h11,8'h22);
    $display("PASS: emitted transport RTL serial round trips, reset and faults");
    $finish;
  end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
