/*
 * cpu_core: 16-bit RISC-like CPU with custom timing instructions.
 * 4-stage pipeline: IF -> ID -> EX -> WB
 * 16 general-purpose registers (x0 hardwired to 0)
 * Custom instructions for pin/timer control (opcode 0xF)
 *
 * ISA Encoding (16-bit):
 *   OP_ALU  (0x0): [15:12]=0, [11:8]=rd, [7:4]=rs1, [3:0]=rs2  (ADD only for now)
 *   OP_IMM  (0x8): [15:12]=8, [11:8]=rd, [7:0]=imm8 (sign-ext), rs1=x0
 *   OP_BRANCH (0xA-0xE): Branch/jump instructions
 *   OP_CUSTOM(0xF): [15:12]=F, [11:8]=funct, [7:4]=rs1, [3:0]=rs2/rd
 */
module cpu_core #(
    parameter ADDR_W = 16,
    parameter DATA_W = 16
) (
    input  wire                    clk,
    input  wire                    rst_n,
    // Program memory interface (word address)
    output wire [ADDR_W-1:0]       prog_addr,
    input  wire [15:0]             prog_data,
    // Timer coprocessor interface
    output wire                    timer_wr_en,
    output wire [6:0]              timer_wr_addr,
    output wire [15:0]             timer_wr_data,
    input  wire [15:0]             timer_rd_data,
    // Pin matrix interface
    output wire                    pin_wr_en,
    output wire [3:0]              pin_wr_addr,
    output wire [15:0]             pin_wr_data,
    input  wire [15:0]             pin_rd_data,
    // Host interface
    output wire                    host_wr_en,
    output wire [3:0]              host_wr_addr,
    output wire [15:0]             host_wr_data,
    input  wire [15:0]             host_rd_data,
    // Control
    input  wire                    cpu_start,
    output wire                    cpu_done,
    output wire                    cpu_error,
    // Debug
    output wire [ADDR_W-1:0]       pc_debug,
    // Debug register read port
    input  wire [3:0]              dbg_reg_idx,
    output wire [15:0]             dbg_reg_data
    // Note: reg_debug array removed for Yosys compatibility
);

    // ISA Opcodes
    localparam OP_ALU      = 4'h0;  // ALU ops (ADD, etc.) - rd, rs1, rs2 in [11:8],[7:4],[3:0]
    localparam OP_IMM      = 4'h8;  // Immediate ops - rd in [11:8], imm8 in [7:0]
    localparam OP_MEM      = 4'hC;  // Memory ops (not fully implemented)
    localparam OP_BRANCH   = 4'hE;  // Branch ops (not fully implemented)
    localparam OP_CUSTOM   = 4'hF;  // Custom timing instructions

    // Branch opcodes (new)
    localparam OP_BEQZ     = 4'hA;  // Branch if rs1 == 0
    localparam OP_BNEZ     = 4'hB;  // Branch if rs1 != 0
    localparam OP_BLTZ     = 4'hC;  // Branch if rs1 < 0 (signed)
    localparam OP_BGEZ     = 4'hD;  // Branch if rs1 >= 0 (signed)
    localparam OP_JAL      = 4'hE;  // Jump and Link (rd = PC+2, PC += offset)

    // Custom timing instruction funct codes (for OP_CUSTOM)
    localparam FUNCT_OUT    = 4'h0;  // OUT pin, rs1 (pin in rs1[3:0], val in rs1[15:4]?)
    localparam FUNCT_DIR    = 4'h1;  // DIR pin, rs1
    localparam FUNCT_WAIT   = 4'h2;  // WAIT cycles, rs1 (timer), rs2 (cycles)
    localparam FUNCT_WAITE  = 4'h3;  // WAITE timer, rs1 (pin event)
    localparam FUNCT_TIME   = 4'h4;  // TIME rd, timer (timer in rs1[3:0])
    localparam FUNCT_TCFG   = 4'h5;  // TCFG timer, rs1, rs2
    localparam FUNCT_TUNING  = 4'h6;  // TUNING timer, rs1, rs2
    localparam FUNCT_PINSEL = 4'h7;  // PINSEL pin, rs1
    localparam FUNCT_EVEN   = 4'h8;  // EVEN timer, rs1
    localparam FUNCT_JALR   = 4'hC;  // JALR rd, rs1 (register indirect jump)
    localparam FUNCT_SWAP   = 4'h9;  // SWAP (trigger bank swap)
    localparam FUNCT_VERIFY = 4'hA;  // VERIFY rd (read CRC)
    localparam FUNCT_CAPRD  = 4'hB;  // CAPRD rd, timer
    localparam FUNCT_HALT   = 4'hF;  // HALT - stop CPU

    // Peripheral base addresses
    localparam TIMER_BASE  = 16'hF000;
    localparam PIN_BASE    = 16'hF100;
    localparam HOST_BASE   = 16'hF200;

    // Pipeline registers
    reg [2:0]  pipe_st;
    localparam S_IF   = 3'd0;
    localparam S_ID   = 3'd1;
    localparam S_EX   = 3'd2;
    localparam S_WB   = 3'd3;
    localparam S_STALL = 3'd4;

    // CPU run state
    reg cpu_running;

    // IF stage
    reg [ADDR_W-1:0] pc, pc_next;
    reg [15:0]       if_instr;

    // ID stage - pipeline registers
    reg [15:0]       id_instr;
    reg [ADDR_W-1:0] id_pc;
    reg [3:0]        id_rd, id_rs1, id_rs2;
    reg [3:0]        id_funct;
    reg [7:0]        id_imm8;
    reg [11:0]       id_imm12;
    reg [7:0]        id_off8;
    reg [15:0]       id_rs1_val, id_rs2_val;
    reg [15:0]       id_alu_result;  // ALU computed in ID stage for forwarding
    reg              id_reg_write;
    reg              id_mem_read, id_mem_write;
    reg [ADDR_W-1:0] id_mem_addr;
    reg [15:0]       id_mem_wdata;
    reg              id_branch_taken;
    reg [ADDR_W-1:0] id_branch_target;
    reg              id_is_custom;
    reg [3:0]        id_custom_funct;
    reg              id_stall;
    reg              id_is_halt;
    reg              id_is_wait;     // WAIT instruction flag
    reg [15:0]       id_wait_cycles; // cycles to wait
    reg              id_is_jal;      // JAL instruction flag
    reg [3:0]        id_jal_rd;      // JAL destination register
    reg [15:0]       id_jal_target;  // JAL target PC

    // EX stage - pipeline registers
    reg [15:0]       ex_alu_result;
    reg [3:0]        ex_rd;
    reg              ex_reg_write;
    reg              ex_mem_read, ex_mem_write;
    reg [ADDR_W-1:0] ex_mem_addr;
    reg [15:0]       ex_mem_wdata;
    reg              ex_is_custom;
    reg [3:0]        ex_custom_funct;
    reg [3:0]        ex_rs1, ex_rs2;
    reg [15:0]       ex_rs1_val, ex_rs2_val;
    reg [ADDR_W-1:0] ex_pc;
    reg              ex_is_halt;
    reg              ex_is_branch;
    reg [ADDR_W-1:0] ex_branch_target;
    reg              ex_branch_taken;
    reg              ex_is_wait;
    reg [15:0]       ex_wait_cnt;

    // WB stage - pipeline registers
    reg [15:0]       wb_data;
    reg [3:0]        wb_rd;
    reg              wb_reg_write;
    reg              wb_is_halt;
    reg              wb_is_jal;
    reg [3:0]        wb_jal_rd;

    // Register file - initialized to 0
    reg [15:0] regs [0:15];
    integer i;
    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            regs[i] = 16'h0000;
        end
    end

    // ID stage combinational decode temporaries
    reg [3:0] dec_rd, dec_rs1, dec_rs2;
    reg [15:0] rs1_val, rs2_val;
    reg [15:0] imm8_sext;
    reg [15:0] write_data;  // WB stage write data
    reg [15:0] wait_cycles;
    reg        wait_stall;
    reg        branch_cond;
    reg [ADDR_W-1:0] branch_target;
    reg [15:0]       branch_offset;
    reg              is_branch_instr;

    // ALU function
    function [15:0] alu_op;
        input [3:0] funct;
        input [15:0] a, b;
        begin
            case (funct)
                4'h0: alu_op = a + b;  // ADD
                4'h1: alu_op = a - b;  // SUB
                4'h2: alu_op = a & b;  // AND
                4'h3: alu_op = a | b;  // OR
                4'h4: alu_op = a ^ b;  // XOR
                4'h5: alu_op = ($signed(a) < $signed(b)) ? 16'h0001 : 16'h0000; // SLT
                4'h6: alu_op = a << b[3:0];  // SLL
                4'h7: alu_op = a >> b[3:0];  // SRL
                4'h8: alu_op = $signed(a) >>> b[3:0];  // SRA
                default: alu_op = 16'h0000;
            endcase
        end
    endfunction

    // Branch offset sign-extension function
    function [15:0] sign_extend_offset8;
        input [7:0] offset8;
        begin
            // Sign-extend 8-bit offset and shift left by 1 (2-byte aligned)
            sign_extend_offset8 = {{7{offset8[7]}}, offset8, 1'b0};
        end
    endfunction

    // CPU run state: starts on cpu_start pulse, stops on HALT
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cpu_running <= 1'b0;
        end else begin
            if (cpu_start) begin
                cpu_running <= 1'b1;
            end else if (wb_is_halt) begin
                cpu_running <= 1'b0;
            end
        end
    end

    // PC register - byte address (increments by 2 for 16-bit instructions)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 16'h0000;
        end else if (cpu_running && pipe_st == S_IF) begin
            pc <= pc_next;
        end
    end

    // Pipeline control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pipe_st <= S_IF;
        end else if (cpu_running) begin
            case (pipe_st)
                S_IF: begin
                    pipe_st <= S_ID;
                end
                S_ID: begin
                    if (is_branch_instr && branch_cond) begin
                        pipe_st <= S_IF;  // Branch taken - redirect IF
                    end else if (id_stall || wait_stall) begin
                        pipe_st <= S_STALL;
                    end else begin
                        pipe_st <= S_EX;
                    end
                end
                S_STALL: begin
                    if (ex_is_wait && ex_wait_cnt > 0) pipe_st <= S_STALL;
                    else pipe_st <= S_EX;
                end
                S_EX: pipe_st <= S_WB;
                S_WB: pipe_st <= S_IF;
            endcase
        end
    end

    // IF: Fetch instruction - PC is byte address, prog_addr is word address
    // Branch taken in ID stage overrides PC
    always @(*) begin
        if (is_branch_instr && branch_cond) begin
            pc_next = branch_target;
        end else begin
            pc_next = pc + 2; // 16-bit instructions = 2 bytes
        end
    end

    // Convert byte address (PC) to word address for program memory
    assign prog_addr = {1'b0, pc[ADDR_W-1:1]};

    // IF/ID register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_instr <= 16'h0000;
        end else if (cpu_running && pipe_st == S_IF) begin
            if_instr <= prog_data;
        end
    end

    // ID: Decode with forwarding logic INLINE
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_instr <= 16'h0000;
            id_pc <= 16'h0000;
            id_rd <= 0; id_rs1 <= 0; id_rs2 <= 0;
            id_funct <= 0; id_imm8 <= 0; id_imm12 <= 0; id_off8 <= 0;
            id_rs1_val <= 0; id_rs2_val <= 0;
            id_alu_result <= 0;
            id_reg_write <= 0; id_mem_read <= 0; id_mem_write <= 0;
            id_mem_addr <= 0; id_mem_wdata <= 0;
            id_branch_taken <= 0; id_branch_target <= 0;
            id_is_custom <= 0; id_custom_funct <= 0; id_stall <= 0;
            id_is_halt <= 0;
            id_is_wait <= 0;
            id_wait_cycles <= 0;
            id_is_jal <= 0;
            id_jal_rd <= 0;
            id_jal_target <= 0;
            is_branch_instr <= 0;
            branch_cond <= 0;
            branch_target <= 0;
            branch_offset <= 0;
        end else if (cpu_running && pipe_st == S_ID) begin
            id_instr <= if_instr;
            id_pc <= pc;

            // Reset branch defaults
            id_branch_taken <= 0;
            id_branch_target <= 0;
            id_is_jal <= 0;
            id_jal_rd <= 0;
            id_jal_target <= 0;
            is_branch_instr <= 0;
            branch_cond <= 0;
            branch_target <= 0;
            branch_offset <= 0;

            // Default values
            id_reg_write <= 0;
            id_mem_read <= 0;
            id_mem_write <= 0;
            id_branch_taken <= 0;
            id_is_custom <= 0;
            id_custom_funct <= 0;
            id_stall <= 0;
            id_is_halt <= 0;
            id_is_wait <= 0;
            id_wait_cycles <= 0;
            wait_cycles <= 0;
            wait_stall <= 0;

            // Decode register indices based on opcode
            case (if_instr[15:12])
                OP_ALU: begin
                    dec_rd   = if_instr[11:8];
                    dec_rs1  = if_instr[7:4];
                    dec_rs2  = if_instr[3:0];
                    id_funct <= 4'h0; // ADD only for now
                end
                OP_IMM: begin
                    dec_rd   = if_instr[11:8];
                    dec_rs1  = 4'd0;
                    dec_rs2  = 4'd0;
                    id_imm8  <= if_instr[7:0];
                    id_funct <= 4'h0; // ADDI
                end
                // Branch instructions (opcodes 0xA-0xE)
                OP_BEQZ: begin  // BEQZ rs1, offset8
                    dec_rd   = 4'd0;
                    dec_rs1  = if_instr[11:8];
                    dec_rs2  = 4'd0;
                    branch_offset <= sign_extend_offset8(if_instr[7:0]);
                    is_branch_instr <= 1;
                end
                OP_BNEZ: begin  // BNEZ rs1, offset8
                    dec_rd   = 4'd0;
                    dec_rs1  = if_instr[11:8];
                    dec_rs2  = 4'd0;
                    branch_offset <= sign_extend_offset8(if_instr[7:0]);
                    is_branch_instr <= 1;
                end
                OP_BLTZ: begin  // BLTZ rs1, offset8
                    dec_rd   = 4'd0;
                    dec_rs1  = if_instr[11:8];
                    dec_rs2  = 4'd0;
                    branch_offset <= sign_extend_offset8(if_instr[7:0]);
                    is_branch_instr <= 1;
                end
                OP_BGEZ: begin  // BGEZ rs1, offset8
                    dec_rd   = 4'd0;
                    dec_rs1  = if_instr[11:8];
                    dec_rs2  = 4'd0;
                    branch_offset <= sign_extend_offset8(if_instr[7:0]);
                    is_branch_instr <= 1;
                end
                OP_JAL: begin   // JAL rd, offset8
                    dec_rd   = if_instr[11:8];
                    dec_rs1  = 4'd0;
                    dec_rs2  = 4'd0;
                    id_is_jal <= 1;
                    id_jal_rd <= if_instr[11:8];
                    branch_offset <= sign_extend_offset8(if_instr[7:0]);
                    id_jal_target <= pc + 2 + sign_extend_offset8(if_instr[7:0]);
                    is_branch_instr <= 1;  // JAL always taken
                    branch_cond <= 1;
                end
                OP_CUSTOM: begin
                    dec_rd   = if_instr[3:0];
                    dec_rs1  = if_instr[7:4];
                    dec_rs2  = if_instr[3:0];
                    id_custom_funct <= if_instr[11:8];
                    id_funct <= if_instr[11:8];
                end
                default: begin
                    dec_rd   = 4'd0;
                    dec_rs1  = 4'd0;
                    dec_rs2  = 4'd0;
                end
            endcase

            // Forwarding logic INLINE using dec_rs1/dec_rs2 - MOVED UP FOR CUSTOM INSTRUCTIONS
            // RS1 value with forwarding
            if (dec_rs1 == 4'd0) begin
                rs1_val = 16'h0000;
            end else if (ex_reg_write && ex_rd != 0 && ex_rd == dec_rs1) begin
                rs1_val = ex_alu_result;  // Forward from EX
            end else if (wb_reg_write && wb_rd != 0 && wb_rd == dec_rs1) begin
                rs1_val = wb_data;  // Forward from WB
            end else begin
                rs1_val = regs[dec_rs1];
            end

            // RS2 value with forwarding
            if (dec_rs2 == 4'd0) begin
                rs2_val = 16'h0000;
            end else if (ex_reg_write && ex_rd != 0 && ex_rd == dec_rs2) begin
                rs2_val = ex_alu_result;  // Forward from EX
            end else if (wb_reg_write && wb_rd != 0 && wb_rd == dec_rs2) begin
                rs2_val = wb_data;  // Forward from WB
            end else begin
                rs2_val = regs[dec_rs2];
            end

            id_rs1_val <= rs1_val;
            id_rs2_val <= rs2_val;

            id_rd   <= dec_rd;
            id_rs1  <= dec_rs1;
            id_rs2  <= dec_rs2;
            id_imm12 <= if_instr[11:0];
            id_off8  <= if_instr[7:0];

            // Evaluate branch conditions for conditional branches
            case (if_instr[15:12])
                OP_BEQZ: branch_cond <= (rs1_val == 16'h0000);
                OP_BNEZ: branch_cond <= (rs1_val != 16'h0000);
                OP_BLTZ: branch_cond <= (rs1_val[15] == 1'b1);  // MSB = sign bit
                OP_BGEZ: branch_cond <= (rs1_val[15] == 1'b0);  // MSB = sign bit
                default: branch_cond <= 0;
            endcase

            // Calculate branch target for taken branches
            if (is_branch_instr && branch_cond) begin
                branch_target <= pc + branch_offset;
                id_branch_taken <= 1;
                id_branch_target <= pc + branch_offset;
            end

            // Now handle custom instructions using the computed rs1_val/rs2_val
            if (if_instr[15:12] == OP_CUSTOM) begin
                // Check for WAIT instruction
                if (if_instr[11:8] == FUNCT_WAIT) begin
                    id_is_wait <= 1;
                    wait_cycles = rs2_val;  // rs2 has wait cycles
                    wait_stall = (rs2_val != 0);
                    id_wait_cycles <= rs2_val;
                end

                // Check for JALR instruction (register indirect jump)
                if (if_instr[11:8] == FUNCT_JALR) begin
                    is_branch_instr <= 1;
                    branch_cond <= 1;
                    branch_target <= rs1_val;  // Jump to address in rs1
                    id_branch_taken <= 1;
                    id_branch_target <= rs1_val;
                    id_is_jal <= 1;
                    id_jal_rd <= if_instr[3:0];  // rd in [3:0]
                    id_jal_target <= rs1_val;
                    // Return address = PC+2
                    id_alu_result <= pc + 2;
                    id_reg_write <= 1;
                end

                id_is_custom <= 1;
                id_reg_write <= (if_instr[11:8] == FUNCT_TIME || 
                                 if_instr[11:8] == FUNCT_VERIFY || 
                                 if_instr[11:8] == FUNCT_CAPRD);
                id_is_halt <= (if_instr[11:8] == FUNCT_HALT);

                // Handle custom instructions that write to peripherals
                case (if_instr[11:8])
                    FUNCT_OUT: begin  // OUT pin, value
                        id_mem_write <= 1'b1;
                        id_mem_addr <= PIN_BASE + 16'h4;  // REG_OUT
                        id_mem_wdata <= (16'b1 << rs1_val[3:0]);
                    end
                    FUNCT_DIR: begin  // DIR pin, direction
                        id_mem_write <= 1'b1;
                        id_mem_addr <= PIN_BASE + 16'h0;  // REG_DIR
                        id_mem_wdata <= (16'b1 << rs1_val[3:0]);
                    end
                    FUNCT_PINSEL: begin  // PINSEL pin, source
                        id_mem_write <= 1'b1;
                        if (rs1_val[3:0] < 4) begin
                            id_mem_addr <= PIN_BASE + 16'h1;  // REG_SEL (pins 0-3)
                        end else begin
                            id_mem_addr <= PIN_BASE + 16'h2;  // REG_SEL_H (pins 4-7)
                        end
                        id_mem_wdata <= ({12'h0, rs2_val[3:0]} << (rs1_val[3:0] << 2));  // Shift source by pin*4
                    end
                    FUNCT_TUNING: begin  // TUNING timer, rs1 (timer), rs2 (tuning value)
                        id_mem_write <= 1'b1;
                        // Timer address: [6:3]=timer_idx, [3:0]=REG_TUNING(0) or REG_TUNING_H(1)
                        // rs2[8] = select register (0=low, 1=high)
                        // For REG_TUNING (low 8 bits): write rs2_val[7:0]
                        // For REG_TUNING_H (high 16 bits): write rs2_val[15:0]
                        id_mem_addr <= TIMER_BASE + ({12'h0, rs1_val[3:0]} << 4) + (rs2_val[8] ? 16'h1 : 16'h0);
                        id_mem_wdata <= rs2_val[8] ? rs2_val[15:0] : {8'h0, rs2_val[7:0]};
                    end
                    FUNCT_TCFG: begin  // TCFG timer, config
                        id_mem_write <= 1'b1;
                        id_mem_addr <= TIMER_BASE + ({12'h0, rs1_val[3:0]} << 4) + 16'h5;  // REG_MODE (16 bytes per timer)
                        id_mem_wdata <= rs2_val;
                    end
                    default: begin
                        // Other custom instructions (TIME, VERIFY, CAPRD, HALT, etc.) don't write memory
                    end
                endcase
            end

            // Compute ALU result in ID stage for forwarding to next instruction
            case (if_instr[15:12])
                OP_ALU: begin
                    id_alu_result <= alu_op(4'h0, rs1_val, rs2_val); // ADD
                    id_reg_write <= 1;
                end
                OP_IMM: begin
                    // ADDI: rs1_val (x0=0) + sign_extended_imm8
                    imm8_sext = {{8{if_instr[7]}}, if_instr[7:0]};
                    id_alu_result <= rs1_val + imm8_sext;
                    id_reg_write <= 1;
                    // Override rs2_val for immediate
                    id_rs2_val <= imm8_sext;
                end
                // Branch instructions - target computed in ID
                OP_BEQZ, OP_BNEZ, OP_BLTZ, OP_BGEZ: begin
                    // Branch target already computed, condition evaluated
                    // No register write for conditional branches
                end
                OP_JAL: begin
                    // JAL: rd = PC+2, PC = target
                    id_alu_result <= pc + 2;  // Return address
                    id_reg_write <= 1;
                end
                OP_CUSTOM: begin
                    // Custom instruction ALU result handled in WB
                    if (id_is_wait) begin
                        // WAIT doesn't write register
                    end
                end
            endcase

            // Hazard detection - stall if EX is a load and we need the result
            if (ex_mem_read && (ex_rd == dec_rs1 || ex_rd == dec_rs2) && (dec_rs1 != 0 || dec_rs2 != 0)) begin
                id_stall <= 1;
            end
        end
    end

    // EX: Execute
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_alu_result <= 0;
            ex_rd <= 0;
            ex_reg_write <= 0;
            ex_mem_read <= 0; ex_mem_write <= 0;
            ex_mem_addr <= 0; ex_mem_wdata <= 0;
            ex_is_custom <= 0; ex_custom_funct <= 0;
            ex_rs1 <= 0; ex_rs2 <= 0;
            ex_rs1_val <= 0; ex_rs2_val <= 0;
            ex_pc <= 0;
            ex_is_halt <= 0;
            ex_is_branch <= 0;
            ex_branch_target <= 0;
            ex_branch_taken <= 0;
            ex_is_wait <= 0;
            ex_wait_cnt <= 0;
        end else if (cpu_running && (pipe_st == S_EX || pipe_st == S_STALL)) begin
            // Load new instruction from ID when:
            // 1. Normal EX stage (pipe_st == S_EX)
            // 2. WAIT completing in STALL (ex_wait_cnt == 1, about to go to WB)
            if (pipe_st == S_EX || (pipe_st == S_STALL && ex_is_wait && ex_wait_cnt == 1)) begin
                ex_rd <= id_rd;
                ex_reg_write <= id_reg_write;
                ex_mem_read <= id_mem_read;
                ex_mem_write <= id_mem_write;
                ex_mem_addr <= id_mem_addr;
                ex_mem_wdata <= id_mem_wdata;
                ex_is_custom <= id_is_custom;
                ex_custom_funct <= id_custom_funct;
                ex_rs1 <= id_rs1;
                ex_rs2 <= id_rs2;
                ex_rs1_val <= id_rs1_val;
                ex_rs2_val <= id_rs2_val;
                ex_pc <= id_pc;
                ex_is_halt <= id_is_halt;
                ex_is_branch <= id_branch_taken;
                ex_branch_target <= id_branch_target;
                ex_branch_taken <= id_branch_taken;
                ex_is_wait <= id_is_wait;
                ex_wait_cnt <= id_wait_cycles;
            end

            // Pass through ALU result from ID stage
            ex_alu_result <= id_alu_result;

            // Decrement wait counter if active
            if (ex_is_wait && ex_wait_cnt > 0) begin
                ex_wait_cnt <= ex_wait_cnt - 1;
            end
        end
    end

    // WB: Writeback
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_data <= 0;
            wb_rd <= 0;
            wb_reg_write <= 0;
            wb_is_halt <= 0;
            wb_is_jal <= 0;
            wb_jal_rd <= 0;
        end else if (cpu_running && pipe_st == S_WB) begin
            wb_rd <= ex_rd;
            wb_reg_write <= ex_reg_write;
            wb_is_halt <= ex_is_halt;
            wb_is_jal <= ex_is_branch && (ex_rd == ex_rd);  // Track JAL/JALR
            wb_jal_rd <= ex_rd;

            // Compute write data using blocking assignment so regs[ex_rd] sees new value
            if (ex_is_custom) begin
                // Custom instruction results (memory-mapped peripheral access)
                case (ex_custom_funct)
                    FUNCT_TIME: write_data = timer_rd_data;
                    FUNCT_VERIFY: write_data = host_rd_data;
                    FUNCT_CAPRD: write_data = host_rd_data;
                    default: write_data = 0;
                endcase
            end else if (ex_mem_read) begin
                // Memory read (peripheral or RAM)
                if (ex_mem_addr >= TIMER_BASE && ex_mem_addr < PIN_BASE) begin
                    write_data = timer_rd_data;
                end else if (ex_mem_addr >= PIN_BASE && ex_mem_addr < HOST_BASE) begin
                    write_data = pin_rd_data;
                end else if (ex_mem_addr >= HOST_BASE) begin
                    write_data = host_rd_data;
                end else begin
                    write_data = 16'h0000;
                end
            end else begin
                write_data = ex_alu_result;
            end

            // Handle JAL/JALR return address write
            // For JAL/JALR, ex_alu_result already has PC+2 from ID stage
            // The register write happens via wb_reg_write path above

            wb_data <= write_data;

            // Write register file with write_data
            if (ex_reg_write && ex_rd != 0) begin
                regs[ex_rd] <= write_data;
            end
        end
    end

    // Peripheral write enables (from EX stage)
    assign timer_wr_en = (cpu_running && pipe_st == S_EX) && ex_mem_write && (ex_mem_addr >= TIMER_BASE) && (ex_mem_addr < PIN_BASE);
    assign timer_wr_addr = ex_mem_addr[6:0];
    assign timer_wr_data = ex_mem_wdata;

    assign pin_wr_en = (cpu_running && pipe_st == S_EX) && ex_mem_write && (ex_mem_addr >= PIN_BASE) && (ex_mem_addr < HOST_BASE);
    assign pin_wr_addr = ex_mem_addr[3:0];
    assign pin_wr_data = ex_mem_wdata;

    assign host_wr_en = (cpu_running && pipe_st == S_EX) && ex_mem_write && (ex_mem_addr >= HOST_BASE);
    assign host_wr_addr = ex_mem_addr[3:0];
    assign host_wr_data = ex_mem_wdata;

    // Outputs
    assign cpu_done = !cpu_running && (pipe_st == S_IF || wb_is_halt);
    assign cpu_error = 1'b0;
    assign pc_debug = pc;

    // Debug register read port
    assign dbg_reg_data = regs[dbg_reg_idx];

endmodule
