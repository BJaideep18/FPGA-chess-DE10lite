// BASINENI JAIDEEP-127004040, SASTRA UNIVERSITY
// ========================================================================================================================
// chess_top.sv  - TOP LEVEL
// ========================================================================================================================

module chess_top (
    input  wire        CLOCK_50,
    input  wire        KEY0,        
    output wire        VGA_HS, VGA_VS,
    output wire [3:0]  VGA_R, VGA_G, VGA_B,
    output wire [3:0]  GPIO1_ROW,    
    input  wire [2:0]  GPIO1_COL,    
    output wire [9:0]  LEDR
);
    wire reset = ~KEY0;

    wire clk_25m, clk_game;
    clk_divider clk_div (.clk_50m(CLOCK_50), .reset(reset), .clk_25m(clk_25m), .clk_game(clk_game));
   
    wire [9:0] px, py;
    wire       active;
    vga_sync vga (.clk_25m(clk_25m), .reset(reset), .hsync(VGA_HS), .vsync(VGA_VS), .pixel_x(px), .pixel_y(py), .active(active));
   
    wire key_up, key_down, key_left, key_right, key_select, key_cancel;
    keypad_scanner kpad (
        .clk(clk_game), .reset(reset), .row_drive(GPIO1_ROW), .col_read(GPIO1_COL),
        .key_up(key_up), .key_down(key_down), .key_left(key_left), .key_right(key_right),
        .key_select(key_select),.key_cancel(key_cancel)
    );
   
    wire [255:0] board_flat;
    wire [44:0]  cap_w_flat, cap_b_flat;
    wire [5:0]   cursor_sq, selected_sq;
    wire         sel_active, player_turn, bot_thinking;
    wire [2:0]   state_out;
   
    // NEW WIRES
    wire [63:0]  valid_moves;
    wire         w_in_check, b_in_check;
    wire [5:0]   w_king_sq, b_king_sq;
   
    game_logic game (
        .clk(clk_game), .reset(reset),
        .key_up(key_up), .key_down(key_down), .key_left(key_left), .key_right(key_right),
        .key_select(key_select),.key_cancel(key_cancel),
        .board_flat(board_flat), .cap_w_flat(cap_w_flat), .cap_b_flat(cap_b_flat),
        .cursor_sq(cursor_sq),  .selected_sq(selected_sq),
        .sel_active(sel_active), .player_turn(player_turn), .bot_thinking(bot_thinking),
        .state_out(state_out),
        .valid_moves(valid_moves), .w_in_check(w_in_check), .b_in_check(b_in_check),
        .w_king_sq(w_king_sq), .b_king_sq(b_king_sq)
    );
   
    display_engine disp (
        .clk_25m(clk_25m), .reset(reset),
        .pixel_x(px), .pixel_y(py), .active(active),
        .board_flat(board_flat), .cap_w_flat(cap_w_flat), .cap_b_flat(cap_b_flat),
        .cursor_sq(cursor_sq),   .selected_sq(selected_sq),
        .sel_active(sel_active), .player_turn(player_turn), .bot_thinking(bot_thinking),
        .valid_moves(valid_moves), .w_in_check(w_in_check), .b_in_check(b_in_check),
        .w_king_sq(w_king_sq), .b_king_sq(b_king_sq),
        .vga_r(VGA_R), .vga_g(VGA_G), .vga_b(VGA_B)
    );
   
    assign LEDR[2:0] = state_out;
    assign LEDR[3]   = sel_active;
    assign LEDR[4]   = player_turn;
    assign LEDR[9]   = bot_thinking;
    assign LEDR[8:5] = 4'b0;
endmodule

