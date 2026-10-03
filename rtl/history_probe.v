module history_probe (
    clock,
    write_enable,
    write_address,
    write_data,
    read_address,
    read_data
);

    input clock;
    input write_enable;
    input [4:0] write_address;
    input [15:0] write_data;
    input [4:0] read_address;
    output [15:0] read_data;

    wire signal_wire;
    wire [15:0] signal_wire_1;
    wire [4:0] signal_wire_2;
    wire signal_wire_3;
    reg [15:0] history[0:31];
    wire [4:0] signal_wire_4;
    wire [15:0] signal_mem_read_port;
    reg [15:0] signal_reg;
    assign signal_wire = write_enable;
    assign signal_wire_1 = write_data;
    assign signal_wire_2 = write_address;
    assign signal_wire_3 = clock;
    always @(posedge signal_wire_3) begin
        if (signal_wire)
            history[signal_wire_2] <= signal_wire_1;
    end
    assign signal_wire_4 = read_address;
    assign signal_mem_read_port = history[signal_wire_4];
    always @(posedge signal_wire_3) begin
        signal_reg <= signal_mem_read_port;
    end
    assign read_data = signal_reg;

endmodule
