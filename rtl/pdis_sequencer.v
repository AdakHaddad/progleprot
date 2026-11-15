// pdis_sequencer: PIO-inspired sequencer for protocol replay.
// Executes a program of instructions to drive/sample pins.
// Instruction set: DRIVE, WAIT, SAMPLE, SHIFT, BRANCH, CRC
module pdis_sequencer #(
    parameter PROG_DEPTH = 256,
    parameter PROG_W = 32,
    parameter NUM_PINS = 8,
    parameter REG_W = 16,
    parameter NUM_REGS = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Program ROM interface
    output reg [7:0]               prog_addr,
    input  wire [PROG_W-1:0]       prog_data,
    input  wire                    prog_valid,
    input  wire [7:0]              prog_len,  // Program length (number of valid instructions)
    // Pin interface
    inout  wire [NUM_PINS-1:0]     pins,
    // Control
    input  wire                    start,
    output reg                     done,
    output reg                     error,
    // Status
    output reg [7:0]               pc
);

    // Instruction encoding
    localparam OP_NOP      = 4'd0;
    localparam OP_DRIVE    = 4'd1;
    localparam OP_WAIT     = 4'd2;
    localparam OP_SAMPLE   = 4'd3;
    localparam OP_SHIFT    = 4'd4;
    localparam OP_BRANCH   = 4'd5;
    localparam OP_CRC      = 4'd6;
    localparam OP_CALL     = 4'd7;
    localparam OP_RET      = 4'd8;
    localparam OP_LOAD     = 4'd9;
    localparam OP_XOR      = 4'd10;

    localparam DRV_LOW     = 2'd0;
    localparam DRV_HIGH    = 2'd1;
    localparam DRV_Z       = 2'd2;
    localparam DRV_REG     = 2'd3;

    // Pin I/O
    reg [NUM_PINS-1:0] pin_out;
    reg [NUM_PINS-1:0] pin_oe;
    reg [NUM_PINS-1:0] pin_in;
    assign pins = pin_oe ? pin_out : {NUM_PINS{1'bz}};
    always @(*) pin_in = pins;

    // Register file (internal)
    reg [REG_W-1:0] reg_file [0:NUM_REGS-1];

    // State
    reg [1:0] st;
    localparam S_IDLE    = 2'd0;
    localparam S_FETCH   = 2'd1;
    localparam S_EXECUTE = 2'd2;
    localparam S_WAIT    = 2'd3;
    localparam S_DONE    = 2'd4;

    reg [PROG_W-1:0] instr;
    reg [7:0] next_pc;
    reg [15:0] wait_cnt;
    reg [3:0] wait_mode;
    reg [7:0] call_stack [0:7];
    reg [2:0] sp;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            pc <= 8'd0;
            next_pc <= 8'd0;
            prog_addr <= 8'd0;
            done <= 1'b0;
            error <= 1'b0;
            pin_out <= {NUM_PINS{1'b0}};
            pin_oe <= {NUM_PINS{1'b0}};
            wait_cnt <= 16'd0;
            wait_mode <= 4'd0;
            sp <= 3'd0;
            for (i = 0; i < NUM_REGS; i = i + 1) reg_file[i] <= {REG_W{1'b0}};
            for (i = 0; i < 8; i = i + 1) call_stack[i] <= 8'd0;
        end else begin
            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    pc <= 8'd0;
                    next_pc <= 8'd0;
                    prog_addr <= 8'd0;
                    pin_oe <= {NUM_PINS{1'b0}};
                    sp <= 3'd0;
                    if (start && prog_valid) begin
                        st <= S_FETCH;
                    end
                end

                S_FETCH: begin
                    // Check program bounds
                    if (pc >= prog_len) begin
                        done <= 1'b1;
                        st <= S_DONE;
                    end else begin
                        prog_addr <= pc;
                        st <= S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    instr <= prog_data;
                    pc <= next_pc;
                    next_pc <= pc + 1'b1;
                    case (prog_data[31:28])
                        OP_NOP: begin
                            st <= S_FETCH;
                        end

                        OP_DRIVE: begin
                            reg [3:0] pin_mask;
                            reg [1:0] mode;
                            pin_mask = prog_data[27:24];
                            mode = prog_data[23:22];
                            case (mode)
                                DRV_LOW: begin
                                    pin_oe <= pin_oe | pin_mask;
                                    pin_out <= pin_out & ~pin_mask;
                                end
                                DRV_HIGH: begin
                                    pin_oe <= pin_oe | pin_mask;
                                    pin_out <= pin_out | pin_mask;
                                end
                                DRV_Z: begin
                                    pin_oe <= pin_oe & ~pin_mask;
                                end
                                DRV_REG: begin
                                    pin_oe <= pin_oe | pin_mask;
                                    pin_out <= (pin_out & ~pin_mask) | (reg_file[prog_data[21:20]][3:0] & pin_mask);
                                end
                            endcase
                            st <= S_FETCH;
                        end

                        OP_WAIT: begin
                            wait_cnt <= prog_data[15:0];
                            wait_mode <= prog_data[23:20];
                            st <= S_WAIT;
                        end

                        OP_SAMPLE: begin
                            reg [3:0] pin_mask;
                            pin_mask = prog_data[23:20];
                            reg_file[prog_data[27:24]] <= {12'd0, pin_in & pin_mask};
                            st <= S_FETCH;
                        end

                        OP_SHIFT: begin
                            reg [3:0] shift_cnt;
                            reg dir;
                            shift_cnt = prog_data[19:16];
                            dir = prog_data[20];
                            if (dir) begin
                                reg_file[prog_data[27:24]] <= reg_file[prog_data[23:20]] << shift_cnt;
                            end else begin
                                reg_file[prog_data[27:24]] <= reg_file[prog_data[23:20]] >> shift_cnt;
                            end
                            st <= S_FETCH;
                        end

                        OP_BRANCH: begin
                            if (reg_file[prog_data[23:20]] != 0) begin
                                next_pc <= prog_data[15:8];
                            end
                            st <= S_FETCH;
                        end

                        OP_CRC: begin
                            reg [15:0] crc;
                            reg [15:0] data_val;
                            crc = reg_file[prog_data[27:24]];
                            data_val = reg_file[prog_data[23:20]];
                            for (i = 0; i < 16; i = i + 1) begin
                                if ((crc[15] ^ data_val[15-i]) == 1'b1)
                                    crc = (crc << 1) ^ 16'h1021;
                                else
                                    crc = crc << 1;
                            end
                            reg_file[prog_data[27:24]] <= crc;
                            st <= S_FETCH;
                        end

                        OP_CALL: begin
                            call_stack[sp] <= next_pc;
                            sp <= sp + 1'b1;
                            next_pc <= prog_data[15:8];
                            st <= S_FETCH;
                        end

                        OP_RET: begin
                            if (sp > 0) begin
                                sp <= sp - 1'b1;
                                next_pc <= call_stack[sp - 1'b1];
                            end else begin
                                error <= 1'b1;
                            end
                            st <= S_FETCH;
                        end

                        OP_LOAD: begin
                            reg_file[prog_data[27:24]] <= prog_data[15:0];
                            st <= S_FETCH;
                        end

                        OP_XOR: begin
                            reg_file[prog_data[27:24]] <= reg_file[prog_data[23:20]] ^ reg_file[prog_data[19:16]];
                            st <= S_FETCH;
                        end

                        default: begin
                            error <= 1'b1;
                            st <= S_DONE;
                        end
                    endcase
                end

                S_WAIT: begin
                    case (wait_mode[3:2])
                        2'd0: begin // Wait cycles
                            if (wait_cnt == 0) st <= S_FETCH;
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        2'd1: begin // Wait for pin high
                            if ((pin_in & wait_mode[1:0]) != 0) st <= S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; st <= S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        2'd2: begin // Wait for pin low
                            if ((pin_in & wait_mode[1:0]) == 0) st <= S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; st <= S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        2'd3: begin // Wait for pin change
                            if ((pin_in ^ reg_file[0][3:0]) != 0) st <= S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; st <= S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                    endcase
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (!start) st <= S_IDLE;
                end
            endcase
        end
    end
endmodule
