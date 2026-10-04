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
module gqh_response_sequencer (
    clock,
    reset,
    response$index,
    response$slot1_id,
    response$slot2_id,
    response$slot1_action,
    response$slot2_action,
    response_valid,
    tx_ready,
    tx_busy,
    response_ready,
    response_done,
    tx_data,
    tx_valid
);

    input clock;
    input reset;
    input [15:0] response$index;
    input [7:0] response$slot1_id;
    input [7:0] response$slot2_id;
    input [1:0] response$slot1_action;
    input [1:0] response$slot2_action;
    input response_valid;
    input tx_ready;
    input tx_busy;
    output response_ready;
    output response_done;
    output [7:0] tx_data;
    output tx_valid;

    wire signal_not;
    wire signal_eq;
    wire signal_and;
    wire [7:0] signal_const;
    wire [1:0] signal_wire;
    wire [5:0] signal_const_2;
    wire [7:0] signal_cat;
    wire [7:0] signal_wire_1;
    wire [1:0] signal_wire_2;
    wire [7:0] signal_cat_1;
    wire [7:0] signal_wire_3;
    wire [7:0] signal_select;
    wire [15:0] signal_wire_4;
    wire [7:0] signal_select_1;
    reg [7:0] signal_mux;
    wire signal_const_4;
    wire signal_const_5;
    wire signal_mux_1;
    reg signal_cases;
    wire signal_wire_5;
    reg signal_reg;
    wire signal_not_1;
    wire [1:0] signal_const_7;
    wire signal_wire_6;
    wire signal_not_2;
    wire [1:0] signal_mux_2;
    wire [1:0] signal_const_8;
    wire [2:0] signal_const_9;
    wire [2:0] signal_const_10;
    wire signal_wire_7;
    wire signal_wire_8;
    wire [2:0] signal_const_11;
    wire [2:0] signal_add;
    wire [2:0] signal_mux_3;
    wire [2:0] signal_mux_4;
    wire [2:0] signal_mux_5;
    reg [2:0] signal_cases_1;
    wire [2:0] signal_wire_9;
    reg [2:0] signal_reg_1;
    wire signal_eq_1;
    wire [1:0] signal_mux_6;
    wire signal_wire_10;
    wire [1:0] signal_mux_7;
    wire [1:0] signal_const_13;
    wire signal_wire_11;
    wire [1:0] signal_mux_8;
    reg [1:0] signal_cases_2;
    wire [1:0] signal_wire_12;
    (* fsm_encoding="one_hot" *)
    reg [1:0] signal_reg_2;
    wire signal_eq_2;
    wire signal_and_1;
    assign signal_not = ~ signal_wire_7;
    assign signal_eq = signal_const_13 == signal_reg_2;
    assign signal_and = signal_eq & signal_not;
    assign signal_const = 8'b00000000;
    assign signal_wire = response$slot2_action;
    assign signal_const_2 = 6'b000000;
    assign signal_cat = { signal_const_2,
                          signal_wire };
    assign signal_wire_1 = response$slot2_id;
    assign signal_wire_2 = response$slot1_action;
    assign signal_cat_1 = { signal_const_2,
                            signal_wire_2 };
    assign signal_wire_3 = response$slot1_id;
    assign signal_select = signal_wire_4[7:0];
    assign signal_wire_4 = response$index;
    assign signal_select_1 = signal_wire_4[15:8];
    always @* begin
        case (signal_reg_1)
        0:
            signal_mux <= signal_select_1;
        1:
            signal_mux <= signal_select;
        2:
            signal_mux <= signal_wire_3;
        3:
            signal_mux <= signal_cat_1;
        4:
            signal_mux <= signal_wire_1;
        5:
            signal_mux <= signal_cat;
        6:
            signal_mux <= signal_const;
        default:
            signal_mux <= signal_const;
        endcase
    end
    assign signal_const_4 = 1'b0;
    assign signal_const_5 = 1'b1;
    assign signal_mux_1 = signal_not_2 ? signal_const_5 : signal_const_4;
    always @* begin
        case (signal_reg_2)
        2'b10:
            signal_cases <= signal_mux_1;
        default:
            signal_cases <= signal_const_4;
        endcase
    end
    assign signal_wire_5 = signal_cases;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg <= signal_const_4;
        else
            signal_reg <= signal_wire_5;
    end
    assign signal_not_1 = ~ signal_wire_7;
    assign signal_const_7 = 2'b00;
    assign signal_wire_6 = tx_busy;
    assign signal_not_2 = ~ signal_wire_6;
    assign signal_mux_2 = signal_not_2 ? signal_const_7 : signal_reg_2;
    assign signal_const_8 = 2'b10;
    assign signal_const_9 = 3'b111;
    assign signal_const_10 = 3'b000;
    assign signal_wire_7 = reset;
    assign signal_wire_8 = clock;
    assign signal_const_11 = 3'b001;
    assign signal_add = signal_reg_1 + signal_const_11;
    assign signal_mux_3 = signal_eq_1 ? signal_reg_1 : signal_add;
    assign signal_mux_4 = signal_wire_10 ? signal_mux_3 : signal_reg_1;
    assign signal_mux_5 = signal_wire_11 ? signal_const_10 : signal_reg_1;
    always @* begin
        case (signal_reg_2)
        2'b00:
            signal_cases_1 <= signal_mux_5;
        2'b01:
            signal_cases_1 <= signal_mux_4;
        default:
            signal_cases_1 <= signal_reg_1;
        endcase
    end
    assign signal_wire_9 = signal_cases_1;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_1 <= signal_const_10;
        else
            signal_reg_1 <= signal_wire_9;
    end
    assign signal_eq_1 = signal_reg_1 == signal_const_9;
    assign signal_mux_6 = signal_eq_1 ? signal_const_8 : signal_reg_2;
    assign signal_wire_10 = tx_ready;
    assign signal_mux_7 = signal_wire_10 ? signal_mux_6 : signal_reg_2;
    assign signal_const_13 = 2'b01;
    assign signal_wire_11 = response_valid;
    assign signal_mux_8 = signal_wire_11 ? signal_const_13 : signal_reg_2;
    always @* begin
        case (signal_reg_2)
        2'b00:
            signal_cases_2 <= signal_mux_8;
        2'b01:
            signal_cases_2 <= signal_mux_7;
        2'b10:
            signal_cases_2 <= signal_mux_2;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_wire_12 = signal_cases_2;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_2 <= signal_const_7;
        else
            signal_reg_2 <= signal_wire_12;
    end
    assign signal_eq_2 = signal_const_7 == signal_reg_2;
    assign signal_and_1 = signal_eq_2 & signal_not_1;
    assign response_ready = signal_and_1;
    assign response_done = signal_reg;
    assign tx_data = signal_mux;
    assign tx_valid = signal_and;

