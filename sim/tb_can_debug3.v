`timescale 1ns/1ps
module tb_can_debug3;
    parameter CNT_W = 16;

    reg clk = 0, rst_n = 0;
    reg can_rx = 1;
    wire frame_valid;
    wire [28:0] frame_id;
    wire extended_id;
    wire rtr;
    wire [3:0] dlc;
    wire [63:0] frame_data;
    wire crc_error, stuff_error, ack_error;
    wire [7:0] n_frames;
    wire [3:0] state_dbg;
    wire [4:0] st_dbg;
    wire [4:0] st_prev_dbg;
    wire [4:0] bit_idx_dbg;
    wire [7:0] byte_cnt_dbg;
    wire decoded_bit_dbg;
    wire process_bit_dbg;
    wire [3:0] stuff_count_dbg;
    wire expect_stuff_bit_dbg;
    wire sample_clk_dbg;

    can_detect #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .can_rx(can_rx),
        .frame_valid(frame_valid), .frame_id(frame_id), .extended_id(extended_id),
        .rtr(rtr), .dlc(dlc), .frame_data(frame_data),
        .crc_error(crc_error), .stuff_error(stuff_error), .ack_error(ack_error),
        .n_frames(n_frames), .state_dbg(state_dbg),
        .st_dbg(st_dbg), .st_prev_dbg(st_prev_dbg),
        .bit_idx_dbg(bit_idx_dbg), .byte_cnt_dbg(byte_cnt_dbg),
        .decoded_bit_dbg(decoded_bit_dbg), .process_bit_dbg(process_bit_dbg),
        .stuff_count_dbg(stuff_count_dbg), .expect_stuff_bit_dbg(expect_stuff_bit_dbg),
        .sample_clk_dbg(sample_clk_dbg)
    );

    always #5 clk = ~clk;

    // Monitor frame_valid
    always @(posedge clk) begin
        if (frame_valid) begin
            $display("Time %0t: frame_valid=1 frame_id=0x%X data=0x%X", $time, frame_id, frame_data);
        end
    end

    // Monitor state changes
    always @(posedge clk) begin
        if (st_dbg != st_prev_dbg) begin
            $display("Time %0t: State %d -> %d", $time, st_prev_dbg, st_dbg);
        end
    end

    // Detailed debug on sample_clk
    always @(posedge clk) begin
        if (sample_clk_dbg) begin
            $display("Time %0t: st=%d bit_idx=%d sc=%d exp_stuff=%d proc=%d dec=%d rx=%b dlc_reg=%b byte_cnt=%d",
                     $time, st_dbg, bit_idx_dbg, stuff_count_dbg, expect_stuff_bit_dbg,
                     process_bit_dbg, decoded_bit_dbg, can_rx, 
                     (st_dbg == 6) ? dut.dlc_reg : 4'bx, byte_cnt_dbg);
        end
    end

    // Send bit immediately, then wait for next bit period (100 cycles)
    task send_can_bit(input bit_val);
        begin
            can_rx = bit_val;
            repeat (100) @(posedge clk);
        end
    endtask

    // Send first bit (SOF) immediately after reset, then wait
    task send_first_bit(input bit_val);
        begin
            can_rx = bit_val;
            repeat (100) @(posedge clk);
        end
    endtask

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(posedge clk); end
    endtask

    initial begin
        wait_clk(4); rst_n = 1; wait_clk(4);

        $display("Test 1: Standard CAN Frame (11-bit ID) with stuffing");
        // Correct stuffed frame for ID=0x123, DLC=2, Data=0xABCD (64 bits):
        send_first_bit(0);  // bit 0 (SOF)
        send_can_bit(0);  // bit 1
        send_can_bit(0);  // bit 2
        send_can_bit(1);  // bit 3
        send_can_bit(0);  // bit 4
        send_can_bit(0);  // bit 5
        send_can_bit(1);  // bit 6
        send_can_bit(0);  // bit 7
        send_can_bit(0);  // bit 8
        send_can_bit(0);  // bit 9
        send_can_bit(1);  // bit 10
        send_can_bit(1);  // bit 11
        send_can_bit(0);  // bit 12
        send_can_bit(0);  // bit 13
        send_can_bit(0);  // bit 14
        send_can_bit(0);  // bit 15
        send_can_bit(0);  // bit 16
        send_can_bit(1);  // bit 17 - stuff bit!
        send_can_bit(1);  // bit 18
        send_can_bit(0);  // bit 19
        send_can_bit(1);  // bit 20
        send_can_bit(0);  // bit 21
        send_can_bit(1);  // bit 22
        send_can_bit(0);  // bit 23
        send_can_bit(1);  // bit 24
        send_can_bit(0);  // bit 25
        send_can_bit(1);  // bit 26
        send_can_bit(1);  // bit 27
        send_can_bit(1);  // bit 28
        send_can_bit(1);  // bit 29
        send_can_bit(0);  // bit 30
        send_can_bit(0);  // bit 31
        send_can_bit(1);  // bit 32
        send_can_bit(1);  // bit 33
        send_can_bit(0);  // bit 34
        send_can_bit(1);  // bit 35
        send_can_bit(0);  // bit 36
        send_can_bit(1);  // bit 37
        send_can_bit(1);  // bit 38
        send_can_bit(0);  // bit 39
        send_can_bit(1);  // bit 40
        send_can_bit(0);  // bit 41
        send_can_bit(0);  // bit 42
        send_can_bit(1);  // bit 43
        send_can_bit(0);  // bit 44
        send_can_bit(1);  // bit 45
        send_can_bit(1);  // bit 46
        send_can_bit(0);  // bit 47
        send_can_bit(0);  // bit 48
        send_can_bit(0);  // bit 49
        send_can_bit(0);  // bit 50
        send_can_bit(1);  // bit 51
        send_can_bit(1);  // bit 52
        send_can_bit(1);  // bit 53
        send_can_bit(1);  // bit 54
        send_can_bit(1);  // bit 55
        send_can_bit(1);  // bit 56
        send_can_bit(1);  // bit 57
        send_can_bit(1);  // bit 58
        send_can_bit(1);  // bit 59
        send_can_bit(1);  // bit 60
        send_can_bit(1);  // bit 61
        send_can_bit(1);  // bit 62
        send_can_bit(1);  // bit 63
        repeat (20) send_can_bit(1);  // Extra recessive bits for EOF/IFS
        
        wait_clk(200);
        
        $display("Final: frame_valid=%b frame_id=0x%X ext=%b rtr=%b dlc=%d data=0x%X crc_err=%b stuff_err=%b ack_err=%b n_frames=%d state=%d",
                 frame_valid, frame_id, extended_id, rtr, dlc, frame_data, crc_error, stuff_error, ack_error, n_frames, state_dbg);
        
        if (frame_valid && frame_id[10:0] == 11'h123 && !extended_id && !rtr && dlc == 4'd2 && frame_data[15:0] == 16'hABCD && !crc_error && !stuff_error) begin
            $display("  PASS");
        end else begin
            $display("  FAIL");
        end

        $finish;
    end

    initial begin #10000000; $display("TIMEOUT"); $finish; end
endmodule
