module gqh_uart_tx (
    clock,
    reset,
    tx_data,
    tx_valid,
    tx,
    tx_ready,
    tx_busy
);

    input clock;
    input reset;
    input [7:0] tx_data;
    input tx_valid;
    output tx;
    output tx_ready;
    output tx_busy;

    wire signal_eq;
    wire signal_not;
    wire signal_not_1;
    wire signal_eq_1;
    wire signal_and;
    wire gnd;
    wire signal_select;
    wire signal_select_1;
    wire signal_select_2;
    wire signal_select_3;
    wire signal_select_4;
    wire signal_select_5;
    wire signal_select_6;
    wire [7:0] signal_const;
    wire [7:0] signal_wire;
    wire [7:0] signal_mux;
    reg [7:0] signal_cases;
    wire [7:0] signal_wire_1;
    reg [7:0] signal_reg;
    wire signal_select_7;
    reg signal_mux_1;
    wire vdd;
    wire signal_eq_2;
    wire signal_mux_2;
    wire [2:0] signal_const_1;
    wire [2:0] signal_mux_3;
    wire [2:0] signal_mux_4;
    wire [2:0] signal_const_11;
    wire [2:0] signal_const_2;
    wire [2:0] signal_const_4;
    wire [2:0] signal_add;
    wire [2:0] signal_mux_5;
    wire [2:0] signal_mux_6;
    wire [2:0] signal_mux_7;
    reg [2:0] signal_cases_1;
    wire [2:0] signal_wire_2;
    reg [2:0] signal_reg_1;
    wire signal_eq_3;
    wire [2:0] signal_mux_8;
    wire [2:0] signal_mux_9;
    wire [2:0] signal_const_14;
    wire signal_wire_3;
    wire [7:0] signal_const_8;
    wire [7:0] signal_sub;
    wire [7:0] signal_mux_10;
    wire [7:0] signal_sub_1;
    wire [7:0] signal_mux_11;
    wire [7:0] signal_const_12;
    wire [7:0] signal_sub_2;
    wire [7:0] signal_mux_12;
    wire [7:0] signal_sub_3;
    wire [7:0] signal_mux_13;
    wire [7:0] signal_mux_14;
    reg [7:0] signal_cases_2;
    wire [7:0] signal_wire_4;
    reg [7:0] signal_reg_2;
    wire signal_eq_4;
    wire [2:0] signal_mux_15;
    wire signal_wire_5;
    wire [2:0] signal_mux_16;
    reg [2:0] signal_cases_3;
    wire [2:0] signal_wire_6;
    (* fsm_encoding="one_hot" *)
    reg [2:0] signal_reg_3;
    wire signal_eq_5;
    wire signal_mux_17;
    wire signal_wire_7;
    wire signal_mux_18;
    assign signal_eq = signal_const_1 == signal_reg_3;
    assign signal_not = ~ signal_eq;
    assign signal_not_1 = ~ signal_wire_7;
    assign signal_eq_1 = signal_const_1 == signal_reg_3;
    assign signal_and = signal_eq_1 & signal_not_1;
    assign gnd = 1'b0;
    assign signal_select = signal_reg[7:7];
    assign signal_select_1 = signal_reg[6:6];
    assign signal_select_2 = signal_reg[5:5];
    assign signal_select_3 = signal_reg[4:4];
    assign signal_select_4 = signal_reg[3:3];
    assign signal_select_5 = signal_reg[2:2];
    assign signal_select_6 = signal_reg[1:1];
    assign signal_const = 8'b00000000;
    assign signal_wire = tx_data;
    assign signal_mux = signal_wire_5 ? signal_wire : signal_reg;
    always @* begin
        case (signal_reg_3)
        3'b000:
            signal_cases <= signal_mux;
        default:
            signal_cases <= signal_reg;
        endcase
    end
    assign signal_wire_1 = signal_cases;
    always @(posedge signal_wire_3) begin
        if (signal_wire_7)
            signal_reg <= signal_const;
        else
            signal_reg <= signal_wire_1;
    end
    assign signal_select_7 = signal_reg[0:0];
    always @* begin
        case (signal_reg_1)
        0:
            signal_mux_1 <= signal_select_7;
        1:
            signal_mux_1 <= signal_select_6;
        2:
            signal_mux_1 <= signal_select_5;
        3:
            signal_mux_1 <= signal_select_4;
        4:
            signal_mux_1 <= signal_select_3;
        5:
            signal_mux_1 <= signal_select_2;
        6:
            signal_mux_1 <= signal_select_1;
        default:
            signal_mux_1 <= signal_select;
        endcase
    end
    assign vdd = 1'b1;
    assign signal_eq_2 = signal_const_14 == signal_reg_3;
    assign signal_mux_2 = signal_eq_2 ? signal_mux_1 : vdd;
    assign signal_const_1 = 3'b000;
    assign signal_mux_3 = signal_eq_4 ? signal_const_1 : signal_reg_3;
    assign signal_mux_4 = signal_eq_4 ? signal_const_1 : signal_reg_3;
    assign signal_const_11 = 3'b011;
    assign signal_const_2 = 3'b111;
    assign signal_const_4 = 3'b001;
    assign signal_add = signal_reg_1 + signal_const_4;
    assign signal_mux_5 = signal_eq_3 ? signal_reg_1 : signal_add;
    assign signal_mux_6 = signal_eq_4 ? signal_mux_5 : signal_reg_1;
    assign signal_mux_7 = signal_wire_5 ? signal_const_1 : signal_reg_1;
    always @* begin
        case (signal_reg_3)
        3'b000:
            signal_cases_1 <= signal_mux_7;
        3'b010:
            signal_cases_1 <= signal_mux_6;
        default:
            signal_cases_1 <= signal_reg_1;
        endcase
    end
    assign signal_wire_2 = signal_cases_1;
    always @(posedge signal_wire_3) begin
        if (signal_wire_7)
            signal_reg_1 <= signal_const_1;
        else
            signal_reg_1 <= signal_wire_2;
    end
    assign signal_eq_3 = signal_reg_1 == signal_const_2;
    assign signal_mux_8 = signal_eq_3 ? signal_const_11 : signal_reg_3;
    assign signal_mux_9 = signal_eq_4 ? signal_mux_8 : signal_reg_3;
    assign signal_const_14 = 3'b010;
    assign signal_wire_3 = clock;
    assign signal_const_8 = 8'b00000001;
    assign signal_sub = signal_reg_2 - signal_const_8;
    assign signal_mux_10 = signal_eq_4 ? signal_reg_2 : signal_sub;
    assign signal_sub_1 = signal_reg_2 - signal_const_8;
    assign signal_mux_11 = signal_eq_4 ? signal_reg_2 : signal_sub_1;
    assign signal_const_12 = 8'b11101001;
    assign signal_sub_2 = signal_reg_2 - signal_const_8;
    assign signal_mux_12 = signal_eq_4 ? signal_const_12 : signal_sub_2;
    assign signal_sub_3 = signal_reg_2 - signal_const_8;
    assign signal_mux_13 = signal_eq_4 ? signal_const_12 : signal_sub_3;
    assign signal_mux_14 = signal_wire_5 ? signal_const_12 : signal_reg_2;
    always @* begin
        case (signal_reg_3)
        3'b000:
            signal_cases_2 <= signal_mux_14;
        3'b001:
            signal_cases_2 <= signal_mux_13;
        3'b010:
            signal_cases_2 <= signal_mux_12;
        3'b011:
            signal_cases_2 <= signal_mux_11;
        3'b100:
            signal_cases_2 <= signal_mux_10;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_wire_4 = signal_cases_2;
    always @(posedge signal_wire_3) begin
        if (signal_wire_7)
            signal_reg_2 <= signal_const;
        else
            signal_reg_2 <= signal_wire_4;
    end
    assign signal_eq_4 = signal_reg_2 == signal_const;
    assign signal_mux_15 = signal_eq_4 ? signal_const_14 : signal_reg_3;
    assign signal_wire_5 = tx_valid;
    assign signal_mux_16 = signal_wire_5 ? signal_const_4 : signal_reg_3;
    always @* begin
        case (signal_reg_3)
        3'b000:
            signal_cases_3 <= signal_mux_16;
        3'b001:
            signal_cases_3 <= signal_mux_15;
        3'b010:
            signal_cases_3 <= signal_mux_9;
        3'b011:
            signal_cases_3 <= signal_mux_4;
        3'b100:
            signal_cases_3 <= signal_mux_3;
        default:
            signal_cases_3 <= signal_reg_3;
        endcase
    end
    assign signal_wire_6 = signal_cases_3;
    always @(posedge signal_wire_3) begin
        if (signal_wire_7)
            signal_reg_3 <= signal_const_1;
        else
            signal_reg_3 <= signal_wire_6;
    end
    assign signal_eq_5 = signal_const_4 == signal_reg_3;
    assign signal_mux_17 = signal_eq_5 ? gnd : signal_mux_2;
    assign signal_wire_7 = reset;
    assign signal_mux_18 = signal_wire_7 ? vdd : signal_mux_17;
    assign tx = signal_mux_18;
    assign tx_ready = signal_and;
    assign tx_busy = signal_not;

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
module gqh_packet_ram_controller (
    clock,
    reset,
    byte_data,
    byte_valid,
    framing_error,
    update_ready,
    result_valid,
    action,
    tx_ready,
    tx_busy,
    update$item_select,
    update$price,
    update$window_position,
    update$warmup,
    update_valid,
    result_ready,
    session_clear,
    tx_data,
    tx_valid,
    protocol_fault
);

    input clock;
    input reset;
    input [7:0] byte_data;
    input byte_valid;
    input framing_error;
    input update_ready;
    input result_valid;
    input [1:0] action;
    input tx_ready;
    input tx_busy;
    output update$item_select;
    output [15:0] update$price;
    output [3:0] update$window_position;
    output update$warmup;
    output update_valid;
    output result_ready;
    output session_clear;
    output [7:0] tx_data;
    output tx_valid;
    output protocol_fault;

    wire signal_eq;
    wire signal_and;
    wire [7:0] signal_const;
    wire [1:0] signal_const_2;
    wire [1:0] signal_mux;
    wire [1:0] signal_mux_1;
    reg [1:0] signal_cases;
    wire [1:0] signal_wire;
    reg [1:0] signal_reg;
    wire [5:0] signal_const_3;
    wire [7:0] signal_cat;
    wire [1:0] signal_wire_1;
    wire [1:0] signal_mux_2;
    wire [1:0] signal_mux_3;
    reg [1:0] signal_cases_1;
    wire [1:0] signal_wire_2;
    reg [1:0] signal_reg_1;
    wire [7:0] signal_cat_1;
    reg [7:0] signal_mux_4;
    wire signal_eq_1;
    wire signal_and_1;
    wire signal_eq_2;
    wire signal_and_2;
    wire signal_eq_3;
    wire signal_and_3;
    wire signal_const_6;
    wire [7:0] signal_const_7;
    wire signal_lt;
    wire signal_and_4;
    reg signal_cases_2;
    wire signal_mux_5;
    reg signal_cases_3;
    wire signal_wire_3;
    reg signal_reg_2;
    wire [3:0] signal_const_8;
    wire [3:0] signal_const_9;
    wire [3:0] signal_add;
    wire [3:0] signal_mux_6;
    wire [3:0] signal_mux_7;
    wire [3:0] signal_mux_8;
    wire [3:0] signal_mux_9;
    wire [3:0] signal_mux_10;
    reg [3:0] signal_cases_4;
    wire [3:0] signal_wire_4;
    reg [3:0] signal_reg_3;
    reg [7:0] signal_cases_5;
    wire [7:0] signal_wire_5;
    reg [7:0] signal_reg_4;
    wire [15:0] signal_cat_2;
    wire [7:0] signal_const_13;
    wire signal_eq_4;
    wire signal_eq_5;
    wire signal_eq_6;
    wire signal_eq_7;
    wire signal_or;
    wire signal_or_1;
    wire signal_or_2;
    wire signal_and_5;
    (* syn_ramstyle="block_ram" *)
    reg [7:0] request_packet[0:7];
    wire [2:0] signal_const_14;
    wire [2:0] signal_const_17;
    wire [2:0] signal_const_19;
    wire [2:0] signal_const_20;
    reg [2:0] signal_mux_11;
    wire [2:0] signal_mux_12;
    wire [2:0] signal_const_24;
    wire [2:0] signal_const_25;
    wire [2:0] signal_mux_13;
    wire [2:0] signal_const_26;
    wire [2:0] signal_const_27;
    wire [2:0] signal_mux_14;
    wire signal_eq_8;
    wire [2:0] signal_mux_15;
    wire signal_eq_9;
    wire [2:0] signal_mux_16;
    wire signal_eq_10;
    wire [2:0] signal_mux_17;
    wire [7:0] signal_mem_read_port;
    reg [7:0] signal_reg_5;
    wire signal_eq_11;
    wire [3:0] signal_mux_18;
    wire [3:0] signal_const_49;
    wire [3:0] signal_mux_19;
    wire [3:0] signal_mux_20;
    wire [3:0] signal_const_52;
    wire [3:0] signal_const_29;
    wire signal_const_31;
    wire signal_mux_21;
    wire signal_mux_22;
    wire signal_mux_23;
    wire signal_mux_24;
    reg signal_cases_6;
    wire signal_wire_6;
    reg signal_reg_6;
    wire [3:0] signal_mux_25;
    wire [3:0] signal_mux_26;
    wire [3:0] signal_const_33;
    wire [3:0] signal_mux_27;
    wire [3:0] signal_const_34;
    wire [3:0] signal_const_35;
    wire [3:0] signal_const_36;
    wire [3:0] signal_const_37;
    wire signal_wire_7;
    wire signal_not;
    wire signal_wire_8;
    wire signal_and_6;
    wire [3:0] signal_mux_28;
    wire [3:0] signal_const_39;
    wire signal_eq_12;
    wire [7:0] signal_wire_9;
    wire signal_eq_13;
    reg signal_cases_7;
    wire signal_mux_29;
    reg signal_cases_8;
    wire signal_wire_10;
    reg signal_reg_7;
    wire signal_and_7;
    reg signal_cases_9;
    wire signal_mux_30;
    reg signal_cases_10;
    wire signal_wire_11;
    reg signal_reg_8;
    wire [3:0] signal_mux_31;
    wire signal_wire_12;
    wire signal_not_1;
    wire [2:0] signal_mux_32;
    wire [2:0] signal_add_1;
    wire signal_eq_14;
    wire [2:0] signal_mux_33;
    wire signal_wire_13;
    wire [2:0] signal_mux_34;
    wire [2:0] signal_add_2;
    wire [2:0] signal_mux_35;
    wire signal_eq_15;
    wire [2:0] signal_mux_36;
    wire [2:0] signal_mux_37;
    wire [2:0] signal_mux_38;
    reg [2:0] signal_cases_11;
    wire [2:0] signal_wire_14;
    reg [2:0] packet_position;
    wire signal_eq_16;
    wire [3:0] signal_mux_39;
    wire signal_not_2;
    wire signal_not_3;
    wire signal_wire_15;
    wire signal_wire_16;
    wire signal_wire_17;
    wire signal_mux_40;
    wire signal_not_4;
    wire signal_wire_18;
    wire signal_and_8;
    wire signal_mux_41;
    wire signal_wire_19;
    reg signal_reg_9;
    wire signal_not_5;
    wire signal_eq_17;
    wire packet_receiving;
    wire signal_and_9;
    wire signal_and_10;
    wire signal_and_11;
    wire [3:0] signal_mux_42;
    reg [3:0] signal_cases_12;
    wire [3:0] signal_wire_20;
    (* fsm_encoding="one_hot" *)
    reg [3:0] signal_reg_10;
    reg signal_cases_13;
    wire signal_wire_21;
    reg signal_reg_11;
    assign signal_eq = signal_const_52 == signal_reg_10;
    assign signal_and = signal_eq & signal_not_2;
    assign signal_const = 8'b00000000;
    assign signal_const_2 = 2'b00;
    assign signal_mux = signal_reg_6 ? signal_wire_1 : signal_reg;
    assign signal_mux_1 = signal_wire_7 ? signal_mux : signal_reg;
    always @* begin
        case (signal_reg_10)
        4'b0111:
            signal_cases <= signal_mux_1;
        default:
            signal_cases <= signal_reg;
        endcase
    end
    assign signal_wire = signal_cases;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg <= signal_const_2;
        else
            signal_reg <= signal_wire;
    end
    assign signal_const_3 = 6'b000000;
    assign signal_cat = { signal_const_3,
                          signal_reg };
    assign signal_wire_1 = action;
    assign signal_mux_2 = signal_reg_6 ? signal_reg_1 : signal_wire_1;
    assign signal_mux_3 = signal_wire_7 ? signal_mux_2 : signal_reg_1;
    always @* begin
        case (signal_reg_10)
        4'b0111:
            signal_cases_1 <= signal_mux_3;
        default:
            signal_cases_1 <= signal_reg_1;
        endcase
    end
    assign signal_wire_2 = signal_cases_1;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_1 <= signal_const_2;
        else
            signal_reg_1 <= signal_wire_2;
    end
    assign signal_cat_1 = { signal_const_3,
                            signal_reg_1 };
    always @* begin
        case (packet_position)
        0:
            signal_mux_4 <= signal_reg_5;
        1:
            signal_mux_4 <= signal_reg_5;
        2:
            signal_mux_4 <= signal_reg_5;
        3:
            signal_mux_4 <= signal_cat_1;
        4:
            signal_mux_4 <= signal_reg_5;
        5:
            signal_mux_4 <= signal_cat;
        6:
            signal_mux_4 <= signal_const;
        default:
            signal_mux_4 <= signal_const;
        endcase
    end
    assign signal_eq_1 = signal_const_37 == signal_reg_10;
    assign signal_and_1 = signal_eq_1 & signal_not_2;
    assign signal_eq_2 = signal_const_33 == signal_reg_10;
    assign signal_and_2 = signal_eq_2 & signal_not_2;
    assign signal_eq_3 = signal_const_34 == signal_reg_10;
    assign signal_and_3 = signal_eq_3 & signal_not_2;
    assign signal_const_6 = 1'b0;
    assign signal_const_7 = 8'b00010000;
    assign signal_lt = signal_wire_9 < signal_const_7;
    assign signal_and_4 = signal_reg_7 & signal_lt;
    always @* begin
        case (packet_position)
        3'b001:
            signal_cases_2 <= signal_and_4;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_mux_5 = signal_and_11 ? signal_cases_2 : signal_reg_2;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_3 <= signal_mux_5;
        default:
            signal_cases_3 <= signal_reg_2;
        endcase
    end
    assign signal_wire_3 = signal_cases_3;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_2 <= signal_const_6;
        else
            signal_reg_2 <= signal_wire_3;
    end
    assign signal_const_8 = 4'b0000;
    assign signal_const_9 = 4'b0001;
    assign signal_add = signal_reg_3 + signal_const_9;
    assign signal_mux_6 = signal_reg_6 ? signal_add : signal_reg_3;
    assign signal_mux_7 = signal_wire_7 ? signal_mux_6 : signal_reg_3;
    assign signal_mux_8 = signal_reg_8 ? signal_const_8 : signal_reg_3;
    assign signal_mux_9 = signal_eq_16 ? signal_mux_8 : signal_reg_3;
    assign signal_mux_10 = signal_and_11 ? signal_mux_9 : signal_reg_3;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_4 <= signal_mux_10;
        4'b0111:
            signal_cases_4 <= signal_mux_7;
        default:
            signal_cases_4 <= signal_reg_3;
        endcase
    end
    assign signal_wire_4 = signal_cases_4;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_3 <= signal_const_8;
        else
            signal_reg_3 <= signal_wire_4;
    end
    always @* begin
        case (signal_reg_10)
        4'b0101:
            signal_cases_5 <= signal_reg_5;
        default:
            signal_cases_5 <= signal_reg_4;
        endcase
    end
    assign signal_wire_5 = signal_cases_5;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_4 <= signal_const;
        else
            signal_reg_4 <= signal_wire_5;
    end
    assign signal_cat_2 = { signal_reg_4,
                            signal_reg_5 };
    assign signal_const_13 = 8'b00100010;
    assign signal_eq_4 = signal_const_29 == signal_reg_10;
    assign signal_eq_5 = signal_const_35 == signal_reg_10;
    assign signal_eq_6 = signal_const_36 == signal_reg_10;
    assign signal_eq_7 = signal_const_39 == signal_reg_10;
    assign signal_or = signal_eq_7 | signal_eq_6;
    assign signal_or_1 = signal_or | signal_eq_5;
    assign signal_or_2 = signal_or_1 | signal_eq_4;
    assign signal_and_5 = signal_or_2 & signal_not_2;
    always @(posedge signal_wire_16) begin
        if (signal_and_11)
            request_packet[packet_position] <= signal_wire_9;
    end
    assign signal_const_14 = 3'b000;
    assign signal_const_17 = 3'b101;
    assign signal_const_19 = 3'b010;
    assign signal_const_20 = 3'b001;
    always @* begin
        case (packet_position)
        0:
            signal_mux_11 <= signal_const_14;
        1:
            signal_mux_11 <= signal_const_20;
        2:
            signal_mux_11 <= signal_const_19;
        3:
            signal_mux_11 <= signal_const_14;
        4:
            signal_mux_11 <= signal_const_17;
        5:
            signal_mux_11 <= signal_const_14;
        6:
            signal_mux_11 <= signal_const_14;
        default:
            signal_mux_11 <= signal_const_14;
        endcase
    end
    assign signal_mux_12 = signal_reg_6 ? signal_const_17 : signal_const_19;
    assign signal_const_24 = 3'b110;
    assign signal_const_25 = 3'b011;
    assign signal_mux_13 = signal_reg_6 ? signal_const_24 : signal_const_25;
    assign signal_const_26 = 3'b111;
    assign signal_const_27 = 3'b100;
    assign signal_mux_14 = signal_reg_6 ? signal_const_26 : signal_const_27;
    assign signal_eq_8 = signal_const_36 == signal_reg_10;
    assign signal_mux_15 = signal_eq_8 ? signal_mux_13 : signal_mux_14;
    assign signal_eq_9 = signal_const_39 == signal_reg_10;
    assign signal_mux_16 = signal_eq_9 ? signal_mux_12 : signal_mux_15;
    assign signal_eq_10 = signal_const_29 == signal_reg_10;
    assign signal_mux_17 = signal_eq_10 ? signal_mux_11 : signal_mux_16;
    assign signal_mem_read_port = request_packet[signal_mux_17];
    always @(posedge signal_wire_16) begin
        if (signal_and_5)
            signal_reg_5 <= signal_mem_read_port;
    end
    assign signal_eq_11 = signal_reg_5 == signal_const_13;
    assign signal_mux_18 = signal_not_1 ? signal_const_8 : signal_reg_10;
    assign signal_const_49 = 4'b1010;
    assign signal_mux_19 = signal_eq_14 ? signal_const_49 : signal_const_29;
    assign signal_mux_20 = signal_wire_13 ? signal_mux_19 : signal_reg_10;
    assign signal_const_52 = 4'b1001;
    assign signal_const_29 = 4'b1000;
    assign signal_const_31 = 1'b1;
    assign signal_mux_21 = signal_reg_6 ? signal_reg_6 : signal_const_31;
    assign signal_mux_22 = signal_wire_7 ? signal_mux_21 : signal_reg_6;
    assign signal_mux_23 = signal_eq_16 ? signal_const_6 : signal_reg_6;
    assign signal_mux_24 = signal_and_11 ? signal_mux_23 : signal_reg_6;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_6 <= signal_mux_24;
        4'b0111:
            signal_cases_6 <= signal_mux_22;
        default:
            signal_cases_6 <= signal_reg_6;
        endcase
    end
    assign signal_wire_6 = signal_cases_6;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_6 <= signal_const_6;
        else
            signal_reg_6 <= signal_wire_6;
    end
    assign signal_mux_25 = signal_reg_6 ? signal_const_29 : signal_const_39;
    assign signal_mux_26 = signal_wire_7 ? signal_mux_25 : signal_reg_10;
    assign signal_const_33 = 4'b0111;
    assign signal_mux_27 = signal_wire_8 ? signal_const_33 : signal_reg_10;
    assign signal_const_34 = 4'b0110;
    assign signal_const_35 = 4'b0101;
    assign signal_const_36 = 4'b0100;
    assign signal_const_37 = 4'b0010;
    assign signal_wire_7 = result_valid;
    assign signal_not = ~ signal_wire_7;
    assign signal_wire_8 = update_ready;
    assign signal_and_6 = signal_wire_8 & signal_not;
    assign signal_mux_28 = signal_and_6 ? signal_const_37 : signal_reg_10;
    assign signal_const_39 = 4'b0011;
    assign signal_eq_12 = signal_wire_9 == signal_const;
    assign signal_wire_9 = byte_data;
    assign signal_eq_13 = signal_wire_9 == signal_const;
    always @* begin
        case (packet_position)
        3'b000:
            signal_cases_7 <= signal_eq_13;
        default:
            signal_cases_7 <= signal_reg_7;
        endcase
    end
    assign signal_mux_29 = signal_and_11 ? signal_cases_7 : signal_reg_7;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_8 <= signal_mux_29;
        default:
            signal_cases_8 <= signal_reg_7;
        endcase
    end
    assign signal_wire_10 = signal_cases_8;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_7 <= signal_const_6;
        else
            signal_reg_7 <= signal_wire_10;
    end
    assign signal_and_7 = signal_reg_7 & signal_eq_12;
    always @* begin
        case (packet_position)
        3'b001:
            signal_cases_9 <= signal_and_7;
        default:
            signal_cases_9 <= signal_reg_8;
        endcase
    end
    assign signal_mux_30 = signal_and_11 ? signal_cases_9 : signal_reg_8;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_10 <= signal_mux_30;
        default:
            signal_cases_10 <= signal_reg_8;
        endcase
    end
    assign signal_wire_11 = signal_cases_10;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_8 <= signal_const_6;
        else
            signal_reg_8 <= signal_wire_11;
    end
    assign signal_mux_31 = signal_reg_8 ? signal_const_9 : signal_const_39;
    assign signal_wire_12 = tx_busy;
    assign signal_not_1 = ~ signal_wire_12;
    assign signal_mux_32 = signal_not_1 ? signal_const_14 : signal_mux_37;
    assign signal_add_1 = packet_position + signal_const_20;
    assign signal_eq_14 = packet_position == signal_const_26;
    assign signal_mux_33 = signal_eq_14 ? signal_mux_37 : signal_add_1;
    assign signal_wire_13 = tx_ready;
    assign signal_mux_34 = signal_wire_13 ? signal_mux_33 : signal_mux_37;
    assign signal_add_2 = packet_position + signal_const_20;
    assign signal_mux_35 = signal_eq_16 ? signal_const_14 : signal_add_2;
    assign signal_eq_15 = signal_const_8 == signal_reg_10;
    assign signal_mux_36 = signal_eq_15 ? signal_const_14 : packet_position;
    assign signal_mux_37 = signal_wire_17 ? signal_mux_36 : packet_position;
    assign signal_mux_38 = signal_and_11 ? signal_mux_35 : signal_mux_37;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_11 <= signal_mux_38;
        4'b1001:
            signal_cases_11 <= signal_mux_34;
        4'b1010:
            signal_cases_11 <= signal_mux_32;
        default:
            signal_cases_11 <= signal_mux_37;
        endcase
    end
    assign signal_wire_14 = signal_cases_11;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            packet_position <= signal_const_14;
        else
            packet_position <= signal_wire_14;
    end
    assign signal_eq_16 = packet_position == signal_const_26;
    assign signal_mux_39 = signal_eq_16 ? signal_mux_31 : signal_reg_10;
    assign signal_not_2 = ~ signal_wire_15;
    assign signal_not_3 = ~ signal_wire_17;
    assign signal_wire_15 = reset;
    assign signal_wire_16 = clock;
    assign signal_wire_17 = framing_error;
    assign signal_mux_40 = signal_wire_17 ? signal_const_31 : signal_reg_9;
    assign signal_not_4 = ~ packet_receiving;
    assign signal_wire_18 = byte_valid;
    assign signal_and_8 = signal_wire_18 & signal_not_4;
    assign signal_mux_41 = signal_and_8 ? signal_const_31 : signal_mux_40;
    assign signal_wire_19 = signal_mux_41;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_9 <= signal_const_6;
        else
            signal_reg_9 <= signal_wire_19;
    end
    assign signal_not_5 = ~ signal_reg_9;
    assign signal_eq_17 = signal_const_8 == signal_reg_10;
    assign packet_receiving = signal_eq_17 & signal_not_5;
    assign signal_and_9 = packet_receiving & signal_wire_18;
    assign signal_and_10 = signal_and_9 & signal_not_3;
    assign signal_and_11 = signal_and_10 & signal_not_2;
    assign signal_mux_42 = signal_and_11 ? signal_mux_39 : signal_reg_10;
    always @* begin
        case (signal_reg_10)
        4'b0000:
            signal_cases_12 <= signal_mux_42;
        4'b0001:
            signal_cases_12 <= signal_mux_28;
        4'b0010:
            signal_cases_12 <= signal_const_39;
        4'b0011:
            signal_cases_12 <= signal_const_36;
        4'b0100:
            signal_cases_12 <= signal_const_35;
        4'b0101:
            signal_cases_12 <= signal_const_34;
        4'b0110:
            signal_cases_12 <= signal_mux_27;
        4'b0111:
            signal_cases_12 <= signal_mux_26;
        4'b1000:
            signal_cases_12 <= signal_const_52;
        4'b1001:
            signal_cases_12 <= signal_mux_20;
        4'b1010:
            signal_cases_12 <= signal_mux_18;
        default:
            signal_cases_12 <= signal_reg_10;
        endcase
    end
    assign signal_wire_20 = signal_cases_12;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_10 <= signal_const_8;
        else
            signal_reg_10 <= signal_wire_20;
    end
    always @* begin
        case (signal_reg_10)
        4'b0100:
            signal_cases_13 <= signal_eq_11;
        default:
            signal_cases_13 <= signal_reg_11;
        endcase
    end
    assign signal_wire_21 = signal_cases_13;
    always @(posedge signal_wire_16) begin
        if (signal_wire_15)
            signal_reg_11 <= signal_const_6;
        else
            signal_reg_11 <= signal_wire_21;
    end
    assign update$item_select = signal_reg_11;
    assign update$price = signal_cat_2;
    assign update$window_position = signal_reg_3;
    assign update$warmup = signal_reg_2;
    assign update_valid = signal_and_3;
    assign result_ready = signal_and_2;
    assign session_clear = signal_and_1;
    assign tx_data = signal_mux_4;
    assign tx_valid = signal_and;
    assign protocol_fault = signal_reg_9;

