`timescale 1ns/1ps
module tb_ps2;
    parameter CNT_W = 16;
    parameter IDX_W = 8;
    parameter BIN_W = 8;

    reg clk = 0, rst_n = 0;
    reg clk_pin = 1, data_pin = 1;

    wire frame_valid;
    wire [10:0] frame_bits;
    wire parity_error;
    wire [7:0] n_frames;
    wire direction;

    ps2_detect #(.CNT_W(CNT_W), .IDX_W(IDX_W), .BIN_W(BIN_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .clk_pin(clk_pin), .data_pin(data_pin),
        .frame_valid(frame_valid), .frame_bits(frame_bits),
        .parity_error(parity_error), .n_frames(n_frames), .direction(direction)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (frame_valid)
            $display("t=%0t FRAME_VALID bits=%b parity_err=%b n_frames=%d", $time, frame_bits, parity_error, n_frames);
    end

    // PS/2 frame generator - faster clock for simulation
    task send_ps2_frame(input [7:0] data);
        integer i;
        reg parity;
        begin
            parity = ^data; // Odd parity
            $display("t=%0t Sending frame: data=%h parity=%b", $time, data, parity);
            // Start bit
            data_pin = 0; clk_pin = 0; #10000; clk_pin = 1; #10000;
            // 8 data bits
            for (i = 0; i < 8; i = i + 1) begin
                data_pin = data[i]; clk_pin = 0; #10000; clk_pin = 1; #10000;
            end
            // Parity bit
            data_pin = parity; clk_pin = 0; #10000; clk_pin = 1; #10000;
            // Stop bit
            data_pin = 1; clk_pin = 0; #10000; clk_pin = 1; #10000;
            // Idle
            #50000;
        end
    endtask

    initial begin
        $display("Testing PS/2 detector...");
        repeat (2) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // Send key 'A' (make code 0x1C)
        send_ps2_frame(8'h1C);
        repeat (2500) @(posedge clk);
        
        // Send break code for 'A' (F0 1C)
        send_ps2_frame(8'hF0);
        repeat (2500) @(posedge clk);
        send_ps2_frame(8'h1C);
        repeat (2500) @(posedge clk);

        // Extended key (E0 prefix)
        send_ps2_frame(8'hE0);
        repeat (2500) @(posedge clk);
        send_ps2_frame(8'h75); // Up arrow
        repeat (2500) @(posedge clk);

        $display("PS/2 test done. Frames: %d", n_frames);
        $finish;
    end

    initial begin #20000000; $display("TIMEOUT"); $finish; end
endmodule
