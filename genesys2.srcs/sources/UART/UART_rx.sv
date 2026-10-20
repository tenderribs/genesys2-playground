module UART_rx #(
    parameter int SysClkF,
    parameter int BAUDRATE
) (
    input logic clk_i,
    input logic rx_raw_i,
    output logic [7:0] rx_buf_o,
    output logic done_o
);

  localparam int ClkPerBaud = SysClkF / BAUDRATE;
  localparam int ClkPerHalfBaud = ClkPerBaud / 2;

  typedef enum {
    IDLE,
    START,
    SAMPLING,
    OUTPUT
  } state_t;
  state_t state = IDLE;

  logic baud_tick, half_baud_tick;
  logic [$clog2(ClkPerBaud+1)-1:0] cyc_cnt = '0;  // space to count cycles through two bauds

  logic [1:0] rx_sync_buf = '1;
  logic [$clog2(8+1)-1:0] buf_idx = '0;

  logic rx_sync;
  assign rx_sync = rx_sync_buf[1];

  assign half_baud_tick = (cyc_cnt == ClkPerHalfBaud - 1);
  assign baud_tick = (cyc_cnt == ClkPerBaud - 1);

  always_ff @(posedge clk_i) begin
    // 2-FF synchronizer
    rx_sync_buf <= {rx_sync_buf[0], rx_raw_i};

    // generate FSM ticks
    if (state == IDLE | baud_tick) cyc_cnt <= '0;
    else cyc_cnt <= cyc_cnt + 1;

    case (state)
      IDLE: begin
        done_o <= '0;
        if (~rx_sync) begin  // TX started
          state <= START;
        end
      end
      START: begin
        if (half_baud_tick) begin
          if (~rx_sync) begin  // confirm is real TX start
            buf_idx <= '0;
            state   <= SAMPLING;
          end else state <= IDLE;
        end
      end
      SAMPLING: begin
        if (half_baud_tick) begin  // sample the line in the middle
          rx_buf_o[buf_idx] <= rx_sync;

          buf_idx <= buf_idx + 1;

          if (buf_idx == 7) begin
            state <= OUTPUT;
          end
        end
      end
      OUTPUT: begin
        if (half_baud_tick) begin
          done_o <= rx_sync;
          state  <= IDLE;
        end
      end
      default: state <= IDLE;
    endcase

  end
endmodule
