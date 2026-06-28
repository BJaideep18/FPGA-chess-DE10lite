// ========================================================================================================================
// display_engine.sv  - VGA board renderer
// VGA Layout (640x480):
//   Board:        x=96..543,  y=16..463  (448x448, 8x8 @ 56px each)
//   Left panel:   x=0..95     (dead pieces + name labels)
//   Right panel:  x=544..639  (dead pieces + player labels)
//   Top margin:   y=0..15
//   Bottom margin:y=464..479
// ========================================================================================================================

module display_engine (
    input  wire        clk_25m, reset,
    input  wire [9:0]  pixel_x, pixel_y,
    input  wire        active,
    input  wire [255:0] board_flat,
    input  wire [44:0] cap_w_flat, cap_b_flat,
    input  wire [5:0]  cursor_sq, selected_sq,
    input  wire        sel_active, player_turn, bot_thinking,
    input  wire [63:0] valid_moves,
    input  wire        w_in_check, b_in_check, checkmate,
    input  wire [5:0]  w_king_sq, b_king_sq,
    // player_won=1 means human (white) won; player_lost=1 means bot won
    input  wire        player_won, player_lost,
    output reg  [3:0]  vga_r, vga_g, vga_b
);

    wire [2:0] cap_w [0:14]; wire [2:0] cap_b [0:14];
    genvar gi; generate
        for(gi=0; gi<15; gi=gi+1) begin : unflat
            assign cap_w[gi] = cap_w_flat[gi*3+:3];
            assign cap_b[gi] = cap_b_flat[gi*3+:3];
        end
    endgenerate

    // ============================================================
    // COMPLETE 5x7 MINI FONT ROM
    // Each character = 35 bits (7 rows x 5 cols), MSB = top-left
    // ============================================================
    function [34:0] get_char(input [7:0] ch);
        case(ch)
            "A": get_char = 35'b01110_10001_10001_11111_10001_10001_10001;
            "B": get_char = 35'b11110_10001_10001_11110_10001_10001_11110;
            "C": get_char = 35'b01110_10001_10000_10000_10000_10001_01110;
            "D": get_char = 35'b11100_10010_10001_10001_10001_10010_11100;
            "E": get_char = 35'b11111_10000_10000_11110_10000_10000_11111;
            "F": get_char = 35'b11111_10000_10000_11110_10000_10000_10000;
            "G": get_char = 35'b01110_10001_10000_10111_10001_10001_01111;
            "H": get_char = 35'b10001_10001_10001_11111_10001_10001_10001;
            "I": get_char = 35'b01110_00100_00100_00100_00100_00100_01110;
            "J": get_char = 35'b00111_00010_00010_00010_00010_10010_01100;
            "K": get_char = 35'b10001_10010_10100_11000_10100_10010_10001;
            "L": get_char = 35'b10000_10000_10000_10000_10000_10000_11111;
            "M": get_char = 35'b10001_11011_10101_10001_10001_10001_10001;
            "N": get_char = 35'b10001_11001_10101_10011_10001_10001_10001;
            "O": get_char = 35'b01110_10001_10001_10001_10001_10001_01110;
            "P": get_char = 35'b11110_10001_10001_11110_10000_10000_10000;
            "Q": get_char = 35'b01110_10001_10001_10001_10101_10010_01101;
            "R": get_char = 35'b11110_10001_10001_11110_10100_10010_10001;
            "S": get_char = 35'b01110_10001_10000_01110_00001_10001_01110;
            "T": get_char = 35'b11111_00100_00100_00100_00100_00100_00100;
            "U": get_char = 35'b10001_10001_10001_10001_10001_10001_01110;
            "V": get_char = 35'b10001_10001_10001_10001_10001_01010_00100;
            "W": get_char = 35'b10001_10001_10001_10101_10101_11011_10001;
            "X": get_char = 35'b10001_10001_01010_00100_01010_10001_10001;
            "Y": get_char = 35'b10001_10001_01010_00100_00100_00100_00100;
            "Z": get_char = 35'b11111_00001_00010_00100_01000_10000_11111;
            "0": get_char = 35'b01110_10001_10011_10101_11001_10001_01110;
            "1": get_char = 35'b00100_01100_00100_00100_00100_00100_01110;
            "2": get_char = 35'b01110_10001_00001_00110_01000_10000_11111;
            "3": get_char = 35'b11110_00001_00001_01110_00001_00001_11110;
            "4": get_char = 35'b00010_00110_01010_10010_11111_00010_00010;
            "5": get_char = 35'b11111_10000_10000_11110_00001_00001_11110;
            "6": get_char = 35'b01110_10000_10000_11110_10001_10001_01110;
            "7": get_char = 35'b11111_00001_00010_00100_01000_01000_01000;
            "8": get_char = 35'b01110_10001_10001_01110_10001_10001_01110;
            "9": get_char = 35'b01110_10001_10001_01111_00001_00001_01110;
            "!": get_char = 35'b00100_00100_00100_00100_00100_00000_00100;
            " ": get_char = 35'd0;
            default: get_char = 35'd0;
        endcase
    endfunction

    // ============================================================
    // TEXT RENDERING  (2x scaled: each char cell = 12w x 16h px)
    // Helper: pixel (px,py) inside a char at screen origin (ox,oy)?
    // char width=10, height=14 at 2x scale; stride=12 (2px gap)
    // ============================================================

    // We render multiple text "fields" independently and OR them.
    // Each field is defined by: start_x, start_y, string content.
    // We use a task-style approach with individual char checks.

    // Screen coords
    wire [9:0] px = pixel_x;
    wire [9:0] py = pixel_y;

    function is_char_pixel;
        input [9:0] sx, sy;       // string origin
        input [4:0] ci;           // char index in string
        input [7:0] ch;           // ASCII character
        input [9:0] cpx, cpy;     // current pixel
        reg [9:0] lx, ly;
        reg [2:0] fx, fy;
        reg [34:0] bmp;
        begin
            lx = cpx - (sx + ci*12);
            ly = cpy - sy;
            fx = lx[3:1];   // divide by 2 -> col 0..4
            fy = ly[3:1];   // divide by 2 -> row 0..6
            bmp = get_char(ch);
            if (lx < 10 && ly < 14 && fx < 5 && fy < 7)
                is_char_pixel = bmp[(6-fy)*5 + (4-fx)];
            else
                is_char_pixel = 1'b0;
        end
    endfunction

    // ============================================================
    // LAYOUT CONSTANTS
    // Board: x=[96,543]  y=[16,463]
    // Left panel  x=[0,95],   use x=[2,94]
    // Right panel x=[544,639],use x=[546,638]
    // ============================================================

    // --- LEFT SIDE TEXT POSITIONS (outside board, left panel) ---
    // Name line 1: "BASINENI"  -> 8 chars, cell=12 -> 96px, fits at x=2
    // Name line 2: "JAIDEEP"   -> 7 chars
    // Reg line:    "127004040" -> 9 chars
    // Place them ABOVE board area but we have only 15px at top -> not enough.
    // So: use LEFT panel (x<96), stacked vertically centered in y=[16,463]
    //   Row 0 (y=20):  "BASINENI"
    //   Row 1 (y=38):  "JAIDEEP"
    //   Row 2 (y=56):  "127004040"  (yellow)
    // Each row height=14px, gap=4px -> 18px per row.
    // Dead pieces start at y=80 on left.

    localparam [9:0] NX = 10'd2;   // left text start x
    localparam [9:0] NY0 = 10'd20; // BASINENI y
    localparam [9:0] NY1 = 10'd38; // JAIDEEP  y
    localparam [9:0] NY2 = 10'd56; // Reg no   y

    // --- RIGHT SIDE TEXT POSITIONS ---
    // Right panel x=544..639 (96px wide)
    // "COMPUTER"  8 chars * 12 = 96px -> x=544, y=20  (top, near board top)
    // "PLAYER"    6 chars * 12 = 72px -> x=544, y=450 (bottom, near board bottom)
    // Status line (CHECK/MATE/WIN/LOSE) centered -> x=544, y=232 (midpoint)

    localparam [9:0] RX  = 10'd546;  // right text start x
    localparam [9:0] RY_COMP   = 10'd20;  // COMPUTER y (top-right)
    localparam [9:0] RY_PLAYER = 10'd450; // PLAYER y   (bottom-right)
    localparam [9:0] RY_STATUS = 10'd228; // status message y (mid-right)
    localparam [9:0] RY_STATUS2= 10'd248; // second status line

    // ============================================================
    // TEXT PIXEL DETECTION
    // ============================================================
    reg        is_text;
    reg [11:0] txt_color;

    always @(*) begin
        is_text   = 1'b0;
        txt_color = 12'hFFF;

        // ---- LEFT: "BASINENI" ----
        if (py >= NY0 && py < NY0+14 && px >= NX && px < NX+96) begin
            if      (is_char_pixel(NX,NY0,0,"B",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,1,"A",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,2,"S",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,3,"I",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,4,"N",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,5,"E",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,6,"N",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY0,7,"I",px,py)) begin is_text=1; txt_color=12'hFFF; end
        end

        // ---- LEFT: "JAIDEEP" ----
        if (py >= NY1 && py < NY1+14 && px >= NX && px < NX+84) begin
            if      (is_char_pixel(NX,NY1,0,"J",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,1,"A",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,2,"I",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,3,"D",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,4,"E",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,5,"E",px,py)) begin is_text=1; txt_color=12'hFFF; end
            else if (is_char_pixel(NX,NY1,6,"P",px,py)) begin is_text=1; txt_color=12'hFFF; end
        end

        // ---- LEFT: "127004040" (yellow) ----
        if (py >= NY2 && py < NY2+14 && px >= NX && px < NX+108) begin
            txt_color = 12'hFD0;
            if      (is_char_pixel(NX,NY2,0,"1",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,1,"2",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,2,"7",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,3,"0",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,4,"0",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,5,"4",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,6,"0",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,7,"4",px,py)) is_text=1;
            else if (is_char_pixel(NX,NY2,8,"0",px,py)) is_text=1;
            else txt_color = 12'hFFF; // reset if no match (won't matter)
        end

        // ---- RIGHT: "COMPUTER" (red, top) ----
        if (py >= RY_COMP && py < RY_COMP+14 && px >= RX && px < RX+96) begin
            if      (is_char_pixel(RX,RY_COMP,0,"C",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,1,"O",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,2,"M",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,3,"P",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,4,"U",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,5,"T",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,6,"E",px,py)) begin is_text=1; txt_color=12'hF55; end
            else if (is_char_pixel(RX,RY_COMP,7,"R",px,py)) begin is_text=1; txt_color=12'hF55; end
        end

        // ---- RIGHT: "PLAYER" (green, bottom) ----
        if (py >= RY_PLAYER && py < RY_PLAYER+14 && px >= RX && px < RX+72) begin
            if      (is_char_pixel(RX,RY_PLAYER,0,"P",px,py)) begin is_text=1; txt_color=12'h0F5; end
            else if (is_char_pixel(RX,RY_PLAYER,1,"L",px,py)) begin is_text=1; txt_color=12'h0F5; end
            else if (is_char_pixel(RX,RY_PLAYER,2,"A",px,py)) begin is_text=1; txt_color=12'h0F5; end
            else if (is_char_pixel(RX,RY_PLAYER,3,"Y",px,py)) begin is_text=1; txt_color=12'h0F5; end
            else if (is_char_pixel(RX,RY_PLAYER,4,"E",px,py)) begin is_text=1; txt_color=12'h0F5; end
            else if (is_char_pixel(RX,RY_PLAYER,5,"R",px,py)) begin is_text=1; txt_color=12'h0F5; end
        end

        // ---- RIGHT STATUS (mid-right, priority order) ----
        // "YOU ARE"   line 1
        // "WINNER!"   line 2  (gold)   -- player won
        // OR
        // "BETTER"    line 1
        // "LUCK NEXT" line 2
        // "TIME"      line 3  (orange) -- player lost
        // OR
        // "CHECK"     (red blink)
        // OR
        // "CHECKMATE" (red, two lines)

        if (player_won) begin
            // Line 1: "YOU ARE" at RY_STATUS
            if (py >= RY_STATUS && py < RY_STATUS+14) begin
                if      (is_char_pixel(RX,RY_STATUS,0,"Y",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS,1,"O",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS,2,"U",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS,4,"A",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS,5,"R",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS,6,"E",px,py)) begin is_text=1; txt_color=12'hFF0; end
            end
            // Line 2: "WINNER!" at RY_STATUS2
            if (py >= RY_STATUS2 && py < RY_STATUS2+14) begin
                if      (is_char_pixel(RX,RY_STATUS2,0,"W",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,1,"I",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,2,"N",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,3,"N",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,4,"E",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,5,"R",px,py)) begin is_text=1; txt_color=12'hFF0; end
                else if (is_char_pixel(RX,RY_STATUS2,6,"!",px,py)) begin is_text=1; txt_color=12'hFF0; end
            end
        end
        else if (player_lost) begin
            // Line 1: "BETTER" at RY_STATUS
            if (py >= RY_STATUS && py < RY_STATUS+14) begin
                if      (is_char_pixel(RX,RY_STATUS,0,"B",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS,1,"E",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS,2,"T",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS,3,"T",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS,4,"E",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS,5,"R",px,py)) begin is_text=1; txt_color=12'hF80; end
            end
            // Line 2: "LUCK" at RY_STATUS2
            if (py >= RY_STATUS2 && py < RY_STATUS2+14) begin
                if      (is_char_pixel(RX,RY_STATUS2,0,"L",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS2,1,"U",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS2,2,"C",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS2,3,"K",px,py)) begin is_text=1; txt_color=12'hF80; end
            end
            // Line 3: "NEXT TIME" at RY_STATUS2+18
            if (py >= RY_STATUS2+18 && py < RY_STATUS2+32) begin
                localparam [9:0] RY_STATUS3 = RY_STATUS2 + 10'd18;
                if      (is_char_pixel(RX,RY_STATUS3,0,"N",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,1,"E",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,2,"X",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,3,"T",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,5,"T",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,6,"I",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,7,"M",px,py)) begin is_text=1; txt_color=12'hF80; end
                else if (is_char_pixel(RX,RY_STATUS3,8,"E",px,py)) begin is_text=1; txt_color=12'hF80; end
            end
        end
        else if (checkmate) begin
            // "CHECK" line
            if (py >= RY_STATUS && py < RY_STATUS+14) begin
                if      (is_char_pixel(RX,RY_STATUS,0,"C",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,1,"H",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,2,"E",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,3,"C",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,4,"K",px,py)) begin is_text=1; txt_color=12'hF00; end
            end
            // "MATE" line
            if (py >= RY_STATUS2 && py < RY_STATUS2+14) begin
                if      (is_char_pixel(RX,RY_STATUS2,0,"M",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS2,1,"A",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS2,2,"T",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS2,3,"E",px,py)) begin is_text=1; txt_color=12'hF00; end
            end
        end
        else if (w_in_check || b_in_check) begin
            // "CHECK" blinking handled via blink signal in color output
            if (py >= RY_STATUS && py < RY_STATUS+14) begin
                if      (is_char_pixel(RX,RY_STATUS,0,"C",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,1,"H",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,2,"E",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,3,"C",px,py)) begin is_text=1; txt_color=12'hF00; end
                else if (is_char_pixel(RX,RY_STATUS,4,"K",px,py)) begin is_text=1; txt_color=12'hF00; end
            end
        end
    end

    // ============================================================
    // BOARD AND PIECE LOGIC
    // ============================================================
    wire in_board = (pixel_x>=96 && pixel_x<544 && pixel_y>=16 && pixel_y<464);
    wire [9:0] bx = pixel_x - 10'd96;
    wire [9:0] by = pixel_y - 10'd16;
    reg [2:0] sq_col, sq_row;
    reg [9:0] sq_px, sq_py;

    always @(*) begin
        if      (bx < 56)  begin sq_col=3'd0; sq_px=bx; end
        else if (bx < 112) begin sq_col=3'd1; sq_px=bx-10'd56; end
        else if (bx < 168) begin sq_col=3'd2; sq_px=bx-10'd112; end
        else if (bx < 224) begin sq_col=3'd3; sq_px=bx-10'd168; end
        else if (bx < 280) begin sq_col=3'd4; sq_px=bx-10'd224; end
        else if (bx < 336) begin sq_col=3'd5; sq_px=bx-10'd280; end
        else if (bx < 392) begin sq_col=3'd6; sq_px=bx-10'd336; end
        else               begin sq_col=3'd7; sq_px=bx-10'd392; end
    end
    always @(*) begin
        if      (by < 56)  begin sq_row=3'd0; sq_py=by; end
        else if (by < 112) begin sq_row=3'd1; sq_py=by-10'd56; end
        else if (by < 168) begin sq_row=3'd2; sq_py=by-10'd112; end
        else if (by < 224) begin sq_row=3'd3; sq_py=by-10'd168; end
        else if (by < 280) begin sq_row=3'd4; sq_py=by-10'd224; end
        else if (by < 336) begin sq_row=3'd5; sq_py=by-10'd280; end
        else if (by < 392) begin sq_row=3'd6; sq_py=by-10'd336; end
        else               begin sq_row=3'd7; sq_py=by-10'd392; end
    end

    wire [5:0] sq_addr   = {sq_row, sq_col};
    wire       dark_sq   = sq_row[0] ^ sq_col[0];
    wire [3:0] cur_piece = board_flat[sq_addr*4 +: 4];
    wire [2:0] ptype     = cur_piece[2:0];
    wire       pcolor    = cur_piece[3];
    wire is_valid_dest   = sel_active && valid_moves[sq_addr];
    wire is_check_sq     = (w_in_check && sq_addr==w_king_sq) || (b_in_check && sq_addr==b_king_sq);

    // ============================================================
    //  DEAD PIECES (50% size, 28px sprite, 4px gap = 32px/slot)
    // ============================================================
    wire in_dead_left  = (pixel_x>=12 && pixel_x<44 && pixel_y>=80 && pixel_y<464);
    wire in_dead_right = (pixel_x>=596 && pixel_x<628 && pixel_y>=40 && pixel_y<424);

    wire [4:0] dead_sox = in_dead_left ? (pixel_x-10'd12) : (pixel_x-10'd596);
    wire [9:0] base_y   = in_dead_left ? (pixel_y-10'd80) : (pixel_y-10'd40);

    wire [4:0] dead_idx    = base_y / 32;
    wire [4:0] dead_soy    = base_y % 32;
    wire       is_dead_gap = (dead_soy >= 28) || (dead_sox >= 28);

    reg [2:0] dead_ptype;
    always @(*) begin
        dead_ptype = 3'd0;
        if (dead_idx < 15) begin
            if (in_dead_left)  dead_ptype = cap_w[dead_idx];
            if (in_dead_right) dead_ptype = cap_b[dead_idx];
        end
    end

    wire is_dead_area = (in_dead_left||in_dead_right) && (dead_ptype!=0) && !is_dead_gap;

    wire [6:0] v_x_coord = is_dead_area ? {1'b0,dead_sox,1'b0} : {1'b0,sq_px[5:0]};
    wire [6:0] v_y_coord = is_dead_area ? {1'b0,dead_soy,1'b0} : {1'b0,sq_py[5:0]};
    wire [2:0] req_ptype = is_dead_area ? dead_ptype : ptype;

    wire [1:0] spr_shade;
    piece_sprites shapes (
        .piece_type(req_ptype),
        .x_coord   (v_x_coord),
        .y_coord   (v_y_coord),
        .shade     (spr_shade)
    );

    wire in_border = (sq_px<4 || sq_px>=52 || sq_py<4 || sq_py>=52);
    wire is_cur    = (sq_addr == cursor_sq);
    wire is_sel    = (sq_addr == selected_sq) && sel_active;

    reg [23:0] blink;
    always @(posedge clk_25m or posedge reset)
        if (reset) blink <= 0;
        else       blink <= blink + 24'd1;

    // ============================================================
    //  COLOR MUX
    // ============================================================
    reg [3:0] r, g, b;
    wire check_blink_on = blink[23];

    always @(*) begin
        r=4'h0; g=4'h0; b=4'h0;

        if (!active) begin
            r=4'h0; g=4'h0; b=4'h0;
        end

        // UI Text (highest priority)
        else if (is_text && (!(w_in_check||b_in_check) || !check_blink_on ||
                             !(txt_color==12'hF00))) begin
            // For check text, blink it
            if ((w_in_check||b_in_check) && txt_color==12'hF00 && !check_blink_on) begin
                r=4'h0; g=4'h0; b=4'h0;
            end else begin
                r = txt_color[11:8];
                g = txt_color[7:4];
                b = txt_color[3:0];
            end
        end
        else if (is_text) begin
            r = txt_color[11:8]; g = txt_color[7:4]; b = txt_color[3:0];
        end

        // Dead pieces
        else if (is_dead_area && spr_shade != 2'b00) begin
            if (in_dead_left) begin
                case (spr_shade)
                    2'b01: begin r=4'h0; g=4'h6; b=4'h0; end
                    2'b10: begin r=4'h0; g=4'hC; b=4'h0; end
                    2'b11: begin r=4'h8; g=4'hF; b=4'h8; end
                    default: begin r=4'h0; g=4'h0; b=4'h0; end
                endcase
            end else begin
                case (spr_shade)
                    2'b01: begin r=4'h0; g=4'h0; b=4'h0; end
                    2'b10: begin r=4'h1; g=4'h1; b=4'h4; end
                    2'b11: begin r=4'h5; g=4'h5; b=4'hC; end
                    default: begin r=4'h0; g=4'h0; b=4'h0; end
                endcase
            end
        end

        // Outer background
        else if (!in_board) begin
            r=4'h1; g=4'h2; b=4'h3;
        end

        // Square borders
        else if (in_border) begin
            if      (is_cur && is_sel)          begin r=4'hF;g=4'hA;b=4'h0; end
            else if (is_cur)                    begin r=4'h0;g=4'hF;b=4'h3; end
            else if (is_sel)                    begin r=4'hF;g=4'hC;b=4'h0; end
            else if (is_check_sq&&check_blink_on) begin r=4'hF;g=4'h0;b=4'h0; end
            else if (is_valid_dest)             begin r=4'h4;g=4'hC;b=4'hF; end
            else if (dark_sq)                   begin r=4'h5;g=4'h3;b=4'h1; end
            else                                begin r=4'hC;g=4'hA;b=4'h7; end
        end

        // Pieces on board
        else if (ptype!=3'd0 && spr_shade != 2'b00) begin
            if (!pcolor) begin
                case (spr_shade)
                    2'b01: begin r=4'h0; g=4'h6; b=4'h0; end
                    2'b10: begin r=4'h0; g=4'hC; b=4'h0; end
                    2'b11: begin r=4'h8; g=4'hF; b=4'h8; end
                    default: begin r=4'h0; g=4'h0; b=4'h0; end
                endcase
            end else begin
                case (spr_shade)
                    2'b01: begin r=4'h0; g=4'h0; b=4'h0; end
                    2'b10: begin r=4'h1; g=4'h1; b=4'h4; end
                    2'b11: begin r=4'h5; g=4'h5; b=4'hC; end
                    default: begin r=4'h0; g=4'h0; b=4'h0; end
                endcase
            end
        end

        // Square backgrounds
        else begin
            if (is_check_sq && check_blink_on) begin
                r=4'hF; g=4'h0; b=4'h0;
            end else if (is_valid_dest && sq_px>=26 && sq_px<30 && sq_py>=26 && sq_py<30) begin
                r=4'h4; g=4'hC; b=4'hF;
            end else if (dark_sq) begin
                r=4'h7; g=4'h4; b=4'h2;
            end else begin
                r=4'hE; g=4'hD; b=4'hA;
            end
        end
    end

    always @(posedge clk_25m or posedge reset) begin
        if (reset) begin vga_r<=0; vga_g<=0; vga_b<=0; end
        else       begin vga_r<=r; vga_g<=g; vga_b<=b; end
    end

endmodule


