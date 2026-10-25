// Simulation stand-in for the Xilinx IBUFDS primitive, for simulators without
// the Vivado unisims library (e.g. Verilator). Passes the positive input through.
module IBUFDS (
    input  wire I,
    input  wire IB,
    output wire O
);
  assign O = I;
endmodule
