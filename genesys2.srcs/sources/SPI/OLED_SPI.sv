`default_nettype none

module OLED_SPI #(
    parameter int SysClkF
) (
    input wire logic Rst_SIN,
    input wire logic Clk_CI,
    output logic Dc_SO,  // data => 1, cmd => 0
    output logic Rst_SON,
    output logic Sclk_SO,
    output logic Sdin_SO,
    output logic VBat_SON,
    output logic Vdd_SO
);

  localparam int ClkPerMs = SysClkF / 1000;

  localparam int NumCmds = 12;
  localparam logic [7:0] InitCmds[NumCmds] = '{
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

  localparam int NumCols = 128;
  localparam int NumRows = 32;

  typedef enum {
    PWR_VDD,
    RESET,
    INIT,
    PWR_VBAT,
    CLEAR,
    DISP_ON,
    DONE
  } state_t;
  state_t State, State_P;

  logic Dc_S, Dc_SP, Rst_SN, Rst_SPN, VBat_SN, VBat_SPN, Vdd_S, Vdd_SP;

  // generate pulse every ms with counter
  logic MsTick_S;  // pulse every ms
  logic [$clog2(ClkPerMs+1)-1:0] MsSysClkCnt_D, MsSysClkCnt_DP;
  logic [$clog2(100+1)-1:0] MsCtr_D, MsCtr_DP;  // count ms pulse up to 100ms

  logic SpiReady_S, SpiValid_S, SpiValid_SP;
  logic SpiLastSent_S, SpiLastSent_SP;  // last byte handed to shifter, wait for it to finish
  logic [7:0] SpiData_D, SpiData_DP;

  // Initialization command to send
  logic [$clog2(NumCmds+1)-1:0] InitCmdIdx_D, InitCmdIdx_DP;

  // Display buffer contents
  logic [$clog2(NumCols*NumRows+1)-1:0] DispBufIdx_D, DispBufIdx_DP;
  // logic [NumCols*NumRows-1:0] DispBuf_D;
  // logic [$clog2(NumCols+1)-1:0] ColIdx_D, ColIdx_DP;
  // logic [$clog2(NumRows+1)-1:0] RowIdx_D, RowIdx_DP;


  SPI_shifter #(
      .SysClkF(SysClkF),
      .SpiClkF(10_000_000)
  ) spi_shifter (
      .Rst_SIN (Rst_SIN),
      .Clk_CI  (Clk_CI),
      .Data_DI (SpiData_DP),
      .Valid_SI(SpiValid_SP),
      .Sclk_SO (Sclk_SO),
      .Sdin_SO (Sdin_SO),
      .Ready_SO(SpiReady_S)
  );

  always_ff @(posedge Clk_CI, negedge Rst_SIN) begin
    if (~Rst_SIN) begin
      State_P <= PWR_VDD;

      Dc_SP <= '0;
      Rst_SPN <= '1;
      VBat_SPN <= '1;
      Vdd_SP <= '1;

      MsSysClkCnt_DP <= '0;
      MsCtr_DP <= '0;

      SpiValid_SP <= '0;
      SpiData_DP <= '0;
      SpiLastSent_SP <= '0;

      InitCmdIdx_DP <= '0;
      DispBufIdx_DP <= '0;
    end else begin
      State_P <= State;

      Dc_SP <= Dc_S;
      Rst_SPN <= Rst_SN;
      VBat_SPN <= VBat_SN;
      Vdd_SP <= Vdd_S;

      MsSysClkCnt_DP <= MsSysClkCnt_D;
      MsCtr_DP <= MsCtr_D;

      SpiValid_SP<= SpiValid_S;
      SpiData_DP <= SpiData_D;
      SpiLastSent_SP <= SpiLastSent_S;

      InitCmdIdx_DP <= InitCmdIdx_D;
      DispBufIdx_DP <= DispBufIdx_D;
    end
  end

  assign Dc_SO = Dc_SP;
  assign Rst_SON = Rst_SPN;
  assign VBat_SON = VBat_SPN;
  assign Vdd_SO = Vdd_SP;

  always_comb begin
    State = State_P;

    Dc_S = '1;
    Rst_SN = !(State_P == RESET);
    VBat_SN = State_P inside {PWR_VDD, RESET, INIT};
    Vdd_S = '0;

    MsCtr_D = MsCtr_DP;
    if (MsSysClkCnt_DP == ClkPerMs - 1) MsSysClkCnt_D = '0;
    else MsSysClkCnt_D = MsSysClkCnt_DP + 1;
    MsTick_S = (MsSysClkCnt_DP == (ClkPerMs - 1));

    SpiValid_S = SpiValid_SP;
    SpiData_D = SpiData_DP;
    SpiLastSent_S = SpiLastSent_SP;

    InitCmdIdx_D = InitCmdIdx_DP;
    DispBufIdx_D = DispBufIdx_DP;

    // https://digilent.com/reference/programmable-logic/genesys-2/reference-manual#oled
    case (State_P)
      PWR_VDD: begin
        // 1. power up VDD by pulling OLED_VDD low. Wait 1ms
        if (MsTick_S) State = RESET;
      end
      RESET: begin
        // 2. pulse RES# low for at least 3us
        if (MsTick_S) State = INIT;
      end
      INIT: begin
        // 3. send initialization / configuration commands
        Dc_S = '0;  // data <= 1, cmd <= 0

        if (!SpiLastSent_SP) begin
          // offer the next command byte to the shifter
          SpiData_D  = InitCmds[InitCmdIdx_DP];
          SpiValid_S = '1;

          if (SpiValid_SP && SpiReady_S) begin  // handshake: shifter took the byte
            SpiValid_S = '0;

            if (InitCmdIdx_DP == NumCmds - 1) SpiLastSent_S = '1;
            else InitCmdIdx_D = InitCmdIdx_DP + 1;
          end
        end else if (SpiReady_S && !SpiValid_SP) begin
          // shifter idle and nothing pending => last byte fully clocked out
          SpiLastSent_S = '0;
          State = PWR_VBAT;
          MsCtr_D = '0;
        end
      end
      PWR_VBAT: begin
        // 4. Power up VBAT by pulling OLED_VBAT low. Wait 100ms for voltage to stabilize.
        if (MsTick_S) MsCtr_D = MsCtr_DP + 1;

        if (MsCtr_DP == 101) begin
          State = CLEAR;
          DispBufIdx_D = '0;
        end
      end
      CLEAR: begin
        // 5. Clear screen by writing zero to the display buffer.
        Dc_S = '1;  // data <= 1, cmd <= 0

        if (!SpiLastSent_SP) begin
          // write zero bytes to display
          // DispBuf_D[DispBufIdx_DP] = '0;
          SpiData_D = '0;
          SpiValid_S = '1;

          if (SpiValid_SP && SpiReady_S) begin  // handshake: shifter took the byte
            SpiValid_S = '0;

            if (DispBufIdx_DP == NumRows * NumCols - 1) SpiLastSent_S = '1;
            else DispBufIdx_D = DispBufIdx_DP + 1;
          end
        end else if (SpiReady_S && !SpiValid_SP) begin
          // shifter idle and nothing pending => last byte fully clocked out
          SpiLastSent_S = '0;
          State = DISP_ON;
          DispBufIdx_D = '0;
        end
      end
      DISP_ON: begin
        Dc_S = '0;  // data <= 1, cmd <= 0

        // write zero bytes to display
        SpiData_D = 8'hAF;
        SpiValid_S = '1;

        if (SpiValid_SP && SpiReady_S) begin
          SpiValid_S = '0;
          SpiData_D = 8'h00;
        end
        else if (SpiReady_S && !SpiValid_SP) State = DONE;
      end
      DONE: begin end
      default: State = PWR_VDD;
    endcase
  end
endmodule

`default_nettype wire
