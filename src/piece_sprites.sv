// ========================================================================================================================
// piece_sprites.sv
// ========================================================================================================================

module piece_sprites (
    input  wire [2:0]  piece_type,
    input  wire [6:0]  x_coord,    
    input  wire [6:0]  y_coord,    
    output reg  [1:0]  shade       // 00=Clear, 01=Shadow, 10=Mid, 11=Highlight
);

    // Coordinate system and common math nodes
    localparam CX = 7'd28;
    wire [7:0] lx = (x_coord > CX) ? (x_coord - CX) : (CX - x_coord);
    wire [7:0] ly = (7'd56 > y_coord) ? (7'd56 - y_coord) : 8'd0;
    wire [15:0] lx_sq = {8'd0,lx} * {8'd0,lx};
    wire [15:0] ly_sq = {8'd0,ly} * {8'd0,ly};

    // Global Lighting Condition (Light from Top-Left)
    wire is_left_edge  = (x_coord < CX - 7'd2);
    wire is_right_edge = (x_coord > CX + 7'd2);
    wire is_top_edge   = (y_coord < 7'd20);
    wire is_highlight  = (is_left_edge || (is_top_edge && !is_right_edge));
    wire is_shadow     = (is_right_edge && !is_top_edge);

    // ============================================================
    // CONCURRENT GEOMETRY CALCULATIONS
    // ============================================================
   
    // COMMON BASE
    wire base_flat = (y_coord >= 46 && y_coord <= 50) && (lx <= 14);
    wire base_lip  = (y_coord >= 43 && y_coord < 46) && (lx <= 12);
    wire base_curve= (y_coord >= 38 && y_coord < 43) && (lx_sq < ({8'd0, ly} + 16'd5) * 16'd10);
    wire stem_core = (y_coord >= 22 && y_coord < 38) && (lx <= 6);
    wire collar    = (y_coord >= 20 && y_coord < 22) && (lx <= 9);
    wire in_common_base = base_flat || base_lip || base_curve || stem_core || collar;

    // PAWN
    wire [15:0] pawn_dx = (x_coord > CX) ? (x_coord-CX) : (CX-x_coord);
    wire [15:0] pawn_dy = (y_coord > 7'd14) ? (y_coord-7'd14) : (7'd14-y_coord);
    wire [15:0] pawn_r_sq = (pawn_dx*pawn_dx) + (pawn_dy*pawn_dy);
    wire pawn_head = (pawn_r_sq <= 16'd49); // Radius 7
    wire pawn_spec = (x_coord >= 24 && x_coord <= 26) && (y_coord >= 10 && y_coord <= 12);

    // KNIGHT
    wire k_neck_bk = (x_coord >= 16 && x_coord <= 22) && (y_coord >= 16 && y_coord <= 42);
    wire k_neck_fr = (x_coord > 22 && x_coord <= 34) && (y_coord >= 24 && y_coord <= 42) && ( {3'd0,y_coord} > {1'b0,x_coord} - 10 );
    wire k_snout   = (x_coord >= 26 && x_coord <= 40) && (y_coord >= 16 && y_coord <= 24);
    wire k_ears    = (x_coord >= 18 && x_coord <= 22) && (y_coord >= 8 && y_coord <= 16) && ( {3'd0,y_coord} + {1'b0,x_coord} > 30 );
    wire k_jaw_cut = (x_coord >= 24 && x_coord <= 34) && (y_coord >= 24 && y_coord <= 30) && ( {3'd0,y_coord} + {1'b0,x_coord} > 56 );
    wire k_eye_hl  = (x_coord >= 24 && x_coord <= 26) && (y_coord >= 16 && y_coord <= 18);
    wire k_mane    = (x_coord == 16 || x_coord == 18) && (y_coord[1] == 1'b1) && (y_coord >= 20);
    wire k_body    = (k_neck_bk || k_neck_fr || k_snout || k_ears) && !k_jaw_cut && !k_eye_hl && !k_mane;

    // BISHOP
    wire [15:0] b_dy_val = (y_coord > 7'd16) ? (y_coord-7'd16) : (7'd16-y_coord);
    wire b_head = ((lx_sq * 16'd3) + (b_dy_val * b_dy_val) <= 16'd100);
    wire b_cut  = (y_coord >= 10 && y_coord <= 16) && ({3'd0,y_coord} + {1'b0,x_coord} > 38) && ({3'd0,y_coord} + {1'b0,x_coord} < 42);
    wire b_top  = (lx_sq + (y_coord > 6 ? y_coord-6 : 6-y_coord)**2 <= 16'd9);

    // ROOK
    wire r_stem  = (y_coord >= 18 && y_coord <= 38) && (lx <= 10);
    wire r_flare = (y_coord >= 14 && y_coord < 18) && (lx <= 12);
    wire r_batt  = (y_coord >= 8  && y_coord < 14) && (lx <= 14);
    wire r_gap1  = (y_coord < 12) && (x_coord >= 22 && x_coord <= 25);
    wire r_gap2  = (y_coord < 12) && (x_coord >= 31 && x_coord <= 34);

    // QUEEN
    wire q_col2 = (y_coord >= 18 && y_coord < 20) && (lx <= 12);
    wire q_bowl = (y_coord >= 14 && y_coord < 18) && (lx <= 15);
    wire q_s_mid= (y_coord >= 6 && y_coord < 14) && (lx <= 2);
    wire q_s_L1 = (y_coord >= 8 && y_coord < 14) && (x_coord >= 18 && x_coord <= 22) && ({3'd0,y_coord} - {1'b0,x_coord} < -6);
    wire q_s_R1 = (y_coord >= 8 && y_coord < 14) && (x_coord >= 34 && x_coord <= 38) && ({3'd0,y_coord} + {1'b0,x_coord} > 46);
    wire q_s_L2 = (y_coord >= 10 && y_coord < 14) && (x_coord >= 12 && x_coord <= 16);
    wire q_s_R2 = (y_coord >= 10 && y_coord < 14) && (x_coord >= 40 && x_coord <= 44);
    wire q_jewl = (y_coord==6 && lx<=2) || (y_coord==8 && x_coord==18) || (y_coord==8 && x_coord==38);

    // KING
    wire kg_bowl  = (y_coord >= 14 && y_coord < 20) && (lx_sq * 16'd2 + ({8'd0, y_coord > 17 ? y_coord-17 : 17-y_coord})**2 <= 16'd144);
    wire kg_band  = (y_coord >= 12 && y_coord < 14) && (lx <= 10);
    wire kg_crs_v = (y_coord >= 2 && y_coord < 12) && (lx <= 1);
    wire kg_crs_h = (y_coord >= 4 && y_coord <= 6) && (lx <= 4);

    // ============================================================
    // SHADING MULTIPLEXER
    // ============================================================
    always @(*) begin
        shade = 2'b00; // Default transparent
       
        case (piece_type)
            3'd1: begin // PAWN
                if (in_common_base || pawn_head) begin
                    if (pawn_spec) shade = 2'b11;
                    else if (is_shadow || (y_coord >= 38 && is_right_edge)) shade = 2'b01;
                    else if (is_highlight) shade = 2'b11;
                    else shade = 2'b10;
                end
            end
           
            3'd2: begin // KNIGHT
                if (base_flat || base_lip || base_curve || k_body) begin
                    if (k_eye_hl || k_jaw_cut) shade = 2'b01;
                    else if (x_coord < 22 || (y_coord < 20 && x_coord < 28)) shade = 2'b11;
                    else if (x_coord > 30 || (y_coord > 30 && x_coord > 24)) shade = 2'b01;
                    else shade = 2'b10;
                end
            end
           
            3'd3: begin // BISHOP
                if (in_common_base || (b_head && !b_cut) || b_top) begin
                    if ( (y_coord >= 10 && y_coord <= 16) && ({3'd0,y_coord} + {1'b0,x_coord} == 42) ) shade = 2'b01;
                    else if (is_shadow) shade = 2'b01;
                    else if (is_highlight || b_top) shade = 2'b11;
                    else shade = 2'b10;
                end
            end
           
            3'd4: begin // ROOK
                if (base_flat || base_lip || base_curve || r_stem || r_flare || (r_batt && !r_gap1 && !r_gap2)) begin
                    if ((x_coord == 21 && y_coord < 12) || (x_coord == 30 && y_coord < 12)) shade = 2'b01;
                    else if ((x_coord == 26 && y_coord < 12) || (x_coord == 35 && y_coord < 12)) shade = 2'b11;
                    else if (is_shadow) shade = 2'b01;
                    else if (is_highlight) shade = 2'b11;
                    else shade = 2'b10;
                end
            end
           
            3'd5: begin // QUEEN
                if (in_common_base || q_col2 || q_bowl || q_s_mid || q_s_L1 || q_s_R1 || q_s_L2 || q_s_R2) begin
                    if (q_jewl) shade = 2'b11;
                    else if (is_shadow || (y_coord >= 14 && y_coord < 18 && is_right_edge)) shade = 2'b01;
                    else if (is_highlight || q_s_L1 || q_s_L2) shade = 2'b11;
                    else shade = 2'b10;
                end
            end
           
            3'd6: begin // KING
                if (in_common_base || kg_bowl || kg_band || kg_crs_v || kg_crs_h) begin
                    if (kg_crs_v || kg_crs_h) begin
                        if (x_coord < CX) shade = 2'b11; else shade = 2'b10;
                    end
                    else if (is_shadow || (y_coord >= 14 && y_coord < 20 && x_coord > CX + 5)) shade = 2'b01;
                    else if (is_highlight || (y_coord >= 14 && y_coord < 20 && x_coord < CX - 5)) shade = 2'b11;
                    else shade = 2'b10;
                end
            end
           
            default: shade = 2'b00;
        endcase
    end
endmodule


