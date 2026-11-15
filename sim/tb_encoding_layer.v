`timescale 1ns/1ps
module tb_encoding_layer;
    parameter CNT_W = 16;

    reg clk = 0, rst_n = 0;
    reg [1:0] mode = 2'd0;
    reg bit_in = 1, bit_valid = 0;
    reg [3:0] stuff_after = 4'd0;
    wire bit_out, bit_out_valid, stuff_error;

    integer errors = 0;

    encoding_layer #(.CNT_W(CNT_W)) dut (
        .clk(clk), .rst_n(rst_n),
        .mode(mode), .bit_in(bit_in), .bit_valid(bit_valid),
        .bit_out(bit_out), .bit_out_valid(bit_out_valid),
        .stuff_after(stuff_after), .stuff_error(stuff_error)
    );

    always #5 clk = ~clk;

    task wait_clk(input integer n);
        integer j;
        begin for (j = 0; j < n; j = j + 1) @(posedge clk); end
    endtask

    // Send bit and keep valid for full cycle
    task send_bit(input b);
        begin
            @(negedge clk); bit_in = b; bit_valid = 1;
            @(negedge clk); bit_valid = 0;
        end
    endtask

    // Check at posedge after send
    task check_bit(input expected, input desc);
        begin
            @(posedge clk);
            if (bit_out !== expected) begin
                $display("  FAIL %s: got %b, expected %b (valid=%b)", desc, bit_out, expected, bit_out_valid);
                errors = errors + 1;
            end else if (!bit_out_valid) begin
                $display("  FAIL %s: bit_out_valid=0, expected 1", desc);
                errors = errors + 1;
            end else begin
                $display("  PASS %s", desc);
            end
        end
    endtask

    // Expect bit to be held (not output)
    task check_held(input desc);
        begin
            @(posedge clk);
            if (bit_out_valid) begin
                $display("  FAIL %s: bit_out_valid=1, expected 0 (held)", desc);
                errors = errors + 1;
            end else begin
                $display("  PASS %s: correctly held (stuff bit removed)", desc);
            end
        end
    endtask

    initial begin
        wait_clk(2); rst_n = 1; wait_clk(2);

        // ============================================================
        // Test 1: NRZ Mode (mode=0) - Direct bit mapping
        // ============================================================
        $display("Test 1: NRZ Mode");
        mode = 2'd0;
        wait_clk(2);

        send_bit(1); check_bit(1, "NRZ bit 1");
        send_bit(0); check_bit(0, "NRZ bit 0");
        send_bit(1); check_bit(1, "NRZ bit 1");
        send_bit(1); check_bit(1, "NRZ bit 1");

        // ============================================================
        // Test 2: NRZI Mode (mode=1) - Transition=0, No transition=1
        // ============================================================
        $display("Test 2: NRZI Mode");
        mode = 2'd1;
        wait_clk(2);

        // First bit establishes baseline (no output)
        send_bit(1); wait_clk(1); // prev=1
        // No transition -> 1
        send_bit(1); check_bit(1, "NRZI no transition -> 1");
        // Transition -> 0
        send_bit(0); check_bit(0, "NRZI transition -> 0");
        // Transition -> 0
        send_bit(1); check_bit(0, "NRZI transition -> 0");
        // No transition -> 1
        send_bit(1); check_bit(1, "NRZI no transition -> 1");

        // ============================================================
        // Test 3: Manchester Mode (mode=2) - High->Low=0, Low->High=1
        // ============================================================
        $display("Test 3: Manchester Mode");
        mode = 2'd2;
        wait_clk(2);

        // First bit establishes baseline
        send_bit(1); wait_clk(1); // prev=1
        // High->Low = 0
        send_bit(0); check_bit(0, "Manchester 1->0 = 0");
        // Low->High = 1
        send_bit(1); check_bit(1, "Manchester 0->1 = 1");
        // High->Low = 0
        send_bit(0); check_bit(0, "Manchester 1->0 = 0");
        // Low->High = 1
        send_bit(1); check_bit(1, "Manchester 0->1 = 1");

        // ============================================================
        // Test 4: Stuffing Mode (mode=3) - CAN/USB style
        // Stuff after 5 consecutive same bits on WIRE
        // Wire: 1 1 1 1 1 0(stuff) 1 1 1 1 1 0(stuff)...
        // Decoder output: 1 1 1 1 1 1 1 1 1 1 1 1...
        // ============================================================
        $display("Test 4: Stuffing Mode (stuff_after=5)");
        mode = 2'd3;
        stuff_after = 4'd5;
        wait_clk(2);

        // Send 5 ones - all should pass through
        send_bit(1); check_bit(1, "Stuff 1st 1");
        send_bit(1); check_bit(1, "Stuff 2nd 1");
        send_bit(1); check_bit(1, "Stuff 3rd 1");
        send_bit(1); check_bit(1, "Stuff 4th 1");
        send_bit(1); check_bit(1, "Stuff 5th 1 (threshold reached)");
        // 6th bit on wire = stuff bit = 0 (inverted!) -> REMOVED
        send_bit(0); check_held("Stuff bit 0 (inverted) -> REMOVED");
        // Now continue with data - output continues
        send_bit(1); check_bit(1, "Data 1 after stuff");
        send_bit(1); check_bit(1, "Data 2");
        send_bit(1); check_bit(1, "Data 3");
        send_bit(1); check_bit(1, "Data 4");
        send_bit(1); check_bit(1, "Data 5 (threshold)");
        // Next stuff bit = 0 -> REMOVED
        send_bit(0); check_held("Stuff bit 0 -> REMOVED");
        send_bit(1); check_bit(1, "Data 1");

        // Test with zeros
        wait_clk(2);
        mode = 2'd3;
        stuff_after = 4'd3;
        wait_clk(2);

        send_bit(0); check_bit(0, "Zero 1");
        send_bit(0); check_bit(0, "Zero 2");
        send_bit(0); check_bit(0, "Zero 3 (threshold)");
        // Stuff bit = 1 (inverted) -> REMOVED
        send_bit(1); check_held("Stuff bit 1 -> REMOVED");
        send_bit(0); check_bit(0, "Data 1 after stuff");

        // ============================================================
        // Test 5: Stuff Error Detection - stuff bit NOT inverted
        // ============================================================
        $display("Test 5: Stuff Error Detection");
        wait_clk(2);
        mode = 2'd3;
        stuff_after = 4'd3;
        wait_clk(2);

        send_bit(1); check_bit(1, "Error test 1");
        send_bit(1); check_bit(1, "Error test 2");
        send_bit(1); check_bit(1, "Error test 3 (threshold)");
        // Next bit on wire = 1 (NOT inverted = ERROR!) -> still removed but error flagged
        send_bit(1); 
        @(posedge clk);
        if (stuff_error) begin
            $display("  PASS Stuff error detected (stuff bit not inverted)");
        end else begin
            $display("  FAIL Stuff error NOT detected");
            errors = errors + 1;
        end
        // The error bit is still removed (not output)
        check_held("Error bit removed despite error");

        // Another error: zeros with non-inverted stuff
        wait_clk(2);
        send_bit(0); check_bit(0, "Zero error 1");
        send_bit(0); check_bit(0, "Zero error 2");
        send_bit(0); check_bit(0, "Zero error 3 (threshold)");
        // Stuff bit = 0 (NOT inverted = ERROR!)
        send_bit(0);
        @(posedge clk);
        if (stuff_error) begin
            $display("  PASS Stuff error detected (zero stuff not inverted)");
        end else begin
            $display("  FAIL Zero stuff error NOT detected");
            errors = errors + 1;
        end

        if (errors == 0) $display("\nALL ENCODING LAYER TESTS PASSED");
        else $display("\n%0d ENCODING LAYER TEST(S) FAILED", errors);
        $finish;
    end

    initial begin #1000000; $display("TIMEOUT"); $finish; end
endmodule
