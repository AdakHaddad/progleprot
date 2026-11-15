`timescale 1ns/1ps
module tb_can_simple;
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
    wire [15:0] sample_phase_dbg;
    wire sample_clk_dbg;
    wire decoded_bit_dbg;
    wire in_frame_dbg;

    can_detect #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .can_rx(can_rx),
        .frame_valid(frame_valid), .frame_id(frame_id), .extended_id(extended_id),
        .rtr(rtr), .dlc(dlc), .frame_data(frame_data),
        .crc_error(crc_error), .stuff_error(stuff_error), .ack_error(ack_error),
        .n_frames(n_frames), .state_dbg(state_dbg),
        .st_dbg(st_dbg), .sample_phase_dbg(sample_phase_dbg),
        .sample_clk_dbg(sample_clk_dbg), .decoded_bit_dbg(decoded_bit_dbg),
        .in_frame_dbg(in_frame_dbg)
    );

    always #5 clk = ~clk;

    // Monitor
    always @(posedge clk) begin
        if (sample_clk_dbg) begin
            $display("Time %0t: state=%d phase=%d in_frame=%b can_rx=%b decoded=%b frame_id=%h dlc=%d",
                     $time, st_dbg, sample_phase_dbg, in_frame_dbg, can_rx, decoded_bit_dbg, frame_id, dlc);
        end
        if (frame_valid) begin
            $display("FRAME VALID at %0t: id=%h ext=%b rtr=%b dlc=%d data=%h crc_err=%b", 
                     $time, frame_id, extended_id, rtr, dlc, frame_data, crc_error);
        end
    end

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
        
        $display("Time %0t: Sending SOF", $time);
        // SOF - dominant (0) for 100 cycles
        repeat (100) @(posedge clk);
        can_rx = 0;
        $display("Time %0t: SOF sent", $time);
        
        // 11-bit ID: 0x123 = 00010010011
        repeat (100) @(posedge clk); can_rx = 0; // bit 10
        repeat (100) @(posedge clk); can_rx = 0; // bit 9
        repeat (100) @(posedge clk); can_rx = 0; // bit 8
        repeat (100) @(posedge clk); can_rx = 1; // bit 7
        repeat (100) @(posedge clk); can_rx = 0; // bit 6
        repeat (100) @(posedge clk); can_rx = 0; // bit 5
        repeat (100) @(posedge clk); can_rx = 1; // bit 4
        repeat (100) @(posedge clk); can_rx = 0; // bit 3
        repeat (100) @(posedge clk); can_rx = 0; // bit 2
        repeat (100) @(posedge clk); can_rx = 1; // bit 1
        repeat (100) @(posedge clk); can_rx = 1; // bit 0
        
        // SRR=1, IDE=0
        repeat (100) @(posedge clk); can_rx = 1; // SRR
        repeat (100) @(posedge clk); can_rx = 0; // IDE
        
        // RTR=0
        repeat (100) @(posedge clk); can_rx = 0;
        
        // r1=0, r0=0
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 0;
        
        // DLC=2 (0010)
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        
        // Data: 0xAB, 0xCD
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 1;
        
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        
        // CRC = 0x72A5 = 111001010100101
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        repeat (100) @(posedge clk); can_rx = 0;
        repeat (100) @(posedge clk); can_rx = 1;
        
        // CRC delimiter
        repeat (100) @(posedge clk); can_rx = 1;
        // ACK slot
        repeat (100) @(posedge clk); can_rx = 1;
        // ACK delimiter
        repeat (100) @(posedge clk); can_rx = 1;
        // EOF (7 recessive)
        repeat (7) begin
            repeat (100) @(posedge clk); can_rx = 1;
        end
        // IFS (3 recessive)
        repeat (3) begin
            repeat (100) @(posedge clk); can_rx = 1;
        end
        
        repeat (20) @(posedge clk);
        $finish;
    end
    
    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
