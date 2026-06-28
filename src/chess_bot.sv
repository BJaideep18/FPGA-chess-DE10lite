// ========================================================================================================================
// chess_bot.sv  - "COMPUTER BOT ENGINE"
// ========================================================================================================================
module chess_bot (
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire [255:0] board_flat,
    output reg         done,
    output reg  [5:0]  from_sq,
    output reg  [5:0]  to_sq
);
    localparam ST_IDLE=2'd0, ST_SCAN=2'd1, ST_TRY=2'd2, ST_DONE=2'd3;
    reg [1:0] state;
    reg [5:0] fscan, tscan;
    reg [5:0] bfrom, bto;
    reg [23:0] bscore;

    // Pseudo-random number generator for move variety
    reg [15:0] lfsr;
    always @(posedge clk or posedge reset)
        if (reset) lfsr<=16'hACE1;
        else lfsr<={lfsr[14:0],lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};

    // Virtual board state generator
    wire [255:0] v_board;
    genvar vb;
    generate
        for (vb=0; vb<64; vb=vb+1) begin : gen_vboard
            assign v_board[vb*4+:4] =
                (vb[5:0] == tscan) ? board_flat[fscan*4+:4] :
                (vb[5:0] == fscan) ? 4'd0 :                  
                board_flat[vb*4+:4];                          
        end
    endgenerate

    wire [2:0] moving_piece = board_flat[fscan*4+:3];
    wire [2:0] target_piece = board_flat[tscan*4+:3];

    wire [11:0] cap_val =
        (target_piece==3'd1) ? 12'd100 :
        (target_piece==3'd2) ? 12'd350 :
        (target_piece==3'd3) ? 12'd350 :
        (target_piece==3'd4) ? 12'd500 :
        (target_piece==3'd5) ? 12'd900 : 12'd0;

    wire [11:0] moving_piece_val =
        (moving_piece==3'd1) ? 12'd100 :
        (moving_piece==3'd2) ? 12'd350 :
        (moving_piece==3'd3) ? 12'd350 :
        (moving_piece==3'd4) ? 12'd500 :
        (moving_piece==3'd5) ? 12'd900 : 12'd0;

    // Threat and Defense Matrix
    wire [63:0] tscan_attackers;
    wire [63:0] tscan_defenders;
    genvar i;
    generate
        for (i=0; i<64; i=i+1) begin : gen_curr_matrix
            move_validator enemy_chk (
                .from_sq(i[5:0]), .to_sq(tscan),
                .board_flat(board_flat), .player_color(1'b0), // White attacks
                .is_legal(tscan_attackers[i])
            );
            wire is_other_piece = (i[5:0] != fscan);
            wire defend_legal;
            move_validator defend_chk (
                .from_sq(i[5:0]), .to_sq(tscan),
                .board_flat(board_flat), .player_color(1'b1), // Black defends
                .is_legal(defend_legal)
            );
            assign tscan_defenders[i] = is_other_piece & defend_legal;
        end
    endgenerate

    wire square_is_dangerous = |tscan_attackers;
    wire square_is_defended  = |tscan_defenders;

    reg [11:0] threat_penalty;
    always @(*) begin
        if (square_is_dangerous && !square_is_defended) threat_penalty = moving_piece_val + 12'd200;
        else if (square_is_dangerous && square_is_defended) threat_penalty = moving_piece_val;
        else threat_penalty = 12'd0;
    end

    // Structure Bonus - Encourage defending own pieces
    wire [11:0] structure_bonus = (square_is_defended) ? 12'd20 : 12'd0;

    // Fork Matrix
    wire [63:0] fork_targets;
    generate
        for (i=0; i<64; i=i+1) begin : gen_fork
            move_validator fork_chk (
                .from_sq(tscan), .to_sq(i[5:0]),
                .board_flat(v_board), .player_color(1'b1),
                .is_legal(fork_targets[i])
            );
        end
    endgenerate

    reg [11:0] fork_bonus;
    integer fi;
    always @(*) begin
        fork_bonus = 12'd0;
        for (fi=0; fi<64; fi=fi+1) begin
            if (fork_targets[fi] && v_board[fi*4+3] == 1'b0 && v_board[fi*4+:3] != 3'd0) begin
                fork_bonus = fork_bonus + 12'd30;
            end
        end
    end

    // Future Look-Ahead (Check/Blunder)
    reg [5:0] w_king_sq, b_king_sq, b_queen_sq;
    reg b_queen_alive;
    integer sq;
    always @(*) begin
        w_king_sq = 6'd0; b_king_sq = 6'd0;
        b_queen_sq = 6'd0; b_queen_alive = 1'b0;
        for (sq=0; sq<64; sq=sq+1) begin
            if (v_board[sq*4+:4] == {1'b0, 3'd6}) w_king_sq = sq[5:0];
            if (v_board[sq*4+:4] == {1'b1, 3'd6}) b_king_sq = sq[5:0];
            if (v_board[sq*4+:4] == {1'b1, 3'd5}) begin b_queen_sq = sq[5:0]; b_queen_alive = 1'b1; end
        end
    end

    wire [63:0] w_king_attackers_future;
    wire [63:0] b_king_attackers_future;
    wire [63:0] b_queen_attackers_future;

    generate
        for (i=0; i<64; i=i+1) begin : gen_future_radars
            move_validator wkc (
                .from_sq(i[5:0]), .to_sq(w_king_sq),
                .board_flat(v_board), .player_color(1'b1),
                .is_legal(w_king_attackers_future[i])
            );
            move_validator bkc (
                .from_sq(i[5:0]), .to_sq(b_king_sq),
                .board_flat(v_board), .player_color(1'b0),
                .is_legal(b_king_attackers_future[i])
            );
            move_validator bqc (
                .from_sq(i[5:0]), .to_sq(b_queen_sq),
                .board_flat(v_board), .player_color(1'b0),
                .is_legal(b_queen_attackers_future[i])
            );
        end
    endgenerate

    wire [11:0] future_check_bonus  = (|w_king_attackers_future) ? 12'd150 : 12'd0;
    wire [11:0] future_king_blunder = (|b_king_attackers_future) ? 12'd4000 : 12'd0;
    wire [11:0] future_queen_hung   = (b_queen_alive && |b_queen_attackers_future) ? 12'd900 : 12'd0;

    // =======================================================
    // V2.0 ADVANCED PIECE-SQUARE TABLES (Bot plays as Black)
    // =======================================================
    reg  [11:0] pos_val;
    wire [2:0] dest_row = tscan[5:3];
    wire [2:0] dest_col = tscan[2:0];
    always @(*) begin
        pos_val = 12'd0;
        case (moving_piece)
            3'd1: begin // PAWNS
                if (dest_row == 3'd6) pos_val = 12'd250; // Approaching promotion
                else if (dest_row == 3'd5) pos_val = 12'd100;
                else if (dest_row == 3'd4 && dest_col >= 3 && dest_col <= 4) pos_val = 12'd60; // Push Center
                else if (dest_row >= 3'd2) pos_val = 12'd20;
            end
            3'd2: begin // KNIGHTS
                if (dest_row >= 2 && dest_row <= 5 && dest_col >= 2 && dest_col <= 5) begin
                    if (dest_row >= 3 && dest_row <= 4 && dest_col >= 3 && dest_col <= 4) pos_val = 12'd80; // Bullseye
                    else pos_val = 12'd40; // Inner ring
                end else if (dest_col == 0 || dest_col == 7) pos_val = 12'd0; // Rim is grim
                else pos_val = 12'd15;
            end
            3'd3: begin // BISHOPS
                if (dest_row >= 2 && dest_row <= 5 && dest_col >= 2 && dest_col <= 5) pos_val = 12'd40;
                else pos_val = 12'd20;
            end
            3'd4: begin // ROOKS
                if (dest_row == 3'd6) pos_val = 12'd90; // The 7th Rank Menace
                else if (dest_col == 3 || dest_col == 4) pos_val = 12'd30; // Control center files
                else pos_val = 12'd10;
            end
            3'd5: begin // QUEEN
                if (dest_row >= 2 && dest_row <= 5 && dest_col >= 2 && dest_col <= 5) pos_val = 12'd30;
                else pos_val = 12'd10;
            end
            3'd6: begin // KING
                // Keep king safe on the back ranks, tucked into corners
                if (dest_row <= 3'd1 && (dest_col <= 2 || dest_col >= 5)) pos_val = 12'd50;
                else pos_val = 12'd0;
            end
        endcase
    end

    // Final Aggregate Score
    wire [23:0] base_score = 24'd100000;
    wire [23:0] mscore = (base_score + cap_val + pos_val + structure_bonus + fork_bonus + future_check_bonus + {20'd0, lfsr[3:0]})
                         - threat_penalty - future_king_blunder - future_queen_hung;

    wire bot_legal;
    move_validator mv_bot (
        .from_sq(fscan), .to_sq(tscan),
        .board_flat(board_flat), .player_color(1'b1),
        .is_legal(bot_legal)
    );

    wire [2:0] scan_type  = board_flat[fscan*4+:3];
    wire       scan_color = board_flat[fscan*4+3];

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state<=ST_IDLE; done<=0;
            from_sq<=0; to_sq<=1; fscan<=0; tscan<=0; bfrom<=0; bto<=1; bscore<=0;
        end else begin
            done <= 1'b0;
            case (state)
                ST_IDLE: if (start) begin
                    fscan<=0; tscan<=0; bfrom<=0; bto<=1; bscore<=0; state<=ST_SCAN;
                end
                ST_SCAN: begin
                    if (scan_type!=3'd0 && scan_color==1'b1) begin tscan<=0; state<=ST_TRY; end
                    else if (fscan==6'd63) begin from_sq<=bfrom; to_sq<=bto; done<=1; state<=ST_DONE; end
                    else fscan<=fscan+6'd1;
                end
                ST_TRY: begin
                    if (bot_legal && mscore>bscore && future_king_blunder == 0) begin
                        bscore<=mscore; bfrom<=fscan; bto<=tscan;
                    end
                    if (tscan==6'd63) begin
                        if (fscan==6'd63) begin from_sq<=bfrom; to_sq<=bto; done<=1; state<=ST_DONE; end
                        else begin fscan<=fscan+6'd1; state<=ST_SCAN; end
                    end else tscan<=tscan+6'd1;
                end
                ST_DONE: begin
                    if (!start) state<=ST_IDLE;
                end
            endcase
        end
    end
endmodule

