// ========================================================================================================================
// move_validator.sv  - Chess move legality checker
// ========================================================================================================================
module move_validator (
    input  wire [5:0]   from_sq,
    input  wire [5:0]   to_sq,
    input  wire [255:0] board_flat,
    input  wire         player_color,
    input  wire         attack_mode,   // 1 = check-detection (pawn attacks empty sq)
    output reg          is_legal
);
    // ---- row / col ----
    wire [2:0] fr = from_sq[5:3];  wire [2:0] fc = from_sq[2:0];
    wire [2:0] tr = to_sq[5:3];    wire [2:0] tc = to_sq[2:0];

    // ---- pieces ----
    wire [3:0] fp = board_flat[from_sq*4 +: 4];
    wire [3:0] tp = board_flat[to_sq*4   +: 4];
    wire [2:0] ftype = fp[2:0];  wire fcol = fp[3];
    wire [2:0] ttype = tp[2:0];  wire tcol = tp[3];

    // ---- distances ----
    wire [2:0] vd = (tr >= fr) ? (tr - fr) : (fr - tr);
    wire [2:0] hd = (tc >= fc) ? (tc - fc) : (fc - tc);

    // ---- signed deltas ----
    wire signed [3:0] rdiff = $signed({1'b0,tr}) - $signed({1'b0,fr});
    wire signed [3:0] cdiff = $signed({1'b0,tc}) - $signed({1'b0,fc});

    wire dest_empty = (ttype == 3'd0);
    wire dest_opp   = (ttype != 3'd0) && (tcol != player_color);
    wire dest_own   = (ttype != 3'd0) && (tcol == player_color);
    wire can_land   = dest_empty | dest_opp;

    // ============================================================
    // HORIZONTAL PATH CLEAR
    // Check squares strictly between fc and tc on row fr
    // Skip square c if it is outside (fc, tc) exclusive range
    // ============================================================
    wire [2:0] hlo = (fc < tc) ? fc : tc;   // smaller col
    wire [2:0] hhi = (fc < tc) ? tc : fc;   // larger col

    // Square at col C is a blocker only if hlo < C < hhi
    wire h1ok = (3'd1 <= hlo || 3'd1 >= hhi) ? 1'b1 : (board_flat[{fr,3'd1}*4+:3]==3'd0);
    wire h2ok = (3'd2 <= hlo || 3'd2 >= hhi) ? 1'b1 : (board_flat[{fr,3'd2}*4+:3]==3'd0);
    wire h3ok = (3'd3 <= hlo || 3'd3 >= hhi) ? 1'b1 : (board_flat[{fr,3'd3}*4+:3]==3'd0);
    wire h4ok = (3'd4 <= hlo || 3'd4 >= hhi) ? 1'b1 : (board_flat[{fr,3'd4}*4+:3]==3'd0);
    wire h5ok = (3'd5 <= hlo || 3'd5 >= hhi) ? 1'b1 : (board_flat[{fr,3'd5}*4+:3]==3'd0);
    wire h6ok = (3'd6 <= hlo || 3'd6 >= hhi) ? 1'b1 : (board_flat[{fr,3'd6}*4+:3]==3'd0);
    wire horiz_clear = h1ok & h2ok & h3ok & h4ok & h5ok & h6ok;

    // ============================================================
    // VERTICAL PATH CLEAR
    // Check squares strictly between fr and tr on col fc
    // ============================================================
    wire [2:0] vlo = (fr < tr) ? fr : tr;
    wire [2:0] vhi = (fr < tr) ? tr : fr;

    wire v1ok = (3'd1 <= vlo || 3'd1 >= vhi) ? 1'b1 : (board_flat[{3'd1,fc}*4+:3]==3'd0);
    wire v2ok = (3'd2 <= vlo || 3'd2 >= vhi) ? 1'b1 : (board_flat[{3'd2,fc}*4+:3]==3'd0);
    wire v3ok = (3'd3 <= vlo || 3'd3 >= vhi) ? 1'b1 : (board_flat[{3'd3,fc}*4+:3]==3'd0);
    wire v4ok = (3'd4 <= vlo || 3'd4 >= vhi) ? 1'b1 : (board_flat[{3'd4,fc}*4+:3]==3'd0);
    wire v5ok = (3'd5 <= vlo || 3'd5 >= vhi) ? 1'b1 : (board_flat[{3'd5,fc}*4+:3]==3'd0);
    wire v6ok = (3'd6 <= vlo || 3'd6 >= vhi) ? 1'b1 : (board_flat[{3'd6,fc}*4+:3]==3'd0);
    wire vert_clear = v1ok & v2ok & v3ok & v4ok & v5ok & v6ok;

    // ============================================================
    // DIAGONAL PATH CLEAR
    // ============================================================
    wire [3:0] fr4 = {1'b0, fr};
    wire [3:0] fc4 = {1'b0, fc};
    wire [3:0] tr4 = {1'b0, tr};
    wire [3:0] tc4 = {1'b0, tc};

    // Step direction (+1 or -1 in 4-bit signed)
    wire [3:0] rstep = (tr4 >= fr4) ? 4'd1 : 4'hF;  // 4'hF = -1 in 2's complement
    wire [3:0] cstep = (tc4 >= fc4) ? 4'd1 : 4'hF;

    // Intermediate square addresses (4-bit row/col, validated)
    wire [3:0] dr1 = fr4 + rstep;
    wire [3:0] dc1 = fc4 + cstep;
    wire [3:0] dr2 = fr4 + (rstep<<1);        // rstep*2
    wire [3:0] dc2 = fc4 + (cstep<<1);
    wire [3:0] dr3 = fr4 + rstep + (rstep<<1);
    wire [3:0] dc3 = fc4 + cstep + (cstep<<1);
    wire [3:0] dr4 = fr4 + (rstep<<2);
    wire [3:0] dc4 = fc4 + (cstep<<2);
    wire [3:0] dr5 = fr4 + rstep + (rstep<<2);
    wire [3:0] dc5 = fc4 + cstep + (cstep<<2);
    wire [3:0] dr6 = fr4 + (rstep<<1) + (rstep<<2);
    wire [3:0] dc6 = fc4 + (cstep<<1) + (cstep<<2);

    // Valid only if row and col are in [0,7] (no wraparound)
    wire dv1 = (dr1 <= 4'd7) && (dc1 <= 4'd7);
    wire dv2 = (dr2 <= 4'd7) && (dc2 <= 4'd7);
    wire dv3 = (dr3 <= 4'd7) && (dc3 <= 4'd7);
    wire dv4 = (dr4 <= 4'd7) && (dc4 <= 4'd7);
    wire dv5 = (dr5 <= 4'd7) && (dc5 <= 4'd7);
    wire dv6 = (dr6 <= 4'd7) && (dc6 <= 4'd7);

    // Gate: only check square N if vd > N (i.e. it's an intermediate)
    // and the coordinate is valid (no underflow/overflow)
    wire dd1ok = (vd > 3'd1) ? (!dv1 ? 1'b0 : (board_flat[{dr1[2:0],dc1[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire dd2ok = (vd > 3'd2) ? (!dv2 ? 1'b0 : (board_flat[{dr2[2:0],dc2[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire dd3ok = (vd > 3'd3) ? (!dv3 ? 1'b0 : (board_flat[{dr3[2:0],dc3[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire dd4ok = (vd > 3'd4) ? (!dv4 ? 1'b0 : (board_flat[{dr4[2:0],dc4[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire dd5ok = (vd > 3'd5) ? (!dv5 ? 1'b0 : (board_flat[{dr5[2:0],dc5[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire dd6ok = (vd > 3'd6) ? (!dv6 ? 1'b0 : (board_flat[{dr6[2:0],dc6[2:0]}*4+:3]==3'd0)) : 1'b1;
    wire diag_clear = dd1ok & dd2ok & dd3ok & dd4ok & dd5ok & dd6ok;

    // ============================================================
    // MOVE LEGALITY
    // attack_mode=1: pawn threat covers diagonal regardless of
    //                dest content (for check detection)
    // ============================================================
    always @(*) begin
        is_legal = 1'b0;
        if (from_sq == to_sq)    is_legal = 1'b0;
        else if (ftype == 3'd0)  is_legal = 1'b0;
        else if (fcol != player_color) is_legal = 1'b0;
        else if (dest_own)       is_legal = 1'b0;  // can never take own piece
        else case (ftype)

            3'd1: begin // PAWN
                if (player_color == 1'b0) begin
                    // White moves up: rdiff must be negative
                    if (hd==0 && rdiff==-1 && dest_empty)
                        is_legal = 1'b1;
                    else if (hd==0 && rdiff==-2 && fr==3'd6 && dest_empty
                             && board_flat[{3'd5,fc}*4+:3]==3'd0)
                        is_legal = 1'b1;
                    // Capture: diagonal 1 step, opponent present
                    // In attack_mode also cover empty squares (check detection)
                    else if (hd==1 && rdiff==-1 && (dest_opp || attack_mode))
                        is_legal = 1'b1;
                end else begin
                    // Black moves down: rdiff must be positive
                    if (hd==0 && rdiff==1 && dest_empty)
                        is_legal = 1'b1;
                    else if (hd==0 && rdiff==2 && fr==3'd1 && dest_empty
                             && board_flat[{3'd2,fc}*4+:3]==3'd0)
                        is_legal = 1'b1;
                    else if (hd==1 && rdiff==1 && (dest_opp || attack_mode))
                        is_legal = 1'b1;
                end
            end

            3'd2: begin // KNIGHT (jumps, no path check)
                if ((hd==3'd2 && vd==3'd1) || (hd==3'd1 && vd==3'd2))
                    is_legal = 1'b1;
            end

            3'd3: begin // BISHOP
                if (hd==vd && hd>0 && diag_clear)
                    is_legal = 1'b1;
            end

            3'd4: begin // ROOK
                if      (hd==0 && vd>0 && vert_clear)   is_legal = 1'b1;
                else if (vd==0 && hd>0 && horiz_clear)  is_legal = 1'b1;
            end

            3'd5: begin // QUEEN
                if      (hd==0 && vd>0 && vert_clear)   is_legal = 1'b1;
                else if (vd==0 && hd>0 && horiz_clear)  is_legal = 1'b1;
                else if (hd==vd && hd>0 && diag_clear)  is_legal = 1'b1;
            end

            3'd6: begin // KING (1 step any direction)
                if (hd<=1 && vd<=1 && (hd+vd)>0)
                    is_legal = 1'b1;
            end

            default: is_legal = 1'b0;
        endcase
    end
endmodule 


