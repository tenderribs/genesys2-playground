`default_nettype none

module UART_tx #(
    parameter int SysClkF,
    parameter int BaudRate
) (
    input wire logic Rst_SIN,
    input wire logic ClkSrc_CI,
    input wire logic Start_SI,
    input wire logic [7:0] TxBuf_DI,
    output logic Tx_SO,
    output logic TxReady_SO
);

  localparam int CycPerBit = SysClkF / BaudRate;

  typedef enum {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;
  state_t State, State_P;

  logic BaudTick_S;
  logic [$clog2(CycPerBit+1)-1:0] CycCnt_D, CycCnt_DP;  // number of cycles spend in State
  logic [7:0] BufIdx_D, BufIdx_DP;  // idx of bit in TxBuf_D to put on the line
  logic [7:0] TxBuf_D, TxBuf_DP;  // local clone of tx buffer

  assign TxReady_SO = (State_P == IDLE);
  assign BaudTick_S = (CycCnt_DP == CycPerBit - 1);

  always_ff @(posedge ClkSrc_CI, negedge Rst_SIN) begin
    if (~Rst_SIN) begin
      State_P   <= IDLE;
      CycCnt_DP <= '0;
      BufIdx_DP <= '0;
      TxBuf_DP  <= '0;
    end else begin
      State_P   <= State;
      CycCnt_DP <= CycCnt_D;
      BufIdx_DP <= BufIdx_D;
      TxBuf_DP  <= TxBuf_D;
    end
  end

  always_comb begin
    State = State_P;
    CycCnt_D = CycCnt_DP;
    BufIdx_D = BufIdx_DP;
    TxBuf_D = TxBuf_DP;

    // generate FSM ticks
    if (State_P == IDLE | BaudTick_S) CycCnt_D = '0;
    else CycCnt_D = CycCnt_DP + 1;

    case (State_P)
      IDLE: begin
        Tx_SO = 1;

        if (Start_SI) begin
          State   = START;
          TxBuf_D = TxBuf_DI;  // sample and save tx buffer input
        end
      end
      START: begin
        Tx_SO = '0;  // drive line low

        if (BaudTick_S) begin
          BufIdx_D = '0;
          State = DATA;
        end
      end
      DATA: begin
        Tx_SO = TxBuf_DP[BufIdx_DP];

        if (BaudTick_S) begin
          BufIdx_D = BufIdx_DP + 1;

          if (BufIdx_DP == 7) State = STOP;
        end
      end
      STOP: begin
        Tx_SO = '1;

        if (BaudTick_S) begin
          State = IDLE;
        end
      end
      default: State = IDLE;
    endcase
  end
endmodule
`default_nettype wire
