#!/usr/bin/env bash
# Run the testbenches with the Vivado simulator:
#   tb_top   UART loopback through top, once per PC_CLK_PER_BIT
#   tb_oled  OLED power-up sequence and SPI bytes/timing
#
# Usage: sim/run_sim.sh [PC_CLK_PER_BIT ...]
#   sim/run_sim.sh              # nominal PC baud rate (1736 cycles/bit)
#   sim/run_sim.sh 1733 1739    # PC UART slightly fast, then slightly slow
set -euo pipefail

VIVADO_DIR=${XILINX_VIVADO:-/tools/Xilinx/2026.1/Vivado}
REPO=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$REPO/sim/build"

mkdir -p "$BUILD"
cd "$BUILD"

"$VIVADO_DIR/bin/xvlog" -sv "$REPO"/genesys2.srcs/sources/*.sv "$REPO"/genesys2.srcs/sources/*/*.sv \
  "$REPO"/genesys2.srcs/sim_1/new/*.sv >/dev/null
"$VIVADO_DIR/bin/xvlog" "$VIVADO_DIR/data/verilog/src/glbl.v" >/dev/null

status=0
for bit in "${@:-1736}"; do
  "$VIVADO_DIR/bin/xelab" tb_top glbl -L unisims_ver -s "tb_top_$bit" \
    -generic_top "PC_CLK_PER_BIT=$bit" >/dev/null
  out=$("$VIVADO_DIR/bin/xsim" "tb_top_$bit" -R)
  echo "$out" | grep -E '^(PC bit period|sent|TEST|Error)' || true
  echo "$out" | grep -q 'TEST PASSED' || status=1
done

"$VIVADO_DIR/bin/xelab" tb_oled -s tb_oled >/dev/null
out=$("$VIVADO_DIR/bin/xsim" tb_oled -R)
echo "$out" | grep -E '^(OLED|TEST|Error)' || true
echo "$out" | grep -q 'TEST PASSED' || status=1

exit $status
