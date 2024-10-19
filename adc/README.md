# Ava BASIC Amateur Development Client

`zig build` will produce:

* `zig-out/bin/adc`

`adc --serial /dev/cu.usbserial-ibU1IGlC1` will connect to Ava BASIC running on
an iCEBreaker connected to a macOS host.

`adc --socket ../soc/cxxrtl-uart` will connect to a running CXXRTL simulation of
the SoC.


## Legal

Copyright (C) 2024  Asherah Erin Connor

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <https://www.gnu.org/licenses/>.
