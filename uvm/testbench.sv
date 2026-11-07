`include "uvm_macros.svh"

// Interface : regroupe tous les signaux AXI4-Lite
interface axi_if (input logic ACLK, input logic ARESETn);
    logic [7:0]  AWADDR;  logic AWVALID, AWREADY;
    logic [31:0] WDATA;   logic [3:0] WSTRB;  logic WVALID, WREADY;
    logic [1:0]  BRESP;   logic BVALID, BREADY;
    logic [7:0]  ARADDR;  logic ARVALID, ARREADY;
    logic [31:0] RDATA;   logic [1:0] RRESP;  logic RVALID, RREADY;
    logic [31:0] status_in;
endinterface

package axi_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    localparam bit [31:0] STATUS_VAL = 32'hA5A50001;

// Transaction : une ecriture ou une lecture
class axi_item extends uvm_sequence_item;
    `uvm_object_utils(axi_item)
    rand bit          write;
    rand bit [7:0]    addr;
    rand bit [31:0]   data;
    rand bit [3:0]    strb;
    rand int unsigned w_delay, b_delay, r_delay;   // retards du maitre
    bit [31:0] rdata;                              // resultats observes
    bit [1:0]  resp;

    constraint c_addr {
        addr dist {8'h00 := 2, 8'h04 := 1, 8'h08 := 2, 8'h0C := 2, [8'h10:8'hFF] :/ 3};
    }
    constraint c_dly { w_delay inside {[0:4]}; b_delay inside {[0:4]}; r_delay inside {[0:4]}; }

    function new(string name = "axi_item");
        super.new(name);
    endfunction
endclass

