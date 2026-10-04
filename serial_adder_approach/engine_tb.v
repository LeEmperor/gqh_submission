`timescale 1ns/1ps
module engine_tb;
  reg clock=0, reset=1, session_clear=0, update_valid=0, result_ready=0;
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
  reg history_before[0:511], sums_before[0:63];
  reg [3:0] meta_before[0:1];
  reg [19:0] actual_sum;
  reg [15:0] actual_price;
  reg [1023:0] trace;
  integer fd, fields, clear_in, item_in, warm_in, price_in, pos_in;
  integer expected_action, expected_sum, expected_below, expected_above;
  integer count=0, ticks, b, addr, saved_item, saved_price, saved_pos;
  task tick;
    begin #5; clock=1; #5; clock=0; end
  endtask
  initial begin
    if (!$value$plusargs("TRACE=%s", trace)) $fatal(1,"missing trace");
    fd=$fopen(trace,"r"); if (!fd) $fatal(1,"trace open");
    // Poison *all* physical bits before reset, including unused sum addresses.
    for (addr=0;addr<512;addr=addr+1) dut.serial_history[addr]=(addr%3==0);
    for (addr=0;addr<64;addr=addr+1) dut.serial_sums[addr]=(addr%3!=0);
    dut.serial_metadata[0]=4'hf; dut.serial_metadata[1]=4'hb;
    tick(); tick(); reset=0;
    while (!$feof(fd)) begin
      fields=$fscanf(fd,"%d %d %d %d %d %d %d %d %d\n",clear_in,item_in,warm_in,
        price_in,pos_in,expected_action,expected_sum,expected_below,expected_above);
      if (fields!=9) $fatal(1,"bad trace");
      if (clear_in) begin session_clear=1; tick(); session_clear=0; end
      for (addr=0;addr<512;addr=addr+1) history_before[addr]=dut.serial_history[addr];
      for (addr=0;addr<64;addr=addr+1) sums_before[addr]=dut.serial_sums[addr];
      for (addr=0;addr<2;addr=addr+1) meta_before[addr]=dut.serial_metadata[addr];
      item=item_in; warm=warm_in; price=price_in; pos=pos_in;
      saved_item=item; saved_price=price; saved_pos=pos;
      #1;
      if (update_ready!==1) $fatal(1,"not ready");
      update_valid=1; tick(); update_valid=0;
      ticks=0;
      while (!result_valid && ticks<30) begin
        if (update_ready!==0) $fatal(1,"ready while computing");
        tick(); ticks=ticks+1;
      end
      if (ticks!=21 || result_valid!==1) $fatal(1,"bad serial schedule %0d",ticks);
      if (action!==expected_action) $fatal(1,"action sample %0d got %0d wanted %0d",count,action,expected_action);
      actual_sum=0; actual_price=0;
      for (b=0;b<20;b=b+1) actual_sum[b]=dut.serial_sums[saved_item*32+b];
      for (b=0;b<16;b=b+1) actual_price[b]=dut.serial_history[saved_item*256+saved_pos*16+b];
      if (actual_sum!==expected_sum || actual_price!==saved_price)
        $fatal(1,"sum/history sample %0d got sum %0d wanted %0d",count,actual_sum,expected_sum);
      if (dut.serial_metadata[saved_item] !== ((expected_action<<2)|(expected_above<<1)|expected_below))
        $fatal(1,"metadata mismatch %0d",count);
      for (addr=0;addr<512;addr=addr+1)
        if (addr/16 != saved_item*16+saved_pos && dut.serial_history[addr]!==history_before[addr])
          $fatal(1,"unselected history changed");
      for (addr=0;addr<64;addr=addr+1)
        if ((addr/32 != saved_item || addr%32>=20) && dut.serial_sums[addr]!==sums_before[addr])
          $fatal(1,"unselected sum changed");
      if (dut.serial_metadata[1-saved_item]!==meta_before[1-saved_item]) $fatal(1,"other metadata changed");
      // Borrowed fields may change after result_valid. No memory writes while
      // the consumer stalls, including a session_clear offered while busy.
      for (addr=0;addr<512;addr=addr+1) history_before[addr]=dut.serial_history[addr];
      for (addr=0;addr<64;addr=addr+1) sums_before[addr]=dut.serial_sums[addr];
      for (addr=0;addr<2;addr=addr+1) meta_before[addr]=dut.serial_metadata[addr];
      item=~item; price=~price; pos=~pos; warm=~warm; session_clear=1;
      repeat (count%7+1) begin
        tick();
        if (result_valid!==1 || action!==expected_action || update_ready!==0) $fatal(1,"stalled result changed");
        for (addr=0;addr<512;addr=addr+1)
          if (dut.serial_history[addr]!==history_before[addr]) $fatal(1,"stalled history write");
        for (addr=0;addr<64;addr=addr+1)
          if (dut.serial_sums[addr]!==sums_before[addr]) $fatal(1,"stalled sum write");
        for (addr=0;addr<2;addr=addr+1)
          if (dut.serial_metadata[addr]!==meta_before[addr]) $fatal(1,"stalled metadata write");
      end
      session_clear=0; result_ready=1; tick(); result_ready=0;
      count=count+1;
    end
    $display("PASS serial engine: %0d samples, direct-window sum/relation/action, poisoned RAM, other-item preservation, result stalls",count);
    $finish;
  end
endmodule
