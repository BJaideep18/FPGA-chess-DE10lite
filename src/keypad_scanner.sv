// ========================================================================================================================
// keypad_scanner.sv (Optimized Debounce Matrix Fix)
// ========================================================================================================================

module keypad_scanner (
    input  wire       clk,        // 24.4 kHz game clock
    input  wire       reset,
    output reg  [3:0] row_drive,  // Drive one row LOW at a time
    input  wire [2:0] col_read,   // Read columns (LOW = pressed)
    output reg        key_up,
    output reg        key_down,
    output reg        key_left,
    output reg        key_right,
    output reg        key_select,
    output reg        key_cancel
);

    reg [1:0] scan_row;
    reg [2:0] scan_cnt;
   
    // 2-stage sync to prevent metastability
    reg [2:0] col_s1, col_s2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            col_s1 <= 3'b111;
            col_s2 <= 3'b111;
        end else begin
            col_s1 <= col_read;
            col_s2 <= col_s1;
        end
    end

    // Cycle through rows 0->1->2->3->0...
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            scan_row <= 2'd0;
            scan_cnt <= 3'd0;
        end else begin
            if (scan_cnt == 3'd7) begin
                scan_cnt <= 3'd0;
                scan_row <= scan_row + 2'd1;
            end else begin
                scan_cnt <= scan_cnt + 3'd1;
            end
        end
    end

    // Drive the selected row LOW
    always @(*) begin
        case (scan_row)
            2'd0: row_drive = 4'b1110;
            2'd1: row_drive = 4'b1101;
            2'd2: row_drive = 4'b1011;
            2'd3: row_drive = 4'b0111;
            default: row_drive = 4'b1111;
        endcase
    end

    // ============================================================
    //  DEBOUNCE LOGIC
    // ============================================================
    reg [7:0] release_timer;
    reg       is_pressed;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            release_timer <= 8'd0;
            is_pressed    <= 1'b0;
            key_up        <= 1'b0;
            key_down      <= 1'b0;
            key_left      <= 1'b0;
            key_right     <= 1'b0;
            key_select    <= 1'b0;
            key_cancel    <= 1'b0;
        end else begin
            // 1. Always default the output signals to 0 to ensure single-cycle pulses
            key_up     <= 1'b0;
            key_down   <= 1'b0;
            key_left   <= 1'b0;
            key_right  <= 1'b0;
            key_select <= 1'b0;
            key_cancel <= 1'b0;

            // 2. Read the columns only when the row drive has settled (scan_cnt == 6)
            if (scan_cnt == 3'd6) begin
               
                // If any column is LOW, a key on the CURRENT row is being pressed
                if (!col_s2[0] || !col_s2[1] || !col_s2[2]) begin
                   
                    release_timer <= 8'd0; // Reset the release timer immediately
                   
                    // Trigger the pulse ONLY if we aren't already holding a key down
                    if (!is_pressed) begin
                        is_pressed <= 1'b1;

                        // Decode the exact key and fire the correct pulse
                        if (!col_s2[0]) begin // Left column
                            if (scan_row == 2'd1) key_left <= 1'b1;  // '4'
                        end
                        else if (!col_s2[1]) begin // Middle column
                            if      (scan_row == 2'd0) key_up     <= 1'b1; // '2'
                            else if (scan_row == 2'd1) key_select <= 1'b1; // '5'
                            else if (scan_row == 2'd2) key_down   <= 1'b1; // '8'
                            else if (scan_row == 2'd3) key_cancel <= 1'b1; // '0'
                        end
                        else if (!col_s2[2]) begin // Right column
                            if (scan_row == 2'd1) key_right <= 1'b1; // '6'
                        end
                    end
                end else begin
                    // No key detected on THIS row...
                    // Wait for 100 consecutive empty reads (~32ms) across ALL rows to confirm you let go.
                    if (release_timer < 8'd100) begin
                        release_timer <= release_timer + 8'd1;
                    end else begin
                        is_pressed <= 1'b0; // Key has been completely released and debounced
                    end
                end
            end
        end
    end

endmodule


