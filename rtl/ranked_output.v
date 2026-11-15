// ranked_output: Produces a ranked list of protocol hypotheses with confidence.
// Maintains top-N matches, outputs them one per cycle via a streaming interface.
module ranked_output #(
    parameter MAX_RESULTS = 8,
    parameter PROTO_BITS = 4,
    parameter SCORE_BITS = 8,
    parameter CONF_BITS = 8
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    match_valid,
    input  wire [PROTO_BITS-1:0]   match_proto,
    input  wire [SCORE_BITS-1:0]   match_score,    // 0=best, 255=worst
    input  wire                    match_done,     // all fingerprints scanned for this frame
    input  wire                    new_frame,      // pulse when a new frame arrives
    output reg                     result_valid,
    output reg [PROTO_BITS-1:0]    result_proto,
    output reg [CONF_BITS-1:0]     result_conf,    // 255=high confidence, 0=low
    output reg [$clog2(MAX_RESULTS):0] result_rank, // 0=top
    output reg                     list_done,      // pulse when ranked list complete
    output reg                     ambiguous       // 1 if top scores are too close
);
    localparam IDLE     = 2'd0;
    localparam COLLECT  = 2'd1;
    localparam SORT     = 2'd2;
    localparam OUTPUT   = 3'd3;

    reg [1:0] st;

    // Storage for matches per frame
    reg [PROTO_BITS-1:0]  proto_mem [0:MAX_RESULTS-1];
    reg [SCORE_BITS-1:0]  score_mem [0:MAX_RESULTS-1];
    reg                   valid_mem [0:MAX_RESULTS-1];
    reg [$clog2(MAX_RESULTS):0] num_valid;

    // Sorting network registers
    reg [PROTO_BITS-1:0]  sort_proto [0:MAX_RESULTS-1];
    reg [SCORE_BITS-1:0]  sort_score [0:MAX_RESULTS-1];
    reg                   sort_valid [0:MAX_RESULTS-1];

    // Output state
    reg [$clog2(MAX_RESULTS):0] out_idx;
    reg [3:0] sort_stage;

    // Ambiguity threshold: if top 2 scores within this delta, mark ambiguous
    localparam AMBIG_DELTA = 8'd20;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= IDLE;
            num_valid <= 0;
            result_valid <= 1'b0;
            result_proto <= 4'd0;
            result_conf <= 8'd0;
            result_rank <= 0;
            list_done <= 1'b0;
            ambiguous <= 1'b0;
            out_idx <= 0;
            sort_stage <= 0;
            for (integer i = 0; i < MAX_RESULTS; i = i + 1) begin
                proto_mem[i] <= 4'd0;
                score_mem[i] <= 8'd255;
                valid_mem[i] <= 1'b0;
            end
        end else begin
            result_valid <= 1'b0;
            list_done <= 1'b0;

            case (st)
                IDLE: begin
                    if (new_frame) begin
                        // Reset for new frame
                        num_valid <= 0;
                        for (integer i = 0; i < MAX_RESULTS; i = i + 1) begin
                            valid_mem[i] <= 1'b0;
                        end
                        st <= COLLECT;
                    end
                end

                COLLECT: begin
                    if (match_valid) begin
                        // Insert into sorted list (insertion sort, keep best MAX_RESULTS)
                        reg [$clog2(MAX_RESULTS):0] insert_pos;
                        insert_pos = num_valid;
                        // Find position (lower score = better)
                        for (integer i = 0; i < MAX_RESULTS; i = i + 1) begin
                            if (i < num_valid && match_score < score_mem[i]) begin
                                insert_pos = i;
                            end
                        end
                        // Shift down
                        if (num_valid < MAX_RESULTS) num_valid <= num_valid + 1'b1;
                        for (integer i = MAX_RESULTS-1; i > 0; i = i - 1) begin
                            if (i > insert_pos) begin
                                proto_mem[i] <= proto_mem[i-1];
                                score_mem[i] <= score_mem[i-1];
                                valid_mem[i] <= valid_mem[i-1];
                            end
                        end
                        proto_mem[insert_pos] <= match_proto;
                        score_mem[insert_pos] <= match_score;
                        valid_mem[insert_pos] <= 1'b1;
                    end

                    if (match_done) begin
                        // Copy to sort arrays
                        for (integer i = 0; i < MAX_RESULTS; i = i + 1) begin
                            sort_proto[i] <= proto_mem[i];
                            sort_score[i] <= score_mem[i];
                            sort_valid[i] <= valid_mem[i];
                        end
                        sort_stage <= 0;
                        st <= SORT;
                    end
                end

                SORT: begin
                    // Simple bubble sort (small N, unrolled would be better)
                    if (sort_stage < MAX_RESULTS) begin
                        for (integer i = 0; i < MAX_RESULTS-1; i = i + 1) begin
                            if (sort_valid[i] && sort_valid[i+1] && sort_score[i] > sort_score[i+1]) begin
                                // Swap
                                reg [PROTO_BITS-1:0] t_proto;
                                reg [SCORE_BITS-1:0] t_score;
                                reg t_valid;
                                t_proto = sort_proto[i];
                                t_score = sort_score[i];
                                t_valid = sort_valid[i];
                                sort_proto[i] <= sort_proto[i+1];
                                sort_score[i] <= sort_score[i+1];
                                sort_valid[i] <= sort_valid[i+1];
                                sort_proto[i+1] <= t_proto;
                                sort_score[i+1] <= t_score;
                                sort_valid[i+1] <= t_valid;
                            end
                        end
                        sort_stage <= sort_stage + 1'b1;
                    end else begin
                        st <= OUTPUT;
                        out_idx <= 0;
                        // Check ambiguity
                        if (sort_valid[0] && sort_valid[1] && 
                            (sort_score[1] - sort_score[0] < AMBIG_DELTA)) begin
                            ambiguous <= 1'b1;
                        end else begin
                            ambiguous <= 1'b0;
                        end
                    end
                end

                OUTPUT: begin
                    if (sort_valid[out_idx]) begin
                        result_proto <= sort_proto[out_idx];
                        // Confidence: invert score (0->255, 255->0), scale
                        result_conf <= 8'd255 - sort_score[out_idx];
                        result_rank <= out_idx;
                        result_valid <= 1'b1;
                        out_idx <= out_idx + 1'b1;
                    end else begin
                        list_done <= 1'b1;
                        st <= IDLE;
                    end
                end
            endcase
        end
    end
endmodule
