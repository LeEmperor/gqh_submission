`timescale 1ns/1ps
// TEST ONLY. Ideal 81 MHz clock with delayed lock and controllable clock loss.
// This replaces the wrapper only in functional simulation, never in synthesis.
module Gowin_rPLL_81(output reg clkout = 0, output reg locked = 0, input clkin);
  reg run_clock = 1;
  always #(1000.0/81.0/2.0)
    if (run_clock) clkout = ~clkout;
  initial begin
    repeat (32) @(posedge clkin);
    locked = 1;
  end
endmodule
