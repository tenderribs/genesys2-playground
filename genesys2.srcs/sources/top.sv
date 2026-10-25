`default_nettype none

module top (
    input wire logic sysclk_p,
    input wire logic sysclk_n,
    input wire logic btnc,
    input wire logic uart_tx_i,
    output logic uart_rx_o,
    output logic [1:0] led_o,
    output logic oled_dc,
    output logic oled_res,
    output logic oled_sclk,
    output logic oled_sdin,
    output logic oled_vbat,
    output logic oled_vdd
);
  localparam int SysClkF  = 200e6;   // 10 ms at 200 MHz
  localparam int BaudRate = 115200;

  logic clk;
  logic btnc_pulse;
  logic rx_done;

  logic [7:0] data_buf = '0;
  logic [7:0] hold_buf = '0;

  logic pending = '0;
  logic tx_ready;
  logic tx_start;

  IBUFDS u_clk_buf (
      .I (sysclk_p),
      .IB(sysclk_n),
      .O (clk)
  );

  logic Rst_SIN = '0;
  always_ff @(posedge clk) Rst_SIN <= '1;  // low for the first cycle, then released

  // LED for debugging
  Blinky blinky (
      .clk_i(clk),
      .led_o(led_o[0])
  );

  // Convert push button to pulse
  BtnPulse #(
      .SysClkF(SysClkF)
  ) btn_pulse (
      .clk_i  (clk),
      .btn_i  (btnc),
      .pulse_o(btnc_pulse)
  );

  // PC -> FPGA
  UART_rx #(
      .SysClkF (SysClkF),
      .BaudRate(BaudRate)
  ) uart_rx (
      .Rst_SIN (Rst_SIN),
      .Clk_CI  (clk),
      .RxRaw_SI(uart_tx_i),
      .RxBuf_DO(data_buf),
      .Done_SO (rx_done)
  );

  // put RX buf into holding buf while TX busy
  always_ff @(posedge clk) begin
    if (rx_done) begin
      hold_buf <= data_buf;
      pending  <= '1;
    end else if (tx_start) begin
      pending <= '0;
    end
  end
  assign tx_start = pending & tx_ready;

  // FPGA -> PC
  UART_tx #(
      .SysClkF (SysClkF),
      .BaudRate(BaudRate)
  ) uart_tx (
      .Rst_SIN(Rst_SIN),
      .ClkSrc_CI(clk),
      .Start_SI(tx_start),
      .TxBuf_DI(hold_buf),
      .Tx_SO(uart_rx_o),
      .TxReady_SO(tx_ready)
  );

  assign led_o[1] = btnc;

  // OLED screen over SPI
  OLED_SPI #(
      .SysClkF(SysClkF)
  ) oled_spi (
      .Rst_SIN(Rst_SIN),
      .Clk_CI(clk),
      .Dc_SO(oled_dc),
      .Rst_SON(oled_res),
      .Sclk_SO(oled_sclk),
      .Sdin_SO(oled_sdin),
      .VBat_SON(oled_vbat),
      .Vdd_SO(oled_vdd)
  );
endmodule
`default_nettype wire
