module axi4lite_slave (
    input  wire        ACLK,
    input  wire        ARESETn,
    // canal AW
    input  wire [7:0]  AWADDR,
    input  wire        AWVALID,
    output reg         AWREADY,
    // canal W
    input  wire [31:0] WDATA,
    input  wire [3:0]  WSTRB,
    input  wire        WVALID,
    output reg         WREADY,
    // canal B
    output reg  [1:0]  BRESP,
    output reg         BVALID,
    input  wire        BREADY,
    // canal AR
    input  wire [7:0]  ARADDR,
    input  wire        ARVALID,
    output reg         ARREADY,
    // canal R
    output reg  [31:0] RDATA,
    output reg  [1:0]  RRESP,
    output reg         RVALID,
    input  wire        RREADY,
    // valeur lue a l'adresse 0x04
    input  wire [31:0] status_in
);
    localparam OKAY = 2'b00, SLVERR = 2'b10;

    reg [31:0] reg0, reg2, reg3;   // CTRL, DATA0, DATA1

    // ecrit seulement les octets autorises par WSTRB
    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] strb);
        begin
            merge[7:0]   = strb[0] ? nw[7:0]   : old[7:0];
            merge[15:8]  = strb[1] ? nw[15:8]  : old[15:8];
            merge[23:16] = strb[2] ? nw[23:16] : old[23:16];
            merge[31:24] = strb[3] ? nw[31:24] : old[31:24];
        end
    endfunction

    // ---------------- ecriture ----------------
    localparam IDLE = 2'd0, WRITE = 2'd1, RESP = 2'd2;
    reg [1:0] wstate;

    always @(posedge ACLK) begin
        if (!ARESETn) begin
            wstate <= IDLE; AWREADY <= 1'b0; WREADY <= 1'b0;
            BVALID <= 1'b0; BRESP <= OKAY;
            reg0 <= 32'd0; reg2 <= 32'd0; reg3 <= 32'd0;
        end else begin
            case (wstate)
                IDLE: if (AWVALID && WVALID) begin
                          AWREADY <= 1'b1; WREADY <= 1'b1; wstate <= WRITE;
                      end
                WRITE: begin
                          AWREADY <= 1'b0; WREADY <= 1'b0;
                          BRESP   <= OKAY;
                          case (AWADDR)
                              8'h00: reg0 <= merge(reg0, WDATA, WSTRB);
                              8'h04: ;                                  // STATUS en lecture seule : ignore
                              8'h08: reg2 <= merge(reg2, WDATA, WSTRB);
                              8'h0C: reg3 <= merge(reg3, WDATA, WSTRB);
                              default: BRESP <= SLVERR;                 // adresse invalide
                          endcase
                          BVALID <= 1'b1; wstate <= RESP;
                      end
                RESP: if (BREADY) begin
                          BVALID <= 1'b0; wstate <= IDLE;
                      end
                default: wstate <= IDLE;
            endcase
        end
    end

    // ---------------- lecture ----------------
    localparam RIDLE = 2'd0, RREAD = 2'd1, RWAIT = 2'd2;
    reg [1:0] rstate;

    always @(posedge ACLK) begin
        if (!ARESETn) begin
            rstate <= RIDLE; ARREADY <= 1'b0;
            RVALID <= 1'b0; RDATA <= 32'd0; RRESP <= OKAY;
        end else begin
            case (rstate)
                RIDLE: if (ARVALID) begin
                           ARREADY <= 1'b1; rstate <= RREAD;
                       end
                RREAD: begin
                           ARREADY <= 1'b0;
                           RRESP   <= OKAY;
                           case (ARADDR)
                               8'h00: RDATA <= reg0;
                               8'h04: RDATA <= status_in;
                               8'h08: RDATA <= reg2;
                               8'h0C: RDATA <= reg3;
                               default: begin RDATA <= 32'd0; RRESP <= SLVERR; end
                           endcase
                           RVALID <= 1'b1; rstate <= RWAIT;
                       end
                RWAIT: if (RREADY) begin
                           RVALID <= 1'b0; rstate <= RIDLE;
                       end
                default: rstate <= RIDLE;
            endcase
        end
    end
endmodule
