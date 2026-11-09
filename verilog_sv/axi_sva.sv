// Assertions SVA de protocole AXI4-Lite pour axi4lite_slave
// Un module de surveillance : il observe les signaux, il ne pilote rien.
// A brancher en parallele du circuit (voir top dans testbench.sv).
module axi_sva (
    input logic        ACLK, ARESETn,
    input logic [7:0]  AWADDR,  input logic AWVALID, AWREADY,
    input logic [31:0] WDATA,   input logic [3:0] WSTRB, input logic WVALID, WREADY,
    input logic [1:0]  BRESP,   input logic BVALID, BREADY,
    input logic [7:0]  ARADDR,  input logic ARVALID, ARREADY,
    input logic [31:0] RDATA,   input logic [1:0] RRESP, input logic RVALID, RREADY
);
    int unsigned violations;                                                     // nombre total de regles violees
    int unsigned n_ok_b, n_ok_r, n_ok_aw, n_ok_w, n_ok_ar, n_ok_wr, n_ok_rd;   // compteurs de cas non vides

    // ---------- regles que doit respecter l'ESCLAVE (le circuit) ----------
    // A1 : BVALID reste a 1, avec la meme reponse, tant que BREADY n'a pas repondu
    a1_b_stable: assert property (@(posedge ACLK) disable iff (!ARESETn) BVALID && !BREADY |=> BVALID && $stable(BRESP))
        else begin $error("A1 : BVALID retombe ou BRESP change avant BREADY"); violations++; end
    // A2 : meme regle pour la lecture (RVALID, RDATA, RRESP)
    a2_r_stable: assert property (@(posedge ACLK) disable iff (!ARESETn) RVALID && !RREADY |=> RVALID && $stable(RDATA) && $stable(RRESP))
        else begin $error("A2 : RVALID retombe ou RDATA/RRESP change avant RREADY"); violations++; end
    // A3 : seuls OKAY (00) et SLVERR (10) sont permis
    a3_bresp_legal: assert property (@(posedge ACLK) disable iff (!ARESETn) BVALID |-> BRESP inside {2'b00, 2'b10})
        else begin $error("A3 : BRESP illegal (EXOKAY ou DECERR)"); violations++; end
    a4_rresp_legal: assert property (@(posedge ACLK) disable iff (!ARESETn) RVALID |-> RRESP inside {2'b00, 2'b10})
        else begin $error("A4 : RRESP illegal (EXOKAY ou DECERR)"); violations++; end
    // A5 : apres une ecriture acceptee (AW et W), la reponse B arrive au cycle suivant
    a5_write_resp: assert property (@(posedge ACLK) disable iff (!ARESETn) AWVALID && AWREADY && WVALID && WREADY |=> BVALID)
        else begin $error("A5 : pas de reponse B apres l'ecriture"); violations++; end
    // A6 : apres une adresse de lecture acceptee, la reponse R arrive au cycle suivant
    a6_read_resp: assert property (@(posedge ACLK) disable iff (!ARESETn) ARVALID && ARREADY |=> RVALID)
        else begin $error("A6 : pas de reponse R apres l'adresse de lecture"); violations++; end
    // A7 : pas de valeur inconnue (X) sur les sorties de handshake
    a7_no_x: assert property (@(posedge ACLK) disable iff (!ARESETn) !$isunknown({AWREADY, WREADY, BVALID, ARREADY, RVALID}))
        else begin $error("A7 : valeur inconnue sur une sortie de handshake"); violations++; end
    // A8 : pendant le reset (sans disable), les reponses retombent au cycle suivant
    a8_reset: assert property (@(posedge ACLK) !ARESETn |=> !BVALID && !RVALID)
        else begin $error("A8 : BVALID ou RVALID encore a 1 apres le reset"); violations++; end

    // ---------- regles que doit respecter le MAITRE (le driver du banc) ----------
    // A9 : une adresse ou donnee presentee reste stable tant que le circuit n'a pas repondu
    a9_aw_stable: assert property (@(posedge ACLK) disable iff (!ARESETn) AWVALID && !AWREADY |=> AWVALID && $stable(AWADDR))
        else begin $error("A9 : le maitre retire ou change AWADDR avant AWREADY"); violations++; end
    a10_w_stable: assert property (@(posedge ACLK) disable iff (!ARESETn) WVALID && !WREADY |=> WVALID && $stable(WDATA) && $stable(WSTRB))
        else begin $error("A10 : le maitre retire ou change WDATA/WSTRB avant WREADY"); violations++; end
    a11_ar_stable: assert property (@(posedge ACLK) disable iff (!ARESETn) ARVALID && !ARREADY |=> ARVALID && $stable(ARADDR))
        else begin $error("A11 : le maitre retire ou change ARADDR avant ARREADY"); violations++; end

    // ---------- verifie que les regles ont reellement ete exercees (pas de test vide) ----------
    logic bv_q, rv_q;
    always @(posedge ACLK) begin
        bv_q <= BVALID && !BREADY;
        rv_q <= RVALID && !RREADY;
        if (ARESETn) begin
            if (BVALID && BREADY && bv_q)            n_ok_b++;    // reponse B retenue puis acceptee
            if (RVALID && RREADY && rv_q)            n_ok_r++;    // reponse R retenue puis acceptee
            if (AWVALID && !AWREADY)                 n_ok_aw++;   // maitre en attente sur AW
            if (WVALID && !WREADY)                   n_ok_w++;    // maitre en attente sur W
            if (ARVALID && !ARREADY)                 n_ok_ar++;   // maitre en attente sur AR
            if (AWVALID && AWREADY && WVALID && WREADY) n_ok_wr++;   // ecriture acceptee
            if (ARVALID && ARREADY)                  n_ok_rd++;   // adresse de lecture acceptee
        end
    end

    // Resume a appeler en fin de simulation (voir testbench.sv)
    function void report();
        $display("Assertions SVA : %0d violation(s)", violations);
        $display("  regles exercees : B retenue puis acceptee %0d, R retenue puis acceptee %0d, attente AW %0d, W %0d, AR %0d, ecritures %0d, lectures %0d",
                 n_ok_b, n_ok_r, n_ok_aw, n_ok_w, n_ok_ar, n_ok_wr, n_ok_rd);
    endfunction
endmodule
