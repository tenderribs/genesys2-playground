`default_nettype none
module Blinky (
    input wire logic clk_i,
    output logic [0:0] led_o
);
  logic [27:0] cnt = '0;

  always_ff @(posedge clk_i) begin
    cnt <= cnt + 1;
  end

  assign led_o = cnt[27];
endmodule
`default_nettype wire
