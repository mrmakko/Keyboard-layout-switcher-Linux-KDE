# Handoff

## Current behavior

- Select text in a Wayland application and press `Left Ctrl+Space`.
- Input Remapper emits `F24`; KDE launches `src/layout-fix`.
- Mixed US/Russian selections are converted segment by segment.
- Clipboard handling follows an AutoHotkey-style save, paste, and restore
  transaction through a private CopyQ session named `layout-fix`.
- User-visible notifications and program errors are English-only.

## Live deployment paths

- `/home/tony/.local/bin/layout-fix`
- `/home/tony/.local/share/applications/net.local.layout-fix.desktop`
- `/home/tony/.config/systemd/user/layout-fix-clipboard.service`
- `/home/tony/.config/systemd/user/layout-fix-input-remapper.service`
- `/home/tony/.config/input-remapper-2/`
- `/home/tony/.config/copyq-layout-fix/`

The files in this repository are a snapshot of those deployed files on
2026-08-28. Runtime data, lock files, CopyQ public keys, tab databases, and
window geometry were deliberately excluded.

## Where the rest went

The CopyQ crash diagnosis, the applied workaround and its verification moved
to `docs/copyq-image-crash.md` when the project was packaged for release.
Installation is now `./install.sh`, which renders the templates in `config/`
into the live paths listed above.
