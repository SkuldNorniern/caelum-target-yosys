#!/bin/sh
# caelum build --target <t> --mode generic|ice40|ecp5|gowin|xilinx
# out: build/<t>/<mode>/netlist.json, netlist.v, stat.txt (cells), depth.txt (generic only)
# target options: rtl  extra Verilog folder, relative to the project
set -eu
out=$CAELUM_OUT_DIR
mkdir -p "$out"

files=""
for f in "$CAELUM_RTL_DIR"/*.v "$CAELUM_RTL_DIR"/*.sv; do
  [ -f "$f" ] && files="$files $f"
done
if [ -n "${CAELUM_OPT_RTL:-}" ]; then
  for f in "$CAELUM_ROOT/$CAELUM_OPT_RTL"/*.v "$CAELUM_ROOT/$CAELUM_OPT_RTL"/*.sv; do
    [ -f "$f" ] && files="$files $f"
  done
fi
[ -n "$files" ] || { echo "yosys: no Verilog in $CAELUM_RTL_DIR" >&2; exit 1; }

top=$CAELUM_TOP
case "$CAELUM_MODE" in
  generic) synth="synth -top $top -flatten; tee -q -o $out/stat.txt stat; aigmap; tee -q -o $out/depth.txt ltp -noff" ;;
  ice40)   synth="synth_ice40 -top $top; tee -q -o $out/stat.txt stat" ;;
  ecp5)    synth="synth_ecp5 -top $top; tee -q -o $out/stat.txt stat" ;;
  gowin)   synth="synth_gowin -top $top; tee -q -o $out/stat.txt stat" ;;
  xilinx)  synth="synth_xilinx -top $top -flatten; tee -q -o $out/stat.txt stat" ;;
  *) echo "yosys: unknown mode $CAELUM_MODE" >&2; exit 1 ;;
esac

# Caelum emits SystemVerilog constructs (logic, sized casts, return) into .v files
# shellcheck disable=SC2086
yosys -q -l "$out/yosys.log" -p "read_verilog -sv $files; $synth; write_json $out/netlist.json; write_verilog -noattr $out/netlist.v"
echo "yosys: $top ($CAELUM_MODE)"
sed -n '/cells$/,/^$/p' "$out/stat.txt" | head -40
[ -f "$out/depth.txt" ] && grep "Longest topological" "$out/depth.txt" | sed 's/.*(length=/logic depth: /; s/).*//' || true
