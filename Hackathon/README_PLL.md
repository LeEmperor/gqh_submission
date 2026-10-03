# Tang Nano 20K PLL Setup

Use `Gowin\_rPLL.v` as the generated PLL module for the Tang Nano 20K.

## Required files

Add these to the Gowin project:

* `Gowin\_rPLL.v`
* your top-level `.v` / `.sv`
* your `.cst`

`Gowin\_rPLL\_tmp.v` is only an instantiation template and is not required.

## Clock input

The Tang Nano 20K onboard oscillator is 27 MHz on pin 4:

```tcl
IO\_LOC "sys\_clk" 4;
IO\_PORT "sys\_clk" IO\_TYPE=LVCMOS33;
```

## Instantiate the PLL

wire system\_clk;

Gowin\_rPLL pll\_inst (
    .clkout(system\_clk), //change name as necessary
    .clkin (sys\_clk)
);
```

Then use `system\_clk` for the rest of the synchronous logic:

```verilog
always @(posedge system\_clk) begin
    // logic here
end
```

## Important

* `sys\_clk` is the 27 MHz board clock.
* `system\_clk` is the PLL output frequency configured in Gowin IP Generator. //108MHz for now, can be easily changed
* Do not add a `.cst` pin for `system\_clk` unless you intentionally want to output it to a GPIO.
* To change the PLL frequency, regenerate `Gowin\_rPLL.v` in Gowin IP Generator rather than manually editing it.

## Build

1. Run **Synthesize**
2. Run **Place \& Route**
3. Check that setup/hold timing passes
4. Program the generated `.fs` file from `impl/pnr/`

