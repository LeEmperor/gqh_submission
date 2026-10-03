module gqh_heartbeat (
    clock,
    reset,
    led_n
);

    input clock;
    input reset;
    output led_n;

    wire signal_const;
    wire signal_not;
    wire [23:0] signal_const_1;
    wire [23:0] signal_const_2;
    wire signal_wire;
    wire signal_wire_1;
    wire [23:0] signal_const_4;
    wire [23:0] signal_add;
    wire signal_eq;
    wire [23:0] signal_mux;
    wire [23:0] signal_wire_2;
    reg [23:0] signal_reg = 24'b000000000000000000000000;
    wire signal_eq_1;
    wire signal_mux_1;
    wire signal_wire_3;
    reg signal_reg_1 = 1'b0;
    wire signal_not_1;
    assign signal_const = 1'b0;
    assign signal_not = ~ signal_reg_1;
    assign signal_const_1 = 24'b110011011111111001011111;
    assign signal_const_2 = 24'b000000000000000000000000;
    assign signal_wire = reset;
    assign signal_wire_1 = clock;
    assign signal_const_4 = 24'b000000000000000000000001;
    assign signal_add = signal_reg + signal_const_4;
    assign signal_eq = signal_reg == signal_const_1;
    assign signal_mux = signal_eq ? signal_const_2 : signal_add;
    assign signal_wire_2 = signal_mux;
    always @(posedge signal_wire_1) begin
        if (signal_wire)
            signal_reg <= signal_const_2;
        else
            signal_reg <= signal_wire_2;
    end
    assign signal_eq_1 = signal_reg == signal_const_1;
    assign signal_mux_1 = signal_eq_1 ? signal_not : signal_reg_1;
    assign signal_wire_3 = signal_mux_1;
    always @(posedge signal_wire_1) begin
        if (signal_wire)
            signal_reg_1 <= signal_const;
        else
            signal_reg_1 <= signal_wire_3;
    end
    assign signal_not_1 = ~ signal_reg_1;
    assign led_n = signal_not_1;

endmodule
module gqh_reset_release (
    clock,
    reset_btn,
    reset
);

    input clock;
    input reset_btn;
    output reset;

    wire signal_const;
    wire signal_wire;
    wire signal_wire_1;
    wire gnd;
    reg signal_reg = 1'b1;
    reg signal_reg_1 = 1'b1;
    assign signal_const = 1'b1;
    assign signal_wire = reset_btn;
    assign signal_wire_1 = clock;
    assign gnd = 1'b0;
    always @(posedge signal_wire_1 or posedge signal_wire) begin
        if (signal_wire)
            signal_reg <= signal_const;
        else
            signal_reg <= gnd;
    end
    always @(posedge signal_wire_1 or posedge signal_wire) begin
        if (signal_wire)
            signal_reg_1 <= signal_const;
        else
            signal_reg_1 <= signal_reg;
    end
    assign reset = signal_reg_1;

endmodule
module gqh_top (
    sys_clk,
    reset_btn,
    uart_rx_i,
    uart_tx_o,
    led0_n,
    led1_n
);

    input sys_clk;
    input reset_btn;
    input uart_rx_i;
    output uart_tx_o;
    output led0_n;
    output led1_n;

    wire signal_wire;
    wire signal_inst;
    wire signal_wire_1;
    wire signal_wire_2;
    wire signal_inst_1;
    wire signal_wire_3;
    wire vdd;
    assign signal_wire = reset_btn;
    gqh_reset_release
        reset_release
        ( .clock(signal_wire_2),
          .reset_btn(signal_wire),
          .reset(signal_inst) );
    assign signal_wire_1 = signal_inst;
    assign signal_wire_2 = sys_clk;
    gqh_heartbeat
        heartbeat
        ( .clock(signal_wire_2),
          .reset(signal_wire_1),
          .led_n(signal_inst_1) );
    assign signal_wire_3 = signal_inst_1;
    assign vdd = 1'b1;
    assign uart_tx_o = vdd;
    assign led0_n = signal_wire_3;
    assign led1_n = vdd;

endmodule
