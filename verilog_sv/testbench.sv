`timescale 1ns/1ps
// Environnement de verification SystemVerilog a classes (architecture de type UVM, sans la librairie UVM)
// generateur -> driver -> DUT ; monitor -> scoreboard (modele de reference)

interface axi_if (input logic ACLK, input logic ARESETn);
    logic [7:0]  AWADDR;  logic AWVALID, AWREADY;
    logic [31:0] WDATA;   logic [3:0] WSTRB;  logic WVALID, WREADY;
    logic [1:0]  BRESP;   logic BVALID, BREADY;
    logic [7:0]  ARADDR;  logic ARVALID, ARREADY;
    logic [31:0] RDATA;   logic [1:0] RRESP;  logic RVALID, RREADY;
    logic [31:0] status_in;
endinterface

package axi_pkg;
    localparam bit [31:0] STATUS_VAL = 32'hA5A50001;

    // Transaction
    class axi_item;
        rand bit          write;
        rand bit [7:0]    addr;
        rand bit [31:0]   data;
        rand bit [3:0]    strb;
        rand int unsigned w_delay, b_delay, r_delay;
        bit [31:0] rdata;
        bit [1:0]  resp;
        rand bit          adr_ok;   // 1 = adresse valide (70 %), 0 = adresse invalide (30 %)
        constraint c_sel  { adr_ok dist {1 := 7, 0 := 3}; }
        constraint c_addr {
            if (adr_ok) addr inside {8'h00, 8'h04, 8'h08, 8'h0C};
            else        !(addr inside {8'h00, 8'h04, 8'h08, 8'h0C});   // toute adresse sauf les 4 valides
        }
        constraint c_dly { w_delay inside {[0:4]}; b_delay inside {[0:4]}; r_delay inside {[0:4]}; }
    endclass

    // Couverture fonctionnelle : mesure ce que le bus a reellement vu
    class axi_coverage;
        bit       c_write;     // copie de la transaction observee
        bit [7:0] c_addr;

        covergroup cg;
            option.per_instance = 1;

            // P1 : les deux types d'operation
            cp_op: coverpoint c_write {
                bins lecture  = {0};
                bins ecriture = {1};
            }

            // P2 : les 4 registres + les adresses invalides
            cp_cible: coverpoint c_addr {
                bins ctrl          = {8'h00};
                bins status        = {8'h04};
                bins data0         = {8'h08};
                bins data1         = {8'h0C};
                bins invalide_haut = {[8'h10:8'hFF]};
                bins invalide_bas  = {[8'h01:8'h03], [8'h05:8'h07], [8'h09:8'h0B], [8'h0D:8'h0F]};
            }
        endgroup

        function new();
            cg = new();
        endfunction

        // appelee pour chaque transaction observee par le monitor
        function void sample(axi_item t);
            c_write = t.write;
            c_addr  = t.addr;
            cg.sample();
        endfunction

        function real pourcentage();
            return cg.get_inst_coverage();
        endfunction
    endclass

    // Generateur : sequence dirigee puis sequence aleatoire contrainte
    class axi_generator;
        mailbox #(axi_item) gen2drv;
        int unsigned n_rand = 300;
        function new(mailbox #(axi_item) m); gen2drv = m; endfunction

        task run();
            axi_item t;
            bit [7:0] addrs [4] = '{8'h00, 8'h04, 8'h08, 8'h0C};
            // 1) dirige : ecrire puis relire chaque registre
            foreach (addrs[i]) begin
                t = new(); t.write = 1; t.addr = addrs[i]; t.data = $urandom; t.strb = 4'hF;
                t.w_delay = $urandom_range(0,4); t.b_delay = $urandom_range(0,4); t.r_delay = 0;
                gen2drv.put(t);
                t = new(); t.write = 0; t.addr = addrs[i];
                t.w_delay = 0; t.b_delay = 0; t.r_delay = $urandom_range(0,4);
                gen2drv.put(t);
            end
            // 2) aleatoire contraint
            repeat (n_rand) begin
                t = new(); if (!t.randomize()) $fatal(1, "randomize");
                gen2drv.put(t);
            end
        endtask
    endclass

    // Driver : maitre AXI4-Lite
    class axi_driver;
        virtual axi_if vif;
        mailbox #(axi_item) gen2drv;
        int done;
        function new(virtual axi_if v, mailbox #(axi_item) m); vif = v; gen2drv = m; endfunction

        task run(int total);
            axi_item t;
            vif.AWVALID <= 0; vif.WVALID <= 0; vif.BREADY <= 0;
            vif.ARVALID <= 0; vif.RREADY <= 0;
            vif.AWADDR <= 0; vif.WDATA <= 0; vif.WSTRB <= 4'hF; vif.ARADDR <= 0;
            wait (vif.ARESETn === 1'b1);
            @(posedge vif.ACLK);
            repeat (total) begin
                gen2drv.get(t);
                if (t.write) do_write(t); else do_read(t);
                done++;
            end
        endtask

        task do_write(axi_item t);
            vif.AWADDR <= t.addr; vif.AWVALID <= 1;
            repeat (t.w_delay) @(posedge vif.ACLK);
            vif.WDATA <= t.data; vif.WSTRB <= t.strb; vif.WVALID <= 1;
            @(posedge vif.ACLK);
            while (!(vif.AWREADY && vif.WREADY)) @(posedge vif.ACLK);
            vif.AWVALID <= 0; vif.WVALID <= 0;
            while (!vif.BVALID) @(posedge vif.ACLK);
            repeat (t.b_delay) @(posedge vif.ACLK);
            vif.BREADY <= 1;
            @(posedge vif.ACLK);
            vif.BREADY <= 0;
        endtask

        task do_read(axi_item t);
            vif.ARADDR <= t.addr; vif.ARVALID <= 1;
            @(posedge vif.ACLK);
            while (!vif.ARREADY) @(posedge vif.ACLK);
            vif.ARVALID <= 0;
            while (!vif.RVALID) @(posedge vif.ACLK);
            repeat (t.r_delay) @(posedge vif.ACLK);
            vif.RREADY <= 1;
            @(posedge vif.ACLK);
            vif.RREADY <= 0;
        endtask
    endclass

    // Monitor : observe le bus (VALID && READY sur le meme front)
    class axi_monitor;
        virtual axi_if vif;
        mailbox #(axi_item) mon2scb;
        function new(virtual axi_if v, mailbox #(axi_item) m); vif = v; mon2scb = m; endfunction

        task run();
            bit [7:0]  aw_addr, ar_addr;
            bit [31:0] w_data;
            bit [3:0]  w_strb;
            axi_item   t;
            wait (vif.ARESETn === 1'b1);
            forever begin
                @(posedge vif.ACLK);
                if (vif.AWVALID && vif.AWREADY) aw_addr = vif.AWADDR;
                if (vif.WVALID  && vif.WREADY)  begin w_data = vif.WDATA; w_strb = vif.WSTRB; end
                if (vif.BVALID  && vif.BREADY)  begin
                    t = new(); t.write = 1; t.addr = aw_addr; t.data = w_data; t.strb = w_strb; t.resp = vif.BRESP;
                    mon2scb.put(t);
                end
                if (vif.ARVALID && vif.ARREADY) ar_addr = vif.ARADDR;
                if (vif.RVALID  && vif.RREADY)  begin
                    t = new(); t.write = 0; t.addr = ar_addr; t.rdata = vif.RDATA; t.resp = vif.RRESP;
                    mon2scb.put(t);
                end
            end
        endtask
    endclass

    // Scoreboard : modele de reference + comparaison
    class axi_scoreboard;
        mailbox #(axi_item) mon2scb;
        axi_coverage cov;
        bit [31:0] ctrl, d0, d1;
        int errors, checks, n_wr, n_rd, n_err_addr;
        function new(mailbox #(axi_item) m); mon2scb = m; cov = new(); endfunction

        function bit valid_addr(bit [7:0] a);
            return (a == 8'h00 || a == 8'h04 || a == 8'h08 || a == 8'h0C);
        endfunction

        function bit [31:0] merge(bit [31:0] old, bit [31:0] nw, bit [3:0] s);
            bit [31:0] m;
            for (int i = 0; i < 4; i++) m[8*i +: 8] = s[i] ? nw[8*i +: 8] : old[8*i +: 8];
            return m;
        endfunction

        task run();
            axi_item t;
            bit [31:0] expd;
            bit [1:0]  expr;
            forever begin
                mon2scb.get(t);
                checks++;
                cov.sample(t);
                expr = valid_addr(t.addr) ? 2'b00 : 2'b10;
                if (!valid_addr(t.addr)) n_err_addr++;
                if (t.write) begin
                    n_wr++;
                    case (t.addr)
                        8'h00: ctrl = merge(ctrl, t.data, t.strb);
                        8'h08: d0   = merge(d0,   t.data, t.strb);
                        8'h0C: d1   = merge(d1,   t.data, t.strb);
                        default: ;
                    endcase
                    if (t.resp !== expr) begin
                        errors++;
                        $display("[SCB] ERREUR WRITE addr=%h BRESP=%0d attendu %0d", t.addr, t.resp, expr);
                    end
                end else begin
                    n_rd++;
                    case (t.addr)
                        8'h00: expd = ctrl;
                        8'h04: expd = STATUS_VAL;
                        8'h08: expd = d0;
                        8'h0C: expd = d1;
                        default: expd = 32'h0;
                    endcase
                    if (t.rdata !== expd || t.resp !== expr) begin
                        errors++;
                        $display("[SCB] ERREUR READ addr=%h data=%h resp=%0d attendu data=%h resp=%0d",
                                 t.addr, t.rdata, t.resp, expd, expr);
                    end
                end
            end
        endtask
    endclass

    // Environnement
    class axi_env;
        axi_generator  gen;
        axi_driver     drv;
        axi_monitor    mon;
        axi_scoreboard scb;
        mailbox #(axi_item) gen2drv, mon2scb;
        int total;
        function new(virtual axi_if v);
            gen2drv = new(); mon2scb = new();
            gen = new(gen2drv);
            drv = new(v, gen2drv);
            mon = new(v, mon2scb);
            scb = new(mon2scb);
            total = 8 + gen.n_rand;
        endfunction

        task run();
            fork
                gen.run();
                drv.run(total);
                mon.run();
                scb.run();
            join_none
            wait (drv.done == total);
            repeat (20) @(posedge drv.vif.ACLK);   // laisse le scoreboard finir
            report();
        endtask

        function void report();
            $display("--------------------------------------------------");
            $display("Transactions : %0d (ecritures %0d, lectures %0d, adresses invalides %0d)",
                     scb.checks, scb.n_wr, scb.n_rd, scb.n_err_addr);
            $display("Couverture fonctionnelle : %0.1f %%", scb.cov.pourcentage());
            if (scb.errors == 0 && scb.checks == total)
                $display("PASS : %0d transactions verifiees, 0 erreur", scb.checks);
            else
                $display("FAIL : %0d erreur(s), %0d/%0d transactions observees", scb.errors, scb.checks, total);
            $display("--------------------------------------------------");
        endfunction
    endclass
endpackage

module top;
    import axi_pkg::*;
    bit clk = 0;
    bit rstn = 0;
    always #5 clk = ~clk;
    initial #22 rstn = 1;

    axi_if vif (clk, rstn);
    assign vif.status_in = STATUS_VAL;

    axi4lite_slave dut (
        .ACLK(clk), .ARESETn(rstn),
        .AWADDR(vif.AWADDR), .AWVALID(vif.AWVALID), .AWREADY(vif.AWREADY),
        .WDATA(vif.WDATA), .WSTRB(vif.WSTRB), .WVALID(vif.WVALID), .WREADY(vif.WREADY),
        .BRESP(vif.BRESP), .BVALID(vif.BVALID), .BREADY(vif.BREADY),
        .ARADDR(vif.ARADDR), .ARVALID(vif.ARVALID), .ARREADY(vif.ARREADY),
        .RDATA(vif.RDATA), .RRESP(vif.RRESP), .RVALID(vif.RVALID), .RREADY(vif.RREADY),
        .status_in(vif.status_in)
    );

    axi_env env;
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top);
        env = new(vif);
        env.run();
        $finish;
    end
endmodule
