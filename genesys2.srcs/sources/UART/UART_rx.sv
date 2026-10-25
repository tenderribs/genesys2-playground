`default_nettype none
module UART_rx #(
    parameter int SysClkF,
    parameter int BaudRate
) (
    input wire logic Rst_SIN,
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
  state_t State, State_P;

  logic BaudTick_S, HalfBaudTick_S;
  logic [$clog2(ClkPerBaud+1)-1:0] CycCnt_D, CycCnt_DP;  // space to count cycles through two bauds

  logic [1:0] RxSyncBuf_D, RxSyncBuf_DP;
  logic [$clog2(8+1)-1:0] BufIdx_D, BufIdx_DP;
  logic RxSync_S;


  always_ff @(posedge Clk_CI, negedge Rst_SIN) begin
    if (~Rst_SIN) begin
      State_P <= IDLE;
      RxSyncBuf_DP <= '1;  // init val 1 because UART line active low
      BufIdx_DP <= '0;
      CycCnt_DP <= '0;
    end else begin
      State_P <= State;
      RxSyncBuf_DP <= RxSyncBuf_D;
      BufIdx_DP <= BufIdx_D;
      CycCnt_DP <= CycCnt_D;
    end
  end

  assign RxSync_S = RxSyncBuf_DP[1];
  assign BaudTick_S = (CycCnt_DP == ClkPerBaud - 1);
  assign HalfBaudTick_S = (CycCnt_DP == ClkPerHalfBaud - 1);

  always_comb begin
    State = State_P;
    RxSyncBuf_D = {RxSyncBuf_DP[0], RxRaw_SI};
    BufIdx_D = BufIdx_DP;

    // generate FSM ticks
    if (State_P == IDLE | BaudTick_S) CycCnt_D = '0;
    else CycCnt_D = CycCnt_DP + 1;

    case (State_P)
      IDLE: begin
        Done_SO = '0;
        if (~RxSync_S) begin  // TX started
          State = START;
        end
      end
      START: begin
        if (HalfBaudTick_S) begin
          if (~RxSync_S) begin  // confirm is real TX start
            BufIdx_D = '0;
            State = SAMPLING;
          end else State = IDLE;
        end
      end
      SAMPLING: begin
        if (HalfBaudTick_S) begin  // sample the line in the middle
          if (BufIdx_DP == 7) State = OUTPUT;

          RxBuf_DO[BufIdx_DP] = RxSync_S;
          BufIdx_D = BufIdx_DP + 1;
        end
      end
      OUTPUT: begin
        if (HalfBaudTick_S) begin
          Done_SO = RxSync_S;
          State   = IDLE;
        end
      end
      default: State = IDLE;
    endcase
  end
endmodule
`default_nettype wire
