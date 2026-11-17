// sequencer_compiler: Compiles ranked protocol hypothesis into sequencer program.
// Takes protocol ID + parameters, outputs instruction sequence for pdis_sequencer.
module sequencer_compiler #(
    parameter PROG_DEPTH = 256,
    parameter PROG_W = 32,
    parameter MAX_INSTR = 64
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [3:0]              proto_id,
    input  wire [7:0]              proto_param,
    input  wire [7:0]              frame_len,
    input  wire [31:0]             frame_data,
    output reg                     done,
    output reg                     error,
    output reg [7:0]               prog_len,
    // Program memory read port (for m6_top to load after compilation)
    input  wire [7:0]              prog_rd_addr,
    output reg [PROG_W-1:0]        prog_rd_data
);

    // Instruction encoding (matches pdis_sequencer)
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

    // Program memory (internal)
    reg [PROG_W-1:0] prog_mem [0:PROG_DEPTH-1];

    // State machine: one instruction per cycle
    localparam S_IDLE         = 5'd0;
    localparam S_PROLOGUE     = 5'd1;
    localparam S_BODY         = 5'd2;
    localparam S_EPILOGUE     = 5'd3;
    localparam S_DONE         = 5'd4;

    // Sub-states for prologue
    localparam P_SPI_0 = 5'd0, P_SPI_1 = 5'd1, P_SPI_2 = 5'd2, P_SPI_3 = 5'd3, P_SPI_4 = 5'd4;
    localparam P_I2C_0 = 5'd0, P_I2C_1 = 5'd1, P_I2C_2 = 5'd2, P_I2C_3 = 5'd3, P_I2C_4 = 5'd4, P_I2C_5 = 5'd5, P_I2C_6 = 5'd6, P_I2C_7 = 5'd7;
    localparam P_UART_0 = 5'd0, P_UART_1 = 5'd1, P_UART_2 = 5'd2;

    // Sub-states for body (per bit)
    localparam B_SPI_0 = 5'd0, B_SPI_1 = 5'd1, B_SPI_2 = 5'd2, B_SPI_3 = 5'd3, B_SPI_4 = 5'd4, B_SPI_5 = 5'd5, B_SPI_6 = 5'd6, B_SPI_7 = 5'd7;
    localparam B_I2C_0 = 5'd0, B_I2C_1 = 5'd1, B_I2C_2 = 5'd2, B_I2C_3 = 5'd3, B_I2C_4 = 5'd4, B_I2C_5 = 5'd5, B_I2C_6 = 5'd6, B_I2C_7 = 5'd7, B_I2C_8 = 5'd8;
    localparam B_UART_0 = 5'd0, B_UART_1 = 5'd1, B_UART_2 = 5'd2, B_UART_3 = 5'd3;

    // Sub-states for epilogue
    localparam E_SPI_0 = 5'd0, E_SPI_1 = 5'd1;
    localparam E_I2C_0 = 5'd0, E_I2C_1 = 5'd1, E_I2C_2 = 5'd2, E_I2C_3 = 5'd3, E_I2C_4 = 5'd4;
    localparam E_UART_0 = 5'd0, E_UART_1 = 5'd1;

    reg [4:0] st;
    reg [4:0] sub_st;
    reg [7:0] idx;
    reg [7:0] bit_cnt;
    reg [3:0] proto;
    reg [31:0] frame_data_reg;
    reg [7:0] frame_len_reg;
    reg [7:0] next_bit_cnt;

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE;
            sub_st <= 5'd0;
            done <= 1'b0;
            error <= 1'b0;
            prog_len <= 8'd0;
            idx <= 6'd0;
            bit_cnt <= 8'd0;
            proto <= 4'd0;
            frame_data_reg <= 32'd0;
            frame_len_reg <= 8'd0;
            next_bit_cnt <= 8'd0;
            for (i = 0; i < PROG_DEPTH; i = i + 1) prog_mem[i] <= {PROG_W{1'b0}};
        end else begin
            done <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (start) begin
                        proto <= proto_id;
                        frame_data_reg <= frame_data;
                        frame_len_reg <= frame_len;
                        bit_cnt <= frame_len;
                        next_bit_cnt <= frame_len;
                        idx <= 6'd0;
                        sub_st <= 5'd0;
                        st <= S_PROLOGUE;
                    end
                end

                S_PROLOGUE: begin
                    case (proto)
                        4'd1: begin // SPI prologue (5 instructions)
                            case (sub_st)
                                P_SPI_0: prog_mem[idx] <= {OP_LOAD, 4'd1, 4'd0, 4'd0, frame_data_reg[15:0]};
                                P_SPI_1: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, frame_len_reg};
                                P_SPI_2: prog_mem[idx] <= {OP_LOAD, 4'd3, 4'd0, 4'd0, 16'd0};
                                P_SPI_3: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd0, 2'd0, 24'd0};
                                P_SPI_4: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd10};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == P_SPI_4) begin
                                sub_st <= 5'd0;
                                st <= S_BODY;
                            end
                        end
                        4'd2: begin // I2C prologue (8 instructions)
                            case (sub_st)
                                P_I2C_0: prog_mem[idx] <= {OP_LOAD, 4'd1, 4'd0, 4'd0, frame_data_reg[15:0]};
                                P_I2C_1: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, frame_len_reg};
                                P_I2C_2: prog_mem[idx] <= {OP_DRIVE, 4'd8, 2'd1, 2'd0, 24'd0};
                                P_I2C_3: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd1, 2'd0, 24'd0};
                                P_I2C_4: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                                P_I2C_5: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd0, 2'd0, 24'd0};
                                P_I2C_6: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                                P_I2C_7: prog_mem[idx] <= {OP_DRIVE, 4'd8, 2'd0, 2'd0, 24'd0};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == P_I2C_7) begin
                                sub_st <= 5'd0;
                                st <= S_BODY;
                            end
                        end
                        4'd3: begin // UART prologue (3 instructions)
                            case (sub_st)
                                P_UART_0: prog_mem[idx] <= {OP_LOAD, 4'd1, 4'd0, 4'd0, frame_data_reg[15:0]};
                                P_UART_1: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, 8'd10};
                                P_UART_2: prog_mem[idx] <= {OP_DRIVE, 4'd2, 2'd1, 2'd0, 24'd0};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == P_UART_2) begin
                                sub_st <= 5'd0;
                                st <= S_BODY;
                            end
                        end
                        default: begin
                            error <= 1'b1;
                            st <= S_DONE;
                        end
                    endcase
                end

                S_BODY: begin
                    case (proto)
                        4'd1: begin // SPI bit loop (8 instructions per bit)
                            if (bit_cnt == 0) begin
                                sub_st <= 5'd0;
                                st <= S_EPILOGUE;
                            end else begin
                                next_bit_cnt = bit_cnt - 1;
                                case (sub_st)
                                    B_SPI_0: prog_mem[idx] <= {OP_DRIVE, 4'd1, 2'd0, 2'd0, 24'd0};     // SCK low
                                    B_SPI_1: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd5};
                                    B_SPI_2: prog_mem[idx] <= {OP_DRIVE, 4'd2, 2'd0, 2'd0, 24'd0};     // DRIVE MOSI
                                    B_SPI_3: prog_mem[idx] <= {OP_DRIVE, 4'd1, 2'd1, 2'd0, 24'd0};     // SCK high
                                    B_SPI_4: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd5};
                                    B_SPI_5: prog_mem[idx] <= {OP_SAMPLE, 4'd3, 4'd2, 24'd0};         // Sample MISO
                                    B_SPI_6: prog_mem[idx] <= {OP_SHIFT, 4'd3, 4'd3, 4'd1, 4'd1, 16'd0}; // SHIFT R3
                                    B_SPI_7: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, next_bit_cnt}; // Decrement counter
                                endcase
                                idx <= idx + 1;
                                sub_st <= sub_st + 1;
                                if (sub_st == B_SPI_7) begin
                                    sub_st <= 5'd0;
                                    bit_cnt <= next_bit_cnt;
                                end
                            end
                        end
                        4'd2: begin // I2C bit loop (9 or 10 instructions per bit)
                            if (bit_cnt == 0) begin
                                sub_st <= 5'd0;
                                st <= S_EPILOGUE;
                            end else begin
                                next_bit_cnt = bit_cnt - 1;
                                case (sub_st)
                                    B_I2C_0: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd0, 2'd0, 24'd0};      // SDA from R1[7]
                                    B_I2C_1: prog_mem[idx] <= {OP_DRIVE, 4'd8, 2'd1, 2'd0, 24'd0};      // SCL high
                                    B_I2C_2: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                                    B_I2C_3: prog_mem[idx] <= {OP_SAMPLE, 4'd3, 4'd4, 24'd0};          // Sample SDA on ACK bit (bit_cnt==1)
                                    B_I2C_4: prog_mem[idx] <= {OP_DRIVE, 4'd8, 2'd0, 2'd0, 24'd0};      // SCL low
                                    B_I2C_5: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                                    B_I2C_6: prog_mem[idx] <= {OP_SHIFT, 4'd1, 4'd1, 4'd1, 4'd1, 16'd0}; // SHIFT R1 left
                                    B_I2C_7: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, next_bit_cnt}; // Decrement counter
                                endcase
                                idx <= idx + 1;
                                sub_st <= sub_st + 1;
                                // Skip SAMPLE on non-ACK bits
                                if (bit_cnt == 1) begin
                                    if (sub_st == B_I2C_7) begin
                                        sub_st <= 5'd0;
                                        bit_cnt <= next_bit_cnt;
                                    end
                                end else begin
                                    if (sub_st == B_I2C_2) begin
                                        // Skip B_I2C_3 (sample), go to B_I2C_4
                                        sub_st <= B_I2C_4;
                                    end else if (sub_st == B_I2C_7) begin
                                        sub_st <= 5'd0;
                                        bit_cnt <= next_bit_cnt;
                                    end
                                end
                            end
                        end
                        4'd3: begin // UART bit loop (4 instructions per bit)
                            if (bit_cnt == 0) begin
                                sub_st <= 5'd0;
                                st <= S_EPILOGUE;
                            end else begin
                                next_bit_cnt = bit_cnt - 1;
                                case (sub_st)
                                    B_UART_0: prog_mem[idx] <= {OP_DRIVE, 4'd2, 2'd0, 2'd0, 24'd0};     // Drive TX
                                    B_UART_1: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd100};
                                    B_UART_2: prog_mem[idx] <= {OP_SHIFT, 4'd1, 4'd1, 4'd1, 4'd0, 16'd0}; // SHIFT R1 right
                                    B_UART_3: prog_mem[idx] <= {OP_LOAD, 4'd2, 4'd0, 4'd0, 8'd0, next_bit_cnt}; // Decrement counter
                                endcase
                                idx <= idx + 1;
                                sub_st <= sub_st + 1;
                                if (sub_st == B_UART_3) begin
                                    sub_st <= 5'd0;
                                    bit_cnt <= next_bit_cnt;
                                end
                            end
                        end
                        default: begin
                            sub_st <= 5'd0;
                            st <= S_EPILOGUE;
                        end
                    endcase
                end

                S_EPILOGUE: begin
                    case (proto)
                        4'd1: begin // SPI epilogue (2 instructions)
                            case (sub_st)
                                E_SPI_0: prog_mem[idx] <= {OP_DRIVE, 4'd16, 2'd1, 2'd0, 24'd0};
                                E_SPI_1: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd10};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == E_SPI_1) begin
                                prog_mem[idx] <= {OP_NOP, 28'd0};
                                idx <= idx + 1;
                                prog_len <= idx;
                                st <= S_DONE;
                            end
                        end
                        4'd2: begin // I2C epilogue (5 instructions)
                            case (sub_st)
                                E_I2C_0: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd0, 2'd0, 24'd0};
                                E_I2C_1: prog_mem[idx] <= {OP_DRIVE, 4'd8, 2'd1, 2'd0, 24'd0};
                                E_I2C_2: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                                E_I2C_3: prog_mem[idx] <= {OP_DRIVE, 4'd4, 2'd1, 2'd0, 24'd0};
                                E_I2C_4: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd4};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == E_I2C_4) begin
                                prog_mem[idx] <= {OP_NOP, 28'd0};
                                idx <= idx + 1;
                                prog_len <= idx;
                                st <= S_DONE;
                            end
                        end
                        4'd3: begin // UART epilogue (2 instructions)
                            case (sub_st)
                                E_UART_0: prog_mem[idx] <= {OP_DRIVE, 4'd2, 2'd1, 2'd0, 24'd0};
                                E_UART_1: prog_mem[idx] <= {OP_WAIT, 4'd0, 4'd0, 16'd200};
                            endcase
                            idx <= idx + 1;
                            sub_st <= sub_st + 1;
                            if (sub_st == E_UART_1) begin
                                prog_mem[idx] <= {OP_NOP, 28'd0};
                                idx <= idx + 1;
                                prog_len <= idx;
                                st <= S_DONE;
                            end
                        end
                        default: begin
                            prog_mem[idx] <= {OP_NOP, 28'd0};
                            idx <= idx + 1;
                            prog_len <= idx;
                            st <= S_DONE;
                        end
                    endcase
                end

                S_DONE: begin
                    done <= 1'b1;
                end
            endcase
        end
    end
endmodule