endmodule
module gqh_uart_rx (
    clock,
    reset,
    rx,
    byte_data,
    byte_valid,
    framing_error
);

    input clock;
    input reset;
    input rx;
    output [7:0] byte_data;
    output byte_valid;
    output framing_error;

    wire signal_const;
    wire signal_const_1;
    wire signal_mux;
    wire signal_mux_1;
    reg signal_cases;
    wire signal_wire;
    reg signal_reg;
    wire signal_mux_2;
    wire signal_mux_3;
    reg signal_cases_1;
    wire signal_wire_1;
    reg signal_reg_1;
    wire [7:0] signal_const_6;
    wire [6:0] signal_select;
    wire [7:0] signal_cat;
    wire [7:0] signal_mux_4;
    wire [1:0] signal_const_7;
    wire [1:0] signal_mux_5;
    wire [1:0] signal_const_15;
    wire [2:0] signal_const_8;
    wire [2:0] signal_const_9;
    wire [2:0] signal_const_10;
    wire [2:0] signal_add;
    wire [2:0] signal_mux_6;
    wire [2:0] signal_mux_7;
    wire [2:0] signal_mux_8;
    wire [2:0] signal_mux_9;
    reg [2:0] signal_cases_2;
    wire [2:0] signal_wire_2;
    reg [2:0] signal_reg_2;
    wire signal_eq;
    wire [1:0] signal_mux_10;
    wire [1:0] signal_mux_11;
    wire [1:0] signal_const_18;
    wire [1:0] signal_mux_12;
    wire [7:0] signal_const_14;
    wire [7:0] signal_sub;
    wire [7:0] signal_mux_13;
    wire [7:0] signal_const_16;
    wire [7:0] signal_sub_1;
    wire [7:0] signal_mux_14;
    wire [7:0] signal_mux_15;
    wire [7:0] signal_sub_2;
    wire [7:0] signal_mux_16;
    wire [7:0] signal_const_21;
    wire [7:0] signal_mux_17;
    reg [7:0] signal_cases_3;
    wire [7:0] signal_wire_3;
    reg [7:0] signal_reg_3;
    wire signal_eq_1;
    wire [1:0] signal_mux_18;
    wire [1:0] signal_const_22;
    wire signal_not;
    wire vdd;
    wire signal_wire_4;
    wire signal_wire_5;
    wire signal_wire_6;
    reg signal_reg_4 = 1'b1;
    wire signal_and;
    wire [1:0] signal_mux_19;
    reg [1:0] signal_cases_4;
    wire [1:0] signal_wire_7;
    (* fsm_encoding="one_hot" *)
    reg [1:0] signal_reg_5;
    reg [7:0] signal_cases_5;
    wire [7:0] signal_wire_8;
    reg [7:0] signal_reg_6;
    assign signal_const = 1'b0;
    assign signal_const_1 = 1'b1;
    assign signal_mux = signal_wire_6 ? signal_const : signal_const_1;
    assign signal_mux_1 = signal_eq_1 ? signal_mux : signal_const;
    always @* begin
        case (signal_reg_5)
        2'b11:
            signal_cases <= signal_mux_1;
        default:
            signal_cases <= signal_const;
        endcase
    end
    assign signal_wire = signal_cases;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg <= signal_const;
        else
            signal_reg <= signal_wire;
    end
    assign signal_mux_2 = signal_wire_6 ? signal_const_1 : signal_const;
    assign signal_mux_3 = signal_eq_1 ? signal_mux_2 : signal_const;
    always @* begin
        case (signal_reg_5)
        2'b11:
            signal_cases_1 <= signal_mux_3;
        default:
            signal_cases_1 <= signal_const;
        endcase
    end
    assign signal_wire_1 = signal_cases_1;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_1 <= signal_const;
        else
            signal_reg_1 <= signal_wire_1;
    end
    assign signal_const_6 = 8'b00000000;
    assign signal_select = signal_reg_6[7:1];
    assign signal_cat = { signal_wire_6,
                          signal_select };
    assign signal_mux_4 = signal_eq_1 ? signal_cat : signal_reg_6;
    assign signal_const_7 = 2'b00;
    assign signal_mux_5 = signal_eq_1 ? signal_const_7 : signal_reg_5;
    assign signal_const_15 = 2'b11;
    assign signal_const_8 = 3'b111;
    assign signal_const_9 = 3'b000;
    assign signal_const_10 = 3'b001;
    assign signal_add = signal_reg_2 + signal_const_10;
    assign signal_mux_6 = signal_eq ? signal_reg_2 : signal_add;
    assign signal_mux_7 = signal_eq_1 ? signal_mux_6 : signal_reg_2;
    assign signal_mux_8 = signal_wire_6 ? signal_reg_2 : signal_const_9;
    assign signal_mux_9 = signal_eq_1 ? signal_mux_8 : signal_reg_2;
    always @* begin
        case (signal_reg_5)
        2'b01:
            signal_cases_2 <= signal_mux_9;
        2'b10:
            signal_cases_2 <= signal_mux_7;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_wire_2 = signal_cases_2;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_2 <= signal_const_9;
        else
            signal_reg_2 <= signal_wire_2;
    end
    assign signal_eq = signal_reg_2 == signal_const_8;
    assign signal_mux_10 = signal_eq ? signal_const_15 : signal_reg_5;
    assign signal_mux_11 = signal_eq_1 ? signal_mux_10 : signal_reg_5;
    assign signal_const_18 = 2'b10;
    assign signal_mux_12 = signal_wire_6 ? signal_const_7 : signal_const_18;
    assign signal_const_14 = 8'b00000001;
    assign signal_sub = signal_reg_3 - signal_const_14;
    assign signal_mux_13 = signal_eq_1 ? signal_reg_3 : signal_sub;
    assign signal_const_16 = 8'b11101001;
    assign signal_sub_1 = signal_reg_3 - signal_const_14;
    assign signal_mux_14 = signal_eq_1 ? signal_const_16 : signal_sub_1;
    assign signal_mux_15 = signal_wire_6 ? signal_reg_3 : signal_const_16;
    assign signal_sub_2 = signal_reg_3 - signal_const_14;
    assign signal_mux_16 = signal_eq_1 ? signal_mux_15 : signal_sub_2;
    assign signal_const_21 = 8'b01110100;
    assign signal_mux_17 = signal_and ? signal_const_21 : signal_reg_3;
    always @* begin
        case (signal_reg_5)
        2'b00:
            signal_cases_3 <= signal_mux_17;
        2'b01:
            signal_cases_3 <= signal_mux_16;
        2'b10:
            signal_cases_3 <= signal_mux_14;
        2'b11:
            signal_cases_3 <= signal_mux_13;
        default:
            signal_cases_3 <= signal_reg_3;
        endcase
    end
    assign signal_wire_3 = signal_cases_3;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_3 <= signal_const_6;
        else
            signal_reg_3 <= signal_wire_3;
    end
    assign signal_eq_1 = signal_reg_3 == signal_const_6;
    assign signal_mux_18 = signal_eq_1 ? signal_mux_12 : signal_reg_5;
    assign signal_const_22 = 2'b01;
    assign signal_not = ~ signal_wire_6;
    assign vdd = 1'b1;
    assign signal_wire_4 = reset;
    assign signal_wire_5 = clock;
    assign signal_wire_6 = rx;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_4 <= vdd;
        else
            signal_reg_4 <= signal_wire_6;
    end
    assign signal_and = signal_reg_4 & signal_not;
    assign signal_mux_19 = signal_and ? signal_const_22 : signal_reg_5;
    always @* begin
        case (signal_reg_5)
        2'b00:
            signal_cases_4 <= signal_mux_19;
        2'b01:
            signal_cases_4 <= signal_mux_18;
        2'b10:
            signal_cases_4 <= signal_mux_11;
        2'b11:
            signal_cases_4 <= signal_mux_5;
        default:
            signal_cases_4 <= signal_reg_5;
        endcase
    end
    assign signal_wire_7 = signal_cases_4;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_5 <= signal_const_7;
        else
            signal_reg_5 <= signal_wire_7;
    end
    always @* begin
        case (signal_reg_5)
        2'b10:
            signal_cases_5 <= signal_mux_4;
        default:
            signal_cases_5 <= signal_reg_6;
        endcase
    end
    assign signal_wire_8 = signal_cases_5;
    always @(posedge signal_wire_5) begin
        if (signal_wire_4)
            signal_reg_6 <= signal_const_6;
        else
            signal_reg_6 <= signal_wire_8;
    end
    assign byte_data = signal_reg_6;
    assign byte_valid = signal_reg_1;
    assign framing_error = signal_reg;