endmodule
module gqh_transaction_controller (
    clock,
    reset,
    request$index,
    request$slot1_id,
    request$slot1_price,
    request$slot2_id,
    request$slot2_price,
    request_valid,
    update_ready,
    result_valid,
    action,
    response_ready,
    response_done,
    request_ready,
    receive_enable,
    update$item_select,
    update$price,
    update$window_position,
    update$warmup,
    update_valid,
    result_ready,
    session_clear,
    response$index,
    response$slot1_id,
    response$slot2_id,
    response$slot1_action,
    response$slot2_action,
    response_valid
);

    input clock;
    input reset;
    input [15:0] request$index;
    input [7:0] request$slot1_id;
    input [15:0] request$slot1_price;
    input [7:0] request$slot2_id;
    input [15:0] request$slot2_price;
    input request_valid;
    input update_ready;
    input result_valid;
    input [1:0] action;
    input response_ready;
    input response_done;
    output request_ready;
    output receive_enable;
    output update$item_select;
    output [15:0] update$price;
    output [3:0] update$window_position;
    output update$warmup;
    output update_valid;
    output result_ready;
    output session_clear;
    output [15:0] response$index;
    output [7:0] response$slot1_id;
    output [7:0] response$slot2_id;
    output [1:0] response$slot1_action;
    output [1:0] response$slot2_action;
    output response_valid;

    wire signal_eq;
    wire signal_and;
    wire [1:0] signal_const;
    wire [1:0] signal_mux;
    reg [1:0] signal_cases;
    wire [1:0] signal_wire;
    reg [1:0] signal_reg;
    wire [1:0] signal_wire_1;
    wire [1:0] signal_mux_1;
    reg [1:0] signal_cases_1;
    wire [1:0] signal_wire_2;
    reg [1:0] signal_reg_1;
    wire signal_eq_1;
    wire signal_and_1;
    wire signal_eq_2;
    wire signal_eq_3;
    wire signal_or;
    wire signal_and_2;
    wire signal_eq_4;
    wire signal_eq_5;
    wire signal_or_1;
    wire signal_and_3;
    wire [15:0] signal_const_2;
    wire signal_lt;
    wire [3:0] signal_const_3;
    wire [3:0] signal_const_4;
    wire [3:0] signal_add;
    wire [3:0] signal_mux_2;
    wire [3:0] signal_mux_3;
    wire [3:0] signal_mux_4;
    reg [3:0] signal_cases_2;
    wire [3:0] signal_wire_3;
    reg [3:0] signal_reg_2;
    wire [15:0] signal_wire_4;
    wire [15:0] signal_wire_5;
    wire [15:0] signal_mux_5;
    wire [7:0] signal_const_6;
    wire [7:0] signal_wire_6;
    wire [7:0] signal_wire_7;
    wire signal_eq_6;
    wire signal_eq_7;
    wire signal_or_2;
    wire [7:0] signal_mux_6;
    wire signal_eq_8;
    wire signal_not;
    wire signal_wire_8;
    wire signal_wire_9;
    wire signal_wire_10;
    wire [3:0] signal_mux_7;
    wire [3:0] signal_const_8;
    wire signal_wire_11;
    wire [3:0] signal_mux_8;
    wire [3:0] signal_const_9;
    wire [3:0] signal_mux_9;
    wire [3:0] signal_const_10;
    wire [3:0] signal_mux_10;
    wire [3:0] signal_const_11;
    wire [3:0] signal_mux_11;
    wire [3:0] signal_const_12;
    wire [3:0] signal_mux_12;
    wire [3:0] signal_const_13;
    wire signal_wire_12;
    wire signal_not_1;
    wire signal_wire_13;
    wire signal_and_4;
    wire [3:0] signal_mux_13;
    wire [3:0] signal_const_15;
    wire [15:0] signal_const_16;
    wire [15:0] signal_wire_14;
    wire signal_eq_9;
    wire [3:0] signal_mux_14;
    wire signal_wire_15;
    wire signal_and_5;
    wire [3:0] signal_mux_15;
    reg [3:0] signal_cases_3;
    wire [3:0] signal_wire_16;
    (* fsm_encoding="one_hot" *)
    reg [3:0] signal_reg_3;
    wire signal_eq_10;
    wire signal_and_6;
    assign signal_eq = signal_const_9 == signal_reg_3;
    assign signal_and = signal_eq & signal_not;
    assign signal_const = 2'b00;
    assign signal_mux = signal_wire_12 ? signal_wire_1 : signal_reg;
    always @* begin
        case (signal_reg_3)
        4'b0110:
            signal_cases <= signal_mux;
        default:
            signal_cases <= signal_reg;
        endcase
    end
    assign signal_wire = signal_cases;
    always @(posedge signal_wire_9) begin
        if (signal_wire_8)
            signal_reg <= signal_const;
        else
            signal_reg <= signal_wire;
    end
    assign signal_wire_1 = action;
    assign signal_mux_1 = signal_wire_12 ? signal_wire_1 : signal_reg_1;
    always @* begin
        case (signal_reg_3)
        4'b0100:
            signal_cases_1 <= signal_mux_1;
        default:
            signal_cases_1 <= signal_reg_1;
        endcase
    end
    assign signal_wire_2 = signal_cases_1;
    always @(posedge signal_wire_9) begin
        if (signal_wire_8)
            signal_reg_1 <= signal_const;
        else
            signal_reg_1 <= signal_wire_2;
    end
    assign signal_eq_1 = signal_const_13 == signal_reg_3;
    assign signal_and_1 = signal_eq_1 & signal_not;
    assign signal_eq_2 = signal_const_10 == signal_reg_3;
    assign signal_eq_3 = signal_const_12 == signal_reg_3;
    assign signal_or = signal_eq_3 | signal_eq_2;
    assign signal_and_2 = signal_or & signal_not;
    assign signal_eq_4 = signal_const_11 == signal_reg_3;
    assign signal_eq_5 = signal_const_15 == signal_reg_3;
    assign signal_or_1 = signal_eq_5 | signal_eq_4;
    assign signal_and_3 = signal_or_1 & signal_not;
    assign signal_const_2 = 16'b0000000000010000;
    assign signal_lt = signal_wire_14 < signal_const_2;
    assign signal_const_3 = 4'b0000;
    assign signal_const_4 = 4'b0001;
    assign signal_add = signal_reg_2 + signal_const_4;
    assign signal_mux_2 = signal_wire_12 ? signal_add : signal_reg_2;
    assign signal_mux_3 = signal_eq_9 ? signal_const_3 : signal_reg_2;
    assign signal_mux_4 = signal_and_5 ? signal_mux_3 : signal_reg_2;
    always @* begin
        case (signal_reg_3)
        4'b0000:
            signal_cases_2 <= signal_mux_4;
        4'b0110:
            signal_cases_2 <= signal_mux_2;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_wire_3 = signal_cases_2;
    always @(posedge signal_wire_9) begin
        if (signal_wire_8)
            signal_reg_2 <= signal_const_3;
        else
            signal_reg_2 <= signal_wire_3;
    end
    assign signal_wire_4 = request$slot2_price;
    assign signal_wire_5 = request$slot1_price;
    assign signal_mux_5 = signal_or_2 ? signal_wire_4 : signal_wire_5;
    assign signal_const_6 = 8'b00100010;
    assign signal_wire_6 = request$slot2_id;
    assign signal_wire_7 = request$slot1_id;
    assign signal_eq_6 = signal_const_10 == signal_reg_3;
    assign signal_eq_7 = signal_const_11 == signal_reg_3;
    assign signal_or_2 = signal_eq_7 | signal_eq_6;
    assign signal_mux_6 = signal_or_2 ? signal_wire_6 : signal_wire_7;
    assign signal_eq_8 = signal_mux_6 == signal_const_6;
    assign signal_not = ~ signal_wire_8;
    assign signal_wire_8 = reset;
    assign signal_wire_9 = clock;
    assign signal_wire_10 = response_done;
    assign signal_mux_7 = signal_wire_10 ? signal_const_3 : signal_reg_3;
    assign signal_const_8 = 4'b1000;
    assign signal_wire_11 = response_ready;
    assign signal_mux_8 = signal_wire_11 ? signal_const_8 : signal_reg_3;
    assign signal_const_9 = 4'b0111;
    assign signal_mux_9 = signal_wire_12 ? signal_const_9 : signal_reg_3;
    assign signal_const_10 = 4'b0110;
    assign signal_mux_10 = signal_wire_13 ? signal_const_10 : signal_reg_3;
    assign signal_const_11 = 4'b0101;
    assign signal_mux_11 = signal_wire_12 ? signal_const_11 : signal_reg_3;
    assign signal_const_12 = 4'b0100;
    assign signal_mux_12 = signal_wire_13 ? signal_const_12 : signal_reg_3;
    assign signal_const_13 = 4'b0010;
    assign signal_wire_12 = result_valid;
    assign signal_not_1 = ~ signal_wire_12;
    assign signal_wire_13 = update_ready;
    assign signal_and_4 = signal_wire_13 & signal_not_1;
    assign signal_mux_13 = signal_and_4 ? signal_const_13 : signal_reg_3;
    assign signal_const_15 = 4'b0011;
    assign signal_const_16 = 16'b0000000000000000;
    assign signal_wire_14 = request$index;
    assign signal_eq_9 = signal_wire_14 == signal_const_16;
    assign signal_mux_14 = signal_eq_9 ? signal_const_4 : signal_const_15;
    assign signal_wire_15 = request_valid;
    assign signal_and_5 = signal_and_6 & signal_wire_15;
    assign signal_mux_15 = signal_and_5 ? signal_mux_14 : signal_reg_3;
    always @* begin
        case (signal_reg_3)
        4'b0000:
            signal_cases_3 <= signal_mux_15;
        4'b0001:
            signal_cases_3 <= signal_mux_13;
        4'b0010:
            signal_cases_3 <= signal_const_15;
        4'b0011:
            signal_cases_3 <= signal_mux_12;
        4'b0100:
            signal_cases_3 <= signal_mux_11;
        4'b0101:
            signal_cases_3 <= signal_mux_10;
        4'b0110:
            signal_cases_3 <= signal_mux_9;
        4'b0111:
            signal_cases_3 <= signal_mux_8;
        4'b1000:
            signal_cases_3 <= signal_mux_7;
        default:
            signal_cases_3 <= signal_reg_3;
        endcase
    end
    assign signal_wire_16 = signal_cases_3;
    always @(posedge signal_wire_9) begin
        if (signal_wire_8)
            signal_reg_3 <= signal_const_3;
        else
            signal_reg_3 <= signal_wire_16;
    end
    assign signal_eq_10 = signal_const_3 == signal_reg_3;
    assign signal_and_6 = signal_eq_10 & signal_not;
    assign request_ready = signal_and_6;
    assign receive_enable = signal_and_6;
    assign update$item_select = signal_eq_8;
    assign update$price = signal_mux_5;
    assign update$window_position = signal_reg_2;
    assign update$warmup = signal_lt;
    assign update_valid = signal_and_3;
    assign result_ready = signal_and_2;
    assign session_clear = signal_and_1;
    assign response$index = signal_wire_14;
    assign response$slot1_id = signal_wire_7;
    assign response$slot2_id = signal_wire_6;
    assign response$slot1_action = signal_reg_1;
    assign response$slot2_action = signal_reg;
    assign response_valid = signal_and;

