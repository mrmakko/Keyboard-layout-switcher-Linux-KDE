# The CopyQ image-MIME crash, and why the clipboard code looks like this

`layout-fix` keeps a private CopyQ session so that the clipboard survives the
paste it performs. That session is configured to never read image data, and
image clipboards take a separate `wl-clipboard` path instead. This document
records why.

## Confirmed CopyQ crash

Three crashes were recorded on 2026-08-28 at 08:45:37, 09:31:32, and
09:31:49, and the same fault recurred on 2026-09-05 (22:18:34, 22:22:51,
23:03:38) and 2026-09-07 at 08:20:02 (Asia/Bangkok) — the last one one second
after a `Left Ctrl+Space` conversion, four crashes over eight conversions in
that session. All were `SIGSEGV` in this child process:

```text
/usr/bin/copyq --clipboard-access monitorClipboard
```

The failing stack is consistent across the coredumps:

```text
QHash<QString, QVariant>::emplace
DataControlOffer::retrieveData                 libKF6GuiAddons.so.6
QMimeData::imageData                           libQt6Core.so.6
cloneData                                      copyq
X11PlatformClipboard::updateClipboardData      copyq
Scriptable::monitorClipboard                   copyq
```

The journal immediately before a crash contains messages such as:

```text
ELAPSED 660 ms accessing [:imageData]
```

Versions at the 2026-09-07 recurrence (`qt6-qtbase` had been updated from
6.11.1 since the first diagnosis, which did not help):

```text
copyq-16.0.0-1.fc44.x86_64
kf6-kguiaddons-6.29.0-1.fc44.x86_64
qt6-qtbase-6.11.2-2.fc44.x86_64
```

Conclusion: the Python converter and its systemd parent do not segfault. The
private CopyQ Wayland clipboard-access helper crashes while cloning image MIME
data through `DataControlOffer`. The main CopyQ process survives and starts a
new helper, which explains intermittent notifications and continued operation.

## Applied isolation of the image MIME path

CopyQ 16 reaches `QMimeData::imageData()` from exactly one place,
`ClipboardDataGuard::getImageData()` in `src/common/clipboarddataguard.cpp`,
and that function returns early when the size limit for the probe string
`image/` is zero:

```cpp
// Use "image/" as probe: matches broad rules like image/.*:0
// but not format-specific ones like image/png:0.
const qint64 maxBytes = maxBytesForMime(QStringLiteral("image/"));
if (maxBytes == 0)
    return {};
```

The rule patterns are anchored, so a rule whose pattern is exactly `image/`
matches the probe and nothing else; real types such as `image/png` still fall
through to the default rule. The private session is therefore configured with

```text
clipboard_mime_size_limit=image/:0;.*:100M
```

set both as a CopyQ option (`config/copyq-layout-fix/copyq-layout-fix.conf`)
and as `COPYQ_CLIPBOARD_MIME_SIZE_LIMIT` in
`config/systemd/user/layout-fix-clipboard.service`, which the
`--clipboard-access` children inherit. The environment variable takes
precedence over the option; both are set so the session behaves the same when
started outside systemd.

This removes the crash but also removes CopyQ's only way of reading or writing
binary image data, so `src/layout-fix` no longer routes an image-only
clipboard through CopyQ. `image_snapshot_mime()` inspects
`wl-paste --list-types` and takes the raw-bytes path (`wl-paste --type` /
`wl-copy --type`) only when the clipboard offers a binary image type and no
text type — which mirrors CopyQ's own rule of ignoring binary images whenever
text is available. Everything else still uses the CopyQ save/paste/restore
transaction and its multi-format snapshot. The raw-bytes path is a byte-for-
byte copy, whereas CopyQ used to decode to `QImage` and re-encode.

Two details worth keeping in mind:

- `wl-copy` forks a background process that keeps serving the selection and
  inherits the standard streams, so `restore_clipboard()` must not leave a
  pipe open on it; waiting for that pipe to close blocks until the clipboard
  owner is replaced.
- A restored image clipboard is owned by `wl-copy` and offers only the single
  saved MIME type, not the original multi-format offer.

## Verification on 2026-09-07

```text
python3 src/layout-fix --self-test          OK
python3 -m py_compile src/layout-fix        OK
text snapshot uses the CopyQ path           PASS
text restored byte-for-byte                 PASS
CopyQ no longer reads image data            PASS  (clipboard("image/png") is empty)
image snapshot uses the raw-bytes path      PASS
PNG restored byte-for-byte                  PASS
PNG decodes to identical pixels             PASS
15 mixed text/PNG transaction cycles        PASS  (every restore byte-identical)
```

No new `copyq` coredump and no `monitorClipboard` restart was recorded during
those cycles. The crash was intermittent under real use, so the live
`Left Ctrl+Space` shortcut still needs a few days of ordinary use to confirm.

## Next bounded objective

Confirm under real use, then decide whether anything further is needed:

1. Watch `coredumpctl list /usr/bin/copyq` for a few days of ordinary use.
2. If a crash reappears, capture whether it still comes through
   `getImageData()` or through another slow MIME type — the same
   `clipboard_mime_size_limit` mechanism can exclude other patterns.
3. Report the `DataControlOffer::retrieveData` use-after-free upstream
   (kf6-kguiaddons / CopyQ) rather than carrying the workaround forever.
4. The live `Left Ctrl+Space` shortcut must remain mapped only through F24.
