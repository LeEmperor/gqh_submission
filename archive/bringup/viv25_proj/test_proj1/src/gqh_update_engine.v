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
    wire signal_lt;
    wire signal_lt_1;
    wire signal_not;
    wire signal_and;
    wire [1:0] signal_mux_1;
    wire [15:0] signal_select;
    wire signal_lt_2;
    wire [15:0] signal_const_6;
    reg [15:0] previous_b;
    reg [15:0] previous_a;
    wire [15:0] signal_mux_2;
    wire signal_const_8;
    wire signal_eq;
    wire signal_and_1;
    wire [19:0] signal_const_9;
    reg [19:0] sum_b;
    wire signal_const_10;
    wire signal_eq_1;
    wire signal_and_2;
    wire signal_and_3;
    wire signal_or;
    wire [3:0] signal_const_12;
    wire [19:0] signal_cat;
    wire signal_not_1;
    wire signal_and_4;
    wire signal_not_2;
    wire signal_eq_2;
    wire signal_and_5;
    wire [15:0] signal_wire_1;
    reg [15:0] signal_reg;
    reg [15:0] engine_history[0:31];
    wire [3:0] signal_wire_2;
    reg [3:0] signal_reg_1;
    wire [4:0] signal_cat_1;
    wire [15:0] signal_mem_read_port;
    reg [15:0] signal_reg_2;
    wire [19:0] signal_cat_2;
    wire [19:0] signal_sub;
    wire [19:0] signal_mux_3;
    wire [19:0] signal_add;
    wire [19:0] signal_wire_3;
    reg [19:0] sum_a;
    wire signal_wire_4;
    reg signal_reg_3;
    wire [19:0] signal_mux_4;
    wire [15:0] signal_select_1;
    wire signal_lt_3;
    wire signal_not_3;
    wire signal_and_6;
    wire [1:0] signal_mux_5;
    wire signal_wire_5;
    reg signal_reg_4;
    wire [1:0] signal_mux_6;
    reg [1:0] signal_reg_5;
    wire signal_not_4;
    wire [1:0] signal_const_19;
    wire signal_eq_3;
    wire signal_and_7;
    wire signal_wire_6;
    wire signal_not_5;
    wire signal_not_6;
    wire signal_wire_7;
    wire signal_wire_8;
    wire signal_wire_9;
    wire signal_and_8;
    wire [1:0] signal_mux_7;
    wire signal_wire_10;
    wire [1:0] signal_mux_8;
    wire signal_eq_4;
    wire [1:0] signal_mux_9;
    wire signal_eq_5;
    wire [1:0] signal_mux_10;
    wire [1:0] signal_mux_11;
    wire [1:0] signal_wire_11;
    reg [1:0] engine_state;
    wire signal_eq_6;
    wire signal_and_9;
    wire signal_and_10;
    assign signal_const = 2'b00;
    assign signal_const_2 = 2'b10;
    assign signal_const_3 = 2'b01;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            held_b <= signal_const;
        else
            if (signal_and_1)
                held_b <= signal_wire;
    end
    assign signal_wire = signal_mux_6;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            held_a <= signal_const;
        else
            if (signal_and_2)
                held_a <= signal_wire;
    end
    assign signal_mux = signal_reg_3 ? held_b : held_a;
    assign signal_lt = signal_reg < signal_select;
    assign signal_lt_1 = signal_mux_2 < signal_select_1;
    assign signal_not = ~ signal_lt_1;
    assign signal_and = signal_not & signal_lt;
    assign signal_mux_1 = signal_and ? signal_const_3 : signal_mux;
    assign signal_select = signal_add[19:4];
    assign signal_lt_2 = signal_select < signal_reg;
    assign signal_const_6 = 16'b0000000000000000;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            previous_b <= signal_const_6;
        else
            if (signal_and_1)
                previous_b <= signal_reg;
    end
    always @(posedge signal_wire_8) begin
        if (signal_or)
            previous_a <= signal_const_6;
        else
            if (signal_and_2)
                previous_a <= signal_reg;
    end
    assign signal_mux_2 = signal_reg_3 ? previous_b : previous_a;
    assign signal_const_8 = 1'b1;
    assign signal_eq = signal_reg_3 == signal_const_8;
    assign signal_and_1 = signal_and_5 & signal_eq;
    assign signal_const_9 = 20'b00000000000000000000;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            sum_b <= signal_const_9;
        else
            if (signal_and_1)
                sum_b <= signal_wire_3;
    end
    assign signal_const_10 = 1'b0;
    assign signal_eq_1 = signal_reg_3 == signal_const_10;
    assign signal_and_2 = signal_and_5 & signal_eq_1;
    assign signal_and_3 = signal_eq_6 & signal_wire_6;
    assign signal_or = signal_wire_7 | signal_and_3;
    assign signal_const_12 = 4'b0000;
    assign signal_cat = { signal_const_12,
                          signal_reg };
    assign signal_not_1 = ~ signal_wire_7;
    assign signal_and_4 = signal_eq_5 & signal_not_1;
    assign signal_not_2 = ~ signal_wire_7;
    assign signal_eq_2 = engine_state == signal_const_2;
    assign signal_and_5 = signal_eq_2 & signal_not_2;
    assign signal_wire_1 = update$price;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg <= signal_const_6;
        else
            if (signal_and_8)
                signal_reg <= signal_wire_1;
    end
    always @(posedge signal_wire_8) begin
        if (signal_and_5)
            engine_history[signal_cat_1] <= signal_reg;
    end
    assign signal_wire_2 = update$window_position;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_1 <= signal_const_12;
        else
            if (signal_and_8)
                signal_reg_1 <= signal_wire_2;
    end
    assign signal_cat_1 = { signal_reg_3,
                            signal_reg_1 };
    assign signal_mem_read_port = engine_history[signal_cat_1];
    always @(posedge signal_wire_8) begin
        if (signal_and_4)
            signal_reg_2 <= signal_mem_read_port;
    end
    assign signal_cat_2 = { signal_const_12,
                            signal_reg_2 };
    assign signal_sub = signal_mux_4 - signal_cat_2;
    assign signal_mux_3 = signal_reg_4 ? signal_mux_4 : signal_sub;
    assign signal_add = signal_mux_3 + signal_cat;
    assign signal_wire_3 = signal_add;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            sum_a <= signal_const_9;
        else
            if (signal_and_2)
                sum_a <= signal_wire_3;
    end
    assign signal_wire_4 = update$item_select;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_3 <= signal_const_10;
        else
            if (signal_and_8)
                signal_reg_3 <= signal_wire_4;
    end
    assign signal_mux_4 = signal_reg_3 ? sum_b : sum_a;
    assign signal_select_1 = signal_mux_4[19:4];
    assign signal_lt_3 = signal_select_1 < signal_mux_2;
    assign signal_not_3 = ~ signal_lt_3;
    assign signal_and_6 = signal_not_3 & signal_lt_2;
    assign signal_mux_5 = signal_and_6 ? signal_const_2 : signal_mux_1;
    assign signal_wire_5 = update$warmup;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            signal_reg_4 <= signal_const_10;
        else
            if (signal_and_8)
                signal_reg_4 <= signal_wire_5;
    end
    assign signal_mux_6 = signal_reg_4 ? signal_const : signal_mux_5;
    always @(posedge signal_wire_8) begin
        if (signal_or)
            signal_reg_5 <= signal_const;
        else
            if (signal_and_5)
                signal_reg_5 <= signal_mux_6;
    end
    assign signal_not_4 = ~ signal_wire_7;
    assign signal_const_19 = 2'b11;
    assign signal_eq_3 = engine_state == signal_const_19;
    assign signal_and_7 = signal_eq_3 & signal_not_4;
    assign signal_wire_6 = session_clear;
    assign signal_not_5 = ~ signal_wire_6;
    assign signal_not_6 = ~ signal_wire_7;
    assign signal_wire_7 = reset;
    assign signal_wire_8 = clock;
    assign signal_wire_9 = update_valid;
    assign signal_and_8 = signal_and_10 & signal_wire_9;
    assign signal_mux_7 = signal_and_8 ? signal_const_3 : engine_state;
    assign signal_wire_10 = result_ready;
    assign signal_mux_8 = signal_wire_10 ? signal_const : engine_state;
    assign signal_eq_4 = engine_state == signal_const_2;
    assign signal_mux_9 = signal_eq_4 ? signal_const_19 : signal_mux_8;
    assign signal_eq_5 = engine_state == signal_const_3;
    assign signal_mux_10 = signal_eq_5 ? signal_const_2 : signal_mux_9;
    assign signal_mux_11 = signal_eq_6 ? signal_mux_7 : signal_mux_10;
    assign signal_wire_11 = signal_mux_11;
    always @(posedge signal_wire_8) begin
        if (signal_wire_7)
            engine_state <= signal_const;
        else
            engine_state <= signal_wire_11;
    end
    assign signal_eq_6 = engine_state == signal_const;
    assign signal_and_9 = signal_eq_6 & signal_not_6;
    assign signal_and_10 = signal_and_9 & signal_not_5;
    assign update_ready = signal_and_10;
    assign result_valid = signal_and_7;
    assign action = signal_reg_5;

endmodule
