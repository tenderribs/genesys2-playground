module BtnPulse #(
    parameter int SysClkF = 200_000_000
) (
    input  logic clk_i,
    input  logic btn_i,
    output logic pulse_o
);
  localparam int DbncCycles = SysClkF * 10e-3;  // 10 ms debounce

  // debounced one-shot push button circuit
  logic [1:0] btn_sync = '0;
  logic [$clog2(DbncCycles+1)-1:0] debounce_cnt = '0;

  always_ff @(posedge clk_i) begin
    btn_sync <= {btn_sync[0], btn_i};  // 2-FF synchronizer
    pulse_o  <= '0;

    if (!btn_sync[1]) begin
      debounce_cnt <= '0;
    end else if (debounce_cnt < DbncCycles) begin
      debounce_cnt <= debounce_cnt + 1;
      pulse_o <= (debounce_cnt == DbncCycles - 1);
    end
  end
endmodule
