`timescale 1ns/1ps
// Focused emitted-RTL check. Compile with the complete competition RTL.
// signal_reg[0..4] are the five payload registers inspected in that RTL.
module response_payload_reset_tb;
  reg clock = 0, reset = 0, response_valid = 0;
  reg [15:0] index = 0;
  reg [7:0] id1 = 0, id2 = 0;
  reg [1:0] action1 = 0, action2 = 0;
  reg allow_tx = 0, hold_busy = 0;
  wire ready, done, valid, uart_ready, uart_busy, tx;
  wire [7:0] data;
  reg [7:0] expected [0:7];
  integer accepted = 0, cycles = 0;

  gqh_response_sequencer seq (
    .clock(clock), .reset(reset), .response$index(index),
    .response$slot1_id(id1), .response$slot2_id(id2),
    .response$slot1_action(action1), .response$slot2_action(action2),
    .response_valid(response_valid), .tx_ready(uart_ready & allow_tx),
    .tx_busy(uart_busy | hold_busy), .response_ready(ready),
    .response_done(done), .tx_data(data), .tx_valid(valid)
  );
  gqh_uart_tx uart (
    .clock(clock), .reset(reset), .tx_data(data),
    .tx_valid(valid & allow_tx), .tx(tx),
    .tx_ready(uart_ready), .tx_busy(uart_busy)
  );

  always @(posedge clock) begin
    if (!reset && valid && allow_tx && uart_ready) begin
      if (accepted >= 8 || data !== expected[accepted])
        $fatal(1, "unexpected byte %0d: %h", accepted, data);
      accepted = accepted + 1;
    end
  end

  task tick;
    begin
      #5 clock = 1;
      #1;
      if (tx !== 1'b0 && tx !== 1'b1) $fatal(1, "unknown external TX");
      if ((reset || !uart_busy) && tx !== 1'b1) $fatal(1, "TX not idle high");
      #4 clock = 0;
    end
  endtask

  task quiet;
    integer n;
    begin
      for (n = 0; n < 12; n = n + 1) begin
        tick;
        if (valid !== 0 || done !== 0 || ready !== 1 || uart_busy !== 0)
          $fatal(1, "stale payload affected control before capture");
      end
    end
  endtask

  task offer(input [15:0] ix, input [7:0] a, b, input [1:0] ac, bc);
    begin
      if (ready !== 1) $fatal(1, "not ready for fresh response");
      index = ix; id1 = a; id2 = b; action1 = ac; action2 = bc;
      expected[0] = ix[15:8]; expected[1] = ix[7:0];
      expected[2] = a; expected[3] = {6'b0, ac};
      expected[4] = b; expected[5] = {6'b0, bc};
      expected[6] = 0; expected[7] = 0;
      accepted = 0; response_valid = 1; tick; response_valid = 0;
      // Disturb all producer fields after the single capture edge.
      index = ~ix; id1 = ~a; id2 = ~b; action1 = ~ac; action2 = ~bc;
    end
  endtask

  task finish_response;
    integer n;
    begin
      allow_tx = 0; hold_busy = 1;
      for (n = 0; n < 9; n = n + 1) begin
        tick;
        if (valid !== 1 || data !== expected[0] || done !== 0 || ready !== 0)
          $fatal(1, "captured response did not survive stall");
      end
      allow_tx = 1; cycles = 0;
      while (accepted < 8 || uart_busy) begin
        tick; cycles = cycles + 1;
        if (cycles > 20000) $fatal(1, "response timeout");
        if (done !== 0 || ready !== 0) $fatal(1, "completion before final drain");
      end
      for (n = 0; n < 17; n = n + 1) begin
        tick;
        if (valid !== 0 || done !== 0 || ready !== 0)
          $fatal(1, "drain hold lost");
      end
      hold_busy = 0; tick;
      if (done !== 1 || ready !== 1) $fatal(1, "missing final completion");
      tick;
      if (done !== 0 || accepted != 8) $fatal(1, "duplicate completion/byte");
    end
  endtask

  initial begin
    // No simulator-zero assumption: all 36 payload bits start unknown.
    seq.signal_reg = 2'bxx; seq.signal_reg_1 = 8'hxx;
    seq.signal_reg_2 = 2'bxx; seq.signal_reg_3 = 8'hxx;
    seq.signal_reg_4 = 16'hxxxx;
    reset = 1; tick; reset = 0; allow_tx = 1;
    if ({seq.signal_reg, seq.signal_reg_1, seq.signal_reg_2,
         seq.signal_reg_3, seq.signal_reg_4} !== {36{1'bx}})
      $fatal(1, "payload reset/initialization unexpectedly present");
    quiet;
    offer(16'habcd, 8'h22, 8'h11, 2, 1); finish_response;
    offer(16'h1357, 8'h11, 8'h22, 1, 0); finish_response;

    // Reset aborts a captured, stalled response. Retained nonzero poison must
    // neither be transmitted nor influence control; restart replaces it all.
    allow_tx = 0;
    offer(16'hdead, 8'ha5, 8'h5a, 3, 2);
    repeat (5) tick;
    reset = 1; tick; reset = 0;
    if ({seq.signal_reg, seq.signal_reg_1, seq.signal_reg_2,
         seq.signal_reg_3, seq.signal_reg_4} !== {2'd2,8'h5a,2'd3,8'ha5,16'hdead})
      $fatal(1, "reset did not retain the poison payload");
    allow_tx = 1; hold_busy = 0; accepted = 0; quiet;
    if (accepted != 0) $fatal(1, "aborted payload transmitted");
    offer(16'hf00d, 8'h33, 8'hcc, 0, 3); finish_response;
    $display("PASS response payload RTL: 36 unknown startup bits, retained nonzero reset poison, stalled abort/restart, three distinct responses, production UART idle high and final stop-bit drain");
    $finish;
  end
endmodule
