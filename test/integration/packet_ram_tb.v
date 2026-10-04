`timescale 1ns/1ps
// Default covers the historical four-state engine. Candidate runners may
// select extended states and digit-by-digit reset coverage with these defines.
`ifndef HOPT_ENGINE_RESULT_STATE
`define HOPT_ENGINE_RESULT_STATE 3
`endif
`ifndef HOPT_CORE_MHZ
`define HOPT_CORE_MHZ 27
`endif
`ifndef HOPT_UART_DIVISOR
`define HOPT_UART_DIVISOR 234
`endif
`ifndef HOPT_TOP
`define HOPT_TOP gqh_competition_top
`endif
module competition_tb;
  // Independent wall-time host, with a 27 MHz reference on every board target.
  localparam real CORE = 1000.0/`HOPT_CORE_MHZ;
  localparam integer DIVISOR = `HOPT_UART_DIVISOR;
  localparam real HOST_BIT = 1000000000.0/115200.0;
  reg sys_clk = 0;
  always #(1000.0/27.0/2.0) sys_clk = ~sys_clk;
  reg reset_btn = 0, uart_rx_i = 1;
  wire uart_tx_o, led0_n, led1_n;
  `HOPT_TOP dut(.*);
`ifdef HOPT_PLL
  wire core_clock = dut.core_clk;
`else
  wire core_clock = sys_clk;
`endif
  wire fault_led_n;
`ifdef HOPT_NO_DIAGNOSTICS
  // Fault lockout is functional even when its external indicator is omitted.
  assign fault_led_n = ~dut.packet_ram_controller.protocol_fault;
  always @(posedge core_clock)
    if (led0_n !== 1 || led1_n !== 1) $fatal(1,"diagnostic LEDs must stay off");