endmodule
module gqh_request_decoder (
    clock,
    reset,
    receive_enable,
    byte_data,
    byte_valid,
    framing_error,
    request_ready,
    request$index,
    request$slot1_id,
    request$slot1_price,
    request$slot2_id,
    request$slot2_price,
    request_valid,
    protocol_fault
);

    input clock;
    input reset;
    input receive_enable;
    input [7:0] byte_data;
    input byte_valid;
    input framing_error;
    input request_ready;
    output [15:0] request$index;
    output [7:0] request$slot1_id;
    output [15:0] request$slot1_price;
    output [7:0] request$slot2_id;
    output [15:0] request$slot2_price;
    output request_valid;
    output protocol_fault;

    wire signal_not;
    wire signal_not_1;
    wire signal_and;
    wire signal_and_1;
    wire [15:0] signal_const;
    wire [7:0] signal_select;
    wire [15:0] signal_cat;
    wire [7:0] signal_select_1;
    wire [15:0] signal_cat_1;
    reg [15:0] signal_cases;
    wire [15:0] signal_mux;
    wire [15:0] signal_mux_1;
    wire [15:0] signal_mux_2;
    wire [15:0] signal_wire;
    reg [15:0] signal_reg;
    wire [7:0] signal_const_2;
    reg [7:0] signal_cases_1;
    wire [7:0] signal_mux_3;
    wire [7:0] signal_mux_4;
    wire [7:0] signal_mux_5;
    wire [7:0] signal_wire_1;
    reg [7:0] signal_reg_1;
    wire [7:0] signal_select_2;
    wire [15:0] signal_cat_2;
    wire [7:0] signal_select_3;
    wire [15:0] signal_cat_3;
    reg [15:0] signal_cases_2;
    wire [15:0] signal_mux_6;
    wire [15:0] signal_mux_7;
    wire [15:0] signal_mux_8;
    wire [15:0] signal_wire_2;
    reg [15:0] signal_reg_2;
    reg [7:0] signal_cases_3;
    wire [7:0] signal_mux_9;
    wire [7:0] signal_mux_10;
    wire [7:0] signal_mux_11;
    wire [7:0] signal_wire_3;
    reg [7:0] signal_reg_3;
    wire [7:0] signal_select_4;
    wire [15:0] signal_cat_4;
    wire [7:0] signal_select_5;
    wire [7:0] signal_wire_4;
    wire [15:0] signal_cat_5;
    reg [15:0] signal_cases_4;
    wire signal_const_12;
    wire signal_const_13;
    wire signal_mux_12;
    wire signal_mux_13;
    wire signal_mux_14;
    wire signal_wire_5;
    reg signal_reg_4;
    wire signal_not_2;
    wire [2:0] signal_const_19;
    wire signal_wire_6;
    wire signal_wire_7;
    wire [2:0] signal_const_21;
    wire [2:0] signal_add;
    wire [2:0] signal_mux_15;
    wire [2:0] signal_mux_16;
    wire [2:0] signal_mux_17;
    wire [2:0] signal_wire_8;
    reg [2:0] signal_reg_5;
    reg signal_cases_5;
    wire signal_mux_18;
    wire signal_wire_9;
    wire signal_and_2;
    wire signal_mux_19;
    wire signal_mux_20;
    wire signal_mux_21;
    wire signal_wire_10;
    reg signal_reg_6;
    wire signal_not_3;
    wire signal_wire_11;
    wire signal_and_3;
    wire signal_and_4;
    wire [15:0] signal_mux_22;
    wire signal_wire_12;
    wire [15:0] signal_mux_23;
    wire signal_wire_13;
    wire [15:0] signal_mux_24;
    wire [15:0] signal_wire_14;
    reg [15:0] signal_reg_7;
    assign signal_not = ~ signal_wire_13;
    assign signal_not_1 = ~ signal_reg_4;
    assign signal_and = signal_reg_6 & signal_not_1;
    assign signal_and_1 = signal_and & signal_not;
    assign signal_const = 16'b0000000000000000;
    assign signal_select = signal_reg[15:8];
    assign signal_cat = { signal_select,
                          signal_wire_4 };
    assign signal_select_1 = signal_reg[7:0];
    assign signal_cat_1 = { signal_wire_4,
                            signal_select_1 };
    always @* begin
        case (signal_reg_5)
        3'b110:
            signal_cases <= signal_cat_1;
        3'b111:
            signal_cases <= signal_cat;
        default:
            signal_cases <= signal_reg;
        endcase
    end
    assign signal_mux = signal_and_4 ? signal_cases : signal_reg;
    assign signal_mux_1 = signal_wire_12 ? signal_mux : signal_reg;
    assign signal_mux_2 = signal_wire_13 ? signal_reg : signal_mux_1;
    assign signal_wire = signal_mux_2;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg <= signal_const;
        else
            signal_reg <= signal_wire;
    end
    assign signal_const_2 = 8'b00000000;
    always @* begin
        case (signal_reg_5)
        3'b101:
            signal_cases_1 <= signal_wire_4;
        default:
            signal_cases_1 <= signal_reg_1;
        endcase
    end
    assign signal_mux_3 = signal_and_4 ? signal_cases_1 : signal_reg_1;
    assign signal_mux_4 = signal_wire_12 ? signal_mux_3 : signal_reg_1;
    assign signal_mux_5 = signal_wire_13 ? signal_reg_1 : signal_mux_4;
    assign signal_wire_1 = signal_mux_5;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_1 <= signal_const_2;
        else
            signal_reg_1 <= signal_wire_1;
    end
    assign signal_select_2 = signal_reg_2[15:8];
    assign signal_cat_2 = { signal_select_2,
                            signal_wire_4 };
    assign signal_select_3 = signal_reg_2[7:0];
    assign signal_cat_3 = { signal_wire_4,
                            signal_select_3 };
    always @* begin
        case (signal_reg_5)
        3'b011:
            signal_cases_2 <= signal_cat_3;
        3'b100:
            signal_cases_2 <= signal_cat_2;
        default:
            signal_cases_2 <= signal_reg_2;
        endcase
    end
    assign signal_mux_6 = signal_and_4 ? signal_cases_2 : signal_reg_2;
    assign signal_mux_7 = signal_wire_12 ? signal_mux_6 : signal_reg_2;
    assign signal_mux_8 = signal_wire_13 ? signal_reg_2 : signal_mux_7;
    assign signal_wire_2 = signal_mux_8;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_2 <= signal_const;
        else
            signal_reg_2 <= signal_wire_2;
    end
    always @* begin
        case (signal_reg_5)
        3'b010:
            signal_cases_3 <= signal_wire_4;
        default:
            signal_cases_3 <= signal_reg_3;
        endcase
    end
    assign signal_mux_9 = signal_and_4 ? signal_cases_3 : signal_reg_3;
    assign signal_mux_10 = signal_wire_12 ? signal_mux_9 : signal_reg_3;
    assign signal_mux_11 = signal_wire_13 ? signal_reg_3 : signal_mux_10;
    assign signal_wire_3 = signal_mux_11;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_3 <= signal_const_2;
        else
            signal_reg_3 <= signal_wire_3;
    end
    assign signal_select_4 = signal_reg_7[15:8];
    assign signal_cat_4 = { signal_select_4,
                            signal_wire_4 };
    assign signal_select_5 = signal_reg_7[7:0];
    assign signal_wire_4 = byte_data;
    assign signal_cat_5 = { signal_wire_4,
                            signal_select_5 };
    always @* begin
        case (signal_reg_5)
        3'b000:
            signal_cases_4 <= signal_cat_5;
        3'b001:
            signal_cases_4 <= signal_cat_4;
        default:
            signal_cases_4 <= signal_reg_7;
        endcase
    end
    assign signal_const_12 = 1'b0;
    assign signal_const_13 = 1'b1;
    assign signal_mux_12 = signal_and_4 ? signal_reg_4 : signal_const_13;
    assign signal_mux_13 = signal_wire_12 ? signal_mux_12 : signal_reg_4;
    assign signal_mux_14 = signal_wire_13 ? signal_const_13 : signal_mux_13;
    assign signal_wire_5 = signal_mux_14;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_4 <= signal_const_12;
        else
            signal_reg_4 <= signal_wire_5;
    end
    assign signal_not_2 = ~ signal_reg_4;
    assign signal_const_19 = 3'b000;
    assign signal_wire_6 = reset;
    assign signal_wire_7 = clock;
    assign signal_const_21 = 3'b001;
    assign signal_add = signal_reg_5 + signal_const_21;
    assign signal_mux_15 = signal_and_4 ? signal_add : signal_const_19;
    assign signal_mux_16 = signal_wire_12 ? signal_mux_15 : signal_reg_5;
    assign signal_mux_17 = signal_wire_13 ? signal_const_19 : signal_mux_16;
    assign signal_wire_8 = signal_mux_17;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_5 <= signal_const_19;
        else
            signal_reg_5 <= signal_wire_8;
    end
    always @* begin
        case (signal_reg_5)
        3'b111:
            signal_cases_5 <= signal_const_13;
        default:
            signal_cases_5 <= signal_mux_19;
        endcase
    end
    assign signal_mux_18 = signal_and_4 ? signal_cases_5 : signal_mux_19;
    assign signal_wire_9 = request_ready;
    assign signal_and_2 = signal_reg_6 & signal_wire_9;
    assign signal_mux_19 = signal_and_2 ? signal_const_12 : signal_reg_6;
    assign signal_mux_20 = signal_wire_12 ? signal_mux_18 : signal_mux_19;
    assign signal_mux_21 = signal_wire_13 ? signal_const_12 : signal_mux_20;
    assign signal_wire_10 = signal_mux_21;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_6 <= signal_const_12;
        else
            signal_reg_6 <= signal_wire_10;
    end
    assign signal_not_3 = ~ signal_reg_6;
    assign signal_wire_11 = receive_enable;
    assign signal_and_3 = signal_wire_11 & signal_not_3;
    assign signal_and_4 = signal_and_3 & signal_not_2;
    assign signal_mux_22 = signal_and_4 ? signal_cases_4 : signal_reg_7;
    assign signal_wire_12 = byte_valid;
    assign signal_mux_23 = signal_wire_12 ? signal_mux_22 : signal_reg_7;
    assign signal_wire_13 = framing_error;
    assign signal_mux_24 = signal_wire_13 ? signal_reg_7 : signal_mux_23;
    assign signal_wire_14 = signal_mux_24;
    always @(posedge signal_wire_7) begin
        if (signal_wire_6)
            signal_reg_7 <= signal_const;
        else
            signal_reg_7 <= signal_wire_14;
    end
    assign request$index = signal_reg_7;
    assign request$slot1_id = signal_reg_3;
    assign request$slot1_price = signal_reg_2;
    assign request$slot2_id = signal_reg_1;
    assign request$slot2_price = signal_reg;
    assign request_valid = signal_and_1;
    assign protocol_fault = signal_reg_4;

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
    reg [1:0] held_b;
    wire [1:0] signal_wire;
    reg [1:0] held_a;
    wire [1:0] signal_mux;
    wire signal_const_6;
    reg previous_below_b;
    wire signal_lt;
    wire signal_wire_1;
    reg previous_below_a;
    wire signal_mux_1;
    wire signal_not;
    wire signal_and;
    wire [1:0] signal_mux_2;
    reg previous_above_b;
    wire [3:0] signal_const_10;
    wire [19:0] signal_cat;
    wire signal_not_1;
    wire signal_and_1;
    wire [15:0] signal_const_11;
    wire [15:0] signal_wire_2;
    reg [15:0] signal_reg;
    (* syn_ramstyle="block_ram" *)
    reg [15:0] engine_history[0:31];
    wire [3:0] signal_wire_3;
    reg [3:0] signal_reg_1;
    wire [4:0] signal_cat_1;
    wire [15:0] signal_mem_read_port;
    reg [15:0] signal_reg_2;
    wire [19:0] signal_cat_2;
    wire signal_const_14;
    wire signal_eq;
    wire signal_and_2;
    wire [19:0] signal_const_15;
    reg [19:0] sum_b;
    wire signal_eq_1;
    wire signal_not_2;
    wire signal_eq_2;
    wire signal_and_3;
    wire signal_and_4;
    wire signal_and_5;
    wire signal_or;
    wire [19:0] signal_wire_4;
    reg [19:0] sum_a;
    wire [19:0] signal_mux_3;
    wire [19:0] signal_sub;
    wire [19:0] signal_mux_4;
    wire [19:0] signal_add;
    wire [15:0] signal_select;
    wire signal_lt_1;
    wire signal_wire_5;
    reg previous_above_a;
    wire signal_wire_6;
    reg signal_reg_3;
    wire signal_mux_5;
    wire signal_not_3;
    wire signal_and_6;
    wire [1:0] signal_mux_6;
    wire signal_wire_7;
    reg signal_reg_4;
    wire [1:0] signal_mux_7;
    reg [1:0] signal_reg_5;
    wire signal_not_4;
    wire [1:0] signal_const_21;
    wire signal_eq_3;
    wire signal_and_7;
    wire signal_wire_8;
    wire signal_not_5;
    wire signal_not_6;
    wire signal_wire_9;
    wire signal_wire_10;
    wire signal_wire_11;
    wire signal_and_8;
    wire [1:0] signal_mux_8;
    wire signal_wire_12;
    wire [1:0] signal_mux_9;
    wire signal_eq_4;
    wire [1:0] signal_mux_10;
    wire signal_eq_5;
    wire [1:0] signal_mux_11;
    wire [1:0] signal_mux_12;
    wire [1:0] signal_wire_13;
    reg [1:0] engine_state;
    wire signal_eq_6;
    wire signal_and_9;
    wire signal_and_10;
    assign signal_const = 2'b00;
    assign signal_const_2 = 2'b10;
    assign signal_const_3 = 2'b01;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            held_b <= signal_const;
        else
            if (signal_and_2)
                held_b <= signal_wire;
    end
    assign signal_wire = signal_mux_7;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            held_a <= signal_const;
        else
            if (signal_and_4)
                held_a <= signal_wire;
    end
    assign signal_mux = signal_reg_3 ? held_b : held_a;
    assign signal_const_6 = 1'b0;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            previous_below_b <= signal_const_6;
        else
            if (signal_and_2)
                previous_below_b <= signal_wire_1;
    end
    assign signal_lt = signal_reg < signal_select;
    assign signal_wire_1 = signal_lt;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            previous_below_a <= signal_const_6;
        else
            if (signal_and_4)
                previous_below_a <= signal_wire_1;
    end
    assign signal_mux_1 = signal_reg_3 ? previous_below_b : previous_below_a;
    assign signal_not = ~ signal_mux_1;
    assign signal_and = signal_not & signal_lt;
    assign signal_mux_2 = signal_and ? signal_const_3 : signal_mux;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            previous_above_b <= signal_const_6;
        else
            if (signal_and_2)
                previous_above_b <= signal_wire_5;
    end
    assign signal_const_10 = 4'b0000;
    assign signal_cat = { signal_const_10,
                          signal_reg };
    assign signal_not_1 = ~ signal_wire_9;
    assign signal_and_1 = signal_eq_5 & signal_not_1;
    assign signal_const_11 = 16'b0000000000000000;
    assign signal_wire_2 = update$price;
    always @(posedge signal_wire_10) begin
        if (signal_wire_9)
            signal_reg <= signal_const_11;
        else
            if (signal_and_8)
                signal_reg <= signal_wire_2;
    end
    always @(posedge signal_wire_10) begin
        if (signal_and_3)
            engine_history[signal_cat_1] <= signal_reg;
    end
    assign signal_wire_3 = update$window_position;
    always @(posedge signal_wire_10) begin
        if (signal_wire_9)
            signal_reg_1 <= signal_const_10;
        else
            if (signal_and_8)
                signal_reg_1 <= signal_wire_3;
    end
    assign signal_cat_1 = { signal_reg_3,
                            signal_reg_1 };
    assign signal_mem_read_port = engine_history[signal_cat_1];
    always @(posedge signal_wire_10) begin
        if (signal_and_1)
            signal_reg_2 <= signal_mem_read_port;
    end
    assign signal_cat_2 = { signal_const_10,
                            signal_reg_2 };
    assign signal_const_14 = 1'b1;
    assign signal_eq = signal_reg_3 == signal_const_14;
    assign signal_and_2 = signal_and_3 & signal_eq;
    assign signal_const_15 = 20'b00000000000000000000;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            sum_b <= signal_const_15;
        else
            if (signal_and_2)
                sum_b <= signal_wire_4;
    end
    assign signal_eq_1 = signal_reg_3 == signal_const_6;
    assign signal_not_2 = ~ signal_wire_9;
    assign signal_eq_2 = engine_state == signal_const_2;
    assign signal_and_3 = signal_eq_2 & signal_not_2;
    assign signal_and_4 = signal_and_3 & signal_eq_1;
    assign signal_and_5 = signal_eq_6 & signal_wire_8;
    assign signal_or = signal_wire_9 | signal_and_5;
    assign signal_wire_4 = signal_add;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            sum_a <= signal_const_15;
        else
            if (signal_and_4)
                sum_a <= signal_wire_4;
    end
    assign signal_mux_3 = signal_reg_3 ? sum_b : sum_a;
    assign signal_sub = signal_mux_3 - signal_cat_2;
    assign signal_mux_4 = signal_reg_4 ? signal_mux_3 : signal_sub;
    assign signal_add = signal_mux_4 + signal_cat;
    assign signal_select = signal_add[19:4];
    assign signal_lt_1 = signal_select < signal_reg;
    assign signal_wire_5 = signal_lt_1;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            previous_above_a <= signal_const_6;
        else
            if (signal_and_4)
                previous_above_a <= signal_wire_5;
    end
    assign signal_wire_6 = update$item_select;
    always @(posedge signal_wire_10) begin
        if (signal_wire_9)
            signal_reg_3 <= signal_const_6;
        else
            if (signal_and_8)
                signal_reg_3 <= signal_wire_6;
    end
    assign signal_mux_5 = signal_reg_3 ? previous_above_b : previous_above_a;
    assign signal_not_3 = ~ signal_mux_5;
    assign signal_and_6 = signal_not_3 & signal_lt_1;
    assign signal_mux_6 = signal_and_6 ? signal_const_2 : signal_mux_2;
    assign signal_wire_7 = update$warmup;
    always @(posedge signal_wire_10) begin
        if (signal_wire_9)
            signal_reg_4 <= signal_const_6;
        else
            if (signal_and_8)
                signal_reg_4 <= signal_wire_7;
    end
    assign signal_mux_7 = signal_reg_4 ? signal_const : signal_mux_6;
    always @(posedge signal_wire_10) begin
        if (signal_or)
            signal_reg_5 <= signal_const;
        else
            if (signal_and_3)
                signal_reg_5 <= signal_mux_7;
    end
    assign signal_not_4 = ~ signal_wire_9;
    assign signal_const_21 = 2'b11;
    assign signal_eq_3 = engine_state == signal_const_21;
    assign signal_and_7 = signal_eq_3 & signal_not_4;
    assign signal_wire_8 = session_clear;
    assign signal_not_5 = ~ signal_wire_8;
    assign signal_not_6 = ~ signal_wire_9;
    assign signal_wire_9 = reset;
    assign signal_wire_10 = clock;
    assign signal_wire_11 = update_valid;
    assign signal_and_8 = signal_and_10 & signal_wire_11;
    assign signal_mux_8 = signal_and_8 ? signal_const_3 : engine_state;
    assign signal_wire_12 = result_ready;
    assign signal_mux_9 = signal_wire_12 ? signal_const : engine_state;
    assign signal_eq_4 = engine_state == signal_const_2;
    assign signal_mux_10 = signal_eq_4 ? signal_const_21 : signal_mux_9;
    assign signal_eq_5 = engine_state == signal_const_3;
    assign signal_mux_11 = signal_eq_5 ? signal_const_2 : signal_mux_10;
    assign signal_mux_12 = signal_eq_6 ? signal_mux_8 : signal_mux_11;
    assign signal_wire_13 = signal_mux_12;
    always @(posedge signal_wire_10) begin
        if (signal_wire_9)
            engine_state <= signal_const;
        else
            engine_state <= signal_wire_13;
    end
    assign signal_eq_6 = engine_state == signal_const;
    assign signal_and_9 = signal_eq_6 & signal_not_6;
    assign signal_and_10 = signal_and_9 & signal_not_5;
    assign update_ready = signal_and_10;
    assign result_valid = signal_and_7;
    assign action = signal_reg_5;

