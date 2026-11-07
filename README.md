# Esclave AXI4-Lite : conception et vérification

Un périphérique **esclave AXI4-Lite** avec quatre registres, décrit en Verilog et en VHDL, et trois environnements
de vérification : un en **UVM**, un en SystemVerilog (à classes) et un en VHDL-2008.

## Le circuit

| Adresse | Registre | Accès |
|---|---|---|
| `0x00` | CTRL | lecture / écriture |
| `0x04` | STATUS | lecture seule (renvoie l'entrée `status_in`) |
| `0x08` | DATA0 | lecture / écriture |
| `0x0C` | DATA1 | lecture / écriture |

- Deux machines à états **indépendantes**, une pour l'écriture (canaux AW, W, B) et une pour la lecture (canaux AR, R).
- `WSTRB` : seuls les octets autorisés sont écrits.
- Toute autre adresse répond **SLVERR** (`10`). Une écriture sur STATUS est ignorée.

## Organisation

```
verilog_sv/   circuit en Verilog + banc de test SystemVerilog à classes (Vivado xsim)
uvm/          environnement UVM (agent, driver, moniteur, scoreboard, séquences) pour le même circuit (Vivado xsim)
vhdl/         circuit en VHDL + banc de test VHDL-2008 (GHDL, simulateur libre)
```

## Vérification VHDL (testé avec GHDL)

Le banc `tb_axi4lite.vhd` reprend l'architecture du banc SystemVerilog :

- **générateur et driver** : maître AXI4-Lite. 8 transactions dirigées (écrire puis relire chaque registre),
  puis **300 transactions aléatoires** (graines fixes, le test se rejoue à l'identique) : lecture ou écriture,
  70 % d'adresses valides et 30 % d'adresses invalides, données, `WSTRB` et délais aléatoires ;
- **moniteur et scoreboard** : le moniteur observe seulement le bus (VALID et READY au même front d'horloge) ;
  un modèle de référence prédit la valeur lue et le code de réponse, puis compare ;
- **couverture fonctionnelle** : 2 bins pour le type d'opération, 6 bins pour la cible (les 4 registres et deux
  zones d'adresses invalides) ;
- **assertions de protocole** (vérifiées à chaque front d'horloge) : pas de valeur inconnue sur les sorties de
  handshake, `BVALID` et `RVALID` restent à 1 avec une valeur stable tant que `BREADY` / `RREADY` n'a pas répondu,
  jamais de code de réponse EXOKAY ou DECERR.

Lancer (avec GHDL 4 ou plus récent) :

```
cd vhdl
./run.sh
```
ou, à la main :
```
ghdl -a --std=08 axi4lite_slave.vhd tb_axi4lite.vhd
ghdl -e --std=08 tb_axi4lite
ghdl -r --std=08 tb_axi4lite
```

Résultat obtenu :

```
Transactions : 308 (ecritures 148, lectures 160, adresses invalides 81)
Couverture fonctionnelle : 100.0 %   (cp_op 2/2 bins, cp_cible 6/6 bins)
Assertions de protocole : 8776 verifications, 0 violation(s)
PASS : 308 transactions verifiees, 0 erreur, 0 violation d'assertion
```

**Le banc détecte bien un circuit faux.** J'ai introduit volontairement quatre bogues dans le circuit, et le banc
échoue à chaque fois : `WSTRB` ignoré sur CTRL (32 erreurs), STATUS qui lit CTRL (30 erreurs), écriture à une adresse
invalide qui répond OKAY (41 erreurs), et `BVALID` qui retombe avant `BREADY` (violation de l'assertion A2).

## Vérification SystemVerilog (Vivado)

`verilog_sv/testbench.sv` est un environnement à classes, d'architecture inspirée d'UVM mais sans la bibliothèque UVM :
générateur, driver, moniteur, scoreboard (modèle de référence), et une classe de couverture fonctionnelle (`covergroup`).
Il se lance avec Vivado xsim :

```
cd verilog_sv
xvlog -sv axi4lite_slave.v testbench.sv
xelab -timescale 1ns/1ps -debug typical top -s sim
xsim sim -runall
```

Exécution sous Vivado du banc à classes : 308 transactions, PASS, 0 erreur (avant l'ajout de la couverture).
La contrainte des adresses invalides a ensuite été corrigée (voir ci-dessous) : toute adresse autre que les
4 registres peut être générée, y compris `0x01` à `0x0F`. La version actuelle, avec couverture et cette
correction, n'a pas encore été relancée sous Vivado.

## Vérification UVM (Vivado)

Le dossier `uvm/` contient un environnement de vérification avec la bibliothèque UVM : séquences (dirigée puis
aléatoire contrainte), driver, moniteur, scoreboard avec modèle de référence, agent, environnement et test.
Voir `uvm/README.md` pour le détail et pour la commande de lancement.

## Limites connues

- Pas de synthèse ni d'essai sur FPGA : le projet est vérifié en simulation uniquement.
- Le circuit VHDL est une traduction écrite à la main du circuit Verilog. Sa conformité est vérifiée par le banc VHDL ;
  l'équivalence avec la version Verilog n'est pas prouvée formellement.
- La couverture du banc SystemVerilog n'a pas encore été mesurée sur la version actuelle. Avant la correction de la
  contrainte d'adresses (`addr >= 8'h10`, qui ne produisait jamais `0x01` à `0x0F`), le bin `invalide_bas` ne pouvait
  pas être atteint ; le banc VHDL génère ces adresses et atteint 100 %.
- Pas d'assertions SVA dans les versions SystemVerilog et UVM (les assertions de protocole sont dans le banc VHDL).
- L'environnement UVM ne contient pas de classe de couverture fonctionnelle.
- Le driver lance une seule transaction à la fois : une écriture et une lecture simultanées ne sont pas testées.
