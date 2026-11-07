# Environnement UVM pour l'esclave AXI4-Lite

Banc de vérification écrit avec la bibliothèque **UVM** (SystemVerilog), pour le même circuit que le reste du dépôt
(`axi4lite_slave.v`, identique à celui du dossier `verilog_sv`).

## Composants

| Composant UVM | Rôle |
|---|---|
| `axi_item` (sequence item) | une transaction : lecture ou écriture, adresse, données, `WSTRB`, délais aléatoires. Contraintes d'adresse et de délais. |
| `axi_wr_rd_seq` (sequence) | séquence dirigée : écrit puis relit chacun des 4 registres (8 transactions) |
| `axi_rand_seq` (sequence) | séquence aléatoire contrainte : 300 transactions |
| `axi_driver` | joue le rôle du maître AXI4-Lite sur l'interface virtuelle |
| `axi_monitor` | observe le bus et transmet chaque transaction terminée |
| `axi_scoreboard` | modèle de référence des registres (prend en compte `WSTRB`, STATUS en lecture seule, adresses invalides) ; compare la donnée lue et le code de réponse (OKAY / SLVERR) |
| `axi_agent` | regroupe séquenceur, driver et moniteur |
| `axi_env` | environnement : agent + scoreboard |
| `axi_test` | lance les deux séquences |
| `top` | module de test : horloge, reset, interface, circuit sous test, `run_test("axi_test")` |

## Lancer (Vivado xsim, qui inclut UVM)

Dans le « Vivado Tcl Shell », depuis ce dossier :

```
run_uvm.bat
```
ou, une commande à la fois :
```
xvlog -sv -L uvm axi4lite_slave.v testbench.sv
xelab -L uvm -debug typical top -s sim
xsim sim -runall
```

À la fin du log, le scoreboard affiche :

```
PASS : ... transactions verifiees, 0 erreur
```

## Limites

- Pas de classe de couverture fonctionnelle ni d'assertions dans cette version UVM (elles sont dans le banc VHDL
  et, pour la couverture, dans le banc SystemVerilog à classes du dossier `verilog_sv`).
- La contrainte d'adresse produit les 4 registres et des adresses invalides de `0x10` à `0xFF` (pas de `0x01` à `0x0F`).
- Le driver lance une seule transaction à la fois.
