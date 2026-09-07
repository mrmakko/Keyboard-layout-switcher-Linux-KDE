# Input Remapper example

`install.sh --left-ctrl` writes these files for you: it detects your keyboards
from `/proc/bus/input/devices`, drops a `layout-fix` preset into each and
enables autoload. The copies here are only for reference, and their device
names are specific to the machine they came from.

The mapping itself:

- input: `Left Ctrl` + `Space` (event codes 29 and 57)
- output: `F24` (event code 194)
- release combination keys: on

`layout-fix-input-remapper.service` then autoloads the preset when the
graphical session starts.
