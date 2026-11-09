"""Injecte 6 bugs dans le circuit, un par un, et verifie que l'assertion prevue se declenche.
Usage (depuis le dossier sva_check) : python3 run_mutants.py"""
import subprocess, pathlib, tempfile, re
src = pathlib.Path("../verilog_sv/axi4lite_slave.v").read_text(encoding="utf-8")
MUT = [
 ("A1", "BVALID retombe sans BREADY",   "RESP: if (BREADY) begin\n                          BVALID <= 1'b0; wstate <= IDLE;\n                      end",
                                         "RESP: begin\n                          BVALID <= 1'b0; wstate <= IDLE;\n                      end"),
 ("A2", "RDATA change pendant l'attente", "RWAIT: if (RREADY) begin", "RWAIT: if (!RREADY) RDATA <= RDATA + 1; else if (RREADY) begin"),
 ("A3", "BRESP = DECERR (11)",            "default: BRESP <= SLVERR;", "default: BRESP <= 2'b11;"),
 ("A4", "RRESP = EXOKAY (01)",            "RRESP   <= OKAY;", "RRESP   <= 2'b01;"),
 ("A5", "pas de reponse B apres l'ecriture", "BVALID <= 1'b1; wstate <= RESP;", "BVALID <= 1'b0; wstate <= RESP;"),
 ("A6", "RVALID en retard",               "RVALID <= 1'b1; rstate <= RWAIT;", "RVALID <= 1'b0; rstate <= RWAIT;"),
]
ok = 0
with tempfile.TemporaryDirectory() as d:
    for name, desc, a, b in MUT:
        assert a in src, name
        f = pathlib.Path(d) / f"{name}.v"; f.write_text(src.replace(a, b, 1), encoding="utf-8")
        out = subprocess.run(["sh", "run_sva.sh", str(f)], capture_output=True, text=True).stdout
        hit = re.findall(r"Assertion failed in \S+\.(a\d+_\w+)", out)
        good = any(h.startswith(name.lower() + "_") for h in hit)
        ok += good
        print(f"{'detecte ' if good else 'RATE    '} : {name}  {desc}  ->  {sorted(set(hit))}")
print(f"{len(MUT)} mutants, {ok} detectes par l'assertion prevue")
