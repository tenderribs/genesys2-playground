`default_nettype none

module OLED_SPI #(
    parameter int SysClkF
) (
    input wire logic clk_i,
    output logic dc_o,  // data => 1, cmd => 0
    output logic res_no,
    output logic sclk_o,
    output logic sdin_o,
    output logic vbat_o,
    output logic vdd_o
);

  localparam int ClkPerMs = SysClkF / 1000;

  typedef enum {
    PWR_VDD,
    RESET,
    INIT,
    PWR_VBAT,
    CLEAR,
    DISP_ON
  } state_t;
  state_t state = PWR_VDD;

  logic [7:0] spi_data = '0;
  logic spi_valid, spi_ready;

  SPI_shifter #(
      .SysClkF(SysClkF),
      .SpiClkF(10_000_000)
  ) spi_shifter (
      .clk_i  (clk_i),
      .data_i (spi_data),
      .valid_i(spi_valid),
      .sclk_o (sclk_o),
      .sdin_o (sdin_o),
      .ready_o(spi_ready)
  );

  // generate pulse every ms with counter
  logic [$clog2(ClkPerMs+1)-1:0] ms_sysclk_cnt = '0;
  logic [$clog2(100+1)-1:0] ms_ctr = '0;  // count ms pulse up to 100ms

  // pulse every ms
  logic ms_tick;
  assign ms_tick = (ms_sysclk_cnt == (ClkPerMs - 1));
  always_ff @(posedge clk_i) begin
    if (ms_sysclk_cnt == ClkPerMs - 1) ms_sysclk_cnt <= '0;
    else ms_sysclk_cnt <= ms_sysclk_cnt + 1;
  end

  localparam int NumCmds = 12;
  localparam logic [7:0] InitCmds[NumCmds] = '{
      8'h8D,
      8'h14,  // Charge pump enable
      8'hD9,
      8'hF1,  // Set pre-charge period
      8'h81,
      8'h0F,  // Contrast control
      8'hA0,  // Column inversion disable
      8'hC0,  // Scan direction
      8'hDA,
      8'h00,  // COM pins configuration
      8'h20,
      8'h00  // Addressing mode: horizontal
  };
  logic [$clog2(NumCmds+1)-1:0] init_cmd_idx = '0;

  localparam int NumCols = 128;
  localparam int NumRows = 32;
  logic [$clog2(NumCols+1)-1:0] col_idx = '0;
  logic [$clog2(NumRows+1)-1:0] row_idx = '0;
  logic [$clog2(NumCols*NumRows+1)-1:0] disp_buf_idx = '0;
  logic [7:0] disp_buf[NumCols*NumRows];

  always_ff @(posedge clk_i) begin
    vdd_o  <= '0;
    res_no <= !(state == RESET);
    vbat_o <= state inside {PWR_VDD, RESET, INIT};  // active low
    dc_o   <= '1;

    // https://digilent.com/reference/programmable-logic/genesys-2/reference-manual#oled
    case (state)
      PWR_VDD: begin
        // 1. power up VDD by pulling OLED_VDD low. Wait 1ms
        if (ms_tick) state <= RESET;
      end
      RESET: begin
        // 2. pulse RES# low for at least 3us (so wait 1ms)
        if (ms_tick) begin
          state <= INIT;
          init_cmd_idx <= '0;
        end
      end
      INIT: begin
        // 3. send initialization / configuration commands
        dc_o <= '0;  // data <= 1, cmd <= 0

        // start new SPI logic [7:0] transfer
        spi_data <= InitCmds[init_cmd_idx];
        spi_valid <= '1;

        if (spi_valid && spi_ready) begin
          if (init_cmd_idx == NumCmds - 1) begin
            state  <= PWR_VBAT;
            ms_ctr <= '0;
          end else begin
            init_cmd_idx <= init_cmd_idx + 1;
            spi_valid <= '0;
          end
        end
      end
      PWR_VBAT: begin
        // 4. Power up VBAT by pulling OLED_VBAT low. Wait 100ms for voltage to stabilize.
        if (ms_tick) ms_ctr <= ms_ctr + 1;

        if (ms_ctr == 100) begin
          state <= CLEAR;
          disp_buf_idx <= '0;
        end
      end
      CLEAR: begin
        // 5. Clear screen by writing zero to the display buffer.
        dc_o <= '1;  // data <= 1, cmd <= 0

        // write zero logic [7:0]s to display
        spi_data <= '0;
        disp_buf[disp_buf_idx] <= '0;
        spi_valid <= '1;

        if (spi_valid && spi_ready) begin

          if (disp_buf_idx == NumRows * NumCols - 1) begin
            state <= DISP_ON;
            disp_buf_idx <= '0;
          end else begin
            disp_buf_idx <= disp_buf_idx + 1;
            spi_valid <= '0;
          end
        end
      end
      DISP_ON: begin
        // TBD haven't gotten farther than this
        dc_o <= '0;  // data <= 1, cmd <= 0
      end
      default: state <= PWR_VDD;
    endcase
  end
endmodule

`default_nettype wire
