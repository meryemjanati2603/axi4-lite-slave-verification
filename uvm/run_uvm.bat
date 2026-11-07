@echo off
REM A lancer dans le "Vivado Tcl Shell" (ou une invite ou Vivado est dans le PATH), depuis ce dossier.
xvlog -sv -L uvm axi4lite_slave.v testbench.sv
xelab -L uvm -debug typical top -s sim
xsim sim -runall
