`default_nettype none

module UART_tx #(
    parameter int SysClkF,
    parameter int BAUDRATE
) (
    input wire logic ClkSrc_CI,
    input wire logic Start_SI,
    input wire logic [7:0] TxBuf_DI,
    output logic Tx_SO,
    output logic TxReady_SO
);

  localparam int CycPerBit = SysClkF / BAUDRATE;

  typedef enum {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;
  state_t state_;

  logic BaudTick_D;
  logic [$clog2(CycPerBit+1)-1:0] CycCnt_D = '0;  // number of cycles spend in State
  logic [7:0] BufIdx_D = '0;  // idx of bit in TxBuf_D to put on the line
  logic [7:0] TxBuf_D = '0;  // local clone of tx buffer

  assign TxReady_SO = (State == IDLE);
  assign BaudTick_D = (CycCnt_D == CycPerBit - 1);

  always_ff @(posedge ClkSrc_CI) begin
    // generate FSM ticks
    if (State == IDLE | BaudTick_D) CycCnt_D <= '0;
    else CycCnt_D <= CycCnt_D + 1;

    case (State)
      IDLE: begin
        Tx_SO <= '1;

        if (Start_SI) begin
          State   <= START;
          TxBuf_D <= TxBuf_DI;  // sample and save tx buffer input
        end
      end
      START: begin
        Tx_SO <= '0;  // drive line low

        if (BaudTick_D) begin
          BufIdx_D <= '0;
          State <= DATA;
        end
      end
      DATA: begin
        Tx_SO <= TxBuf_D[BufIdx_D];

        if (BaudTick_D) begin
          BufIdx_D <= BufIdx_D + 1;

          if (BufIdx_D == 7) State <= STOP;
        end
      end
      STOP: begin
        Tx_SO <= '1;

        if (BaudTick_D) begin
          State <= IDLE;
        end
      end
      default: State <= IDLE;
    endcase
  end
endmodule
`default_nettype wire
