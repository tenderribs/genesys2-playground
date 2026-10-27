`timescale 1ns / 1ps

// Testbench for OLED_SPI: a model of the display's SSD1306 controller receives
// the SPI bytes and checks them, together with the power-up sequence, against
// the Digilent reference manual and the SSD1306 datasheet:
//   https://digilent.com/reference/programmable-logic/genesys-2/reference-manual#oled
//
// SysClkF is the FPGA clock frequency. Keep the board's 200 MHz for the SPI
// timing checks to be meaningful; a lower value only makes the run faster.
module tb_oled #(
    parameter int SysClkF = 200_000_000
);
  localparam realtime ClkPeriod = 1e9 / SysClkF;  // ns

  // SSD1306 4-wire SPI timing (datasheet "4-wire Serial interface characteristics")
  localparam realtime TCycle = 100;  // SCLK period
  localparam realtime TClkL = 20;  // SCLK low time
  localparam realtime TClkH = 20;  // SCLK high time
  localparam realtime TDsw = 15;  // SDIN setup before rising SCLK
  localparam realtime TDhw = 15;  // SDIN hold after rising SCLK
  localparam realtime TAs = 15;  // D/C# setup before a byte's last rising SCLK
  localparam realtime TAh = 15;  // D/C# hold after a rising SCLK

  // power-up sequence (Digilent reference manual)
  localparam realtime TVddToRes = 1ms;  // VDD on -> RES# low
  localparam realtime TResLow = 3us;  // RES# low pulse width
  localparam realtime TVbatSettle = 100ms;  // VBAT on -> first display write
  localparam realtime Timeout = 150ms;

  // The expected bytes are written out here on purpose instead of reusing the
  // DUT's table: the testbench encodes the spec, so a typo in the RTL shows up.
  localparam int NumInitCmds = 12;
  localparam logic [7:0] InitCmds[NumInitCmds] = '{
      8'h8D,
      8'h14,  // Charge pump enable
      8'hD9,
      8'hF1,  // Set pre-charge period
      8'h81,
      8'h0F,  // Contrast control
      8'hA0,  // Column inversion disable
      8'hC0,  // Scan direction
      8'hDA,
      8'h00,  // COM pins configuration
      8'h20,
      8'h00  // Addressing mode: horizontal
  };
  localparam int DisplayBytes = 128 * 32 / 8;  // 1 bit per pixel
  localparam logic [7:0] DisplayOn = 8'hAF;

  localparam int RstCycles = 10;  // how long the FPGA reset is held

  logic clk = 0;
  logic rst_n = 1;
  logic dc, res_n, sclk, sdin, vbat, vdd;

  always #(ClkPeriod / 2) clk = ~clk;

  // Assert the reset between clock edges so the DUT's asynchronous reset path
  // is exercised (at time 0 there would be no edge on rst_n to trigger it),
  // then release it synchronously with a non-blocking assignment like a
  // flip-flop would, so it doesn't race with the DUT's clock edge.
  initial begin
    #1 rst_n = 0;
    repeat (RstCycles) @(posedge clk);
    rst_n <= 1;
  end

  OLED_SPI #(
      .SysClkF(SysClkF)
  ) dut (
      .Rst_SIN(rst_n),
      .Clk_CI (clk),
      .Dc_SO  (dc),
      .Rst_SON(res_n),
      .Sclk_SO(sclk),
      .Sdin_SO(sdin),
      .VBat_SON(vbat),
      .Vdd_SO (vdd)
  );

  int n_err = 0;

  // $display instead of $error: Verilator stops at the first $error, but the
  // test should keep going and report everything it finds
  function automatic void fail(string msg);
    n_err++;
    if (n_err <= 20) $display("Error: [%0.3f us] %s", $realtime / 1e3, msg);
    else if (n_err == 21) $display("Error: more than 20 errors, not printing the rest");
  endfunction

  // ---------------------------------------------------------------------------
  // Reset monitor. While the FPGA is in reset, the display must be in its safe
  // state: VDD and VBAT off, RES# not asserted (the power-up sequence pulses it
  // later) and no SPI clock. Each problem is reported once, at reset release.
  // ---------------------------------------------------------------------------
  // SCLK is sampled here instead of counting its edges: its reset value makes
  // it go X->1 when reset is asserted, which already counts as a posedge.
  // (a flag instead of an X initial value marks the first sample, because
  // 2-state simulators like Verilator turn X into 0)
  bit bad_vdd_in_rst = 0, bad_vbat_in_rst = 0, bad_res_in_rst = 0, bad_sclk_in_rst = 0;
  bit sclk_sampled_in_rst = 0;
  logic sclk_in_rst;

  always @(posedge clk) begin
    if (rst_n === 1'b0) begin
      if (vdd !== 1'b1) bad_vdd_in_rst = 1;  // active low
      if (vbat !== 1'b1) bad_vbat_in_rst = 1;  // active low
      if (res_n !== 1'b1) bad_res_in_rst = 1;
      if (sclk_sampled_in_rst && sclk !== sclk_in_rst) bad_sclk_in_rst = 1;
      sclk_in_rst = sclk;
      sclk_sampled_in_rst = 1;
    end
  end

  always @(posedge rst_n) begin
    if (bad_vdd_in_rst) fail("VDD not off (high) during reset");
    if (bad_vbat_in_rst) fail("VBAT not off (high) during reset");
    if (bad_res_in_rst) fail("RES# not inactive (high) during reset");
    if (bad_sclk_in_rst) fail("SCLK toggled during reset");
  end

  // ---------------------------------------------------------------------------
  // Power-up sequence monitor, active once reset is released. VDD, RES# and
  // VBAT only change on clock edges, so sampling them on the clock loses no
  // information. Changes are detected relative to the safe "off" state.
  // ---------------------------------------------------------------------------
  realtime t_vdd_on = -1, t_res_low = -1, t_res_high = -1, t_vbat_on = -1;
  int n_res_pulses = 0;
  int n_init_cmds = 0;  // command bytes received before the first data byte
  logic vdd_q = 1, res_n_q = 1, vbat_q = 1;  // last sampled values, start "off"

  always @(posedge clk) begin
    if (rst_n === 1'b1) begin
      if (vdd !== vdd_q) begin  // active low
        if (vdd === 1'b0) t_vdd_on = $realtime;
        else fail("VDD switched off again after power-up");
        vdd_q = vdd;
      end

      if (res_n !== res_n_q) begin
        if (res_n === 1'b0) begin
          n_res_pulses++;
          t_res_low = $realtime;
          if (t_vdd_on < 0) fail("RES# asserted before VDD was switched on");
          else if (t_res_low - t_vdd_on < TVddToRes)
            fail($sformatf("RES# asserted %0.3f ms after VDD on, need >= 1 ms",
                           (t_res_low - t_vdd_on) / 1e6));
        end else if (res_n === 1'b1) begin
          t_res_high = $realtime;
          if (t_res_high - t_res_low < TResLow)
            fail($sformatf("RES# pulse %0.0f ns, need >= 3 us", t_res_high - t_res_low));
        end
        res_n_q = res_n;
      end

      if (vbat !== vbat_q) begin  // active low
        if (vbat === 1'b0) begin
          t_vbat_on = $realtime;
          if (n_init_cmds < NumInitCmds)
            fail($sformatf("VBAT switched on after only %0d of %0d init commands",
                           n_init_cmds, NumInitCmds));
        end else begin
          fail("VBAT switched off again after power-up");
        end
        vbat_q = vbat;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // SSD1306 model: shifts SDIN in MSB first on each rising SCLK while RES# is
  // high, and samples D/C# together with the 8th bit. CS# is tied low on the
  // board, so every rising edge counts and byte framing is only kept by
  // counting edges.
  // ---------------------------------------------------------------------------
  typedef struct {
    logic       dc;
    logic [7:0] data;
  } spi_byte_t;

  spi_byte_t rx_bytes[$];
  logic [7:0] shift_reg;
  int n_bits = 0;
  bit seen_data = 0, seen_display_on = 0;
  realtime t_rise = -1, t_fall = -1, t_sdin = 0, t_dc = 0;

  always @(posedge sclk) begin : receiver
    spi_byte_t b;

    if (rst_n !== 1'b1) disable receiver;  // checked by the reset monitor

    if (t_rise >= 0 && $realtime - t_rise < TCycle)
      fail($sformatf("SCLK period %0.1f ns, need >= %0.0f ns", $realtime - t_rise, TCycle));
    if (t_fall >= 0 && $realtime - t_fall < TClkL)
      fail($sformatf("SCLK low for %0.1f ns, need >= %0.0f ns", $realtime - t_fall, TClkL));
    if ($realtime - t_sdin < TDsw)
      fail($sformatf("SDIN setup %0.1f ns, need >= %0.0f ns", $realtime - t_sdin, TDsw));
    t_rise = $realtime;

    if (res_n === 1'b1) begin
      if (n_res_pulses == 0) fail("SCLK activity before the display was reset");

      shift_reg = {shift_reg[6:0], sdin};
      n_bits++;
      if (n_bits == 8) begin
        n_bits = 0;
        if ($realtime - t_dc < TAs)
          fail($sformatf("D/C# setup %0.1f ns, need >= %0.0f ns", $realtime - t_dc, TAs));

        b.dc   = dc;
        b.data = shift_reg;
        rx_bytes.push_back(b);

        if (dc === 1'b1 && !seen_data) begin
          seen_data = 1;
          if (t_vbat_on < 0) fail("display data written before VBAT was switched on");
          else if ($realtime - t_vbat_on < TVbatSettle)
            fail($sformatf("display data written %0.3f ms after VBAT on, need >= 100 ms",
                           ($realtime - t_vbat_on) / 1e6));
        end
        if (dc === 1'b0 && !seen_data) n_init_cmds++;
        if (dc === 1'b0 && seen_data && shift_reg == DisplayOn) seen_display_on = 1;
      end
    end
  end

  always @(negedge sclk) begin
    if (t_rise >= 0 && $realtime - t_rise < TClkH)
      fail($sformatf("SCLK high for %0.1f ns, need >= %0.0f ns", $realtime - t_rise, TClkH));
    t_fall = $realtime;
  end

  always @(sdin) begin
    if (t_rise >= 0 && $realtime - t_rise < TDhw)
      fail($sformatf("SDIN hold %0.1f ns, need >= %0.0f ns", $realtime - t_rise, TDhw));
    t_sdin = $realtime;
  end

  always @(dc) begin
    if (n_bits != 0) fail($sformatf("D/C# changed after bit %0d of a byte", n_bits));
    if (t_rise >= 0 && $realtime - t_rise < TAh)
      fail($sformatf("D/C# hold %0.1f ns, need >= %0.0f ns", $realtime - t_rise, TAh));
    t_dc = $realtime;
  end

  // reset clears the controller's bit counter
  always @(negedge res_n) n_bits = 0;

  // ---------------------------------------------------------------------------
  // Byte stream check: init commands, then zero data covering the whole
  // display, then the display-on command, then nothing.
  // ---------------------------------------------------------------------------
  int n_clear = 0;

  // returns string so the literals aren't padded to equal width like in a ?:
  function automatic string kind(logic dc);
    if (dc) return "data";
    return "command";
  endfunction

  function automatic void check_byte_stream();
    int i = 0;

    for (int k = 0; k < NumInitCmds; k++) begin
      if (i >= rx_bytes.size()) begin
        fail($sformatf("only %0d of %0d init commands received", k, NumInitCmds));
        return;
      end
      if (rx_bytes[i].dc !== 1'b0 || rx_bytes[i].data !== InitCmds[k])
        fail($sformatf("init byte %0d: expected command 0x%02h, got %s 0x%02h", k, InitCmds[k],
                       kind(rx_bytes[i].dc), rx_bytes[i].data));
      i++;
    end

    while (i < rx_bytes.size() && rx_bytes[i].dc === 1'b1) begin
      if (rx_bytes[i].data !== 8'h00)
        fail($sformatf("clear byte %0d is 0x%02h, expected 0x00", n_clear, rx_bytes[i].data));
      n_clear++;
      i++;
    end
    if (n_clear < DisplayBytes)
      fail($sformatf("clear wrote %0d bytes, the display has %0d", n_clear, DisplayBytes));

    if (i >= rx_bytes.size()) begin
      fail("display-on command 0xAF never received");
      return;
    end
    if (rx_bytes[i].dc !== 1'b0 || rx_bytes[i].data !== DisplayOn)
      fail($sformatf("expected display-on command 0xAF, got %s 0x%02h",
                     kind(rx_bytes[i].dc), rx_bytes[i].data));
    i++;

    if (i < rx_bytes.size())
      fail($sformatf("%0d unexpected bytes after display-on", rx_bytes.size() - i));
  endfunction

  initial begin
    $display("OLED: FPGA clock %0d MHz", SysClkF / 1_000_000);

    while (!seen_display_on && $realtime < Timeout) #1us;
    #100us;  // catch stray bytes after display-on

    if (n_res_pulses != 1) fail($sformatf("RES# pulsed %0d times, expected 1", n_res_pulses));
    check_byte_stream();

    $display("OLED: received %0d bytes: %0d init commands, %0d clear bytes, display on: %s",
             rx_bytes.size(), n_init_cmds, n_clear,
             seen_display_on ? string'("yes") : string'("no"));
    $display("OLED: errors %0d", n_err);
    if (n_err == 0) $display("TEST PASSED");
    else $display("TEST FAILED");
    $finish;
  end
endmodule
