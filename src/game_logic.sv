// ========================================================================================================================
// game_logic.sv  - Main game state machine
// ========================================================================================================================

module game_logic (
    input  wire         clk,
    input  wire         reset,
    input  wire         key_up, key_down, key_left, key_right,
    input  wire         key_select, key_cancel,
    output wire [255:0] board_flat,
    output wire [44:0]  cap_w_flat,
    output wire [44:0]  cap_b_flat,
    output reg  [5:0]   cursor_sq,
    output reg  [5:0]   selected_sq,
    output reg          sel_active,
    output reg          player_turn,
    output reg          bot_thinking,
    output wire [2:0]   state_out,
    // Visual outputs
    output wire [63:0]  valid_moves,
    output wire         w_in_check,
    output wire         b_in_check,
    output wire [5:0]   w_king_sq,
    output wire [5:0]   b_king_sq,
    // Game result
    output reg          checkmate,
    output reg          player_won,
    output reg          player_lost
);

    // ============================================================
    // States
    // ============================================================
    localparam S_INIT     = 3'd0,
               S_PLAYER   = 3'd1,
               S_SELECTED = 3'd2,
               S_PMOVE    = 3'd3,
               S_BTHINK   = 3'd4,
               S_BMOVE    = 3'd5,
               S_GAMEOVER = 3'd6;

    reg [2:0] state;
    assign state_out = state;

    // ============================================================
    // Piece constants
    // ============================================================
    localparam NONE=3'd0, PAWN=3'd1, KNIGHT=3'd2, BISHOP=3'd3,
               ROOK=3'd4, QUEEN=3'd5, KING=3'd6;
    localparam W=1'b0, B=1'b1;

    // ============================================================
    // Board and graveyard
    // ============================================================
    reg [3:0] board    [0:63];
    reg [2:0] cap_w    [0:14];  // black pieces captured by white (shown left)
    reg [2:0] cap_b    [0:14];  // white pieces captured by black (shown right)
    reg [3:0] cap_w_cnt;
    reg [3:0] cap_b_cnt;

    genvar gi;
    generate
        for (gi=0; gi<64; gi=gi+1) begin : flatten_board
            assign board_flat[gi*4+:4] = board[gi];
        end
        for (gi=0; gi<15; gi=gi+1) begin : flatten_graveyard
            assign cap_w_flat[gi*3+:3] = cap_w[gi];
            assign cap_b_flat[gi*3+:3] = cap_b[gi];
        end
    endgenerate

    // ============================================================
    // VALID MOVE SCANNER (64 parallel, normal mode, for player UI)
    // ============================================================
    genvar vi;
    generate
        for (vi=0; vi<64; vi=vi+1) begin : gen_valid_moves
            move_validator mv_dest (
                .from_sq      (selected_sq),
                .to_sq        (vi[5:0]),
                .board_flat   (board_flat),
                .player_color (player_turn),
                .attack_mode  (1'b0),
                .is_legal     (valid_moves[vi])
            );
        end
    endgenerate

    wire move_ok = valid_moves[cursor_sq];

    // ============================================================
    // KING POSITION FINDER (combinational priority scan)
    // ============================================================
    integer j;
    reg [5:0] wk_sq, bk_sq;
    always @(*) begin
        wk_sq = 6'd60;  // white king default start
        bk_sq = 6'd4;   // black king default start
        for (j=0; j<64; j=j+1) begin
            if (board[j] == {W, KING}) wk_sq = j[5:0];
            if (board[j] == {B, KING}) bk_sq = j[5:0];
        end
    end
    assign w_king_sq = wk_sq;
    assign b_king_sq = bk_sq;

    // ============================================================
    // CHECK DETECTOR (128 parallel, attack_mode=1)
    // attack_mode=1: pawn diagonal threat covers empty squares too
    // w_attackers[i]=1 : black piece at sq[i] attacks white king
    // b_attackers[i]=1 : white piece at sq[i] attacks black king
    // ============================================================
    wire [63:0] w_attackers;
    wire [63:0] b_attackers;
    genvar ci;
    generate
        for (ci=0; ci<64; ci=ci+1) begin : gen_check
            move_validator chk_w (
                .from_sq      (ci[5:0]),
                .to_sq        (wk_sq),
                .board_flat   (board_flat),
                .player_color (B),
                .attack_mode  (1'b1),
                .is_legal     (w_attackers[ci])
            );
            move_validator chk_b (
                .from_sq      (ci[5:0]),
                .to_sq        (bk_sq),
                .board_flat   (board_flat),
                .player_color (W),
                .attack_mode  (1'b1),
                .is_legal     (b_attackers[ci])
            );
        end
    endgenerate

    assign w_in_check = |w_attackers;
    assign b_in_check = |b_attackers;

    // ============================================================
    // CHECKMATE DETECTOR (4096 parallel)
    // wlegal[from][to] = white can make that move
    // blegal[from][to] = black can make that move
    // If checked side has zero legal moves -> checkmate
    // ============================================================
    wire [63:0] wlegal [0:63];
    wire [63:0] blegal [0:63];

    genvar mi, mj;
    generate
        for (mi=0; mi<64; mi=mi+1) begin : cm_from
            for (mj=0; mj<64; mj=mj+1) begin : cm_to
                move_validator cm_w (
                    .from_sq      (mi[5:0]),
                    .to_sq        (mj[5:0]),
                    .board_flat   (board_flat),
                    .player_color (W),
                    .attack_mode  (1'b0),
                    .is_legal     (wlegal[mi][mj])
                );
                move_validator cm_b (
                    .from_sq      (mi[5:0]),
                    .to_sq        (mj[5:0]),
                    .board_flat   (board_flat),
                    .player_color (B),
                    .attack_mode  (1'b0),
                    .is_legal     (blegal[mi][mj])
                );
            end
        end
    endgenerate

    // OR-reduce per from-square, then across all squares
    wire [63:0] w_any_from;
    wire [63:0] b_any_from;
    genvar ri;
    generate
        for (ri=0; ri<64; ri=ri+1) begin : reduce_moves
            assign w_any_from[ri] = |wlegal[ri];
            assign b_any_from[ri] = |blegal[ri];
        end
    endgenerate
    wire w_has_move = |w_any_from;
    wire b_has_move = |b_any_from;

    // ============================================================
    // BOT
    // ============================================================
    wire       bot_done;
    wire [5:0] bot_from, bot_to;
    reg        bot_start;

    chess_bot bot (
        .clk        (clk),
        .reset      (reset),
        .start      (bot_start),
        .board_flat (board_flat),
        .done       (bot_done),
        .from_sq    (bot_from),
        .to_sq      (bot_to)
    );

    // ============================================================
    // STATE MACHINE
    // ============================================================
    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state        <= S_INIT;
            cursor_sq    <= 6'b110_100;  // e2 (row6, col4)
            selected_sq  <= 6'd0;
            sel_active   <= 0;
            player_turn  <= W;
            bot_thinking <= 0;
            bot_start    <= 0;
            cap_w_cnt    <= 0;
            cap_b_cnt    <= 0;
            checkmate    <= 0;
            player_won   <= 0;
            player_lost  <= 0;
            for (i=0; i<15; i=i+1) begin
                cap_w[i] <= 3'd0;
                cap_b[i] <= 3'd0;
            end
        end else begin
            bot_start <= 1'b0;

            case (state)

                // --------------------------------------------------
                S_INIT: begin
                    checkmate   <= 0;
                    player_won  <= 0;
                    player_lost <= 0;
                    cap_w_cnt   <= 0;
                    cap_b_cnt   <= 0;
                    for (i=0; i<15; i=i+1) begin
                        cap_w[i] <= 3'd0;
                        cap_b[i] <= 3'd0;
                    end
                    // Black back rank (row 0, sq 0-7)
                    board[0] <={B,ROOK};   board[1] <={B,KNIGHT}; board[2] <={B,BISHOP};
                    board[3] <={B,QUEEN};  board[4] <={B,KING};   board[5] <={B,BISHOP};
                    board[6] <={B,KNIGHT}; board[7] <={B,ROOK};
                    // Black pawns (row 1, sq 8-15)
                    board[8] <={B,PAWN};   board[9] <={B,PAWN};
                    board[10]<={B,PAWN};   board[11]<={B,PAWN};
                    board[12]<={B,PAWN};   board[13]<={B,PAWN};
                    board[14]<={B,PAWN};   board[15]<={B,PAWN};
                    // Empty rows 2-5 (sq 16-47)
                    board[16]<=4'd0; board[17]<=4'd0; board[18]<=4'd0; board[19]<=4'd0;
                    board[20]<=4'd0; board[21]<=4'd0; board[22]<=4'd0; board[23]<=4'd0;
                    board[24]<=4'd0; board[25]<=4'd0; board[26]<=4'd0; board[27]<=4'd0;
                    board[28]<=4'd0; board[29]<=4'd0; board[30]<=4'd0; board[31]<=4'd0;
                    board[32]<=4'd0; board[33]<=4'd0; board[34]<=4'd0; board[35]<=4'd0;
                    board[36]<=4'd0; board[37]<=4'd0; board[38]<=4'd0; board[39]<=4'd0;
                    board[40]<=4'd0; board[41]<=4'd0; board[42]<=4'd0; board[43]<=4'd0;
                    board[44]<=4'd0; board[45]<=4'd0; board[46]<=4'd0; board[47]<=4'd0;
                    // White pawns (row 6, sq 48-55)
                    board[48]<={W,PAWN};   board[49]<={W,PAWN};
                    board[50]<={W,PAWN};   board[51]<={W,PAWN};
                    board[52]<={W,PAWN};   board[53]<={W,PAWN};
                    board[54]<={W,PAWN};   board[55]<={W,PAWN};
                    // White back rank (row 7, sq 56-63)
                    board[56]<={W,ROOK};   board[57]<={W,KNIGHT}; board[58]<={W,BISHOP};
                    board[59]<={W,QUEEN};  board[60]<={W,KING};   board[61]<={W,BISHOP};
                    board[62]<={W,KNIGHT}; board[63]<={W,ROOK};

                    state <= S_PLAYER;
                end

                // --------------------------------------------------
                S_PLAYER: begin
                    // ---- Checkmate / stalemate check on entry ----
                    // Board is stable here; combinational wires valid
                    if (w_in_check && !w_has_move) begin
                        // White king in check with no escape -> bot wins
                        checkmate   <= 1'b1;
                        player_lost <= 1'b1;
                        state       <= S_GAMEOVER;
                    end else if (b_in_check && !b_has_move) begin
                        // Black king in check with no escape -> player wins
                        checkmate  <= 1'b1;
                        player_won <= 1'b1;
                        state      <= S_GAMEOVER;
                    end else begin
                        // Normal player input
                        sel_active   <= 1'b0;
                        player_turn  <= W;
                        bot_thinking <= 1'b0;

                        if      (key_up    && cursor_sq[5:3]!=3'd0)
                            cursor_sq <= cursor_sq - 6'b001000;
                        else if (key_down  && cursor_sq[5:3]!=3'd7)
                            cursor_sq <= cursor_sq + 6'b001000;
                        else if (key_left  && cursor_sq[2:0]!=3'd0)
                            cursor_sq <= cursor_sq - 6'b000001;
                        else if (key_right && cursor_sq[2:0]!=3'd7)
                            cursor_sq <= cursor_sq + 6'b000001;

                        if (key_select && board[cursor_sq][2:0]!=NONE
                                       && board[cursor_sq][3]==W) begin
                            selected_sq <= cursor_sq;
                            sel_active  <= 1'b1;
                            state       <= S_SELECTED;
                        end
                    end
                end

                // --------------------------------------------------
                S_SELECTED: begin
                    sel_active <= 1'b1;

                    if      (key_up    && cursor_sq[5:3]!=3'd0)
                        cursor_sq <= cursor_sq - 6'b001000;
                    else if (key_down  && cursor_sq[5:3]!=3'd7)
                        cursor_sq <= cursor_sq + 6'b001000;
                    else if (key_left  && cursor_sq[2:0]!=3'd0)
                        cursor_sq <= cursor_sq - 6'b000001;
                    else if (key_right && cursor_sq[2:0]!=3'd7)
                        cursor_sq <= cursor_sq + 6'b000001;

                    if (key_cancel) begin
                        sel_active <= 0;
                        state      <= S_PLAYER;
                    end else if (key_select) begin
                        if (cursor_sq == selected_sq) begin
                            // Deselect
                            sel_active <= 0;
                            state      <= S_PLAYER;
                        end else if (board[cursor_sq][3]==W
                                  && board[cursor_sq][2:0]!=NONE) begin
                            // Switch to another white piece
                            selected_sq <= cursor_sq;
                        end else if (move_ok) begin
                            // Legal move confirmed
                            state <= S_PMOVE;
                        end
                        // else: stay, illegal destination
                    end
                end

                // --------------------------------------------------
                S_PMOVE: begin
                    // Record captured black piece into cap_w[]
                    if (board[cursor_sq][2:0]!=NONE && board[cursor_sq][3]==B) begin
                        if (cap_w_cnt < 15) begin
                            cap_w[cap_w_cnt] <= board[cursor_sq][2:0];
                            cap_w_cnt        <= cap_w_cnt + 4'd1;
                        end
                    end
                    // Execute move
                    board[cursor_sq]   <= board[selected_sq];
                    board[selected_sq] <= 4'd0;
                    // Pawn promotion: white reaches row 0
                    if (board[selected_sq][2:0]==PAWN && cursor_sq[5:3]==3'd0)
                        board[cursor_sq] <= {W, QUEEN};

                    sel_active   <= 1'b0;
                    player_turn  <= B;
                    bot_thinking <= 1'b1;
                    bot_start    <= 1'b1;
                    state        <= S_BTHINK;
                end

                // --------------------------------------------------
                S_BTHINK: begin
                    if (bot_done) state <= S_BMOVE;
                end

                // --------------------------------------------------
                S_BMOVE: begin
                    // Record captured white piece into cap_b[]
                    if (board[bot_to][2:0]!=NONE && board[bot_to][3]==W) begin
                        if (cap_b_cnt < 15) begin
                            cap_b[cap_b_cnt] <= board[bot_to][2:0];
                            cap_b_cnt        <= cap_b_cnt + 4'd1;
                        end
                    end
                    // Execute bot move
                    board[bot_to]   <= board[bot_from];
                    board[bot_from] <= 4'd0;
                    // Pawn promotion: black reaches row 7
                    if (board[bot_from][2:0]==PAWN && bot_to[5:3]==3'd7)
                        board[bot_to] <= {B, QUEEN};

                    bot_thinking <= 1'b0;
                    player_turn  <= W;
                    // Return to S_PLAYER where checkmate is evaluated
                    // with the updated board (1-cycle settle is fine
                    // since check wires are purely combinational and
                    // board regs are updated at this clock edge)
                    state <= S_PLAYER;
                end

                // --------------------------------------------------
                S_GAMEOVER: begin
                    // Freeze. Only reset can restart.
                    sel_active   <= 1'b0;
                    bot_thinking <= 1'b0;
                end

                default: state <= S_INIT;

            endcase
        end
    end
endmodule


