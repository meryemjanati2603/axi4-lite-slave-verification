`timescale 1ns/1ps
// Banc minimal pour verifier les assertions (sans classes ni UVM) : un maitre dirige avec des delais.
module tb_sva_check;
    logic clk = 0, rstn = 0;
    always #5 clk = ~clk;
    logic [7:0] awaddr, araddr; logic awvalid, awready; logic [31:0] wdata; logic [3:0] wstrb; logic wvalid, wready;
    logic [1:0] bresp; logic bvalid, bready; logic arvalid, arready; logic [31:0] rdata; logic [1:0] rresp; logic rvalid, rready;
    axi4lite_slave dut(.ACLK(clk), .ARESETn(rstn), .AWADDR(awaddr), .AWVALID(awvalid), .AWREADY(awready),
        .WDATA(wdata), .WSTRB(wstrb), .WVALID(wvalid), .WREADY(wready), .BRESP(bresp), .BVALID(bvalid), .BREADY(bready),
        .ARADDR(araddr), .ARVALID(arvalid), .ARREADY(arready), .RDATA(rdata), .RRESP(rresp), .RVALID(rvalid), .RREADY(rready),
        .status_in(32'hA5A50001));
    axi_sva sva(.ACLK(clk), .ARESETn(rstn), .AWADDR(awaddr), .AWVALID(awvalid), .AWREADY(awready),
        .WDATA(wdata), .WSTRB(wstrb), .WVALID(wvalid), .WREADY(wready), .BRESP(bresp), .BVALID(bvalid), .BREADY(bready),
        .ARADDR(araddr), .ARVALID(arvalid), .ARREADY(arready), .RDATA(rdata), .RRESP(rresp), .RVALID(rvalid), .RREADY(rready));

    task automatic wr(input [7:0] a, input [31:0] d, input [3:0] s, input int bdelay);
        @(posedge clk); #1 awaddr = a; awvalid = 1; wdata = d; wstrb = s; wvalid = 1;
        do @(posedge clk); while (!(awready && wready));   // le circuit a vu la poignee de main a ce front
        #1 awvalid = 0; wvalid = 0;
        wait (bvalid); repeat (bdelay) @(posedge clk);
        #1 bready = 1; @(posedge clk); #1 bready = 0;
    endtask
    task automatic rd(input [7:0] a, input int rdelay);
        @(posedge clk); #1 araddr = a; arvalid = 1;
        do @(posedge clk); while (!arready);
        #1 arvalid = 0;
        wait (rvalid); repeat (rdelay) @(posedge clk);
        #1 rready = 1; @(posedge clk); #1 rready = 0;
    endtask
    initial begin
        awvalid = 0; wvalid = 0; arvalid = 0; bready = 0; rready = 0; awaddr = 0; wdata = 0; wstrb = 0; araddr = 0;
        repeat (3) @(posedge clk); #1 rstn = 1; repeat (2) @(posedge clk);
        begin : seq
            logic [7:0] adr [7];
            adr[0]=8'h00; adr[1]=8'h04; adr[2]=8'h08; adr[3]=8'h0C; adr[4]=8'h10; adr[5]=8'h01; adr[6]=8'hF0;
            for (int i = 0; i < 7; i++) begin
                wr(adr[i], 32'hDEAD0000 + i, 4'hF, i % 4);
                rd(adr[i], (i + 1) % 4);
            end
            for (int k = 0; k < 100; k++) begin
                if ($urandom_range(0,1)) wr(adr[$urandom_range(0,6)], $urandom, $urandom_range(0,15), $urandom_range(0,4));
                else                     rd(adr[$urandom_range(0,6)], $urandom_range(0,4));
            end
        end
        repeat (5) @(posedge clk);
        sva.report();
        $display("Fin du banc minimal");
        $finish;
    end
endmodule
