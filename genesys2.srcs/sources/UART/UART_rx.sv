`default_nettype none
module UART_rx #(
    parameter int SysClkF,
    parameter int BaudRate
) (
    input wire logic Clk_CI,
    input wire logic RxRaw_SI,
    output logic [7:0] RxBuf_DO,
    output logic Done_SO
);

  localparam int ClkPerBaud = SysClkF / BaudRate;
  localparam int ClkPerHalfBaud = ClkPerBaud / 2;

  typedef enum {
    IDLE,
    START,
    SAMPLING,
    OUTPUT
  } state_t;
  state_t State = IDLE;

  logic BaudTick_S, HalfBaudTick_S;
  logic [$clog2(ClkPerBaud+1)-1:0] CycCnt_D = '0;  // space to count cycles through two bauds

  logic [1:0] RxSyncBuf_D = '1;
  logic [$clog2(8+1)-1:0] BufIdx_D = '0;

  logic RxSync_S;
  assign RxSync_S = RxSyncBuf_D[1];

  assign HalfBaudTick_S = (CycCnt_D == ClkPerHalfBaud - 1);
  assign BaudTick_S = (CycCnt_D == ClkPerBaud - 1);

  always_ff @(posedge Clk_CI) begin
    // 2-FF synchronizer
    RxSyncBuf_D <= {RxSyncBuf_D[0], RxRaw_SI};

    // generate FSM ticks
    if (State == IDLE | BaudTick_S) CycCnt_D <= '0;
    else CycCnt_D <= CycCnt_D + 1;

    case (State)
      IDLE: begin
        Done_SO <= '0;
        if (~RxSync_S) begin  // TX started
          State <= START;
        end
      end
      START: begin
        if (HalfBaudTick_S) begin
          if (~RxSync_S) begin  // confirm is real TX start
            BufIdx_D <= '0;
            State <= SAMPLING;
          end else State <= IDLE;
        end
      end
      SAMPLING: begin
        if (HalfBaudTick_S) begin  // sample the line in the middle
          RxBuf_DO[BufIdx_D] <= RxSync_S;

          BufIdx_D <= BufIdx_D + 1;

          if (BufIdx_D == 7) begin
            State <= OUTPUT;
          end
        end
      end
      OUTPUT: begin
        if (HalfBaudTick_S) begin
          Done_SO <= RxSync_S;
          State   <= IDLE;
        end
      end
      default: State <= IDLE;
    endcase

  end
endmodule
`default_nettype wire
