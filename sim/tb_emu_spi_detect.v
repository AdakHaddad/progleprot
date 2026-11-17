module tb_emu_spi_detect;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 8'hF6;  // CS=1 (pin2), SCK=0 (pin0), MOSI=1 (pin1), MISO=1 (pin3) - SPI Mode 0 idle
    reg [7:0] uio_in = 8'hFF;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_protocol_emu dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;

    wire [7:0] pin_out = dut.pin_out;
    wire [7:0] pin_oe  = dut.pin_oe;
    wire [7:0] seq_pc  = dut.seq_pc;
    wire       seq_done = dut.seq_done;
    wire       seq_error = dut.seq_error;
    wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
    wire [15:0] reg1 = dut.u_sequencer.reg_file[1];
    wire [15:0] reg2 = dut.u_sequencer.reg_file[2];
    wire [15:0] reg3 = dut.u_sequencer.reg_file[3];
    wire [2:0] seq_st = dut.u_sequencer.st;
    wire [15:0] seq_wait_cnt = dut.u_sequencer.wait_cnt;
    wire [5:0] seq_wait_mode = dut.u_sequencer.wait_mode;
    wire [7:0] seq_pin_in_sync = dut.u_sequencer.pin_in_sync;
    wire [7:0] seq_pin_in_prev = dut.u_sequencer.pin_in_prev;

    localparam S_IDLE    = 3'd0;
    localparam S_FETCH   = 3'd1;
    localparam S_EXECUTE = 3'd2;
    localparam S_WAIT    = 3'd3;
    localparam S_SYNC    = 3'd4;
    localparam S_DONE    = 3'd5;

    // Synchronization flag
    reg program_loaded = 0;

    // Use #delay instead of wait_clk task to avoid re-entrancy issues
    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    // Wait for DONE flag on pin 3
    task wait_for_done;
        begin
            while (!pin_oe[3] || !pin_out[3]) wait_clk(1);
            wait_clk(10);
        end
    endtask

    function [63:0] make_spi_cmd;
        input [31:0] data;
        input [15:0] addr;
        input [7:0]  cmd;
        begin
            make_spi_cmd = {data, addr, cmd, 8'h00};
        end
    endfunction

    task spi_write(input [15:0] addr, input [31:0] data);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(data, addr, 8'h01);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(4);
        end
    endtask

    task spi_run(input [15:0] length);
        integer b;
        reg [63:0] cmd;
        begin
            cmd = make_spi_cmd(32'h0, length, 8'h03);
            uio_in[2] = 0;
            wait_clk(2);
            for (b = 63; b >= 0; b = b - 1) begin
                uio_in[1] = cmd[b];
                uio_in[0] = 0; wait_clk(2);
                uio_in[0] = 1; wait_clk(2);
            end
            uio_in[2] = 1;
            wait_clk(10);
        end
    endtask

    // Instruction encoding - matching pdis_sequencer.v exactly
    function [31:0] INS_LOAD(input [3:0] dst, input [15:0] val);
        begin INS_LOAD = {4'd9, dst, 8'd0, val}; end
    endfunction

    function [31:0] INS_DRIVE(input [3:0] mask, input [1:0] mode, input [1:0] reg_idx);
        begin INS_DRIVE = {4'd1, mask, mode, reg_idx, 20'd0}; end
    endfunction

    function [31:0] INS_WAIT(input [3:0] wait_mode, input [15:0] count);
        begin INS_WAIT = {4'd2, 4'd0, wait_mode, 4'd0, count}; end
    endfunction

    function [31:0] INS_SAMPLE(input [3:0] dst, input [3:0] mask);
        begin INS_SAMPLE = {4'd3, dst, mask, 20'd0}; end
    endfunction

    function [31:0] INS_BRANCH(input [3:0] cond, input [7:0] target);
        begin INS_BRANCH = {4'd5, 4'd0, cond, 4'd0, 8'd0, target}; end
    endfunction

    function [31:0] INS_SHIFT(input [3:0] dst, input [3:0] src, input [3:0] cnt, input dir);
        begin INS_SHIFT = {4'd4, dst, src, cnt, dir, 15'd0}; end
    endfunction

    function [31:0] INS_XOR(input [3:0] dst, input [3:0] src1, input [3:0] src2);
        begin INS_XOR = {4'd10, dst, src1, src2, 16'd0}; end
    endfunction

    function [31:0] INS_SYNC(input [3:0] pin_mask, input [1:0] sync_mode, input [15:0] timeout);
        begin INS_SYNC = {4'd11, pin_mask, sync_mode, 6'd0, timeout}; end
    endfunction

    function [31:0] INS_JUMP_LOOP(input [3:0] loop_reg, input [7:0] target);
        begin INS_JUMP_LOOP = {4'd12, 4'd0, loop_reg, 4'd0, target, 8'd0}; end
    endfunction

    function [31:0] INS_JUMP(input [7:0] target);
        begin INS_JUMP = {4'd12, 4'd0, 4'd0, 4'd0, target, 8'd1}; end
    endfunction

    // ============================================================
    // Initial block 1: Program load and sequencer start
    // ============================================================
    initial begin
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== Protocol Emulator SPI Detection Test ===");

        // Initialize protocol pins for SPI Mode 0: CS=1, SCK=0, MOSI=1, MISO=1
        // ui_in[0]=SCK, ui_in[1]=MOSI, ui_in[2]=CS_N, ui_in[3]=MISO
        ui_in = 8'hF6;  // 11110110: CS=1, SCK=0, MOSI=1, MISO=1
        wait_clk(2);

        // Program includes register initialization via LOAD instructions
        // PC=0: R0 = bit counter (7 = 8 iterations: 7,6,5,4,3,2,1,0)
        spi_write(8'h00, INS_LOAD(4'd0, 16'd7));
        // PC=1: R1 = RX data accumulator (0)
        spi_write(8'h01, INS_LOAD(4'd1, 16'h0000));
        // PC=2: R2 = temp register for sampled bit
        spi_write(8'h02, INS_LOAD(4'd2, 16'h0000));
        // PC=3: R3 = constant 1 (for done flag)
        spi_write(8'h03, INS_LOAD(4'd3, 16'h0001));

        // PC=4: Wait for CS falling edge (pin 2 = 0) - SYNC_FALL=1
        spi_write(8'h04, INS_SYNC(4'h4, 2'b01, 16'd50000));
        
        // PC=5: Wait for SCK rising edge (pin 0) - SYNC_RISE=0
        spi_write(8'h05, INS_SYNC(4'h1, 2'b00, 16'd50000));
        
        // PC=6: SHIFT R1 left by 1 (make room for new bit)
        spi_write(8'h06, INS_SHIFT(4'd1, 4'd1, 4'd1, 1'b1));
        
        // PC=7: SAMPLE MOSI (pin 1) into R2
        spi_write(8'h07, INS_SAMPLE(4'd2, 4'h2));
        
        // PC=8: SHIFT R2 right by 1 (move bit from pos 1 to pos 0)
        spi_write(8'h08, INS_SHIFT(4'd2, 4'd2, 4'd1, 1'b0));
        
        // PC=9: XOR R1 ^ R2 -> R1 (accumulate bit)
        spi_write(8'h09, INS_XOR(4'd1, 4'd1, 4'd2));
        
        // PC=10: JUMP_LOOP R0 -> PC=5 if >0 (loop back to wait for next SCK rise)
        spi_write(8'h0A, INS_JUMP_LOOP(4'd0, 8'd5));
        
        // PC=11: Done - 8 bits received, signal done on pin 3 (use R3=1, mode=drive from reg)
        spi_write(8'h0B, INS_DRIVE(4'h8, 2'b01, 2'd3));
        
        // Pad remaining
        spi_write(8'h0C, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0D, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0E, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0F, INS_LOAD(4'd0, 16'd0));

        $display("Program loaded (16 instructions). Starting sequencer...");
        spi_run(8'd16);
        
        // Signal that program is loaded and sequencer is running
        program_loaded = 1;
    end

    // ============================================================
    // Initial block 2: Drive SPI transaction synchronized with sequencer
    // ============================================================
    initial begin
        integer i;
        // Wait for program to be loaded
        while (!program_loaded) @(posedge clk);
        
        // Wait for sequencer to reach PC=5 in S_SYNC state (executing SYNC from PC=4, waiting for CS fall)
        while (!(seq_pc == 8'd5 && seq_st == S_SYNC)) @(posedge clk);
        wait_clk(2);  // Let sequencer settle in S_SYNC
        
        $display("Starting SPI transaction... (time=%0t, seq_pc=%d, seq_st=%d)", $time, seq_pc, seq_st);
        
        // CS low (falling edge on pin 2) - this should be detected by SYNC at PC=4
        ui_in[2] = 0;
        $display("  CS LOW (time=%0t)", $time);
        // Wait for sequencer to detect CS fall and move to PC=6 (SYNC on SCK rise)
        while (!(seq_pc == 8'd6 && seq_st == S_SYNC)) @(posedge clk);
        wait_clk(2);
        $display("  CS fall detected, sequencer at PC=%d waiting for SCK rise (time=%0t)", seq_pc, $time);
        
        // 8 SCK cycles, MSB first for 0xA5 = 10100101
        // Bit 7: 1
        ui_in[1] = 1;
        repeat (200) @(negedge clk);
        $display("  Bit 7: MOSI=1, waiting for SCK rise (time=%0t)", $time);
        ui_in[0] = 1;  // SCK rising
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;  // SCK falling
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 6: 0
        ui_in[1] = 0;
        repeat (200) @(negedge clk);
        $display("  Bit 6: MOSI=0 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 5: 1
        ui_in[1] = 1;
        repeat (200) @(negedge clk);
        $display("  Bit 5: MOSI=1 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 4: 0
        ui_in[1] = 0;
        repeat (200) @(negedge clk);
        $display("  Bit 4: MOSI=0 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 3: 0
        ui_in[1] = 0;
        repeat (200) @(negedge clk);
        $display("  Bit 3: MOSI=0 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 2: 1
        ui_in[1] = 1;
        repeat (200) @(negedge clk);
        $display("  Bit 2: MOSI=1 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 1: 0
        ui_in[1] = 0;
        repeat (200) @(negedge clk);
        $display("  Bit 1: MOSI=0 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Bit 0: 1
        ui_in[1] = 1;
        repeat (200) @(negedge clk);
        $display("  Bit 0: MOSI=1 (time=%0t)", $time);
        ui_in[0] = 1;
        $display("  SCK RISING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        ui_in[0] = 0;
        $display("  SCK FALLING (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // CS high (rising edge on pin 2)
        ui_in[2] = 1;
        $display("  CS HIGH (time=%0t)", $time);
        repeat (200) @(negedge clk);
        
        $display("SPI transaction complete (time=%0t)", $time);
    end

    // ============================================================
    // Initial block 3: Monitor for DONE flag and report results
    // ============================================================
    initial begin
        // Wait for reset and program load
        repeat (20) @(negedge clk);
        wait_for_done();
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (bit counter): %d", reg0);
        $display("R1 (RX data): %h (expected A5)", reg1);
        $display("R2 (temp): %h", reg2);
        $display("R3 (constant 1): %h", reg3);

        if (reg1 == 16'h00A5) begin
            $display("SUCCESS: SPI detection works! Received 0xA5");
        end else begin
            $display("FAIL: Expected 0xA5, got %h", reg1);
        end

        $display("Test complete");
        $finish;
    end

    // Monitor sequencer state
    always @(posedge clk) begin
        if (pin_oe[3]) begin
            $display("t=%0t DONE_FLAG=%b pc=%d", $time, pin_out[3], seq_pc);
        end
    end

    // Monitor SPI protocol pins and sequencer state
    always @(posedge clk) begin
        if (seq_st == S_SYNC || seq_st == S_WAIT) begin
            $display("t=%0t ST=%d PC=%d wait_cnt=%d wait_mode=%b pin_sync=%b pin_prev=%b ui_in=%b", 
                     $time, seq_st, seq_pc, seq_wait_cnt, seq_wait_mode, seq_pin_in_sync, seq_pin_in_prev, ui_in[3:0]);
        end
    end

    // Monitor register values during SPI loop (PC 6-10)
    always @(posedge clk) begin
        if (seq_pc >= 8'd6 && seq_pc <= 8'd11 && seq_st == S_EXECUTE) begin
            $display("t=%0t EXEC: PC=%d R0=%d R1=%h R2=%h R3=%h", $time, seq_pc, reg0, reg1, reg2, reg3);
        end
    end

    // Monitor SAMPLE instruction and pin_in_sync
    always @(posedge clk) begin
        if (seq_pc == 8'd7 && seq_st == S_EXECUTE) begin
            $display("t=%0t SAMPLE: pin_in=%b pin_in_sync=%b mask=0x2, sampled=%b", 
                     $time, dut.u_sequencer.pin_in, dut.u_sequencer.pin_in_sync, 
                     (dut.u_sequencer.pin_in_sync & 8'h02));
        end
    end

    // Monitor instruction being fetched
    always @(posedge clk) begin
        if (seq_st == S_FETCH && seq_pc >= 8'd6 && seq_pc <= 8'd11) begin
            $display("t=%0t FETCH: PC=%d instr=%h", $time, seq_pc, dut.u_sequencer.instr);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
