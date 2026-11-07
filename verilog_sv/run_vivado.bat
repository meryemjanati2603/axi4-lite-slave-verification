@echo off
rem Simulation avec Vivado xsim (depuis ce dossier)
xvlog -sv axi4lite_slave.v testbench.sv
xelab -timescale 1ns/1ps -debug typical top -s sim
xsim sim -runall
pause
