#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Install or remove layout-fix for the current user.
set -euo pipefail

repo=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
bin_dir=${XDG_BIN_HOME:-$HOME/.local/bin}
config_home=${XDG_CONFIG_HOME:-$HOME/.config}
data_home=${XDG_DATA_HOME:-$HOME/.local/share}
units=$config_home/systemd/user
desktop=$data_home/applications/net.local.layout-fix.desktop
binary=$bin_dir/layout-fix

say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

uninstall() {
    systemctl --user disable --now layout-fix-clipboard.service \
        layout-fix-input-remapper.service 2>/dev/null || true
    rm -f "$binary" "$desktop" \
        "$units/layout-fix-clipboard.service" \
        "$units/layout-fix-input-remapper.service"
    systemctl --user daemon-reload
    say "Removed layout-fix. Left in place: $config_home/layout-fix and"
    say "$config_home/copyq-layout-fix (your configuration and clipboard history)."
}

if [ "${1:-}" = "--uninstall" ]; then
    uninstall
    exit 0
fi
if [ $# -gt 0 ]; then
    say "usage: $0 [--uninstall]" >&2
    exit 2
fi

missing=()
for tool in copyq wl-paste wl-copy gdbus ydotool notify-send; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    warn "missing required commands: ${missing[*]}"
    warn "install them first; see the Requirements section of README.md"
fi
command -v input-remapper-control >/dev/null \
    || warn "input-remapper is not installed; you will need another way to send F24"

install -Dm 755 "$repo/src/layout-fix" "$binary"
"$binary" --self-test >/dev/null

mkdir -p "$units" "$(dirname "$desktop")"
sed "s|@BIN@|$binary|" "$repo/config/applications/net.local.layout-fix.desktop" > "$desktop"
sed "s|@CONFIG_HOME@|$config_home|" \
    "$repo/config/systemd/user/layout-fix-input-remapper.service" \
    > "$units/layout-fix-input-remapper.service"
install -m 644 "$repo/config/systemd/user/layout-fix-clipboard.service" \
    "$units/layout-fix-clipboard.service"

layouts=$config_home/layout-fix/layouts.toml
if [ ! -e "$layouts" ]; then
    mkdir -p "$(dirname "$layouts")"
    "$binary" --dump-layouts > "$layouts"
    say "Wrote default layout tables to $layouts"
fi

copyq_conf=$config_home/copyq-layout-fix/copyq-layout-fix.conf
if [ ! -e "$copyq_conf" ]; then
    mkdir -p "$(dirname "$copyq_conf")"
    install -m 644 "$repo/config/copyq-layout-fix/copyq-layout-fix.conf" "$copyq_conf"
fi

systemctl --user daemon-reload
systemctl --user enable --now layout-fix-clipboard.service
systemctl --user enable --now layout-fix-input-remapper.service 2>/dev/null \
    || warn "could not start layout-fix-input-remapper.service (input-remapper missing?)"

cat <<NEXT

Installed $binary

Two steps are left, because both depend on your hardware and your desktop:

1. Map your shortcut to F24 in the Input Remapper GUI. Pick your keyboard,
   record Left Ctrl + Space as the input and F24 as the output, name the
   preset "layout-fix" and enable autoload. An example preset for reference:
   examples/input-remapper-2/presets/

2. Bind F24 to the entry in KDE:
   System Settings -> Keyboard -> Shortcuts -> Applications ->
   "Fix Keyboard Layout" -> F24.

Check your KDE layout indices and put them in $layouts if they are not
US first and Russian second:

  gdbus call --session --dest org.kde.keyboard --object-path /Layouts \\
      --method org.kde.KeyboardLayouts.getLayoutsList
NEXT
