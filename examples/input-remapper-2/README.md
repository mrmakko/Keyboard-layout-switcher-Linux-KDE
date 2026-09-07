# Input Remapper example

These are the files from a working setup, for reference. Device names are
specific to that machine, so record the mapping in the Input Remapper GUI
rather than copying `config.json` verbatim:

- input: `Left Ctrl` + `Space` (event codes 29 and 57)
- output: `F24` (event code 194)
- release combination keys: on
- preset name: `layout-fix`, with autoload enabled for your keyboard

`layout-fix-input-remapper.service`, installed by `install.sh`, then autoloads
the preset when the graphical session starts.
