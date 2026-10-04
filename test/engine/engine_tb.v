`timescale 1ns/1ps
module engine_tb;
  reg clock=0, reset=0, session_clear=0, update_valid=0, result_ready=0;
  reg item=0, warm=0;
  reg [15:0] price=0;
  reg [3:0] pos=0;
  wire update_ready, result_valid;
  wire [1:0] action;
  gqh_update_engine dut (
    .clock(clock), .reset(reset), .session_clear(session_clear),
    .update_valid(update_valid), .result_ready(result_ready),
    .update$item_select(item), .update$price(price),
    .update$window_position(pos), .update$warmup(warm),
    .update_ready(update_ready), .result_valid(result_valid), .action(action));
  integer fd, n, j, addr, count=0;
  integer v [0:53];
  reg [4095:0] trace;
  integer accepted_item=0, logical, item_index, record_address;
  reg [23:0] physical [0:1];
  task check;
    input [31:0] actual;
    input integer expected;
    input [255:0] what;
    begin
      if (actual !== expected) begin
        $display("FAIL edge %0d %0s: got %0h expected %0d", count, what, actual, expected);
        $fatal(1);
      end
    end
  endtask
  initial begin
    if (!$value$plusargs("TRACE=%s", trace)) $fatal(1,"missing TRACE");
    fd=$fopen(trace,"r");
    if (fd==0) $fatal(1,"cannot open TRACE");
    // Test-only poison, deliberately absent from generated hardware RTL.
    for (addr=0; addr<32; addr=addr+1) dut.engine_history[addr]=65535-addr;
`ifdef HOPT_RECORDS_IN_BRAM
    physical[0]=24'hFEDCBA; physical[1]=24'hABCDEF;
    dut.engine_records[0]=physical[0]; dut.engine_records[1]=physical[1];
`endif
    while (!$feof(fd)) begin
      n=$fscanf(fd,"%d",v[0]);
      if (n==1) begin
        for (j=1; j<54; j=j+1) begin
          n=$fscanf(fd,"%d",v[j]);
          if (n!=1) $fatal(1,"short trace row");
        end
        reset=v[0]; session_clear=v[1]; update_valid=v[2]; result_ready=v[3];
        item=v[4]; price=v[5]; pos=v[6]; warm=v[7];
        #1;
        check(update_ready,v[8],"pre ready"); check(result_valid,v[9],"pre valid");
        // Power-up register values are unspecified until the first reset edge.
        if (count>0) check(action,v[10],"pre action");
        clock=1; #1;
        check(update_ready,v[11],"post ready"); check(result_valid,v[12],"post valid");
        check(action,v[13],"post action");
`ifdef HOPT_RECORDS_IN_BRAM
        if (v[8] && v[2]) accepted_item=v[4];
        if (v[12] && !v[9]) begin
          record_address=accepted_item;
          physical[record_address]=v[14+accepted_item]
            | (v[16+2*accepted_item]<<20) | (v[17+2*accepted_item]<<21)
            | (v[20+accepted_item]<<22);
        end
        for (item_index=0; item_index<2; item_index=item_index+1) begin
          record_address=item_index;
          check(dut.engine_records[record_address],physical[record_address],"record exact once/preservation");
          logical=(item_index==0 ? dut.record_valid_a : dut.record_valid_b)
            ? dut.engine_records[record_address] : 0;
          check(logical & 20'hFFFFF,v[14+item_index],"sum/direct window");
          check((logical>>20)&1,v[16+2*item_index],"previous below");
          check((logical>>21)&1,v[17+2*item_index],"previous above");
          check((logical>>22)&3,v[20+item_index],"held");
        end
`else
        check(dut.sum_a,v[14],"sum A"); check(dut.sum_b,v[15],"sum B");
        check(dut.previous_below_a,v[16],"below A"); check(dut.previous_above_a,v[17],"above A");
        check(dut.previous_below_b,v[18],"below B"); check(dut.previous_above_b,v[19],"above B");
        check(dut.held_a,v[20],"held A"); check(dut.held_b,v[21],"held B");
`endif
        for (addr=0; addr<32; addr=addr+1)
          check(dut.engine_history[addr],v[22+addr],"RAM preservation/exact once");
        clock=0; #1;
        count=count+1;
      end
    end
    $fclose(fd);
    $display("PASS Icarus: %0d edges, synchronous RAM, scalar/window consistency, reset and stalled results",count);
    $finish;
  end
endmodule