// Sequence dirigee : ecrire puis relire chaque registre
class axi_wr_rd_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(axi_wr_rd_seq)
    function new(string name = "axi_wr_rd_seq"); super.new(name); endfunction
    task body();
        axi_item t;
        bit [7:0] addrs [4] = '{8'h00, 8'h04, 8'h08, 8'h0C};
        bit [7:0] tgt_addr;
        foreach (addrs[i]) begin
            tgt_addr = addrs[i];
            t = axi_item::type_id::create("w");
            start_item(t);
            if (!t.randomize() with {write == 1; addr == tgt_addr; strb == 4'hF;})
                `uvm_fatal("SEQ", "randomize echoue")
            finish_item(t);
            t = axi_item::type_id::create("r");
            start_item(t);
            if (!t.randomize() with {write == 0; addr == tgt_addr;})
                `uvm_fatal("SEQ", "randomize echoue")
            finish_item(t);
        end
    endtask
endclass

// Sequence aleatoire contrainte
class axi_rand_seq extends uvm_sequence #(axi_item);
    `uvm_object_utils(axi_rand_seq)
    int unsigned n = 300;
    function new(string name = "axi_rand_seq"); super.new(name); endfunction
    task body();
        axi_item t;
        repeat (n) begin
            t = axi_item::type_id::create("t");
            start_item(t);
            if (!t.randomize()) `uvm_fatal("SEQ", "randomize echoue")
            finish_item(t);
        end
    endtask
endclass

// Driver : joue le role du maitre AXI
class axi_driver extends uvm_driver #(axi_item);
    `uvm_component_utils(axi_driver)
    virtual axi_if vif;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "interface non trouvee")
    endfunction

    task run_phase(uvm_phase phase);
        vif.AWVALID <= 0; vif.WVALID <= 0; vif.BREADY <= 0;
        vif.ARVALID <= 0; vif.RREADY <= 0;
        vif.AWADDR <= 0; vif.WDATA <= 0; vif.WSTRB <= 4'hF; vif.ARADDR <= 0;
        wait (vif.ARESETn === 1'b1);
        @(posedge vif.ACLK);
        forever begin
            seq_item_port.get_next_item(req);
            if (req.write) do_write(req); else do_read(req);
            seq_item_port.item_done();
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
        t.resp = vif.BRESP;
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
        t.rdata = vif.RDATA; t.resp = vif.RRESP;
        vif.RREADY <= 0;
    endtask
endclass

// Monitor : observe le bus sans le piloter
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)
    virtual axi_if vif;
    uvm_analysis_port #(axi_item) ap;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "interface non trouvee")
    endfunction

    task run_phase(uvm_phase phase);
        bit [7:0]  aw_addr, ar_addr;
        bit [31:0] w_data;
        bit [3:0]  w_strb;
        axi_item   t;
        wait (vif.ARESETn === 1'b1);
        forever begin
            @(posedge vif.ACLK);
            // une transaction a lieu quand VALID et READY valent 1 sur le meme front
            if (vif.AWVALID && vif.AWREADY) aw_addr = vif.AWADDR;
            if (vif.WVALID  && vif.WREADY)  begin w_data = vif.WDATA; w_strb = vif.WSTRB; end
            if (vif.BVALID  && vif.BREADY)  begin
                t = axi_item::type_id::create("mon_wr");
                t.write = 1; t.addr = aw_addr; t.data = w_data; t.strb = w_strb; t.resp = vif.BRESP;
                ap.write(t);
            end
            if (vif.ARVALID && vif.ARREADY) ar_addr = vif.ARADDR;
            if (vif.RVALID  && vif.RREADY)  begin
                t = axi_item::type_id::create("mon_rd");
                t.write = 0; t.addr = ar_addr; t.rdata = vif.RDATA; t.resp = vif.RRESP;
                ap.write(t);
            end
        end
    endtask
endclass

// Scoreboard : modele de reference des registres + comparaison
class axi_scoreboard extends uvm_subscriber #(axi_item);
    `uvm_component_utils(axi_scoreboard)
    bit [31:0] ctrl, d0, d1;      // modele des registres (0 apres reset)
    int errors, checks;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction

    function bit valid_addr(bit [7:0] a);
        return (a == 8'h00 || a == 8'h04 || a == 8'h08 || a == 8'h0C);
    endfunction

    function bit [31:0] merge(bit [31:0] old, bit [31:0] nw, bit [3:0] s);
        bit [31:0] m;
        for (int i = 0; i < 4; i++) m[8*i +: 8] = s[i] ? nw[8*i +: 8] : old[8*i +: 8];
        return m;
    endfunction

    function void write(axi_item t);
        bit [31:0] expd;
        bit [1:0]  expr;
        checks++;
        expr = valid_addr(t.addr) ? 2'b00 : 2'b10;
        if (t.write) begin
            case (t.addr)
                8'h00: ctrl = merge(ctrl, t.data, t.strb);
                8'h08: d0   = merge(d0,   t.data, t.strb);
                8'h0C: d1   = merge(d1,   t.data, t.strb);
                default: ;
            endcase
            if (t.resp !== expr) begin
                errors++;
                `uvm_error("SCB", $sformatf("WRITE addr=%h : BRESP=%0d attendu %0d", t.addr, t.resp, expr))
            end
        end else begin
            case (t.addr)
                8'h00: expd = ctrl;
                8'h04: expd = STATUS_VAL;
                8'h08: expd = d0;
                8'h0C: expd = d1;
                default: expd = 32'h0;
            endcase
            if (t.rdata !== expd || t.resp !== expr) begin
                errors++;
                `uvm_error("SCB", $sformatf("READ addr=%h : data=%h resp=%0d, attendu data=%h resp=%0d",
                                            t.addr, t.rdata, t.resp, expd, expr))
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        if (errors == 0)
            `uvm_info("SCB", $sformatf("PASS : %0d transactions verifiees, 0 erreur", checks), UVM_NONE)
        else
            `uvm_error("SCB", $sformatf("FAIL : %0d erreur(s) sur %0d transactions", errors, checks))
    endfunction
endclass

// Agent : sequenceur + driver + monitor
class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)
    axi_driver drv;
    axi_monitor mon;
    uvm_sequencer #(axi_item) sqr;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        mon = axi_monitor::type_id::create("mon", this);
        drv = axi_driver::type_id::create("drv", this);
        sqr = uvm_sequencer #(axi_item)::type_id::create("sqr", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
endclass

// Environnement : agent + scoreboard
class axi_env extends uvm_env;
    `uvm_component_utils(axi_env)
    axi_agent agent;
    axi_scoreboard scb;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agent = axi_agent::type_id::create("agent", this);
        scb   = axi_scoreboard::type_id::create("scb", this);
    endfunction
    function void connect_phase(uvm_phase phase);
        agent.mon.ap.connect(scb.analysis_export);
    endfunction
endclass

// Test : lance les sequences
class axi_test extends uvm_test;
    `uvm_component_utils(axi_test)
    axi_env env;
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = axi_env::type_id::create("env", this);
    endfunction
    task run_phase(uvm_phase phase);
        axi_wr_rd_seq s1;
        axi_rand_seq  s2;
        phase.raise_objection(this);
        s1 = axi_wr_rd_seq::type_id::create("s1");
        s1.start(env.agent.sqr);
        s2 = axi_rand_seq::type_id::create("s2");
        s2.start(env.agent.sqr);
        #100ns;
        phase.drop_objection(this);
    endtask
endclass

endpackage

// Top : horloge, reset, interface, DUT, lancement du test

module top;
    import uvm_pkg::*;
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

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, top);
        uvm_config_db#(virtual axi_if)::set(null, "*", "vif", vif);
        run_test("axi_test");
    end
endmodule
