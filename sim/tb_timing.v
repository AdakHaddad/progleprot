`timescale 1ns/1ps

module tb_timing;
    reg clk = 0;
    initial begin
        repeat(10) begin
            @(negedge clk);
            $display("t=%0t negedge", $time);
        end
        $finish;
    end
    always #10 clk = ~clk;
endmodule
