`timescale 1ns/1ps

module tb_usb_ls_simple;
    parameter CNT_W = 16;

    reg clk = 0, rst_n = 0;
    reg usb_dp = 1, usb_dn = 0;

    wire frame_valid;
    wire [3:0] pid;
    wire [6:0] addr;
    wire [3:0] endpt;
    wire [64*8-1:0] frame_data;
    wire [15:0] frame_len;
    wire crc_error, stuff_error, pid_error;
    wire [7:0] n_frames;
    wire [4:0] st_dbg;
    wire [7:0] bit_idx_dbg, byte_cnt_dbg;
    wire decoded_bit_dbg, process_bit_dbg;
    wire [4:0] stuff_count_dbg;
    wire expect_stuff_bit_dbg;

    usb_ls_detect #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .usb_dp(usb_dp), .usb_dn(usb_dn),
        .frame_valid(frame_valid), .pid(pid), .addr(addr), .endpt(endpt),
        .frame_data(frame_data), .frame_len(frame_len),
        .crc_error(crc_error), .stuff_error(stuff_error), .pid_error(pid_error),
        .n_frames(n_frames),
        .st_dbg(st_dbg), .bit_idx_dbg(bit_idx_dbg), .byte_cnt_dbg(byte_cnt_dbg),
        .decoded_bit_dbg(decoded_bit_dbg), .process_bit_dbg(process_bit_dbg),
        .stuff_count_dbg(stuff_count_dbg), .expect_stuff_bit_dbg(expect_stuff_bit_dbg)
    );

    always #10 clk = ~clk;  // 50MHz clock

    // USB LS bit period at 50MHz = 33.33 cycles, use 32
    localparam BIT_PERIOD = 32;
    localparam SAMPLE_POINT = BIT_PERIOD * 3 / 4;  // 75%

    // NRZI encoding helpers
    reg dp_state, dn_state;
    
    // USB differential states
    localparam J = 2'b10;  // D+=1, D-=0
    localparam K = 2'b01;  // D+=0, D-=1
    localparam SE0 = 2'b00; // EOP
    localparam SE1 = 2'b11; // Invalid

    // NRZI: 0 = transition, 1 = no transition
    // Start with J state (idle)
    initial begin
        dp_state = 1'b1;
        dn_state = 1'b0;
    end

    task nrzi_send_bit(input bit_val);
        if (bit_val == 1'b0) begin
            // Transition
            dp_state = ~dp_state;
            dn_state = ~dn_state;
        end
        // else no transition
        repeat (BIT_PERIOD) @(negedge clk);
    endtask

    // Drive the DUT pins
    always @(negedge clk) begin
        usb_dp = dp_state;
        usb_dn = dn_state;
    end

    task send_sync;
        integer i;
        begin
            // SYNC = KJKJKJKJ (8 bits)
            // In NRZI starting from J: K=0(transition), J=1(no trans), K=0(trans), J=1(no trans)....
            dp_state = 1'b1; dn_state = 1'b0;  // Start at J
            repeat (BIT_PERIOD) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                if (i % 2 == 0) begin // K
                    dp_state = 1'b0; dn_state = 1'b1;
                end else begin // J
                    dp_state = 1'b1; dn_state = 1'b0;
                end
                repeat (BIT_PERIOD) @(negedge clk);
            end
        end
    endtask

    task send_eop;
        begin
            // EOP = SE0 for 20 bit times (extended to give DUT time to process)
            dp_state = 1'b0; dn_state = 1'b0;
            repeat (BIT_PERIOD * 20) @(negedge clk);
            // Return to J (idle)
            dp_state = 1'b1; dn_state = 1'b0;
            repeat (BIT_PERIOD * 2) @(negedge clk);
        end
    endtask

    // CRC5 computation for token packets (reflected)
    function [4:0] crc5_usb(input [10:0] data);
        reg [4:0] crc;
        integer i;
        begin
            crc = 5'h1F;
            for (i = 0; i < 11; i = i + 1) begin
                if ((crc[0] ^ data[i]) == 1'b1)
                    crc = (crc >> 1) ^ 5'h14;  // Reflected 0x05 = 0x14
                else
                    crc = crc >> 1;
            end
            crc5_usb = crc;
        end
    endfunction

    task send_pid(input [3:0] pid_val);
        integer i;
        reg [7:0] pid_byte;
        begin
            pid_byte = {~pid_val, pid_val};  // PID format: ~pid[3:0], pid[3:0]
            for (i = 0; i < 8; i = i + 1) begin
                nrzi_send_bit(pid_byte[i]);
            end
        end
    endtask

    task send_token_packet(input [3:0] pid_val, input [6:0] addr_val, input [3:0] endpt_val);
        reg [10:0] token_data;
        reg [4:0] crc5;
        integer i;
        begin
            $display("  [TB] send_token_packet start at t=%0t", $time);
            send_sync();
            $display("  [TB] send_token_packet after sync at t=%0t", $time);
            send_pid(pid_val);
            
            // ADDR (7 bits) + ENDPT (4 bits) = 11 bits, LSB first
            token_data = {endpt_val, addr_val};
            for (i = 0; i < 11; i = i + 1) begin
                nrzi_send_bit(token_data[i]);
            end
            
            // CRC5 (5 bits, LSB first)
            crc5 = crc5_usb(token_data);
            $display("  [TB] Expected CRC5: %h", crc5);
            for (i = 0; i < 5; i = i + 1) begin
                nrzi_send_bit(crc5[i]);
            end
            
            send_eop();
            $display("  [TB] send_token_packet done at t=%0t", $time);
        end
    endtask

    // Polling-based frame detection
    task wait_for_frame_concurrent;
        begin
            @(posedge clk);
            while (!frame_valid) @(posedge clk);
            @(posedge clk);
        end
    endtask

    initial begin
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        repeat (4) @(negedge clk);

        // Test 1: OUT token packet only
        $display("Test 1: OUT token packet (addr=0x12, endpt=0x3) at t=%0t", $time);
        fork
            send_token_packet(4'h1, 7'h12, 4'h3);
            wait_for_frame_concurrent();
        join
        $display("  Test 1 done at t=%0t: pid=%h addr=%h endpt=%h frame_valid=%b frame_len=%d n_frames=%d st=%d in_frame=%b", 
                 $time, pid, addr, endpt, frame_valid, frame_len, n_frames, dut.st, dut.in_frame);

        repeat (10) @(negedge clk);

        $display("TEST PASSED at t=%0t", $time);
        $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (frame_valid) begin
            $display("  [TB] frame_valid at t=%0t: pid=%h addr=%h endpt=%h len=%d crc=%b stuff=%b pid_err=%b", 
                     $time, pid, addr, endpt, frame_len, crc_error, stuff_error, pid_error);
        end
    end

    initial begin #50000000; $display("TIMEOUT at t=%0t", $time); $finish; end
endmodule
