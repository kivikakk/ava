# Ava BASIC Amateur Development Client

`zig build` will produce:

* `zig-out/bin/adc`

`adc --serial /dev/cu.usbserial-ibU1IGlC1` will connect to Ava BASIC running on
an iCEBreaker connected to a macOS host.

`adc --socket ../soc/cxxrtl-uart` will connect to a running CXXRTL simulation of
the SoC.
