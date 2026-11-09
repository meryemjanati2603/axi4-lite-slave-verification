#!/bin/sh
# Verifie les assertions SVA avec Verilator 5 (outil libre). Usage : sh run_sva.sh [circuit.v]
# Par defaut : le circuit du dossier verilog_sv.  Lance depuis le dossier sva_check.
DUT=${1:-../verilog_sv/axi4lite_slave.v}
rm -rf obj_dir
verilator --binary --assert --timing -Wno-fatal -Wno-lint --top-module tb_sva_check \
    "$DUT" ../verilog_sv/axi_sva.sv tb_sva_check.sv > build.log 2>&1 || { tail -20 build.log; exit 1; }
./obj_dir/Vtb_sva_check
