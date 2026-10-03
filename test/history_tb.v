`timescale 1ns/1ps
module history_tb;
  reg clock = 0, write_enable = 0;
  reg [4:0] write_address = 0, read_address = 0;
  reg [15:0] write_data = 0;
  wire [15:0] read_data;
  history_probe dut(.*);
  always #5 clock = ~clock;
  integer i;
  initial begin
    // Write every word; no assumptions about uninitialized storage.
    for (i = 0; i < 32; i = i + 1) begin
      @(negedge clock); write_enable = 1; write_address = i; write_data = i * 2053 + 17;
      @(posedge clock); #1;
    end
    @(negedge clock); write_enable = 0;
    for (i = 31; i >= 0; i = i - 1) begin
      read_address = i;
      @(posedge clock); #1;
      if (read_data !== ((i * 2053 + 17) & 65535)) $fatal(1, "RAM read %d", i);
      @(negedge clock);
    end
    read_address = 7; write_address = 7; write_data = 65535; write_enable = 1;
    @(posedge clock); #1;
    if (read_data !== 16'd14388) $fatal(1, "collision must read old word");
    @(negedge clock); write_enable = 0;
    @(posedge clock); #1;
    if (read_data !== 16'hffff) $fatal(1, "updated word missing");
    @(negedge clock); read_address = 0; #1;
    if (read_data !== 16'hffff) $fatal(1, "asynchronous read unexpected");
    @(posedge clock); #1;
    if (read_data !== 16'd17) $fatal(1, "one-edge latency");
    $display("PASS: emitted RAM read/write, latency and read-first collision");
    $finish;
  end
endmodule
