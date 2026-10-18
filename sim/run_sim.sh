#!/usr/bin/env bash
# Run the top-level UART loopback testbench with the Vivado simulator.
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

"$VIVADO_DIR/bin/xvlog" -sv "$REPO"/genesys2.srcs/sources_1/new/*.sv \
  "$REPO/genesys2.srcs/sim_1/new/tb_top.sv" >/dev/null
"$VIVADO_DIR/bin/xvlog" "$VIVADO_DIR/data/verilog/src/glbl.v" >/dev/null

status=0
for bit in "${@:-1736}"; do
  "$VIVADO_DIR/bin/xelab" tb_top glbl -L unisims_ver -s "tb_top_$bit" \
    -generic_top "PC_CLK_PER_BIT=$bit" >/dev/null
  out=$("$VIVADO_DIR/bin/xsim" "tb_top_$bit" -R)
  echo "$out" | grep -E '^(PC bit period|sent|TEST|Error)' || true
  echo "$out" | grep -q 'TEST PASSED' || status=1
done
exit $status
