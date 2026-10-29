# Vikey for Linux — plan and status

Tony, 2026-10-29: "now build the Linux version" (after Windows shipped). Parity target: the Mac app.

## How it works on Linux

Linux has no global keyboard hook that works under Wayland, so Vikey is an **IBus input engine**
(`ibus-engine-vikey`), the way every Vietnamese IME on Linux works (ibus-unikey, ibus-bamboo). IBus delivers
the key events of the focused app to the engine and the engine commits text back, in every toolkit, on X11
and Wayland, GNOME and KDE. Same `Engine/` C++ as macOS/Windows/iOS; the platform layer is `Linux/ibus/`.

| macOS feature | Linux |
|---|---|
| Telex, tone placement, spelling, restore-if-invalid | same engine (`Linux/check.sh` runs the engine lock on CI, x64 + arm64) |
| Auto switch EN/VI, doubled key, look-back, Backspace undo, 5 s pause | `Linux/ibus/Core.cpp`, a port of the Windows/macOS core with an output sink |
| Switch hotkey (⌥Z) | Alt+Z inside the engine (modifier-only chords tracked from modifier key events); IBus' own input-source key also works |
| Per-app memory | X11 `_NET_ACTIVE_WINDOW` WM_CLASS; on Wayland only XWayland apps (Wayland gives engines no app identity) |
| Per-website memory | not available (needs a browser extension) |
| Menu bar icon V/E + menu | IBus panel properties: V/E symbol, Tiếng Việt toggle, Tự chuyển, Mở Vikey…, Xem nhật ký gõ…, Giới thiệu |
| Settings window, typing log, About | `vikey-settings` (GTK4 + libadwaita), 1:1 rows with the Mac window; writes `~/.config/vikey/settings.json`, the engine watches it |
| Launch at login | IBus starts the engine with the session (row in the window is informational) |
| Auto update | apt/dnf repo on vikey.app (TODO); row informational |
| Typing log | same JSONL at `~/.local/share/vikey/typing-log.jsonl`; terminals/password managers excluded by WM_CLASS |
| Output | no pre-edit: text is committed straight (like Mac/Win). Delete via `delete_surrounding_text` when the client supports it, else forwarded BackSpace keys |

## Phases

| # | Phase | Status |
|---|---|---|
| 0 | Ubuntu 24.04 VM "Vikey-Linux" in VMPal | done (needed host disk cleanup) |
| 1 | Engine lock on Linux CI | done (ubuntu-latest + ubuntu-24.04-arm) |
| 2 | IBus engine | done: live suite 14/14 in the VM (GNOME Wayland) from the installed .deb |
| 3 | Settings app / typing log / About | done (screenshots sent to Tony) |
| 4 | Packages: .deb + .rpm (CPack), CI upload to the GitHub release, `release.sh --linux` | done; .deb installed and tested in the VM (prefix /usr) |
| 5 | QA: `Linux/Tests/livetest.py` 14/14 on GNOME (Wayland session, XWayland test window), package install | done in the dev VM; clean-VM install not done (no disk) |
| 6 | Site: Linux card on /download, home button (behind `<!-- linux -->` until release.json has `linux`) | written |
| later | Fcitx5 engine, apt repo for updates, browser extension for per-site memory | |

## Gotchas learned (also in memory)

- IBus drops the global engine when the last client goes away: tests run `ibus engine vikey` first.
- GTK resets the IM context right after inserting a passthrough key: the engine ignores a `reset` within 300 ms of its own output, or the auto-switch look-back is wiped after every word.
- Settings are a shared JSON file: stats go to `stats.json` (engine only), settings are re-read before each write, language switches go through the one-shot `~/.config/vikey/command` file.
- The IBus component bakes the libexec path: the default install prefix is `/usr`, like the packages.
- `Tools/autoswitch/{driver/bench,driver/drvlazy,touch/touchsim,sim/sim0,test/h0,test/h10}` are tracked macOS binaries; a Linux build overwrites them (`git checkout -- Tools` before pulling in the VM).
