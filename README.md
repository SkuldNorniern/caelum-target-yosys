# caelum-target-yosys

Yosys for Caelum: synthesis of the emitted Verilog, cell counts and logic depth. Modes `generic`, `ice40`, `ecp5`, `gowin`, `xilinx`.

```toml
[target-dependencies]
yosys = { git = "https://github.com/SkuldNorniern/caelum-target-yosys" }

[target.synth]
provider = "yosys"
```

```bash
caelum build --target synth                 # generic gates + depth
caelum build --target synth --mode ice40
```

out in `build/<target>/<mode>/`: `summary.toml` (for `caelum report`), `stat.txt`, `netlist.json`, `netlist.v`, `yosys.log`. needs yosys (OSS CAD Suite).
