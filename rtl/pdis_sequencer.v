/*
 * pdis_sequencer: PIO-inspired sequencer for protocol replay.
 * Executes a program of instructions to drive/sample pins.
 * Instruction set: DRIVE, WAIT, SAMPLE, SHIFT, BRANCH, CRC, CALL, RET, LOAD, XOR, SYNC, JUMP
 */
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
    input  wire [7:0]              prog_len,
    // Pin interface (separate I/O for external bidirectional handling)
    input  wire [NUM_PINS-1:0]     pin_in,
    output reg [NUM_PINS-1:0]      pin_out,
    output reg [NUM_PINS-1:0]      pin_oe,
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
    localparam OP_SYNC     = 4'd11;  // Edge resync / pin change detection
    localparam OP_JUMP     = 4'd12;  // Unconditional jump (for loops/back-to-back)

    localparam DRV_LOW     = 2'd0;
    localparam DRV_HIGH    = 2'd1;
    localparam DRV_Z       = 2'd2;
    localparam DRV_REG     = 2'd3;

    // WAIT modes (wait_mode[3:2])
    localparam WAIT_CYCLES  = 2'd0;
    localparam WAIT_HIGH    = 2'd1;
    localparam WAIT_LOW     = 2'd2;
    localparam WAIT_CHANGE  = 2'd3;

    // SYNC modes (sync_mode[1:0] in wait_mode[5:4])
    localparam SYNC_RISE    = 2'd0;
    localparam SYNC_FALL    = 2'd1;
    localparam SYNC_ANY     = 2'd2;
    localparam SYNC_LEVEL   = 2'd3;

    // Register file
    reg [REG_W-1:0] reg_file [0:NUM_REGS-1];

    // State
    reg [2:0] st;
    reg [2:0] next_st;
    localparam S_IDLE    = 3'd0;
    localparam S_FETCH   = 3'd1;
    localparam S_EXECUTE = 3'd2;
    localparam S_WAIT    = 3'd3;
    localparam S_SYNC    = 3'd4;
    localparam S_DONE    = 3'd5;

    reg [PROG_W-1:0] instr;
    reg [15:0] wait_cnt;
    reg [5:0] wait_mode;  // Extended for SYNC: [5:4]=sync_mode, [3:0]=pin_mask
    reg [7:0] call_stack [0:7];
    reg [2:0] sp;

    // Edge detection: store previous pin_in for edge detection
    reg [NUM_PINS-1:0] pin_in_prev;
    reg [NUM_PINS-1:0] pin_in_sync;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            pc <= 8'd0;
            prog_addr <= 8'd0;
            done <= 1'b0;
            error <= 1'b0;
            pin_out <= {NUM_PINS{1'b0}};
            pin_oe <= {NUM_PINS{1'b0}};
            wait_cnt <= 16'd0;
            wait_mode <= 6'd0;
            sp <= 3'd0;
            pin_in_prev <= {NUM_PINS{1'b0}};
            pin_in_sync <= {NUM_PINS{1'b0}};
            for (i = 0; i < NUM_REGS; i = i + 1) reg_file[i] <= {REG_W{1'b0}};
            for (i = 0; i < 8; i = i + 1) call_stack[i] <= 8'd0;
        end else begin
            // Synchronize pin_in (2-stage for metastability protection)
            pin_in_prev <= pin_in_sync;
            pin_in_sync <= pin_in;

            // Default next state is current state
            next_st = st;

            case (st)
                S_IDLE: begin
                    done <= 1'b0;
                    error <= 1'b0;
                    pc <= 8'd0;
                    prog_addr <= 8'd0;
                    pin_oe <= {NUM_PINS{1'b0}};
                    sp <= 3'd0;
                    if (start && prog_valid) begin
                        next_st = S_FETCH;
                    end
                end

                S_FETCH: begin
                    if (pc >= prog_len) begin
                        done <= 1'b1;
                        next_st = S_DONE;
                    end else begin
                        prog_addr <= pc;
                        next_st = S_EXECUTE;
                    end
                end

                S_EXECUTE: begin
                    instr <= prog_data;
                    case (prog_data[31:28])
                        OP_NOP: begin
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
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
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
                        end

                        OP_WAIT: begin
                            wait_cnt <= prog_data[15:0];
                            wait_mode <= {2'b00, prog_data[23:20]};
                            pc <= pc + 1'b1;
                            next_st = S_WAIT;
                        end

                        OP_SAMPLE: begin
                            reg [3:0] pin_mask;
                            pin_mask = prog_data[23:20];
                            reg_file[prog_data[27:24]] <= {12'd0, pin_in_sync & pin_mask};
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
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
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
                        end

                        OP_BRANCH: begin
                            if (reg_file[prog_data[23:20]] != 0) begin
                                pc <= prog_data[15:8];
                            end else begin
                                pc <= pc + 1'b1;
                            end
                            next_st = S_FETCH;
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
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
                        end

                        OP_CALL: begin
                            call_stack[sp] <= pc + 1'b1;
                            sp <= sp + 1'b1;
                            pc <= prog_data[15:8];
                            next_st = S_FETCH;
                        end

                        OP_RET: begin
                            if (sp > 0) begin
                                sp <= sp - 1'b1;
                                pc <= call_stack[sp - 1'b1];
                            end else begin
                                error <= 1'b1;
                                pc <= pc + 1'b1;
                            end
                            next_st = S_FETCH;
                        end

                        OP_LOAD: begin
                            reg_file[prog_data[27:24]] <= prog_data[15:0];
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
                        end

                        OP_XOR: begin
                            reg_file[prog_data[27:24]] <= reg_file[prog_data[23:20]] ^ reg_file[prog_data[19:16]];
                            pc <= pc + 1'b1;
                            next_st = S_FETCH;
                        end

                        OP_SYNC: begin
                            wait_cnt <= prog_data[15:0];
                            wait_mode <= {prog_data[23:22], prog_data[27:24]};
                            pc <= pc + 1'b1;
                            next_st = S_SYNC;
                        end

                        OP_JUMP: begin
                            if (prog_data[7:0] == 0) begin
                                reg [3:0] loop_reg;
                                loop_reg = prog_data[23:20];
                                if (reg_file[loop_reg] > 0) begin
                                    reg_file[loop_reg] <= reg_file[loop_reg] - 1'b1;
                                    pc <= prog_data[15:8];
                                end else begin
                                    pc <= pc + 1'b1;
                                end
                            end else begin
                                pc <= prog_data[15:8];
                            end
                            next_st = S_FETCH;
                        end

                        default: begin
                            error <= 1'b1;
                            next_st = S_DONE;
                        end
                    endcase
                end

                S_WAIT: begin
                    case (wait_mode[3:2])
                        WAIT_CYCLES: begin
                            if (wait_cnt == 0) next_st = S_FETCH;
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        WAIT_HIGH: begin
                            if ((pin_in_sync & wait_mode[1:0]) != 0) next_st = S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; next_st = S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        WAIT_LOW: begin
                            if ((pin_in_sync & wait_mode[1:0]) == 0) next_st = S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; next_st = S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                        WAIT_CHANGE: begin
                            if ((pin_in_sync ^ reg_file[0][3:0]) != 0) next_st = S_FETCH;
                            else if (wait_cnt == 0) begin error <= 1'b1; next_st = S_DONE; end
                            else wait_cnt <= wait_cnt - 1'b1;
                        end
                    endcase
                end

                S_SYNC: begin
                    reg [3:0] pin_mask;
                    reg [1:0] sync_mode;
                    reg [1:0] target_level;
                    reg [NUM_PINS-1:0] rising_edges;
                    reg [NUM_PINS-1:0] falling_edges;
                    reg sync_matched;
                    
                    pin_mask = wait_mode[3:0];
                    sync_mode = wait_mode[5:4];
                    target_level = wait_mode[5:4];
                    
                    // Detect edges using current pin_in vs previous synchronized pin_in_sync
                    rising_edges = (pin_in & ~pin_in_sync) & pin_mask;
                    falling_edges = (~pin_in & pin_in_sync) & pin_mask;
                    sync_matched = 1'b0;
                    
                    // DEBUG
                    $display("t=%0t SYNC_DEBUG: st=S_SYNC pc=%d pin_in=%b pin_in_sync=%b pin_mask=%b rising=%b falling=%b sync_mode=%d wait_cnt=%d", 
                             $time, pc, pin_in, pin_in_sync, pin_mask, rising_edges, falling_edges, sync_mode, wait_cnt);
                    
                    case (sync_mode)
                        SYNC_RISE: begin
                            if (rising_edges != 0) sync_matched = 1'b1;
                        end
                        SYNC_FALL: begin
                            if (falling_edges != 0) sync_matched = 1'b1;
                        end
                        SYNC_ANY: begin
                            if ((rising_edges | falling_edges) != 0) sync_matched = 1'b1;
                        end
                        SYNC_LEVEL: begin
                            if (((pin_in_sync ^ {6'd0, target_level}) & pin_mask) == 0) sync_matched = 1'b1;
                        end
                    endcase
                    
                    if (sync_matched) begin
                        $display("t=%0t SYNC_MATCHED: pc=%d next_st=S_FETCH", $time, pc);
                        next_st = S_FETCH;
                    end else if (wait_cnt == 0) begin
                        error <= 1'b1;
                        next_st = S_DONE;
                    end else begin
                        wait_cnt <= wait_cnt - 1'b1;
                    end
                end

                S_DONE: begin
                    done <= 1'b1;
                    if (!start) next_st = S_IDLE;
                end
            endcase

            // Apply next state
            st <= next_st;
        end
    end
endmodule
