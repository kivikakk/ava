# Ava BASIC core

`zig build` will produce:

* `zig-out/bin/avacore` (RV32ICM ELF)
* `zig-out/bin/avacore.imem.bin` (raw image)
* `zig-out/bin/avacore.dmem.bin` (raw image)

The `.imem.bin` image is loaded onto the target board's SPI flash.  
The `.dmem.bin` image is currently compiled into the gateware.