`else
  assign fault_led_n = led1_n;
`endif
  reg [63:0] requests [0:4095], responses [0:4095];
  reg [7:0] received [0:65535];
  integer tx_frames = 0;
  integer seen = 0, epoch = 0, cycles = 0, accepted_cycle = -1;
  integer latency_file, trace_file, count = 0, scanned;
  integer latency_start = 0, latency_other = 0;
  reg allowed = 0;
  reg measuring = 1;
  reg [1023:0] trace_path, latency_path;

  // Packet RAM latency is final receive-byte acceptance to first TX acceptance.
  // It includes synchronous field reads and both engine commands; wire timing
  // is independently checked below. This differs from the legacy controller
  // response-offer endpoint and must not be merged with that measurement.
  always @(posedge core_clock) begin
    cycles = cycles + 1;
    if (dut.uart_tx.tx_ready && dut.uart_tx.tx_valid) tx_frames = tx_frames+1;
    if (dut.reset_release.reset) begin
      accepted_cycle = -1; allowed = 0;
    end else begin
      if (dut.packet_ram_controller.packet_receiving) allowed = 0;
      if (dut.packet_ram_controller.byte_valid && !dut.packet_ram_controller.framing_error
          && dut.packet_ram_controller.packet_receiving && dut.packet_ram_controller.packet_position == 7) begin
        accepted_cycle = cycles; allowed = 1;
      end
      if (dut.uart_tx.tx_ready && dut.uart_tx.tx_valid && accepted_cycle >= 0) begin
        if (measuring) begin
          $fdisplay(latency_file,"%0d,%0d",{dut.packet_ram_controller.request_packet[0],dut.packet_ram_controller.request_packet[1]},cycles-accepted_cycle);
          if ({dut.packet_ram_controller.request_packet[0],dut.packet_ram_controller.request_packet[1]} == 0) latency_start=cycles-accepted_cycle;
          else latency_other=cycles-accepted_cycle;
        end
        accepted_cycle=-1;
      end
      if (dut.uart_tx.tx_busy && dut.packet_ram_controller.packet_receiving)
        $fatal(1,"receive rearmed before final TX drain");
    end
  end

  // Decode TX using independent nominal baud sampling, with an additional
  // whole-stop-bit observer at every core cycle. Ignore a reset-aborted frame.
  initial forever begin : receiver
    reg [7:0] assembled;
    integer bitno, frame_epoch;
    @(negedge uart_tx_o);
    frame_epoch = epoch;
    if (!allowed && !reset_btn) $fatal(1,"TX before complete request acceptance");
    fork
      begin
        #(HOST_BIT/2.0);
        if (epoch == frame_epoch && uart_tx_o !== 0) $fatal(1,"bad TX start");
        for (bitno=0;bitno<8;bitno=bitno+1) begin
          #(HOST_BIT); assembled[bitno] = uart_tx_o;
        end
        #(HOST_BIT);
        if (epoch == frame_epoch) begin
          if (uart_tx_o !== 1) $fatal(1,"bad TX stop");
          received[seen] = assembled; seen = seen+1;
        end
      end
      begin
        #(9.0*DIVISOR*CORE + CORE/4.0);
        for (integer s=0;s<DIVISOR;s=s+1) begin
          if (epoch == frame_epoch && uart_tx_o !== 1) $fatal(1,"short TX stop bit");
          #(CORE);
        end
      end
    join
  end

  task send_byte(input [7:0] b, input stop);
    begin
      uart_rx_i = 0; #(HOST_BIT);
      for (integer bitno=0;bitno<8;bitno=bitno+1) begin
        uart_rx_i = b[bitno]; #(HOST_BIT);
      end
      uart_rx_i = stop; #(HOST_BIT);
    end
  endtask
  task reset_board;
    begin
      epoch = epoch+1;
      reset_btn = 1; uart_rx_i = 1;
      repeat (5) @(negedge core_clock);
      if (uart_tx_o !== 1) $fatal(1,"reset TX idle");
      reset_btn = 0;
      #(HOST_BIT*12); // Let independent decoder discard an aborted frame.
      if (fault_led_n !== 1 || uart_tx_o !== 1) $fatal(1,"reset recovery status");
    end
  endtask
  task send_request(input [63:0] req, input integer pauses);
    begin
      for (integer j=0;j<8;j=j+1) begin
        if (j<7 && uart_tx_o !== 1) $fatal(1,"early serial response");
        send_byte(req[63-j*8 -: 8],1);
        if (pauses && j<7) #(HOST_BIT*(j+1)*3);
      end
    end
  endtask
  task check_response(input [63:0] expected, input integer base);
    begin
      #(HOST_BIT*85);
      if (seen != base+8) $fatal(1,"response count got %0d wanted 8",seen-base);
      for (integer j=0;j<8;j=j+1)
        if (received[base+j] !== expected[63-j*8 -: 8])
          $fatal(1,"byte %0d got %02x expected %02x",j,received[base+j],expected[63-j*8 -: 8]);
      if (uart_tx_o !== 1) $fatal(1,"TX after response");
    end
  endtask
  task transaction(input integer row, input integer pauses);
    integer base;
    begin
      base = seen; send_request(requests[row],pauses);
      check_response(responses[row],base);
      if (fault_led_n !== 1) $fatal(1,"unexpected protocol fault row %0d",row);
    end
  endtask
  task populate;
    begin
      for (integer row=0;row<17;row=row+1) transaction(row,0);
    end
  endtask

  initial begin : main
    integer base, frame_base;
    if (!$value$plusargs("TRACE=%s",trace_path) || !$value$plusargs("LATENCY=%s",latency_path))
      $fatal(1,"missing paths");
    trace_file = $fopen(trace_path,"r"); latency_file = $fopen(latency_path,"w");
    if (!trace_file || !latency_file) $fatal(1,"file open");
    $fdisplay(latency_file,"index,accept_to_first_tx_accept_cycles");
    while (!$feof(trace_file)) begin
      scanned = $fscanf(trace_file,"%h %h\n",requests[count],responses[count]);
      if (scanned == 2) count=count+1;
    end
    $fclose(trace_file);
    // True emitted initialization, no button reset before first full session.
