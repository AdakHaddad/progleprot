module tb_emu_i2c_detect;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 8'h03;  // SDA=1 (pin0), SCL=1 (pin1) - I2C idle (both high due to pull-ups)
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
    wire [2:0] seq_st = dut.u_sequencer.st;
    wire [15:0] reg0 = dut.u_sequencer.reg_file[0];
    wire [15:0] reg1 = dut.u_sequencer.reg_file[1];
    wire [15:0] reg2 = dut.u_sequencer.reg_file[2];
    wire [15:0] reg3 = dut.u_sequencer.reg_file[3];
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

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

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

        $display("=== Protocol Emulator I²C Detection Test ===");

        // I²C pins: ui_in[0]=SDA, ui_in[1]=SCL
        // Idle: SDA=1, SCL=1 (both released, pulled up)
        ui_in = 8'h03;  // 00000011: SDA=1, SCL=1
        wait_clk(2);

        // Program: I²C Slave Detection (detect START, receive 8-bit address+RW, detect ACK slot)
        // PC=0: R0 = bit counter (8)
        spi_write(8'h00, INS_LOAD(4'd0, 16'd7));
        // PC=1: R1 = RX data accumulator (0)
        spi_write(8'h01, INS_LOAD(4'd1, 16'h0000));
        // PC=2: R2 = temp register
        spi_write(8'h02, INS_LOAD(4'd2, 16'h0000));
        // PC=3: R3 = constant 1 (for done flag)
        spi_write(8'h03, INS_LOAD(4'd3, 16'h0001));

        // PC=4: Wait for START condition (SDA falling while SCL high) - SYNC_FALL on SDA (pin 0)
        spi_write(8'h04, INS_SYNC(4'h1, 2'b01, 16'd50000));
        
        // PC=5: Wait for SCL rising edge (pin 1) - SYNC_RISE
        spi_write(8'h05, INS_SYNC(4'h2, 2'b00, 16'd50000));
        
        // PC=6: SHIFT R1 left by 1 (make room for new bit)
        spi_write(8'h06, INS_SHIFT(4'd1, 4'd1, 4'd1, 1'b1));
        
        // PC=7: SAMPLE SDA (pin 0) into R2
        spi_write(8'h07, INS_SAMPLE(4'd2, 4'h1));
        
        // PC=8: XOR R1 ^ R2 -> R1 (accumulate bit)
        spi_write(8'h08, INS_XOR(4'd1, 4'd1, 4'd2));
        
        // PC=9: JUMP_LOOP R0 -> PC=5 if >0 (loop back to wait for next SCL rise)
        spi_write(8'h09, INS_JUMP_LOOP(4'd0, 8'd5));
        
        // PC=10: Wait for SCL rising edge for ACK bit (9th clock)
        spi_write(8'h0A, INS_SYNC(4'h2, 2'b00, 16'd50000));
        
        // PC=11: SAMPLE SDA for ACK into R3 (overwrite constant)
        spi_write(8'h0B, INS_SAMPLE(4'd3, 4'h1));
        
        // PC=12: Wait for STOP condition (SDA rising while SCL high) - SYNC_RISE on SDA
        spi_write(8'h0C, INS_SYNC(4'h1, 2'b00, 16'd50000));
        
        // PC=13: Done - signal done on pin 3
        spi_write(8'h0D, INS_DRIVE(4'h8, 2'b01, 2'd3));
        
        // Pad remaining
        spi_write(8'h0E, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0F, INS_LOAD(4'd0, 16'd0));

        $display("Program loaded (15 instructions). Starting sequencer...");
        spi_run(8'd15);
        
        program_loaded = 1;
    end

    // ============================================================
    // Initial block 2: Drive I²C transaction as slave
    // ============================================================
    initial begin
        // Wait for program to be loaded
        while (!program_loaded) @(posedge clk);
        
        // Wait for sequencer to reach PC=5 in S_SYNC state (waiting for START)
        while (!(seq_pc == 8'd5 && seq_st == S_SYNC)) @(posedge clk);
        wait_clk(2);
        
        $display("Starting I²C transaction... (time=%0t, seq_pc=%d, seq_st=%d)", $time, seq_pc, seq_st);
        
        // START condition: SDA falls while SCL high
        ui_in[0] = 0;  // SDA low
        $display("  START: SDA LOW (time=%0t)", $time);
        repeat (2000) @(negedge clk);
        
        // Wait for sequencer to detect START and move to waiting for SCL rise
        while (!(seq_pc == 8'd6 && seq_st == S_SYNC)) @(posedge clk);
        wait_clk(2);
        $display("  START detected, waiting for SCL rise (time=%0t)", $time);
        
        // 8 SCL cycles for address 0xA5 (0x50 << 1 | 1 = 10100101) - MSB first
        
        // Bit 7: 1
        ui_in[0] = 1;  // SDA=1
        ui_in[1] = 0; repeat (500) @(negedge clk);  // SCL low
        ui_in[1] = 1; $display("  SCL RISE bit 7: SDA=1 (time=%0t)", $time); repeat (2000) @(negedge clk);  // SCL high - sample here
        ui_in[1] = 0; repeat (2000) @(negedge clk);  // SCL low
        
        // Bit 6: 0
        ui_in[0] = 0;
        ui_in[1] = 1; $display("  SCL RISE bit 6: SDA=0 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 5: 1
        ui_in[0] = 1;
        ui_in[1] = 1; $display("  SCL RISE bit 5: SDA=1 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 4: 0
        ui_in[0] = 0;
        ui_in[1] = 1; $display("  SCL RISE bit 4: SDA=0 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 3: 0
        ui_in[0] = 0;
        ui_in[1] = 1; $display("  SCL RISE bit 3: SDA=0 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 2: 1
        ui_in[0] = 1;
        ui_in[1] = 1; $display("  SCL RISE bit 2: SDA=1 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 1: 0
        ui_in[0] = 0;
        ui_in[1] = 1; $display("  SCL RISE bit 1: SDA=0 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // Bit 0: 1 (R/W bit = 1 for read)
        ui_in[0] = 1;
        ui_in[1] = 1; $display("  SCL RISE bit 0: SDA=1 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        
        // ACK slot (9th clock): Slave pulls SDA low
        ui_in[0] = 0;  // Slave ACK (pull SDA low)
        ui_in[1] = 1; $display("  SCL RISE ACK: SDA=0 (time=%0t)", $time); repeat (2000) @(negedge clk);
        ui_in[1] = 0; repeat (2000) @(negedge clk);
        ui_in[0] = 1;  // Release SDA after ACK
        
        // STOP condition: SDA rises while SCL high
        ui_in[1] = 1; repeat (500) @(negedge clk);  // SCL high
        ui_in[0] = 1; $display("  STOP: SDA HIGH (time=%0t)", $time); repeat (2000) @(negedge clk);
        
        $display("I²C transaction complete (time=%0t)", $time);
    end

    // ============================================================
    // Initial block 3: Monitor for DONE flag and report results
    // ============================================================
    initial begin
        repeat (20) @(negedge clk);
        wait_for_done();
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (bit counter): %d", reg0);
        $display("R1 (RX data): %h (expected A5 = address 0x50 + R)", reg1);
        $display("R2 (temp): %h", reg2);
        $display("R3 (ACK sampled): %h (expected 0 = ACK received)", reg3);

        if (reg1 == 16'h00A5 && reg3 == 16'h0000) begin
            $display("SUCCESS: I²C detection works! Received 0xA5, ACK=0");
        end else begin
            $display("FAIL: Expected 0xA5 and ACK=0, got data=%h ACK=%h", reg1, reg3);
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

    // Monitor SAMPLE instruction and pin_in_sync
    always @(posedge clk) begin
        if (seq_pc == 8'd7 && seq_st == S_EXECUTE) begin
            $display("t=%0t SAMPLE: pin_in=%b pin_in_sync=%b mask=0x1, sampled=%b", 
                     $time, dut.u_sequencer.pin_in, dut.u_sequencer.pin_in_sync, 
                     (dut.u_sequencer.pin_in_sync & 8'h01));
        end
    end

    // Monitor instruction being fetched
    always @(posedge clk) begin
        if (seq_st == S_FETCH && seq_pc >= 8'd6 && seq_pc <= 8'd13) begin
            $display("t=%0t FETCH: PC=%d instr=%h", $time, seq_pc, dut.u_sequencer.instr);
        end
    end

    // Monitor register values during I2C loop (PC 6-10)
    always @(posedge clk) begin
        if (seq_pc >= 8'd6 && seq_pc <= 8'd13 && seq_st == S_EXECUTE) begin
            $display("t=%0t EXEC: PC=%d R0=%d R1=%h R2=%h R3=%h", $time, seq_pc, reg0, reg1, reg2, reg3);
        end
    end

    // Monitor I2C protocol pins and sequencer state
    always @(posedge clk) begin
        if (seq_st == S_SYNC || seq_st == S_WAIT) begin
            $display("t=%0t ST=%d PC=%d wait_cnt=%d wait_mode=%b pin_sync=%b pin_prev=%b ui_in=%b", 
                     $time, seq_st, seq_pc, seq_wait_cnt, seq_wait_mode, seq_pin_in_sync, seq_pin_in_prev, ui_in[1:0]);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
