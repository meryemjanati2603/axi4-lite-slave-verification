-- Banc de test VHDL-2008 de l'esclave AXI4-Lite.
-- Meme architecture que le banc SystemVerilog : generateur + driver (maitre AXI),
-- moniteur + modele de reference (scoreboard), couverture fonctionnelle, et en plus
-- des assertions de protocole. Sequence dirigee (8 transactions) puis aleatoire (300).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.env.all;

entity tb_axi4lite is
end entity;

architecture sim of tb_axi4lite is
    constant STATUS_VAL : std_logic_vector(31 downto 0) := x"A5A50001";
    constant N_DIRIGE   : integer := 8;
    constant N_RAND     : integer := 300;
    constant TOTAL      : integer := N_DIRIGE + N_RAND;

    signal ACLK, ARESETn : std_logic := '0';
    signal AWADDR, ARADDR : std_logic_vector(7 downto 0) := (others => '0');
    signal AWVALID, WVALID, BREADY, ARVALID, RREADY : std_logic := '0';
    signal AWREADY, WREADY, BVALID, ARREADY, RVALID : std_logic;
    signal WDATA : std_logic_vector(31 downto 0) := (others => '0');
    signal WSTRB : std_logic_vector(3 downto 0) := x"F";
    signal BRESP, RRESP : std_logic_vector(1 downto 0);
    signal RDATA : std_logic_vector(31 downto 0);

    signal driver_done : boolean := false;
    signal a_checks, a_viol : integer := 0;     -- compteurs des assertions de protocole

    function is_valid_addr(a : std_logic_vector(7 downto 0)) return boolean is
    begin
        return a = x"00" or a = x"04" or a = x"08" or a = x"0C";
    end function;

    function merge(old, nw : std_logic_vector(31 downto 0);
                   s : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(31 downto 0);
    begin
        for i in 0 to 3 loop
            if s(i) = '1' then r(8*i+7 downto 8*i) := nw(8*i+7 downto 8*i);
            else               r(8*i+7 downto 8*i) := old(8*i+7 downto 8*i);
            end if;
        end loop;
        return r;
    end function;
begin
    ACLK    <= not ACLK after 5 ns;
    ARESETn <= '1' after 22 ns;

    dut : entity work.axi4lite_slave
        port map (ACLK => ACLK, ARESETn => ARESETn,
                  AWADDR => AWADDR, AWVALID => AWVALID, AWREADY => AWREADY,
                  WDATA => WDATA, WSTRB => WSTRB, WVALID => WVALID, WREADY => WREADY,
                  BRESP => BRESP, BVALID => BVALID, BREADY => BREADY,
                  ARADDR => ARADDR, ARVALID => ARVALID, ARREADY => ARREADY,
                  RDATA => RDATA, RRESP => RRESP, RVALID => RVALID, RREADY => RREADY,
                  status_in => STATUS_VAL);

    -- ------------------------------------------------------------------
    -- Generateur + driver : maitre AXI4-Lite
    -- ------------------------------------------------------------------
    driver : process
        variable s1 : positive := 11;       -- graines fixes : le test se rejoue a l'identique
        variable s2 : positive := 29;
        variable x  : real;

        impure function rnd(lo, hi : integer) return integer is
            variable r : integer;
        begin
            uniform(s1, s2, x);
            r := lo + integer(floor(x * real(hi - lo + 1)));
            if r > hi then r := hi; end if;
            return r;
        end function;

        impure function rnd32 return std_logic_vector is
        begin
            return std_logic_vector(to_unsigned(rnd(0, 65535), 16)) &
                   std_logic_vector(to_unsigned(rnd(0, 65535), 16));
        end function;

        procedure tick is
        begin
            wait until rising_edge(ACLK);
        end procedure;

        procedure do_write(addr : std_logic_vector(7 downto 0);
                           data : std_logic_vector(31 downto 0);
                           strb : std_logic_vector(3 downto 0);
                           w_delay, b_delay : integer) is
        begin
            AWADDR <= addr; AWVALID <= '1';
            for i in 1 to w_delay loop tick; end loop;
            WDATA <= data; WSTRB <= strb; WVALID <= '1';
            tick;
            while not (AWREADY = '1' and WREADY = '1') loop tick; end loop;
            AWVALID <= '0'; WVALID <= '0';
            while BVALID /= '1' loop tick; end loop;
            for i in 1 to b_delay loop tick; end loop;
            BREADY <= '1';
            tick;
            BREADY <= '0';
        end procedure;

        procedure do_read(addr : std_logic_vector(7 downto 0); r_delay : integer) is
        begin
            ARADDR <= addr; ARVALID <= '1';
            tick;
            while ARREADY /= '1' loop tick; end loop;
            ARVALID <= '0';
            while RVALID /= '1' loop tick; end loop;
            for i in 1 to r_delay loop tick; end loop;
            RREADY <= '1';
            tick;
            RREADY <= '0';
        end procedure;

        type addr_array is array (0 to 3) of std_logic_vector(7 downto 0);
        constant VALID : addr_array := (x"00", x"04", x"08", x"0C");

        variable wr      : boolean;
        variable addr    : std_logic_vector(7 downto 0);
        variable a_int   : integer;
    begin
        wait until ARESETn = '1';
        tick;

        -- 1) dirige : ecrire puis relire chaque registre
        for i in 0 to 3 loop
            do_write(VALID(i), rnd32, x"F", rnd(0, 4), rnd(0, 4));
            do_read(VALID(i), rnd(0, 4));
        end loop;

        -- 2) aleatoire contraint : 70 % d'adresses valides, 30 % d'adresses invalides
        for i in 1 to N_RAND loop
            wr := rnd(0, 1) = 1;
            if rnd(0, 9) < 7 then
                addr := VALID(rnd(0, 3));
            else
                loop                                   -- n'importe quelle adresse sauf les 4 valides
                    a_int := rnd(1, 255);
                    addr  := std_logic_vector(to_unsigned(a_int, 8));
                    exit when not is_valid_addr(addr);
                end loop;
            end if;
            if wr then
                do_write(addr, rnd32, std_logic_vector(to_unsigned(rnd(0, 15), 4)), rnd(0, 4), rnd(0, 4));
            else
                do_read(addr, rnd(0, 4));
            end if;
        end loop;

        driver_done <= true;
        wait;
    end process;

    -- ------------------------------------------------------------------
    -- Moniteur + modele de reference (scoreboard) + couverture + rapport
    -- Le moniteur observe seulement le bus (VALID et READY au meme front d'horloge).
    -- ------------------------------------------------------------------
    monitor_scoreboard : process
        variable aw_addr, ar_addr : std_logic_vector(7 downto 0) := (others => '0');
        variable w_data  : std_logic_vector(31 downto 0) := (others => '0');
        variable w_strb  : std_logic_vector(3 downto 0)  := (others => '0');
        -- modele de reference
        variable ctrl, d0, d1 : std_logic_vector(31 downto 0) := (others => '0');
        variable expd : std_logic_vector(31 downto 0);
        variable expr : std_logic_vector(1 downto 0);
        variable errors, checks, n_wr, n_rd, n_err_addr : integer := 0;
        variable idle_after_done : integer := 0;
        -- couverture : bins de cp_op (2) et de cp_cible (6)
        variable op_bin     : std_logic_vector(0 to 1) := "00";  -- lecture, ecriture
        variable cible_bin  : std_logic_vector(0 to 5) := "000000";
        variable cov_op, cov_cible, cov_total : real;
        variable hit_op, hit_cible : integer;

        procedure sample(is_write : boolean; a : std_logic_vector(7 downto 0)) is
            variable ai : integer := to_integer(unsigned(a));
        begin
            if is_write then op_bin(1) := '1'; else op_bin(0) := '1'; end if;
            if    ai = 16#00# then cible_bin(0) := '1';        -- ctrl
            elsif ai = 16#04# then cible_bin(1) := '1';        -- status
            elsif ai = 16#08# then cible_bin(2) := '1';        -- data0
            elsif ai = 16#0C# then cible_bin(3) := '1';        -- data1
            elsif ai >= 16#10# then cible_bin(4) := '1';       -- invalide_haut
            else                    cible_bin(5) := '1';       -- invalide_bas (0x01 a 0x0F)
            end if;
        end procedure;

        procedure check_write(a : std_logic_vector(7 downto 0);
                              d : std_logic_vector(31 downto 0);
                              s : std_logic_vector(3 downto 0);
                              resp : std_logic_vector(1 downto 0)) is
        begin
            n_wr := n_wr + 1;
            if is_valid_addr(a) then expr := "00"; else expr := "10"; n_err_addr := n_err_addr + 1; end if;
            case a is
                when x"00"  => ctrl := merge(ctrl, d, s);
                when x"08"  => d0   := merge(d0,   d, s);
                when x"0C"  => d1   := merge(d1,   d, s);
                when others => null;
            end case;
            if resp /= expr then
                errors := errors + 1;
                report "ERREUR WRITE addr=" & to_hstring(a) & " BRESP=" & to_hstring("00" & resp)
                       & " attendu " & to_hstring("00" & expr) severity error;
            end if;
        end procedure;

        procedure check_read(a : std_logic_vector(7 downto 0);
                             d : std_logic_vector(31 downto 0);
                             resp : std_logic_vector(1 downto 0)) is
        begin
            n_rd := n_rd + 1;
            if is_valid_addr(a) then expr := "00"; else expr := "10"; n_err_addr := n_err_addr + 1; end if;
            case a is
                when x"00"  => expd := ctrl;
                when x"04"  => expd := STATUS_VAL;
                when x"08"  => expd := d0;
                when x"0C"  => expd := d1;
                when others => expd := (others => '0');
            end case;
            if d /= expd or resp /= expr then
                errors := errors + 1;
                report "ERREUR READ addr=" & to_hstring(a) & " data=" & to_hstring(d)
                       & " attendu data=" & to_hstring(expd) severity error;
            end if;
        end procedure;
    begin
        wait until ARESETn = '1';
        loop
            wait until rising_edge(ACLK);
            if AWVALID = '1' and AWREADY = '1' then aw_addr := AWADDR; end if;
            if WVALID  = '1' and WREADY  = '1' then w_data := WDATA; w_strb := WSTRB; end if;
            if BVALID  = '1' and BREADY  = '1' then
                checks := checks + 1;
                sample(true, aw_addr);
                check_write(aw_addr, w_data, w_strb, BRESP);
            end if;
            if ARVALID = '1' and ARREADY = '1' then ar_addr := ARADDR; end if;
            if RVALID  = '1' and RREADY  = '1' then
                checks := checks + 1;
                sample(false, ar_addr);
                check_read(ar_addr, RDATA, RRESP);
            end if;

            if driver_done then
                idle_after_done := idle_after_done + 1;     -- laisse le moniteur finir (20 cycles)
                if idle_after_done = 20 then
                    hit_op := 0; hit_cible := 0;
                    for i in op_bin'range    loop if op_bin(i)    = '1' then hit_op    := hit_op + 1;    end if; end loop;
                    for i in cible_bin'range loop if cible_bin(i) = '1' then hit_cible := hit_cible + 1; end if; end loop;
                    cov_op    := 100.0 * real(hit_op)    / 2.0;
                    cov_cible := 100.0 * real(hit_cible) / 6.0;
                    cov_total := (cov_op + cov_cible) / 2.0;
                    report "--------------------------------------------------";
                    report "Transactions : " & integer'image(checks) & " (ecritures " & integer'image(n_wr)
                           & ", lectures " & integer'image(n_rd) & ", adresses invalides " & integer'image(n_err_addr) & ")";
                    report "Couverture fonctionnelle : " & integer'image(integer(cov_total * 10.0) / 10) & "."
                           & integer'image(integer(cov_total * 10.0) mod 10) & " %   (cp_op " & integer'image(hit_op)
                           & "/2 bins, cp_cible " & integer'image(hit_cible) & "/6 bins)";
                    report "Assertions de protocole : " & integer'image(a_checks) & " verifications, "
                           & integer'image(a_viol) & " violation(s)";
                    if errors = 0 and checks = TOTAL and a_viol = 0 then
                        report "PASS : " & integer'image(checks) & " transactions verifiees, 0 erreur, 0 violation d'assertion";
                    else
                        report "FAIL : " & integer'image(errors) & " erreur(s), " & integer'image(a_viol) & " violation(s), "
                               & integer'image(checks) & "/" & integer'image(TOTAL) & " transactions observees" severity failure;
                    end if;
                    report "--------------------------------------------------";
                    finish;
                end if;
            end if;
        end loop;
    end process;

    -- ------------------------------------------------------------------
    -- Assertions de protocole (verifiees a chaque front d'horloge apres le reset)
    -- ------------------------------------------------------------------
    protocol_assertions : process
        variable prev_bvalid, prev_bready, prev_rvalid, prev_rready : std_logic := '0';
        variable prev_rdata : std_logic_vector(31 downto 0) := (others => '0');
        variable prev_bresp, prev_rresp : std_logic_vector(1 downto 0) := "00";
        variable n_checks, n_viol : integer := 0;
    begin
        wait until ARESETn = '1';
        loop
            wait until rising_edge(ACLK);
            -- A1 : pas de valeur inconnue sur les sorties de handshake
            n_checks := n_checks + 1;
            if is_x(AWREADY) or is_x(WREADY) or is_x(BVALID) or is_x(ARREADY) or is_x(RVALID) then
                n_viol := n_viol + 1;
                report "ASSERTION A1 : valeur inconnue sur une sortie de handshake" severity error;
            end if;
            -- A2 : BVALID reste a 1, avec BRESP stable, tant que BREADY n'a pas repondu
            n_checks := n_checks + 1;
            if prev_bvalid = '1' and prev_bready = '0' then
                if BVALID /= '1' or BRESP /= prev_bresp then
                    n_viol := n_viol + 1;
                    report "ASSERTION A2 : BVALID ou BRESP a change avant BREADY" severity error;
                end if;
            end if;
            -- A3 : RVALID reste a 1, avec RDATA et RRESP stables, tant que RREADY n'a pas repondu
            n_checks := n_checks + 1;
            if prev_rvalid = '1' and prev_rready = '0' then
                if RVALID /= '1' or RDATA /= prev_rdata or RRESP /= prev_rresp then
                    n_viol := n_viol + 1;
                    report "ASSERTION A3 : RVALID, RDATA ou RRESP a change avant RREADY" severity error;
                end if;
            end if;
            -- A4 : les reponses ne valent jamais EXOKAY (01) ni DECERR (11)
            n_checks := n_checks + 1;
            if (BVALID = '1' and (BRESP = "01" or BRESP = "11")) or
               (RVALID = '1' and (RRESP = "01" or RRESP = "11")) then
                n_viol := n_viol + 1;
                report "ASSERTION A4 : code de reponse non prevu" severity error;
            end if;

            prev_bvalid := BVALID; prev_bready := BREADY; prev_bresp := BRESP;
            prev_rvalid := RVALID; prev_rready := RREADY; prev_rdata := RDATA; prev_rresp := RRESP;

            a_checks <= n_checks;
            a_viol   <= n_viol;
        end loop;
    end process;

end architecture;
