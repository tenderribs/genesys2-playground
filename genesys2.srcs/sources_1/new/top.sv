module top (
    input logic sysclk_p,
    input logic sysclk_n,
    input logic btnc,
    input logic uart_tx_i,
    output logic [1:0] led_o,
    output logic uart_rx_o
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

  // LED for debugging
  Blinky blinky (
      .clk_i(clk),
      .led_o(led_o[0])
  );

  // Convert push button to pulse
  BtnPulse #(
      .SYSCLK_F(SysClkF)
  ) btn_pulse (
      .clk_i  (clk),
      .btn_i  (btnc),
      .pulse_o(btnc_pulse)
  );

  // PC -> FPGA
  UART_rx #(
      .SYSCLK_F(SysClkF),
      .BAUDRATE(BaudRate)
  ) uart_rx (
      .clk_i(clk),
      .rx_raw_i(uart_tx_i),
      .rx_buf_o(data_buf),
      .done_o(rx_done)
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
      .SYSCLK_F(SysClkF),
      .BAUDRATE(BaudRate)
  ) uart_tx (
      .clk_i(clk),
      .start_i(tx_start),
      .tx_buf_i(hold_buf),
      .tx_ready_o(tx_ready),
      .tx_o(uart_rx_o)
  );

  assign led_o[1] = btnc;
endmodule
