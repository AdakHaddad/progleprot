`timescale 1ns/1ps
module tb_can_debug2;
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

    can_detect #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .can_rx(can_rx),
        .frame_valid(frame_valid), .frame_id(frame_id), .extended_id(extended_id),
        .rtr(rtr), .dlc(dlc), .frame_data(frame_data),
        .crc_error(crc_error), .stuff_error(stuff_error), .ack_error(ack_error),
        .n_frames(n_frames), .state_dbg(state_dbg)
    );

    always #5 clk = ~clk;

    // Monitor decoded bits by checking state transitions
    integer sample_count = 0;
    always @(posedge clk) begin
        if (dut.sample_clk) begin
            sample_count <= sample_count + 1;
            $display("Sample %d: time=%0t state=%d decoded=%b can_rx=%b frame_id=%h dlc=%d data=%h",
                     sample_count, $time, dut.st, dut.decoded_bit, can_rx, frame_id, dlc, frame_data);
        end
    end

    initial begin
        rst_n = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
        
        // Send stuffed frame for ID=0x123, DLC=2, Data=0xABCD
        // Stuffed bits (68 bits):
        send_can_bit(0);  // bit 0: SOF
        send_can_bit(0);  // bit 1: ID[10]
        send_can_bit(0);  // bit 2: ID[9]
        send_can_bit(1);  // bit 3: ID[8]
        send_can_bit(0);  // bit 4: ID[7]
        send_can_bit(0);  // bit 5: ID[6]
        send_can_bit(1);  // bit 6: ID[5]
        send_can_bit(0);  // bit 7: ID[4]
        send_can_bit(0);  // bit 8: ID[3]
        send_can_bit(0);  // bit 9: ID[2]
        send_can_bit(1);  // bit 10: ID[1]
        send_can_bit(1);  // bit 11: ID[0]
        send_can_bit(1);  // bit 12: SRR
        send_can_bit(0);  // bit 13: IDE
        send_can_bit(0);  // bit 14: RTR
        send_can_bit(0);  // bit 15: r1
        send_can_bit(0);  // bit 16: r0
        send_can_bit(0);  // bit 17: DLC[3]
        send_can_bit(0);  // bit 18: DLC[2]
        send_can_bit(1);  // bit 19: DLC[1] (stuff bit inserted after this? No, 5 zeros at 13-17)
        send_can_bit(0);  // bit 20: DLC[0] - wait, this is wrong
        // Let me just send the precomputed stuffed sequence
    end

    task send_can_bit(input bit_val);
        begin
            repeat (100) @(posedge clk);
            can_rx = bit_val;
        end
    endtask

    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
