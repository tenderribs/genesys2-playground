`default_nettype none

module UART_tx #(
    parameter int SysClkF,
    parameter int BAUDRATE
) (
    input wire logic clk_i,
    input wire logic start_i,
    input wire logic [7:0] tx_buf_i,
    output logic tx_o,
    output logic tx_ready_o
);

  localparam int CycPerBit = SysClkF / BAUDRATE;

  typedef enum {
    IDLE,
    START,
    DATA,
    STOP
  } state_t;
  state_t state = IDLE;

  logic baud_tick;
  logic [$clog2(CycPerBit+1)-1:0] cyc_cnt = '0;  // number of cycles spend in state
  logic [7:0] buf_idx = '0;  // idx of bit in tx_buf to put on the line
  logic [7:0] tx_buf = '0;  // local clone of tx buffer

  assign tx_ready_o = (state == IDLE);
  assign baud_tick  = (cyc_cnt == CycPerBit - 1);

  always_ff @(posedge clk_i) begin
    // generate FSM ticks
    if (state == IDLE | baud_tick) cyc_cnt <= '0;
    else cyc_cnt <= cyc_cnt + 1;

    case (state)
      IDLE: begin
        tx_o <= '1;

        if (start_i) begin
          state  <= START;
          tx_buf <= tx_buf_i;  // sample and save tx buffer input
        end
      end
      START: begin
        tx_o <= '0;  // drive line low

        if (baud_tick) begin
          buf_idx <= '0;
          state   <= DATA;
        end
      end
      DATA: begin
        tx_o <= tx_buf[buf_idx];

        if (baud_tick) begin
          buf_idx <= buf_idx + 1;

          if (buf_idx == 7) state <= STOP;
        end
      end
      STOP: begin
        tx_o <= '1;

        if (baud_tick) begin
          state <= IDLE;
        end
      end
      default: state <= IDLE;
    endcase
  end
endmodule
`default_nettype wire
