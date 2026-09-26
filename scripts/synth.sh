#!/bin/sh
# caelum build --target <t> --mode generic|ice40|ecp5|gowin|xilinx
# out: build/<t>/<mode>/netlist.json, netlist.v, stat.txt (cells), depth.txt (generic only)
# target options: rtl  extra Verilog folder, relative to the project
set -eu

die() { echo "yosys: $*" >&2; exit 1; }
out=$CAELUM_OUT_DIR
mkdir -p "$out"

files=""
for f in "$CAELUM_RTL_DIR"/*.v "$CAELUM_RTL_DIR"/*.sv; do
  [ -f "$f" ] && files="$files $f"
done
if [ -n "${CAELUM_OPT_RTL:-}" ]; then
  [ -d "$CAELUM_ROOT/$CAELUM_OPT_RTL" ] || die "rtl folder not found: $CAELUM_ROOT/$CAELUM_OPT_RTL"
  for f in "$CAELUM_ROOT/$CAELUM_OPT_RTL"/*.v "$CAELUM_ROOT/$CAELUM_OPT_RTL"/*.sv; do
    [ -f "$f" ] && files="$files $f"
  done
fi
[ -n "$files" ] || die "no Verilog in $CAELUM_RTL_DIR"

top=$CAELUM_TOP
case "$CAELUM_MODE" in
  generic) synth="synth -top $top -flatten; tee -q -o $out/stat.txt stat; aigmap; tee -q -o $out/depth.txt ltp -noff" ;;
  ice40)   synth="synth_ice40 -top $top; tee -q -o $out/stat.txt stat" ;;
  ecp5)    synth="synth_ecp5 -top $top; tee -q -o $out/stat.txt stat" ;;
  gowin)   synth="synth_gowin -top $top; tee -q -o $out/stat.txt stat" ;;
  xilinx)  synth="synth_xilinx -top $top -flatten; tee -q -o $out/stat.txt stat" ;;
  *) die "unknown mode $CAELUM_MODE (generic, ice40, ecp5, gowin, xilinx)" ;;
esac

# Caelum emits SystemVerilog constructs (logic, sized casts) into .v files
log=$out/yosys.log
status=0
# shellcheck disable=SC2086
yosys -q -l "$log" -p "read_verilog -sv $files; $synth; write_json $out/netlist.json; write_verilog -noattr $out/netlist.v" \
  > /dev/null 2>&1 || status=$?
if [ "$status" -ne 0 ]; then
  echo "yosys: synthesis of $top failed (exit $status), from $log:" >&2
  { grep -E "ERROR|Error" "$log" || tail -n 20 "$log"; } | sed 's/^/  /' >&2
  exit 1
fi

echo "yosys: $top ($CAELUM_MODE)"
sed -n '/cells$/,/^$/p' "$out/stat.txt" | head -40
[ -f "$out/depth.txt" ] && grep "Longest topological" "$out/depth.txt" | sed 's/.*(length=/logic depth: /; s/).*//' || true