endmodule
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
    wire signal_not;
    wire signal_inst;
    wire signal_wire;
    wire signal_select_1;
    wire signal_wire_1;
    wire signal_select_2;
    wire signal_select_3;
    wire signal_select_4;
    wire [1:0] signal_select_5;
    wire [1:0] signal_select_6;
    wire [7:0] signal_select_7;
    wire [7:0] signal_select_8;
    wire signal_select_9;
    wire signal_wire_2;
    wire signal_select_10;
    wire signal_wire_3;
    wire [1:0] signal_select_11;
    wire [1:0] signal_wire_4;
    wire signal_select_12;
    wire signal_wire_5;
    wire signal_select_13;
    wire signal_select_14;
    wire signal_select_15;
    wire [3:0] signal_select_16;
    wire [15:0] signal_select_17;
    wire signal_select_18;
    wire signal_select_19;
    wire [3:0] signal_inst_1;
    wire signal_select_20;
    wire signal_wire_6;
    wire signal_select_21;
    wire [15:0] signal_select_22;
    wire [7:0] signal_select_23;
    wire [15:0] signal_select_24;
    wire [7:0] signal_select_25;
    wire signal_select_26;
    wire signal_wire_7;
    wire signal_select_27;
    wire signal_select_28;
    wire vdd;
    wire signal_wire_8;
    reg signal_reg = 1'b1;
    reg signal_reg_1 = 1'b1;
    wire [9:0] signal_inst_2;
    wire [7:0] signal_select_29;
    wire signal_select_30;
    wire signal_wire_9;
    wire [65:0] signal_inst_3;
    wire [15:0] signal_select_31;
    wire [63:0] signal_inst_4;
    wire [15:0] signal_select_32;
    wire [10:0] signal_inst_5;
    wire [7:0] signal_select_33;
    wire [7:0] signal_wire_10;
    wire signal_wire_11;
    wire signal_inst_6;
    wire signal_wire_12;
    wire signal_wire_13;
    wire [2:0] signal_inst_7;
    wire signal_select_34;
    assign signal_select = signal_inst_3[65:65];
    assign signal_not = ~ signal_select;
    gqh_heartbeat
        heartbeat
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .led_n(signal_inst) );
    assign signal_wire = signal_inst;
    assign signal_select_1 = signal_inst_5[10:10];
    assign signal_wire_1 = signal_select_1;
    assign signal_select_2 = signal_inst_7[2:2];
    assign signal_select_3 = signal_inst_7[1:1];
    assign signal_select_4 = signal_inst_4[63:63];
    assign signal_select_5 = signal_inst_4[62:61];
    assign signal_select_6 = signal_inst_4[60:59];
    assign signal_select_7 = signal_inst_4[58:51];
    assign signal_select_8 = signal_inst_4[50:43];
    assign signal_select_9 = signal_inst_5[1:1];
    assign signal_wire_2 = signal_select_9;
    assign signal_select_10 = signal_inst_5[0:0];
    assign signal_wire_3 = signal_select_10;
    assign signal_select_11 = signal_inst_1[3:2];
    assign signal_wire_4 = signal_select_11;
    assign signal_select_12 = signal_inst_1[1:1];
    assign signal_wire_5 = signal_select_12;
    assign signal_select_13 = signal_inst_4[25:25];
    assign signal_select_14 = signal_inst_4[24:24];
    assign signal_select_15 = signal_inst_4[23:23];
    assign signal_select_16 = signal_inst_4[22:19];
    assign signal_select_17 = signal_inst_4[18:3];
    assign signal_select_18 = signal_inst_4[2:2];
    assign signal_select_19 = signal_inst_4[26:26];
    gqh_update_engine
        engine
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .session_clear(signal_select_19),
          .update$item_select(signal_select_18),
          .update$price(signal_select_17),
          .update$window_position(signal_select_16),
          .update$warmup(signal_select_15),
          .update_valid(signal_select_14),
          .result_ready(signal_select_13),
          .update_ready(signal_inst_1[0:0]),
          .result_valid(signal_inst_1[1:1]),
          .action(signal_inst_1[3:2]) );
    assign signal_select_20 = signal_inst_1[0:0];
    assign signal_wire_6 = signal_select_20;
    assign signal_select_21 = signal_inst_3[64:64];
    assign signal_select_22 = signal_inst_3[63:48];
    assign signal_select_23 = signal_inst_3[47:40];
    assign signal_select_24 = signal_inst_3[39:24];
    assign signal_select_25 = signal_inst_3[23:16];
    assign signal_select_26 = signal_inst_4[0:0];
    assign signal_wire_7 = signal_select_26;
    assign signal_select_27 = signal_inst_2[9:9];
    assign signal_select_28 = signal_inst_2[8:8];
    assign vdd = 1'b1;
    assign signal_wire_8 = uart_rx_i;
    always @(posedge signal_wire_13) begin
        if (signal_wire_12)
            signal_reg <= vdd;
        else
            signal_reg <= signal_wire_8;
    end
    always @(posedge signal_wire_13) begin
        if (signal_wire_12)
            signal_reg_1 <= vdd;
        else
            signal_reg_1 <= signal_reg;
    end
    gqh_uart_rx
        uart_rx
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .rx(signal_reg_1),
          .byte_data(signal_inst_2[7:0]),
          .byte_valid(signal_inst_2[8:8]),
          .framing_error(signal_inst_2[9:9]) );
    assign signal_select_29 = signal_inst_2[7:0];
    assign signal_select_30 = signal_inst_4[1:1];
    assign signal_wire_9 = signal_select_30;
    gqh_request_decoder
        request_decoder
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .receive_enable(signal_wire_9),
          .byte_data(signal_select_29),
          .byte_valid(signal_select_28),
          .framing_error(signal_select_27),
          .request_ready(signal_wire_7),
          .request$index(signal_inst_3[15:0]),
          .request$slot1_id(signal_inst_3[23:16]),
          .request$slot1_price(signal_inst_3[39:24]),
          .request$slot2_id(signal_inst_3[47:40]),
          .request$slot2_price(signal_inst_3[63:48]),
          .request_valid(signal_inst_3[64:64]),
          .protocol_fault(signal_inst_3[65:65]) );
    assign signal_select_31 = signal_inst_3[15:0];
    gqh_transaction_controller
        controller
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .request$index(signal_select_31),
          .request$slot1_id(signal_select_25),
          .request$slot1_price(signal_select_24),
          .request$slot2_id(signal_select_23),
          .request$slot2_price(signal_select_22),
          .request_valid(signal_select_21),
          .update_ready(signal_wire_6),
          .result_valid(signal_wire_5),
          .action(signal_wire_4),
          .response_ready(signal_wire_3),
          .response_done(signal_wire_2),
          .request_ready(signal_inst_4[0:0]),
          .receive_enable(signal_inst_4[1:1]),
          .update$item_select(signal_inst_4[2:2]),
          .update$price(signal_inst_4[18:3]),
          .update$window_position(signal_inst_4[22:19]),
          .update$warmup(signal_inst_4[23:23]),
          .update_valid(signal_inst_4[24:24]),
          .result_ready(signal_inst_4[25:25]),
          .session_clear(signal_inst_4[26:26]),
          .response$index(signal_inst_4[42:27]),
          .response$slot1_id(signal_inst_4[50:43]),
          .response$slot2_id(signal_inst_4[58:51]),
          .response$slot1_action(signal_inst_4[60:59]),
          .response$slot2_action(signal_inst_4[62:61]),
          .response_valid(signal_inst_4[63:63]) );
    assign signal_select_32 = signal_inst_4[42:27];
    gqh_response_sequencer
        response_sequencer
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .response$index(signal_select_32),
          .response$slot1_id(signal_select_8),
          .response$slot2_id(signal_select_7),
          .response$slot1_action(signal_select_6),
          .response$slot2_action(signal_select_5),
          .response_valid(signal_select_4),
          .tx_ready(signal_select_3),
          .tx_busy(signal_select_2),
          .response_ready(signal_inst_5[0:0]),
          .response_done(signal_inst_5[1:1]),
          .tx_data(signal_inst_5[9:2]),
          .tx_valid(signal_inst_5[10:10]) );
    assign signal_select_33 = signal_inst_5[9:2];
    assign signal_wire_10 = signal_select_33;
    assign signal_wire_11 = reset_btn;
    gqh_reset_release
        reset_release
        ( .clock(signal_wire_13),
          .reset_btn(signal_wire_11),
          .reset(signal_inst_6) );
    assign signal_wire_12 = signal_inst_6;
    assign signal_wire_13 = sys_clk;
    gqh_uart_tx
        uart_tx
        ( .clock(signal_wire_13),
          .reset(signal_wire_12),
          .tx_data(signal_wire_10),
          .tx_valid(signal_wire_1),
          .tx(signal_inst_7[0:0]),
          .tx_ready(signal_inst_7[1:1]),
          .tx_busy(signal_inst_7[2:2]) );
    assign signal_select_34 = signal_inst_7[0:0];
    assign uart_tx_o = signal_select_34;
    assign led0_n = signal_wire;
    assign led1_n = signal_not;

endmodule
