module gqh_update_engine (
    clock,
    reset,
    session_clear,
    update$item_select,
    update$price,
    update$window_position,
    update$warmup,
    update_valid,
    result_ready,
    update_ready,
    result_valid,
    action
);

    input clock;
    input reset;
    input session_clear;
    input update$item_select;
    input [15:0] update$price;
    input [3:0] update$window_position;
    input update$warmup;
    input update_valid;
    input result_ready;
    output update_ready;
    output result_valid;
    output [1:0] action;

    wire [1:0] signal_const;
    wire [1:0] signal_const_2;
    wire [1:0] signal_const_3;
    wire [1:0] signal_select;
    wire [1:0] signal_mux;
    wire signal_select_1;
    wire signal_and;
    wire signal_not;
    wire signal_and_1;
    wire [1:0] signal_mux_1;
    wire signal_and_2;
    wire signal_mux_2;
    wire signal_mux_3;
    wire signal_wire;
    reg signal_reg;
    wire signal_mux_4;
    wire signal_select_2;
    wire signal_mux_5;
    wire signal_mux_6;
    wire signal_wire_1;
    reg signal_reg_1;
    wire signal_xor;
    wire signal_not_1;
    wire signal_and_3;
    wire signal_not_2;
    wire signal_and_4;
    wire signal_or;
    wire signal_mux_7;
    wire signal_mux_8;
    wire signal_wire_2;
    reg signal_reg_2;
    wire signal_and_5;
    wire [3:0] signal_select_3;
    wire [8:0] signal_cat;
    (* syn_ramstyle="block_ram" *)
    reg [0:0] serial_history[0:511];
    wire [3:0] signal_select_4;
    wire [3:0] signal_wire_3;
    wire [8:0] signal_cat_1;
    wire signal_mem_read_port;
    reg signal_reg_3;
    wire signal_not_3;
    wire signal_and_6;
    wire signal_and_7;
    wire signal_xor_1;
    wire gnd;
    wire signal_xor_2;
    wire signal_and_8;
    wire signal_and_9;
    wire signal_or_1;
    wire signal_mux_9;
    wire signal_mux_10;
    wire signal_wire_4;
    reg signal_reg_4;
    wire signal_xor_3;
    wire signal_or_2;
    wire signal_and_10;
    wire signal_and_11;
    wire signal_wire_5;
    wire [5:0] signal_cat_2;
    (* syn_ramstyle="block_ram" *)
    reg [0:0] serial_sums[0:63];
    wire [4:0] signal_const_5;
    wire [4:0] signal_mux_11;
    wire [5:0] signal_cat_3;
    wire signal_mem_read_port_1;
    reg signal_reg_5;
    wire signal_and_12;
    wire signal_xor_4;
    wire signal_xor_5;
    wire signal_select_5;
    wire signal_select_6;
    wire signal_select_7;
    wire signal_select_8;
    wire signal_select_9;
    wire signal_select_10;
    wire signal_select_11;
    wire signal_select_12;
    wire signal_select_13;
    wire signal_select_14;
    wire signal_select_15;
    wire signal_select_16;
    wire signal_select_17;
    wire signal_select_18;
    wire signal_select_19;
    wire [15:0] signal_wire_6;
    wire signal_select_20;
    wire [3:0] signal_select_21;
    reg signal_mux_12;
    wire signal_select_22;
    wire signal_not_4;
    wire signal_and_13;
    wire [2:0] signal_select_23;
    wire [3:0] signal_cat_4;
    wire [3:0] signal_mux_13;
    wire [3:0] signal_wire_7;
    reg [3:0] signal_reg_6;
    wire signal_select_24;
    wire signal_xor_6;
    wire [4:0] signal_const_6;
    wire signal_lt;
    wire signal_not_5;
    wire signal_and_14;
    wire signal_mux_14;
    wire [3:0] signal_cat_5;
    wire [3:0] signal_wire_8;
    (* syn_ramstyle="block_ram" *)
    reg [3:0] serial_metadata[0:1];
    wire [3:0] signal_mem_read_port_2;
    reg [3:0] signal_reg_7;
    wire signal_select_25;
    wire signal_and_15;
    wire signal_const_7;
    reg record_valid_b;
    wire signal_not_6;
    wire signal_and_16;
    wire signal_and_17;
    wire signal_or_3;
    wire vdd;
    reg record_valid_a;
    wire signal_wire_9;
    wire signal_mux_15;
    wire signal_and_18;
    wire signal_not_7;
    wire signal_and_19;
    wire [1:0] signal_mux_16;
    wire signal_wire_10;
    wire [1:0] signal_mux_17;
    reg [1:0] signal_reg_8;
    wire [1:0] signal_const_9;
    wire signal_eq;
    wire signal_and_20;
    wire signal_wire_11;
    wire signal_not_8;
    wire [1:0] signal_mux_18;
    wire signal_wire_12;
    wire signal_not_9;
    wire [4:0] signal_const_15;
    wire signal_wire_13;
    wire [4:0] signal_const_17;
    wire [4:0] signal_add;
    wire [4:0] signal_mux_19;
    wire signal_wire_14;
    wire signal_and_21;
    wire [4:0] signal_mux_20;
    wire [4:0] signal_wire_15;
    reg [4:0] engine_digit;
    wire signal_eq_1;
    wire signal_and_22;
    wire signal_and_23;
    wire [1:0] signal_mux_21;
    wire signal_wire_16;
    wire [1:0] signal_mux_22;
    wire signal_eq_2;
    wire [1:0] signal_mux_23;
    wire signal_eq_3;
    wire [1:0] signal_mux_24;
    wire [1:0] signal_mux_25;
    wire [1:0] signal_wire_17;
    reg [1:0] engine_state;
    wire signal_eq_4;
    wire signal_and_24;
    wire signal_and_25;
    assign signal_const = 2'b00;
    assign signal_const_2 = 2'b10;
    assign signal_const_3 = 2'b01;
    assign signal_select = signal_reg_7[3:2];
    assign signal_mux = signal_mux_15 ? signal_select : signal_const;
    assign signal_select_1 = signal_reg_7[0:0];
    assign signal_and = signal_mux_15 & signal_select_1;
    assign signal_not = ~ signal_and;
    assign signal_and_1 = signal_not & signal_mux_4;
    assign signal_mux_1 = signal_and_1 ? signal_const_3 : signal_mux;
    assign signal_and_2 = signal_eq_3 & signal_not_9;
    assign signal_mux_2 = signal_eq_2 ? signal_mux_4 : signal_reg;
    assign signal_mux_3 = signal_and_21 ? gnd : signal_mux_2;
    assign signal_wire = signal_mux_3;
    always @(posedge signal_wire_13) begin
        signal_reg <= signal_wire;
    end
    assign signal_mux_4 = signal_and_14 ? signal_xor_5 : signal_reg;
    assign signal_select_2 = signal_reg_6[3:3];
    assign signal_mux_5 = signal_eq_2 ? signal_mux_14 : signal_reg_1;
    assign signal_mux_6 = signal_and_21 ? gnd : signal_mux_5;
    assign signal_wire_1 = signal_mux_6;
    always @(posedge signal_wire_13) begin
        signal_reg_1 <= signal_wire_1;
    end
    assign signal_xor = signal_xor_4 ^ signal_and_7;
    assign signal_not_1 = ~ signal_xor;
    assign signal_and_3 = signal_reg_2 & signal_not_1;
    assign signal_not_2 = ~ signal_xor_4;
    assign signal_and_4 = signal_not_2 & signal_and_7;
    assign signal_or = signal_and_4 | signal_and_3;
    assign signal_mux_7 = signal_eq_2 ? signal_or : signal_reg_2;
    assign signal_mux_8 = signal_and_21 ? gnd : signal_mux_7;
    assign signal_wire_2 = signal_mux_8;
    always @(posedge signal_wire_13) begin
        signal_reg_2 <= signal_wire_2;
    end
    assign signal_and_5 = signal_and_11 & signal_not_4;
    assign signal_select_3 = engine_digit[3:0];
    assign signal_cat = { signal_wire_9,
                          signal_wire_3,
                          signal_select_3 };
    always @(posedge signal_wire_13) begin
        if (signal_and_5)
            serial_history[signal_cat] <= signal_and_13;
    end
    assign signal_select_4 = signal_mux_11[3:0];
    assign signal_wire_3 = update$window_position;
    assign signal_cat_1 = { signal_wire_9,
                            signal_wire_3,
                            signal_select_4 };
    assign signal_mem_read_port = serial_history[signal_cat_1];
    always @(posedge signal_wire_13) begin
        if (signal_and_10)
            signal_reg_3 <= signal_mem_read_port;
    end
    assign signal_not_3 = ~ signal_wire_10;
    assign signal_and_6 = signal_not_3 & signal_not_4;
    assign signal_and_7 = signal_and_6 & signal_reg_3;
    assign signal_xor_1 = signal_and_7 ^ signal_reg_2;
    assign gnd = 1'b0;
    assign signal_xor_2 = signal_and_12 ^ signal_and_13;
    assign signal_and_8 = signal_reg_4 & signal_xor_2;
    assign signal_and_9 = signal_and_12 & signal_and_13;
    assign signal_or_1 = signal_and_9 | signal_and_8;
    assign signal_mux_9 = signal_eq_2 ? signal_or_1 : signal_reg_4;
    assign signal_mux_10 = signal_and_21 ? gnd : signal_mux_9;
    assign signal_wire_4 = signal_mux_10;
    always @(posedge signal_wire_13) begin
        signal_reg_4 <= signal_wire_4;
    end
    assign signal_xor_3 = signal_and_13 ^ signal_reg_4;
    assign signal_or_2 = signal_eq_3 | signal_eq_2;
    assign signal_and_10 = signal_or_2 & signal_not_9;
    assign signal_and_11 = signal_eq_2 & signal_not_9;
    assign signal_wire_5 = signal_xor_5;
    assign signal_cat_2 = { signal_wire_9,
                            engine_digit };
    always @(posedge signal_wire_13) begin
        if (signal_and_11)
            serial_sums[signal_cat_2] <= signal_wire_5;
    end
    assign signal_const_5 = 5'b00000;
    assign signal_mux_11 = signal_eq_3 ? signal_const_5 : signal_add;
    assign signal_cat_3 = { signal_wire_9,
                            signal_mux_11 };
    assign signal_mem_read_port_1 = serial_sums[signal_cat_3];
    always @(posedge signal_wire_13) begin
        if (signal_and_10)
            signal_reg_5 <= signal_mem_read_port_1;
    end
    assign signal_and_12 = signal_mux_15 & signal_reg_5;
    assign signal_xor_4 = signal_and_12 ^ signal_xor_3;
    assign signal_xor_5 = signal_xor_4 ^ signal_xor_1;
    assign signal_select_5 = signal_wire_6[15:15];
    assign signal_select_6 = signal_wire_6[14:14];
    assign signal_select_7 = signal_wire_6[13:13];
    assign signal_select_8 = signal_wire_6[12:12];
    assign signal_select_9 = signal_wire_6[11:11];
    assign signal_select_10 = signal_wire_6[10:10];
    assign signal_select_11 = signal_wire_6[9:9];
    assign signal_select_12 = signal_wire_6[8:8];
    assign signal_select_13 = signal_wire_6[7:7];
    assign signal_select_14 = signal_wire_6[6:6];
    assign signal_select_15 = signal_wire_6[5:5];
    assign signal_select_16 = signal_wire_6[4:4];
    assign signal_select_17 = signal_wire_6[3:3];
    assign signal_select_18 = signal_wire_6[2:2];
    assign signal_select_19 = signal_wire_6[1:1];
    assign signal_wire_6 = update$price;
    assign signal_select_20 = signal_wire_6[0:0];
    assign signal_select_21 = engine_digit[3:0];
    always @* begin
        case (signal_select_21)
        0:
            signal_mux_12 <= signal_select_20;
        1:
            signal_mux_12 <= signal_select_19;
        2:
            signal_mux_12 <= signal_select_18;
        3:
            signal_mux_12 <= signal_select_17;
        4:
            signal_mux_12 <= signal_select_16;
        5:
            signal_mux_12 <= signal_select_15;
        6:
            signal_mux_12 <= signal_select_14;
        7:
            signal_mux_12 <= signal_select_13;
        8:
            signal_mux_12 <= signal_select_12;
        9:
            signal_mux_12 <= signal_select_11;
        10:
            signal_mux_12 <= signal_select_10;
        11:
            signal_mux_12 <= signal_select_9;
        12:
            signal_mux_12 <= signal_select_8;
        13:
            signal_mux_12 <= signal_select_7;
        14:
            signal_mux_12 <= signal_select_6;
        default:
            signal_mux_12 <= signal_select_5;
        endcase
    end
    assign signal_select_22 = engine_digit[4:4];
    assign signal_not_4 = ~ signal_select_22;
    assign signal_and_13 = signal_not_4 & signal_mux_12;
    assign signal_select_23 = signal_reg_6[2:0];
    assign signal_cat_4 = { signal_select_23,
                            signal_and_13 };
    assign signal_mux_13 = signal_eq_2 ? signal_cat_4 : signal_reg_6;
    assign signal_wire_7 = signal_mux_13;
    always @(posedge signal_wire_13) begin
        signal_reg_6 <= signal_wire_7;
    end
    assign signal_select_24 = signal_reg_6[3:3];
    assign signal_xor_6 = signal_select_24 ^ signal_xor_5;
    assign signal_const_6 = 5'b00100;
    assign signal_lt = engine_digit < signal_const_6;
    assign signal_not_5 = ~ signal_lt;
    assign signal_and_14 = signal_not_5 & signal_xor_6;
    assign signal_mux_14 = signal_and_14 ? signal_select_2 : signal_reg_1;
    assign signal_cat_5 = { signal_mux_17,
                            signal_mux_14,
                            signal_mux_4 };
    assign signal_wire_8 = signal_cat_5;
    always @(posedge signal_wire_13) begin
        if (signal_and_23)
            serial_metadata[signal_wire_9] <= signal_wire_8;
    end
    assign signal_mem_read_port_2 = serial_metadata[signal_wire_9];
    always @(posedge signal_wire_13) begin
        if (signal_and_2)
            signal_reg_7 <= signal_mem_read_port_2;
    end
    assign signal_select_25 = signal_reg_7[1:1];
    assign signal_and_15 = signal_and_23 & signal_wire_9;
    assign signal_const_7 = 1'b0;
    always @(posedge signal_wire_13) begin
        if (signal_or_3)
            record_valid_b <= signal_const_7;
        else
            if (signal_and_15)
                record_valid_b <= vdd;
    end
    assign signal_not_6 = ~ signal_wire_9;
    assign signal_and_16 = signal_and_23 & signal_not_6;
    assign signal_and_17 = signal_eq_4 & signal_wire_11;
    assign signal_or_3 = signal_wire_12 | signal_and_17;
    assign vdd = 1'b1;
    always @(posedge signal_wire_13) begin
        if (signal_or_3)
            record_valid_a <= signal_const_7;
        else
            if (signal_and_16)
                record_valid_a <= vdd;
    end
    assign signal_wire_9 = update$item_select;
    assign signal_mux_15 = signal_wire_9 ? record_valid_b : record_valid_a;
    assign signal_and_18 = signal_mux_15 & signal_select_25;
    assign signal_not_7 = ~ signal_and_18;
    assign signal_and_19 = signal_not_7 & signal_mux_14;
    assign signal_mux_16 = signal_and_19 ? signal_const_2 : signal_mux_1;
    assign signal_wire_10 = update$warmup;
    assign signal_mux_17 = signal_wire_10 ? signal_const : signal_mux_16;
    always @(posedge signal_wire_13) begin
        if (signal_or_3)
            signal_reg_8 <= signal_const;
        else
            if (signal_and_23)
                signal_reg_8 <= signal_mux_17;
    end
    assign signal_const_9 = 2'b11;
    assign signal_eq = engine_state == signal_const_9;
    assign signal_and_20 = signal_eq & signal_not_9;
    assign signal_wire_11 = session_clear;
    assign signal_not_8 = ~ signal_wire_11;
    assign signal_mux_18 = signal_and_21 ? signal_const_3 : engine_state;
    assign signal_wire_12 = reset;
    assign signal_not_9 = ~ signal_wire_12;
    assign signal_const_15 = 5'b10011;
    assign signal_wire_13 = clock;
    assign signal_const_17 = 5'b00001;
    assign signal_add = engine_digit + signal_const_17;
    assign signal_mux_19 = signal_eq_2 ? signal_add : engine_digit;
    assign signal_wire_14 = update_valid;
    assign signal_and_21 = signal_and_25 & signal_wire_14;
    assign signal_mux_20 = signal_and_21 ? signal_const_5 : signal_mux_19;
    assign signal_wire_15 = signal_mux_20;
    always @(posedge signal_wire_13) begin
        engine_digit <= signal_wire_15;
    end
    assign signal_eq_1 = engine_digit == signal_const_15;
    assign signal_and_22 = signal_eq_2 & signal_eq_1;
    assign signal_and_23 = signal_and_22 & signal_not_9;
    assign signal_mux_21 = signal_and_23 ? signal_const_9 : engine_state;
    assign signal_wire_16 = result_ready;
    assign signal_mux_22 = signal_wire_16 ? signal_const : engine_state;
    assign signal_eq_2 = engine_state == signal_const_2;
    assign signal_mux_23 = signal_eq_2 ? signal_mux_21 : signal_mux_22;
    assign signal_eq_3 = engine_state == signal_const_3;
    assign signal_mux_24 = signal_eq_3 ? signal_const_2 : signal_mux_23;
    assign signal_mux_25 = signal_eq_4 ? signal_mux_18 : signal_mux_24;
    assign signal_wire_17 = signal_mux_25;
    always @(posedge signal_wire_13) begin
        if (signal_wire_12)
            engine_state <= signal_const;
        else
            engine_state <= signal_wire_17;
    end
    assign signal_eq_4 = engine_state == signal_const;
    assign signal_and_24 = signal_eq_4 & signal_not_9;
    assign signal_and_25 = signal_and_24 & signal_not_8;
    assign update_ready = signal_and_25;
    assign result_valid = signal_and_20;
    assign action = signal_reg_8;

endmodule
