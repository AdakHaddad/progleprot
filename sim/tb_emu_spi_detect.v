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

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    // Wait for sequencer to reach a specific PC (it will be in S_FETCH or S_EXECUTE typically)
    task wait_for_pc(input [7:0] target_pc);
        begin
            while (seq_pc != target_pc) wait_clk(1);
            wait_clk(2);
        end
    endtask

    // Wait for sequencer to be in S_SYNC at a specific PC (polling)
    // Note: sequencer increments PC before entering S_SYNC, so for SYNC at PC=N, wait for PC=N+1
    task wait_for_sync_at_pc(input [7:0] target_pc);
        begin
            while (!(seq_pc == target_pc && seq_st == S_SYNC)) wait_clk(1);
            wait_clk(1);
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

    function [31:0] INS_SYNC(input [3:0] pin_mask, input [1:0] sync_mode, input [15:0] timeout);
        begin INS_SYNC = {4'd11, pin_mask, sync_mode, 6'd0, timeout}; end
    endfunction

    function [31:0] INS_JUMP_LOOP(input [3:0] loop_reg, input [7:0] target);
        begin INS_JUMP_LOOP = {4'd12, 4'd0, loop_reg, 4'd0, target, 8'd0}; end
    endfunction

    function [31:0] INS_JUMP(input [7:0] target);
        begin INS_JUMP = {4'd12, 4'd0, 4'd0, 4'd0, target, 8'd1}; end
    endfunction

    // SPI Detection pins: Pin 0=SCK, Pin 1=MOSI, Pin 2=CS_N, Pin 3=MISO
    
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
        // PC=0: R0 = bit counter (8)
        spi_write(8'h00, INS_LOAD(4'd0, 16'd8));
        // PC=1: R1 = RX data accumulator (0)
        spi_write(8'h01, INS_LOAD(4'd1, 16'h0000));
        // PC=2: R2 = temp
        spi_write(8'h02, INS_LOAD(4'd2, 16'h0000));
        // PC=3: R3 = temp
        spi_write(8'h03, INS_LOAD(4'd3, 16'h0001));

        // PC=4: Wait for CS falling edge (pin 2 = 0) - SYNC_FALL=1
        spi_write(8'h04, INS_SYNC(4'h4, 2'b01, 16'd10000));
        
        // PC=5: Wait for SCK rising edge (pin 0) - SYNC_RISE=0
        spi_write(8'h05, INS_SYNC(4'h1, 2'b00, 16'd1000));
        
        // PC=6: SCK rising edge - sample MOSI (pin 1) into R1
        spi_write(8'h06, INS_SAMPLE(4'd1, 4'h2));
        
        // PC=7: Shift R1 left by 1 (prepare for next bit)
        spi_write(8'h07, INS_SHIFT(4'd1, 4'd1, 4'd1, 1'b1));
        
        // PC=8: Decrement bit counter (R0) and loop back to PC=5 if >0
        // JUMP_LOOP: loop_reg=R0 (0), target=PC=5
        spi_write(8'h08, INS_JUMP_LOOP(4'd0, 8'd5));
        
        // PC=9: Done - 8 bits received, signal done on pin 3
        spi_write(8'h09, INS_DRIVE(4'h8, 2'b01, 2'd0));
        
        // Pad remaining
        spi_write(8'h0A, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0B, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0C, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0D, INS_LOAD(4'd0, 16'd0));
        spi_write(8'h0E, INS_LOAD(4'd0, 16'd0));

        $display("Program loaded (15 instructions). Starting sequencer...");
        spi_run(8'd15);

        // Wait for sequencer to start executing - it will reach PC=4 (SYNC on CS)
        // Note: sequencer increments PC before entering S_SYNC, so wait for PC=5 in S_SYNC
        wait_for_sync_at_pc(8'd5);
        $display("t=%0t: Reached PC=5 (SYNC on CS fall, was PC=4)", $time);
        
        // NOW simulate SPI master sending 0xA5 (10100101) MSB first
        // SPI Mode 0: CS low -> 8 SCK cycles with MOSI data -> CS high
        // SCK idles low, sample on rising edge
        
        // Start: CS goes low (falling edge on pin 2)
        ui_in[2] = 0;
        wait_clk(5);
        
        // Now wait for sequencer to reach PC=5 (SYNC on SCK rise) - wait for S_SYNC state
        // SYNC at PC=5 -> sequencer shows PC=6 in S_SYNC
        wait_for_sync_at_pc(8'd6);
        $display("t=%0t: Reached PC=6 (SYNC on SCK rise, was PC=5)", $time);
        
        // Now send 8 bits with SCK rising edge sampling
        // Bit 7: 1
        ui_in[1] = 1; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);  // SCK rise (0->1)
        wait_for_pc(8'd6); // SAMPLE
        wait_for_pc(8'd7); // SHIFT
        wait_for_pc(8'd8); // JUMP_LOOP
        wait_for_sync_at_pc(8'd6); // back to SYNC on SCK rise (PC=5 -> shows PC=6)
        ui_in[0] = 0; wait_clk(2);  // SCK fall (1->0)
        
        // Bit 6: 0
        ui_in[1] = 0; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 5: 1
        ui_in[1] = 1; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 4: 0
        ui_in[1] = 0; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 3: 0
        ui_in[1] = 0; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 2: 1
        ui_in[1] = 1; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 1: 0
        ui_in[1] = 0; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // Bit 0: 1
        ui_in[1] = 1; wait_clk(2);
        ui_in[0] = 1; wait_clk(2);
        wait_for_pc(8'd6);
        wait_for_pc(8'd7);
        wait_for_pc(8'd8);
        wait_for_sync_at_pc(8'd6);
        ui_in[0] = 0; wait_clk(2);
        
        // CS high (rising edge on pin 2) - not needed but clean up
        ui_in[2] = 1;
        wait_clk(10);

        // Wait for sequencer to complete - loop will exit when R0 reaches 0
        // Then PC advances to 9
        wait_for_pc(8'd9);
        wait_clk(100);
        
        $display("=== Results ===");
        $display("Final PC: %d", seq_pc);
        $display("Done: %b, Error: %b", seq_done, seq_error);
        $display("R0 (bit counter): %d", reg0);
        $display("R1 (RX data): %h (expected A5)", reg1);
        $display("R2 (temp): %h", reg2);
        $display("R3 (temp): %h", reg3);

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

    initial begin #300000; $display("TIMEOUT"); $finish; end
endmodule
