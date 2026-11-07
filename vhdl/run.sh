#!/bin/sh
# Simulation avec GHDL (simulateur VHDL libre). Depuis ce dossier :  ./run.sh
set -e
ghdl -a --std=08 axi4lite_slave.vhd tb_axi4lite.vhd
ghdl -e --std=08 tb_axi4lite
ghdl -r --std=08 tb_axi4lite --wave=axi4lite.ghw
