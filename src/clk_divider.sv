// ========================================================================================================================
// clk_divider.sv  -
// 50 MHz -> 25 MHz (VGA pixel clock)
// ========================================================================================================================
module clk_divider (
    input  wire clk_50m,
    input  wire reset,
    output wire clk_25m,
    output wire clk_game
);
    reg [26:0] cnt;
    always @(posedge clk_50m or posedge reset) begin
        if (reset) cnt <= 27'd0;
        else       cnt <= cnt + 27'd1;
    end
   
    // cnt[0] divides by 2  = 25 MHz
    // cnt[11] divides by 4096 = ~12.2 kHz (Good enough for game/keypad logic)
   
    assign clk_25m  = cnt[0];   // <--- THIS WAS THE BUG! Changed from 1 to 0.
    assign clk_game = cnt[11];
endmodule



