#!/usr/bin/env bash
# Run the top-level UART loopback testbench with Verilator.
#
# Usage: sim/run_verilator.sh [PC_CLK_PER_BIT ...]
#   sim/run_verilator.sh              # nominal PC baud rate (1736 cycles/bit)
#   sim/run_verilator.sh 1733 1739    # PC UART slightly fast, then slightly slow
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
BUILD="$REPO/sim/build/verilator"

SOURCES=("$REPO/sim/IBUFDS.v")
while IFS= read -r f; do SOURCES+=("$f"); done \
  < <(find "$REPO/genesys2.srcs/sources" -name '*.sv' | sort)
SOURCES+=("$REPO/genesys2.srcs/sim_1/new/tb_top.sv")

status=0
for bit in "${@:-1736}"; do
  obj="$BUILD/tb_top_$bit"
  mkdir -p "$obj"
  verilator --binary --timing -j 0 \
    -Wno-fatal -Wno-lint -Wno-style -Wno-TIMESCALEMOD \
    --top-module tb_top -GPC_CLK_PER_BIT="$bit" -Mdir "$obj" \
    "${SOURCES[@]}" >/dev/null
  # keep running past $error so the testbench prints its summary, like xsim
  out=$("$obj/Vtb_top" +verilator+error+limit+1000000 2>&1 || true)
  echo "$out" | grep -E '^(PC bit period|sent|TEST)|%Error' || true
  echo "$out" | grep -q 'TEST PASSED' || status=1
done
exit $status
