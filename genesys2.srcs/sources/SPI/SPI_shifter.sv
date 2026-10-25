`default_nettype none

// clock out one byte, MSB first
module SPI_shifter #(
    parameter int SysClkF,
    parameter int SpiClkF
) (
    input wire logic Rst_SIN,
    input wire logic Clk_CI,  // FPGA system clock
    input wire logic [7:0] Data_DI,
    input wire logic Valid_SI,
    output logic Sclk_SO,  // SPI clock
    output logic Sdin_SO,  // SPI data out
    output logic Ready_SO
);

  localparam int ClkPerSclk = SysClkF / SpiClkF;
  localparam int HalfClkPerSclk = ClkPerSclk / 2;

  logic [$clog2(ClkPerSclk + 1)-1:0] SysClkCnt_D, SysClkCnt_DP;
  logic [7:0] DataBuf_D, DataBuf_DP;
  logic [2:0] BitIdx_D, BitIdx_DP;

  typedef enum {
    IDLE,
    SHIFT
  } state_t;
  state_t State, State_P;

  assign Ready_SO = (State_P == IDLE);

  always_ff @(posedge Clk_CI, negedge Rst_SIN) begin
    if (~Rst_SIN) begin
      SysClkCnt_DP <= SysClkCnt_D;
      DataBuf_DP <= DataBuf_D;
      BitIdx_DP <= BitIdx_D;
    end else begin
      SysClkCnt_DP <= '0;
      DataBuf_DP <= '0;
      BitIdx_DP <= '0;
    end
  end

  always_comb begin
    SysClkCnt_D = SysClkCnt_DP;
    DataBuf_D = DataBuf_DP;
    BitIdx_D = BitIdx_DP;

    case (State_P)
      IDLE: begin
        if (Ready_SO && Valid_SI) begin
          // sample data bytes and move to next state
          DataBuf_D = Data_DI;

          State = SHIFT;
          BitIdx_D = '0;
          SysClkCnt_D = '0;
        end
      end
      SHIFT: begin
        // data sent on the falling sclk edge
        Sclk_SO = (SysClkCnt_DP > HalfClkPerSclk - 1);
        Sdin_SO = DataBuf_DP[7-BitIdx_DP];  // MSB first

        // increment bit idx on sclk counter rollover
        if (SysClkCnt_DP == ClkPerSclk - 1) begin
          if (BitIdx_DP == 7) State = IDLE;

          BitIdx_D = BitIdx_DP + 1;
          SysClkCnt_D = '0;
        end else begin
          SysClkCnt_D = SysClkCnt_DP + 1;
        end
      end
      default: State = IDLE;
    endcase
  end
endmodule

`default_nettype wire
