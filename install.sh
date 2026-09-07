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
remapper_dir=$config_home/input-remapper-2

mode=kde
shortcut=""
say() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<USAGE
usage: $0 [--left-ctrl] [--shortcut KEYS] [--uninstall]

  (no options)      bind Ctrl+Space as a KDE global shortcut
  --left-ctrl       bind Left Ctrl+Space only, through Input Remapper and F24,
                    so Right Ctrl+Space keeps working in applications
  --shortcut KEYS   use another KDE shortcut, e.g. --shortcut 'Meta+Space'
  --uninstall       remove everything this script installs
USAGE
}

# kglobalaccel caches the shortcut a desktop file registered, so a changed
# X-KDE-Shortcuts is only picked up after the component is unregistered.
refresh_shortcut() {
    gdbus call --session --dest org.kde.kglobalaccel \
        --object-path /component/net_local_layout_fix_desktop \
        --method org.kde.kglobalaccel.Component.cleanUp >/dev/null 2>&1 || true
    command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
}

remove_remapper_entries() {
    [ -e "$remapper_dir/config.json" ] || return 0
    python3 - "$remapper_dir/config.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    config = json.load(handle)
autoload = config.get("autoload", {})
for device in [d for d, preset in autoload.items() if preset == "layout-fix"]:
    del autoload[device]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=4)
    handle.write("\n")
PY
    rm -f "$remapper_dir"/presets/*/layout-fix.json
}

uninstall() {
    systemctl --user disable --now layout-fix-clipboard.service \
        layout-fix-input-remapper.service 2>/dev/null || true
    rm -f "$binary" "$desktop" \
        "$units/layout-fix-clipboard.service" \
        "$units/layout-fix-input-remapper.service"
    systemctl --user daemon-reload
    remove_remapper_entries
    refresh_shortcut
    say "Removed layout-fix. Left in place: $config_home/layout-fix and"
    say "$config_home/copyq-layout-fix (your configuration and clipboard history)."
}

while [ $# -gt 0 ]; do
    case $1 in
        --left-ctrl) mode=remapper ;;
        --shortcut) shift; [ $# -gt 0 ] || die "--shortcut needs a value"; shortcut=$1 ;;
        --uninstall) uninstall; exit 0 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

if [ "$mode" = remapper ]; then
    [ -n "$shortcut" ] && die "--shortcut and --left-ctrl are mutually exclusive"
    shortcut=F24
else
    shortcut=${shortcut:-Ctrl+Space}
fi

missing=()
for tool in copyq wl-paste wl-copy gdbus ydotool notify-send; do
    command -v "$tool" >/dev/null || missing+=("$tool")
done
if [ ${#missing[@]} -gt 0 ]; then
    warn "missing required commands: ${missing[*]}"
    warn "install them first; see the Requirements section of README.md"
fi

install -Dm 755 "$repo/src/layout-fix" "$binary"
"$binary" --self-test >/dev/null

mkdir -p "$units" "$(dirname "$desktop")"
sed -e "s|@BIN@|$binary|" -e "s|@SHORTCUT@|$shortcut|" \
    "$repo/config/applications/net.local.layout-fix.desktop" > "$desktop"
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

if [ "$mode" = remapper ]; then
    command -v input-remapper-control >/dev/null \
        || die "--left-ctrl needs input-remapper; install it or drop the option"
    keyboards=$(python3 - <<'PY'
import re
blocks = open("/proc/bus/input/devices", encoding="utf-8", errors="replace").read().split("\n\n")
seen = []
for block in blocks:
    handlers = re.search(r"^H: Handlers=(.*)$", block, re.M)
    name = re.search(r'^N: Name="(.*)"$', block, re.M)
    # A real keyboard claims the kbd handler and has LEDs; this skips power
    # buttons, consumer-control endpoints and virtual devices.
    if not handlers or not name:
        continue
    fields = handlers.group(1).split()
    if "kbd" in fields and "leds" in fields and name.group(1) not in seen:
        if "input-remapper" not in name.group(1) and "ydotoold" not in name.group(1):
            seen.append(name.group(1))
print("\n".join(seen))
PY
)
    [ -n "$keyboards" ] || die "found no keyboard in /proc/bus/input/devices"
    mapfile -t devices <<< "$keyboards"
    for device in "${devices[@]}"; do
        mkdir -p "$remapper_dir/presets/$device"
        cat > "$remapper_dir/presets/$device/layout-fix.json" <<'PRESET'
[
    {
        "input_combination": [
            {"type": 1, "code": 29},
            {"type": 1, "code": 57}
        ],
        "target_uinput": "keyboard",
        "output_type": 1,
        "output_code": 194,
        "release_combination_keys": true
    }
]
PRESET
        say "Mapped Left Ctrl+Space on \"$device\""
    done

    python3 - "$remapper_dir/config.json" "${devices[@]}" <<'PY'
import json, os, sys
path, devices = sys.argv[1], sys.argv[2:]
config = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as handle:
        config = json.load(handle)
config.setdefault("autoload", {})
for device in devices:
    config["autoload"][device] = "layout-fix"
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=4)
    handle.write("\n")
PY

    sed "s|@CONFIG_HOME@|$config_home|" \
        "$repo/config/systemd/user/layout-fix-input-remapper.service" \
        > "$units/layout-fix-input-remapper.service"
else
    # Migrate away from a previous --left-ctrl install.
    if [ -e "$units/layout-fix-input-remapper.service" ]; then
        systemctl --user disable --now layout-fix-input-remapper.service 2>/dev/null || true
        rm -f "$units/layout-fix-input-remapper.service"
        remove_remapper_entries
        say "Removed the previous Input Remapper mapping"
    fi
fi

systemctl --user daemon-reload
systemctl --user enable --now layout-fix-clipboard.service
if [ "$mode" = remapper ]; then
    systemctl --user enable --now layout-fix-input-remapper.service 2>/dev/null \
        || warn "could not start layout-fix-input-remapper.service"
fi

refresh_shortcut

say ""
say "Installed $binary"
say "Shortcut: $shortcut"
if [ "$mode" = remapper ]; then
    say "Input Remapper turns Left Ctrl+Space into F24; Right Ctrl+Space is untouched."
fi

if ! systemctl is-active --quiet ydotool 2>/dev/null && [ ! -S /tmp/.ydotool_socket ]; then
    say ""
    say "One step needs root: ydotool's daemon types the converted text."
    say "    sudo systemctl enable --now ydotool"
fi
