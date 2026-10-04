`timescale 1ns/1ps
module tx_tb;
  reg clock=0, reset=1, tx_valid=0;
  reg [7:0] tx_data=0;
  wire tx, tx_ready, tx_busy;
  gqh_uart_tx dut(.*);
  reg [9:0] frame;
  task tick;
    begin #5; clock=1; #5; clock=0; end
  endtask
  initial begin
    tick(); reset=0; #1;
    if (tx!==1 || tx_ready!==1 || tx_busy!==0) $fatal(1,"TX reset");
    // Back-to-back frames, all bytes, exact 234 clocks for all ten bits.
    for (integer value=0;value<256;value=value+1) begin
      tx_data=value; tx_valid=1; tick(); tx_valid=0;
      frame={1'b1,tx_data,1'b0}; tx_data=~tx_data;
      for (integer bitno=0;bitno<10;bitno=bitno+1)
        for (integer cycle=0;cycle<234;cycle=cycle+1) begin
          if (tx!==frame[bitno] || tx_busy!==1 || tx_ready!==0)
            $fatal(1,"TX byte %0d bit %0d clock %0d",value,bitno,cycle);
          tick();
        end
      if (tx!==1 || tx_ready!==1 || tx_busy!==0) $fatal(1,"TX completion");
    end
    $display("PASS LFSR TX: all 256 bytes, exact 234-clock start/data/stop bits, immediate back-to-back acceptance");
    $finish;
  end
endmodule
