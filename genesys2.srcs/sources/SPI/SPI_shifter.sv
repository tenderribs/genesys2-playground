`default_nettype none

// clock out one byte, MSB first
module SPI_shifter #(
    parameter int SysClkF,
    parameter int SpiClkF
) (
    input wire logic clk_i,  // FPGA system clock
    input wire logic [7:0] data_i,
    input wire logic valid_i,
    output logic sclk_o,  // SPI clock
    output logic sdin_o,  // SPI data out
    output logic ready_o
);

  localparam int ClkPerSclk = SysClkF / SpiClkF;
  localparam int HalfClkPerSclk = ClkPerSclk / 2;

  logic [$clog2(ClkPerSclk + 1)-1:0] sclk_sysclk_cnt = '0;

  logic [7:0] data_buf = '0;
  logic [2:0] bit_idx = '0;

  typedef enum {
    IDLE,
    SHIFT
  } state_t;
  state_t state = IDLE;

  assign ready_o = (state == IDLE);

  always_ff @(posedge clk_i) begin
    case (state)
      IDLE: begin
        if (ready_o && valid_i) begin
          // sample data bytes and move to next state
          data_buf <= data_i;
          state <= SHIFT;

          // reset all
          bit_idx <= '0;
          sclk_sysclk_cnt <= '0;
        end
      end
      SHIFT: begin
        // data sent on the falling sclk edge
        sclk_o <= (sclk_sysclk_cnt > HalfClkPerSclk - 1);
        sdin_o <= data_buf[7-bit_idx];  // MSB first

        // increment bit idx on sclk counter rollover
        if (sclk_sysclk_cnt == ClkPerSclk - 1) begin
          sclk_sysclk_cnt <= '0;
          bit_idx <= bit_idx + 1;

          if (bit_idx == 7) begin
            state <= IDLE;
          end
        end else begin
          sclk_sysclk_cnt <= sclk_sysclk_cnt + 1;
        end
      end
      default: state <= IDLE;
    endcase
  end
endmodule

`default_nettype wire
