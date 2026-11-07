-- Esclave AXI4-Lite : traduction VHDL du module Verilog axi4lite_slave.v
-- 4 registres : 0x00 CTRL (lecture/ecriture), 0x04 STATUS (lecture seule, vaut status_in),
--                0x08 DATA0, 0x0C DATA1 (lecture/ecriture). Autre adresse : reponse SLVERR.
-- Deux machines a etats independantes : une pour l'ecriture, une pour la lecture.
library ieee;
use ieee.std_logic_1164.all;

entity axi4lite_slave is
    port (
        ACLK     : in  std_logic;
        ARESETn  : in  std_logic;
        -- canal AW
        AWADDR   : in  std_logic_vector(7 downto 0);
        AWVALID  : in  std_logic;
        AWREADY  : out std_logic;
        -- canal W
        WDATA    : in  std_logic_vector(31 downto 0);
        WSTRB    : in  std_logic_vector(3 downto 0);
        WVALID   : in  std_logic;
        WREADY   : out std_logic;
        -- canal B
        BRESP    : out std_logic_vector(1 downto 0);
        BVALID   : out std_logic;
        BREADY   : in  std_logic;
        -- canal AR
        ARADDR   : in  std_logic_vector(7 downto 0);
        ARVALID  : in  std_logic;
        ARREADY  : out std_logic;
        -- canal R
        RDATA    : out std_logic_vector(31 downto 0);
        RRESP    : out std_logic_vector(1 downto 0);
        RVALID   : out std_logic;
        RREADY   : in  std_logic;
        -- valeur lue a l'adresse 0x04
        status_in : in std_logic_vector(31 downto 0)
    );
end entity;

architecture rtl of axi4lite_slave is
    constant OKAY   : std_logic_vector(1 downto 0) := "00";
    constant SLVERR : std_logic_vector(1 downto 0) := "10";

    signal reg0, reg2, reg3 : std_logic_vector(31 downto 0);   -- CTRL, DATA0, DATA1

    type wstate_t is (IDLE, WRITE_ST, RESP_ST);
    signal wstate : wstate_t;
    type rstate_t is (RIDLE, RREAD, RWAIT);
    signal rstate : rstate_t;

    -- ecrit seulement les octets autorises par WSTRB
    function merge(old, nw : std_logic_vector(31 downto 0);
                   strb : std_logic_vector(3 downto 0)) return std_logic_vector is
        variable r : std_logic_vector(31 downto 0);
    begin
        for i in 0 to 3 loop
            if strb(i) = '1' then
                r(8*i+7 downto 8*i) := nw(8*i+7 downto 8*i);
            else
                r(8*i+7 downto 8*i) := old(8*i+7 downto 8*i);
            end if;
        end loop;
        return r;
    end function;
begin

    -- ---------------- ecriture ----------------
    write_fsm : process (ACLK)
    begin
        if rising_edge(ACLK) then
            if ARESETn = '0' then
                wstate  <= IDLE;
                AWREADY <= '0';
                WREADY  <= '0';
                BVALID  <= '0';
                BRESP   <= OKAY;
                reg0 <= (others => '0');
                reg2 <= (others => '0');
                reg3 <= (others => '0');
            else
                case wstate is
                    when IDLE =>
                        if AWVALID = '1' and WVALID = '1' then
                            AWREADY <= '1';
                            WREADY  <= '1';
                            wstate  <= WRITE_ST;
                        end if;
                    when WRITE_ST =>
                        AWREADY <= '0';
                        WREADY  <= '0';
                        BRESP   <= OKAY;
                        case AWADDR is
                            when x"00"  => reg0 <= merge(reg0, WDATA, WSTRB);
                            when x"04"  => null;                      -- STATUS en lecture seule : ignore
                            when x"08"  => reg2 <= merge(reg2, WDATA, WSTRB);
                            when x"0C"  => reg3 <= merge(reg3, WDATA, WSTRB);
                            when others => BRESP <= SLVERR;           -- adresse invalide
                        end case;
                        BVALID <= '1';
                        wstate <= RESP_ST;
                    when RESP_ST =>
                        if BREADY = '1' then
                            BVALID <= '0';
                            wstate <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- ---------------- lecture ----------------
    read_fsm : process (ACLK)
    begin
        if rising_edge(ACLK) then
            if ARESETn = '0' then
                rstate  <= RIDLE;
                ARREADY <= '0';
                RVALID  <= '0';
                RDATA   <= (others => '0');
                RRESP   <= OKAY;
            else
                case rstate is
                    when RIDLE =>
                        if ARVALID = '1' then
                            ARREADY <= '1';
                            rstate  <= RREAD;
                        end if;
                    when RREAD =>
                        ARREADY <= '0';
                        RRESP   <= OKAY;
                        case ARADDR is
                            when x"00"  => RDATA <= reg0;
                            when x"04"  => RDATA <= status_in;
                            when x"08"  => RDATA <= reg2;
                            when x"0C"  => RDATA <= reg3;
                            when others => RDATA <= (others => '0'); RRESP <= SLVERR;
                        end case;
                        RVALID <= '1';
                        rstate <= RWAIT;
                    when RWAIT =>
                        if RREADY = '1' then
                            RVALID <= '0';
                            rstate <= RIDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture;
