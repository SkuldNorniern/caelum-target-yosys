#!/bin/sh
# caelum build --target <t> --mode generic|ice40|ecp5|gowin|xilinx
# out: build/<t>/<mode>/netlist.json, netlist.v, stat.txt (cells), depth.txt (generic only)
# target options: rtl     extra Verilog folder, relative to the project
#                 family  xilinx mode: xc7 (default), xcup (UltraScale+, has URAM), xcu, xc7s ...
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
  xilinx)  synth="synth_xilinx -top $top -flatten -family ${CAELUM_OPT_FAMILY:-xc7}; tee -q -o $out/stat.txt stat" ;;
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

depth=""
[ -f "$out/depth.txt" ] && depth=$(sed -n 's/.*Longest topological path.*(length=\([0-9]*\)).*/\1/p' "$out/depth.txt" | head -1)

# summary.toml for caelum: the stat cells mapped to lut / ff / carry / bram / dsp / io
awk -v mode="$CAELUM_MODE" -v depth="$depth" '
  $2 == "cells" && total == "" { total = $1; next }
  NF == 2 && $1 ~ /^[0-9]+$/ && $2 !~ /^(wires|wire|ports|port|cells|public)$/ {
    n = $1; c = $2
    if (mode == "generic") {
      if (c ~ /DFF|DLATCH/) k = "ff"; else k = ""
    } else if (mode == "xilinx") {
      if (c ~ /^LUT[1-6]$/) k = "lut"; else if (c ~ /^FD/) k = "ff"; else if (c ~ /^CARRY/) k = "carry"
      else if (c ~ /^RAMB/) k = "bram"; else if (c ~ /^URAM/) k = "uram"; else if (c ~ /^RAM(32|64|128|256)/) k = "lutram"
      else if (c ~ /^DSP48/) k = "dsp"; else if (c ~ /^(IBUF|OBUF|IOBUF|OBUFT)$/) k = "io"; else k = ""
    } else if (mode == "ice40") {
      if (c == "SB_LUT4") k = "lut"; else if (c ~ /^SB_DFF/) k = "ff"; else if (c == "SB_CARRY") k = "carry"
      else if (c ~ /^SB_RAM/) k = "bram"; else if (c == "SB_MAC16") k = "dsp"; else if (c ~ /^SB_IO/) k = "io"; else k = ""
    } else if (mode == "ecp5") {
      if (c == "LUT4") k = "lut"; else if (c == "TRELLIS_FF") k = "ff"; else if (c == "CCU2C") k = "carry"
      else if (c ~ /^(DP16KD|PDPW16KD)$/) k = "bram"; else if (c ~ /^TRELLIS_DPR16X4/) k = "lutram"
      else if (c ~ /^MULT18/) k = "dsp"; else if (c ~ /^TRELLIS_IO/) k = "io"; else k = ""
    } else if (mode == "gowin") {
      if (c ~ /^LUT[1-4]$/) k = "lut"; else if (c ~ /^DFF/) k = "ff"; else if (c == "ALU") k = "carry"
      else if (c ~ /^(SP|SPX9|SDP|SDPB|SDPX9B|DP|DPB|DPX9B|pROM)$/) k = "bram"
      else if (c ~ /^MULT/) k = "dsp"; else if (c ~ /^(IBUF|OBUF|IOBUF|TBUF)$/) k = "io"; else k = ""
    }
    if (k != "") { r[k] += n; if (!(k in seen)) { seen[k] = 1; order[++no] = k } }
  }
  END {
    printf "tool = \"yosys %s\"\n\n[resources]\ncells = %d\n", mode, total
    for (i = 1; i <= no; i++) printf "%s = %d\n", order[i], r[order[i]]
    if (depth != "") printf "\n[timing]\ndepth = %d\n", depth
  }
' "$out/stat.txt" > "$out/summary.toml"

echo "yosys: $top ($CAELUM_MODE), cells per type in $out/stat.txt"
