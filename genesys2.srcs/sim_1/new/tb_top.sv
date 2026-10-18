`timescale 1ns / 1ps

// Loopback testbench for top: a model of the PC sends bytes on uart_tx_i and
// checks that the same bytes come back on uart_rx_o.
//
// PC_CLK_PER_BIT is the PC's bit period in 200 MHz clock cycles. The nominal
// value for 115200 baud is 1736; override it to model a PC UART running
// slightly fast (e.g. 1733) or slow (e.g. 1739).
module tb_top #(
    parameter int PC_CLK_PER_BIT = 1736
);
  localparam string BurstMsg = "The quick brown fox jumps over the lazy dog 0123456789";

  logic clk = 0;
  logic pc_tx = 1;  // PC -> FPGA
  logic fpga_tx;  // FPGA -> PC
  logic [1:0] led;

  always #2.5 clk = ~clk;  // 200 MHz

  top dut (
      .sysclk_p (clk),
      .sysclk_n (~clk),
      .btnc     (1'b0),
      .uart_tx_i(pc_tx),
      .led_o    (led),
      .uart_rx_o(fpga_tx)
  );

  logic [7:0] expected[$];  // bytes sent but not yet echoed
  int n_sent = 0, n_ok = 0, n_err = 0;

  // PC transmitter: start bit, 8 data bits LSB first, 1 stop bit
  task automatic send(input logic [7:0] b);
    expected.push_back(b);
    n_sent++;
    pc_tx = 0;
    repeat (PC_CLK_PER_BIT) @(posedge clk);
    for (int i = 0; i < 8; i++) begin
      pc_tx = b[i];
      repeat (PC_CLK_PER_BIT) @(posedge clk);
    end
    pc_tx = 1;
    repeat (PC_CLK_PER_BIT) @(posedge clk);
  endtask

  // PC receiver: samples the FPGA's TX line in the middle of each bit
  initial begin
    logic [7:0] got, exp;
    forever begin
      @(negedge fpga_tx);
      repeat (PC_CLK_PER_BIT / 2) @(posedge clk);
      for (int i = 0; i < 8; i++) begin
        repeat (PC_CLK_PER_BIT) @(posedge clk);
        got[i] = fpga_tx;
      end
      repeat (PC_CLK_PER_BIT) @(posedge clk);

      if (expected.size() == 0) begin
        $error("unexpected byte 0x%02h", got);
        n_err++;
      end else begin
        exp = expected.pop_front();
        if (fpga_tx !== 1'b1) begin
          $error("framing error (stop bit low) on byte 0x%02h", got);
          n_err++;
        end else if (got !== exp) begin
          $error("expected 0x%02h, got 0x%02h", exp, got);
          n_err++;
        end else begin
          n_ok++;
        end
      end
    end
  end

  initial begin
    $display("PC bit period: %0d clock cycles", PC_CLK_PER_BIT);
    repeat (2000) @(posedge clk);

    // single bytes with idle time in between
    foreach (BurstMsg[i]) begin
      if (i >= 3) break;
      send(BurstMsg[i]);
      repeat (30000) @(posedge clk);
    end

    // back-to-back burst
    foreach (BurstMsg[i]) send(BurstMsg[i]);

    repeat (20 * 10 * PC_CLK_PER_BIT) @(posedge clk);  // let the echoes drain

    n_err += expected.size();  // bytes that never came back
    $display("sent %0d, echoed correctly %0d, errors %0d", n_sent, n_ok, n_err);
    if (n_err == 0 && n_ok == n_sent) $display("TEST PASSED");
    else $display("TEST FAILED");
    $finish;
  end
endmodule
