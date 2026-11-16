`timescale 1ns/1ps

module tb_tt_wrapper;
    reg clk = 0, rst_n = 0, ena = 1;
    reg [7:0] ui_in = 0;
    reg [7:0] uio_in = 0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    tt_um_protocol_disc dut (
        .ui_in(ui_in), .uo_out(uo_out), .uio_in(uio_in), .uio_out(uio_out), .uio_oe(uio_oe),
        .ena(ena), .clk(clk), .rst_n(rst_n)
    );

    always #10 clk = ~clk;  // 50MHz

    // Test signals: SPI on pins 0,1,4
    reg [15:0] spi_data = 16'hA5;
    integer i;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(negedge clk); end
    endtask

    initial begin
        // Reset
        rst_n = 0;
        wait_clk(4);
        rst_n = 1;
        wait_clk(4);

        $display("=== TT Wrapper Test ===");

        // Configure: NRZ encoding (0), no stuffing
        uio_in[4:3] = 2'b00;  // enc_mode_ch0 = NRZ
        uio_in[7:5] = 3'b000; // stuff_after_ch0 = 0
        wait_clk(2);

        // Send SPI frame
        $display("Sending SPI frame...");
        ui_in[4] = 0;  // CS low
        wait_clk(4);
        for (i = 7; i >= 0; i = i - 1) begin
            ui_in[1] = spi_data[i];  // MOSI on pin 1
            ui_in[0] = 0; wait_clk(2);  // SCK low
            ui_in[0] = 1; wait_clk(2);  // SCK high
        end
        ui_in[4] = 1;  // CS high
        wait_clk(10);

        // Start scan and immediately wait for scan_done
        $display("Starting scan...");
        uio_in[1] = 1;  // scan_start
        wait_clk(2);
        uio_in[1] = 0;
        
        // Wait for scan_done pulse - poll immediately
        repeat (200000) @(posedge clk);
        if (!uo_out[2]) repeat (200000) @(posedge clk);
        
        $display("Scan done detected! uo_out=%b, uio_out=%b", uo_out, uio_out);
        $display("  Scan done: %b, List done: %b, Result valid: %b, Proto: %h, Rank: %h",
                 uo_out[2], uo_out[7], uo_out[5], uio_out[7:4], uio_out[3:0]);

        // Start replay and wait for replay_done
        $display("Starting replay...");
        uio_in[2] = 1;  // replay_start
        wait_clk(2);
        uio_in[2] = 0;
        
        // Wait for replay_done pulse
        repeat (200000) @(posedge clk);
        if (!uo_out[4]) repeat (200000) @(posedge clk);
        
        $display("Replay done detected! uo_out=%b", uo_out);
        $display("  Replay done: %b, Error: %b", uo_out[4], uo_out[3]);

        // Clear
        uio_in[0] = 1;
        wait_clk(2);
        uio_in[0] = 0;
        wait_clk(10);

        $display("Test complete");
        $finish;
    end

    // Monitor
    always @(posedge clk) begin
        if (uo_out[2] || uo_out[4] || uo_out[5] || uo_out[7]) begin
            $display("t=%0t uo_out=%b uio_out=%b", $time, uo_out, uio_out);
        end
    end

    initial begin #5000000; $display("TIMEOUT"); $finish; end
endmodule
