`timescale 1ns/1ps
module tb_can_align;
    parameter CNT_W = 16;

    reg clk = 0, rst_n = 0;
    reg can_rx = 1;
    wire sample_clk_dbg;
    wire [4:0] st_dbg;
    wire [4:0] bit_idx_dbg;
    wire decoded_bit_dbg;
    wire process_bit_dbg;
    wire [3:0] stuff_count_dbg;
    wire expect_stuff_bit_dbg;
    wire [4:0] st_prev_dbg;
    wire frame_valid;

    can_detect #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .can_rx(can_rx),
        .frame_valid(frame_valid),
        .st_dbg(st_dbg), .st_prev_dbg(st_prev_dbg),
        .bit_idx_dbg(bit_idx_dbg),
        .decoded_bit_dbg(decoded_bit_dbg), .process_bit_dbg(process_bit_dbg),
        .stuff_count_dbg(stuff_count_dbg), .expect_stuff_bit_dbg(expect_stuff_bit_dbg),
        .sample_clk_dbg(sample_clk_dbg)
    );

    always #5 clk = ~clk;

    // Monitor sample_clk and can_rx
    always @(posedge clk) begin
        if (sample_clk_dbg) begin
            $display("Time %0t: sample_clk=1 st=%d bit_idx=%d rx=%b proc=%d dec=%b sc=%d exp_stuff=%d",
                     $time, st_dbg, bit_idx_dbg, can_rx, process_bit_dbg, decoded_bit_dbg, 
                     stuff_count_dbg, expect_stuff_bit_dbg);
        end
    end

    task send_can_bit(input bit_val);
        begin
            can_rx = bit_val;
            repeat (100) @(posedge clk);
        end
    endtask

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

        $display("Starting frame transmission");
        
        // Correct stuffed frame for ID=0x123, DLC=2, Data=0xABCD
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
        repeat (30) send_can_bit(1);  // Extra recessive bits
        
        wait_clk(200);
        $finish;
    end

    initial begin #10000000; $display("TIMEOUT"); $finish; end
endmodule
