# Ava BASIC compiler and stack-machine interpreter

`zig build` will produce:

* `zig-out/bin/avabasic`

`avabasic repl` will run the interactive (CLI) interpreter.  
`avabasic --help` will show other modes of execution.

A `flake.nix` is provided -- you can directly run:

```shell
nix run 'github:charlottia/ava#avabasic'
```