endmodule
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
module gqh_competition_top (
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

    wire signal_select;
    wire signal_wire;
    wire signal_select_1;
    wire signal_select_2;
    wire [1:0] signal_select_3;
    wire [1:0] signal_wire_1;
    wire signal_select_4;
    wire signal_wire_2;
    wire signal_select_5;
    wire signal_select_6;
    wire signal_select_7;
    wire [3:0] signal_select_8;
    wire [15:0] signal_select_9;
    wire signal_select_10;
    wire signal_select_11;
    wire [3:0] signal_inst;
    wire signal_select_12;
    wire signal_wire_3;
    wire signal_select_13;
    wire signal_select_14;
    wire vdd;
    wire signal_wire_4;
    reg signal_reg = 1'b1;
    reg signal_reg_1 = 1'b1;
    wire [9:0] signal_inst_1;
    wire [7:0] signal_select_15;
    wire [34:0] signal_inst_2;
    wire [7:0] signal_select_16;
    wire [7:0] signal_wire_5;
    wire signal_wire_6;
    wire signal_inst_3;
    wire signal_wire_7;
    wire signal_wire_8;
    wire [2:0] signal_inst_4;
    wire signal_select_17;
    assign signal_select = signal_inst_2[33:33];
    assign signal_wire = signal_select;
    assign signal_select_1 = signal_inst_4[2:2];
    assign signal_select_2 = signal_inst_4[1:1];
    assign signal_select_3 = signal_inst[3:2];
    assign signal_wire_1 = signal_select_3;
    assign signal_select_4 = signal_inst[1:1];
    assign signal_wire_2 = signal_select_4;
    assign signal_select_5 = signal_inst_2[23:23];
    assign signal_select_6 = signal_inst_2[22:22];
    assign signal_select_7 = signal_inst_2[21:21];
    assign signal_select_8 = signal_inst_2[20:17];
    assign signal_select_9 = signal_inst_2[16:1];
    assign signal_select_10 = signal_inst_2[0:0];
    assign signal_select_11 = signal_inst_2[24:24];
    gqh_update_engine
        engine
        ( .clock(signal_wire_8),
          .reset(signal_wire_7),
          .session_clear(signal_select_11),
          .update$item_select(signal_select_10),
          .update$price(signal_select_9),
          .update$window_position(signal_select_8),
          .update$warmup(signal_select_7),
          .update_valid(signal_select_6),
          .result_ready(signal_select_5),
          .update_ready(signal_inst[0:0]),
          .result_valid(signal_inst[1:1]),
          .action(signal_inst[3:2]) );
    assign signal_select_12 = signal_inst[0:0];
    assign signal_wire_3 = signal_select_12;
    assign signal_select_13 = signal_inst_1[9:9];
    assign signal_select_14 = signal_inst_1[8:8];
    assign vdd = 1'b1;
    assign signal_wire_4 = uart_rx_i;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg <= vdd;
        else
            signal_reg <= signal_wire_4;
    end
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_1 <= vdd;
        else
            signal_reg_1 <= signal_reg;
    end
    gqh_uart_rx
        uart_rx
        ( .clock(signal_wire_8),
          .reset(signal_wire_7),
          .rx(signal_reg_1),
          .byte_data(signal_inst_1[7:0]),
          .byte_valid(signal_inst_1[8:8]),
          .framing_error(signal_inst_1[9:9]) );
    assign signal_select_15 = signal_inst_1[7:0];
    gqh_packet_ram_controller
        packet_ram_controller
        ( .clock(signal_wire_8),
          .reset(signal_wire_7),
          .byte_data(signal_select_15),
          .byte_valid(signal_select_14),
          .framing_error(signal_select_13),
          .update_ready(signal_wire_3),
          .result_valid(signal_wire_2),
          .action(signal_wire_1),
          .tx_ready(signal_select_2),
          .tx_busy(signal_select_1),
          .update$item_select(signal_inst_2[0:0]),
          .update$price(signal_inst_2[16:1]),
          .update$window_position(signal_inst_2[20:17]),
          .update$warmup(signal_inst_2[21:21]),
          .update_valid(signal_inst_2[22:22]),
          .result_ready(signal_inst_2[23:23]),
          .session_clear(signal_inst_2[24:24]),
          .tx_data(signal_inst_2[32:25]),
          .tx_valid(signal_inst_2[33:33]),
          .protocol_fault(signal_inst_2[34:34]) );
    assign signal_select_16 = signal_inst_2[32:25];
    assign signal_wire_5 = signal_select_16;
    assign signal_wire_6 = reset_btn;
    gqh_reset_release
        reset_release
        ( .clock(signal_wire_8),
          .reset_btn(signal_wire_6),
          .reset(signal_inst_3) );
    assign signal_wire_7 = signal_inst_3;
    assign signal_wire_8 = sys_clk;
    gqh_uart_tx
        uart_tx
        ( .clock(signal_wire_8),
          .reset(signal_wire_7),
          .tx_data(signal_wire_5),
          .tx_valid(signal_wire),
          .tx(signal_inst_4[0:0]),
          .tx_ready(signal_inst_4[1:1]),
          .tx_busy(signal_inst_4[2:2]) );
    assign signal_select_17 = signal_inst_4[0:0];
    assign uart_tx_o = signal_select_17;
    assign led0_n = vdd;
    assign led1_n = vdd;

endmodule