`ifdef HOPT_PLL
    wait(dut.pll_locked === 1);
`endif
    repeat (12) @(negedge core_clock);
    if (uart_tx_o !== 1 || fault_led_n !== 1 || led0_n !== 1) $fatal(1,"startup status");
    for (integer row=0;row<count;row=row+1) transaction(row,row%31==0);
    $fclose(latency_file); measuring=0;
    $display("PASS: %0d production-divisor serial oracle packets; core latency session=%0d other=%0d cycles",count,latency_start,latency_other);

    // Framing error after partial valid input: sticky lockout, no timeout/rearm.
    base=seen; send_byte(0,1); send_byte(8'h42,0);
    uart_rx_i=1; #(HOST_BIT*15);
    if (fault_led_n !== 0) $fatal(1,"missing framing fault");
    send_request(requests[0],0); #(HOST_BIT*85);
    if (seen != base || fault_led_n !== 0) $fatal(1,"framing lockout");
    reset_board(); populate();
    // Busy input after accepted request must fault; accepted response finishes.
    base=seen; send_request(requests[17],0); send_byte(8'h99,1);
    check_response(responses[17],base);
    if (fault_led_n !== 0) $fatal(1,"missing busy fault");
    base=seen; send_request(requests[0],0); #(HOST_BIT*85);
    if (seen != base || fault_led_n !== 0) $fatal(1,"busy sticky lockout");
    reset_board(); populate();

    // Reset during the data bits of each request byte, with populated history.
    for (integer offset=0;offset<8;offset=offset+1) begin
      base=seen;
      for (integer j=0;j<offset;j=j+1) send_byte(requests[17][63-j*8 -: 8],1);
      uart_rx_i=0; #(HOST_BIT*4.25);
      reset_board(); #(HOST_BIT*85);
      if (seen != base) $fatal(1,"stale response after RX reset");
      populate();
    end
    // Reset during each real engine phase on first and second slots.
    for (integer slot=0;slot<2;slot=slot+1) begin
      for (integer state=1;state<=`HOPT_ENGINE_RESULT_STATE;state=state+1) begin
        for (integer digit=0;digit<
`ifdef HOPT_ENGINE_SERIAL_DIGITS
            ((state==2 || state==4) ? `HOPT_ENGINE_SERIAL_DIGITS : 1)
`else
            1
`endif
            ;digit=digit+1) begin
          base=seen;
          fork
            send_request(requests[17],0);
            begin
              if (slot==1) begin
                wait(dut.engine.engine_state==`HOPT_ENGINE_RESULT_STATE);
                wait(dut.engine.engine_state==0);
              end
              wait(dut.engine.engine_state==state);
`ifdef HOPT_ENGINE_SERIAL_DIGITS
              if (state==2 || state==4) wait(dut.engine.engine_digit==digit);
`endif
              @(negedge core_clock); reset_board();
            end
          join
          #(HOST_BIT*85);
          if (seen != base) $fatal(1,"stale processing response");
          populate();
        end
      end
    end
    // Reset during data bits of each response frame; drop the partial frame.
    for (integer offset=0;offset<8;offset=offset+1) begin
      frame_base=tx_frames;
      send_request(requests[17],0);
      wait(tx_frames == frame_base+offset+1);
      #(HOST_BIT*4.25);
      reset_board();
      base=seen; #(HOST_BIT*85);
      if (seen != base) $fatal(1,"stale TX after reset");
      populate();
    end
`ifdef HOPT_NO_DIAGNOSTICS
    reset_board(); repeat(100) @(negedge core_clock);
    if (led0_n !== 1 || led1_n !== 1 || fault_led_n !== 1 || uart_tx_o !== 1)
      $fatal(1,"LED-free idle");
    $display("PASS: startup, legal pauses, full stops, sticky framing/busy faults, RX/engine/TX reset recovery and LEDs off");
`else
    // Observe the real default heartbeat after >13.5M clocks.
    reset_board(); repeat(13500005) @(negedge core_clock);
    if (led0_n !== 0 || led1_n !== 1 || uart_tx_o !== 1) $fatal(1,"heartbeat/idle");
    $display("PASS: startup, legal pauses, full stops, sticky framing/busy faults, RX/engine/TX reset recovery and heartbeat");
`endif
    $finish;
  end
  initial begin #100000000000; $fatal(1,"watchdog timeout"); end
endmodule
