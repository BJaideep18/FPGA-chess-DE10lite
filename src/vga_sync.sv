// ========================================================================================================================
// vga_sync.sv  - 640x480 @ 60Hz VGA timing generator
// ========================================================================================================================

module vga_sync (
    input  wire        clk_25m,
    input  wire        reset,
    output wire        hsync,
    output wire        vsync,
    output wire [9:0]  pixel_x,
    output wire [9:0]  pixel_y,
    output wire        active
);
    // Standard 640x480 @ 60Hz timing
    localparam H_VIS  = 640; localparam H_FP = 16;
    localparam H_SYNC =  96; localparam H_BP = 48; localparam H_TOT = 800;
    localparam V_VIS  = 480; localparam V_FP = 10;
    localparam V_SYNC =   2; localparam V_BP = 33; localparam V_TOT = 525;

    reg [9:0] hcnt, vcnt;

    always @(posedge clk_25m or posedge reset) begin
        if (reset) hcnt <= 10'd0;
        else if (hcnt == H_TOT-1) hcnt <= 10'd0;
        else hcnt <= hcnt + 10'd1;
    end
    always @(posedge clk_25m or posedge reset) begin
        if (reset) vcnt <= 10'd0;
        else if (hcnt == H_TOT-1) begin
            if (vcnt == V_TOT-1) vcnt <= 10'd0;
            else vcnt <= vcnt + 10'd1;
        end
    end

    assign hsync   = ~(hcnt >= H_VIS+H_FP && hcnt < H_VIS+H_FP+H_SYNC);
    assign vsync   = ~(vcnt >= V_VIS+V_FP && vcnt < V_VIS+V_FP+V_SYNC);
    assign pixel_x = hcnt;
    assign pixel_y = vcnt;
    assign active  = (hcnt < H_VIS) && (vcnt < V_VIS);
endmodule

