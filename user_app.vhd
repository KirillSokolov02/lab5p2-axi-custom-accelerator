-- Greg Stitt
-- University of Florida

library ieee;
use ieee.std_logic_1164.all;

use work.config_pkg.all;
use work.user_pkg.all;

entity user_app is
    port (
        clks : in std_logic_vector(CLKS_RANGE);
        rst  : in std_logic;

        -- memory-map interface
        mmap_wr_en   : in  std_logic;
        mmap_wr_addr : in  std_logic_vector(MMAP_ADDR_RANGE);
        mmap_wr_data : in  std_logic_vector(MMAP_DATA_RANGE);
        mmap_rd_en   : in  std_logic;
        mmap_rd_addr : in  std_logic_vector(MMAP_ADDR_RANGE);
        mmap_rd_data : out std_logic_vector(MMAP_DATA_RANGE)
        );
end user_app;

architecture default of user_app is

    signal go   : std_logic;
    signal done : std_logic;
    signal size : std_logic_vector(C_MEM_ADDR_WIDTH downto 0);

    signal mem_in_wr_data : std_logic_vector(C_MEM_IN_WIDTH-1 downto 0);
    signal mem_in_wr_addr : std_logic_vector(C_MEM_ADDR_WIDTH-1 downto 0);
    signal mem_in_rd_data : std_logic_vector(C_MEM_IN_WIDTH-1 downto 0);
    signal mem_in_rd_addr : std_logic_vector(C_MEM_ADDR_WIDTH-1 downto 0);
    signal mem_in_wr_en   : std_logic;
    signal mem_in_send    : std_logic;
    signal mem_in_ack     : std_logic;

    signal dp_received  : std_logic;
    signal dp_send      : std_logic;
    signal dp_ack       : std_logic;
    signal dp_delay_ack : std_logic;
    signal dp_data_out  : std_logic_vector(C_MEM_OUT_WIDTH-1 downto 0);
    signal dp_valid_out : std_logic;

    signal mem_out_wr_data  : std_logic_vector(C_MEM_OUT_WIDTH-1 downto 0);
    signal mem_out_wr_addr  : std_logic_vector(C_MEM_ADDR_WIDTH-1 downto 0);
    signal mem_out_rd_data  : std_logic_vector(C_MEM_OUT_WIDTH-1 downto 0);
    signal mem_out_rd_addr  : std_logic_vector(C_MEM_ADDR_WIDTH-1 downto 0);
    signal mem_out_wr_en    : std_logic;
    signal mem_out_received : std_logic;

begin

    -----------------------------------------------------------------------------
    -- Clock domain 1

    U_MMAP : entity work.memory_map
        port map (
            clk     => clks(0),
            rst     => rst,
            wr_en   => mmap_wr_en,
            wr_addr => mmap_wr_addr,
            wr_data => mmap_wr_data,
            rd_en   => mmap_rd_en,
            rd_addr => mmap_rd_addr,
            rd_data => mmap_rd_data,

            go              => go,
            size            => size,
            done            => done,
            mem_in_wr_data  => mem_in_wr_data,
            mem_in_wr_addr  => mem_in_wr_addr,
            mem_in_wr_en    => mem_in_wr_en,
            mem_out_rd_data => mem_out_rd_data,
            mem_out_rd_addr => mem_out_rd_addr
            );

    -- Input bram
    U_MEM_IN : entity work.ram(SYNC_READ)
        generic map (
            num_words  => 2**C_MEM_ADDR_WIDTH,
            word_width => C_MEM_IN_WIDTH,
            addr_width => C_MEM_ADDR_WIDTH)
        port map (
            clk   => clks(0),
            wen   => mem_in_wr_en,
            waddr => mem_in_wr_addr,
            wdata => mem_in_wr_data,
            raddr => mem_in_rd_addr,
            rdata => mem_in_rd_data);

    -- Generates reads from mem_in bram every time that the acknowledge is
    -- received from the destination domain. 

    U_MEM_IN_ADDR_GEN : entity work.addr_gen_in
        generic map (
            width => C_MEM_ADDR_WIDTH)
        port map (
            clk      => clks(0),
            rst      => rst,
            size     => size,
            go       => go,
            send     => mem_in_send,
            received => mem_in_ack,
            addr     => mem_in_rd_addr);

    -- handshake synchronizer for domain 1 to domain 2

    U_DP_IN_SYNC : entity work.handshake
        port map (
            clk_src   => clks(0),
            clk_dest  => clks(1),
            rst       => rst,
            go        => mem_in_send,
            delay_ack => dp_delay_ack,
            rcv       => dp_received,
            ack       => mem_in_ack);

    -----------------------------------------------------------------------------
    -- Clock domain 2
    -- Simple datapath

    U_DATAPATH : entity work.datapath
        port map (
            clk       => clks(1),
            rst       => rst,
            en        => C_1,
            valid_in  => dp_received,
            valid_out => dp_valid_out,
            data_in   => mem_in_rd_data,
            data_out  => dp_data_out);

    -- this register will hold a valid datapath output until the next valid
    -- output, which allows the destination in domain 1 to read it after the
    -- handshake.

    U_DP_OUTPUT : entity work.reg
        generic map (
            width => 17)
        port map (
            clk    => clks(1),
            rst    => rst,
            en     => dp_valid_out,
            input  => dp_data_out,
            output => mem_out_wr_data);

    -- creates the send signal for the second handshake. Note that this will
    -- create a pulse because dp_valid_out will never be valid for more than a
    -- cycle because the source will not send a second piece of data until the
    -- first one has been acknowledged.

    U_DP_SEND : entity work.reg
        generic map (
            width => 1)
        port map (
            clk       => clks(1),
            rst       => rst,
            en        => C_1,
            input(0)  => dp_valid_out,
            output(0) => dp_send);

    -- delay the acknowledge until the result has been transferred back to
    -- domain 1. Note that this basically will prevent the pipeline from ever
    -- having more than one valid set of data. This could be improved by adding
    -- a FIFO to buffer data. However, if you are going to use a FIFO, you can
    -- get rid of the handshake (see next part of lab).
    dp_delay_ack <= not dp_ack;

    -----------------------------------------------------------------------------
    -- Clock domain 1

    -- handshake synchronizer from domain 2 to domain 1
    U_DP_OUT_SYNC : entity work.handshake
        port map (
            clk_src   => clks(1),
            clk_dest  => clks(0),
            rst       => rst,
            go        => dp_send,
            delay_ack => C_0,
            rcv       => mem_out_received,
            ack       => dp_ack);

    -- Output memory
    U_MEM_OUT : entity work.ram(SYNC_READ)
        generic map (
            num_words  => 2**C_MEM_ADDR_WIDTH,
            word_width => C_MEM_OUT_WIDTH,
            addr_width => C_MEM_ADDR_WIDTH)
        port map (
            clk   => clks(0),
            wen   => mem_out_wr_en,
            waddr => mem_out_wr_addr,
            wdata => mem_out_wr_data,
            raddr => mem_out_rd_addr,
            rdata => mem_out_rd_data);

    -- output address generator that writes to memory every time it receives a
    -- message from the output handshake synchronizer.
    U_MEM_OUT_ADDR_GEN : entity work.addr_gen_out
        generic map (
            width => C_MEM_ADDR_WIDTH)
        port map (
            clk  => clks(0),
            rst  => rst,
            size => size,
            go   => go,
            en   => mem_out_received,
            addr => mem_out_wr_addr,
            wen  => mem_out_wr_en,
            done => done);


end default;
