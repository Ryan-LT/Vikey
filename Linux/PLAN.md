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
| 0 | Ubuntu 24.04 VM "Vikey-Linux" in VMPal | created; blocked on host disk space (see memory) |
| 1 | Engine lock on Linux CI | done (ubuntu-latest + ubuntu-24.04-arm) |
| 2 | IBus engine | written, compiles in CI; live test pending |
| 3 | Settings app / typing log / About | written, compiles in CI; screenshots pending |
| 4 | Packages: .deb + .rpm (CPack), CI upload to the GitHub release, `release.sh --linux` | written |
| 5 | QA: `Linux/Tests/livetest.py` 14/14 on GNOME (Wayland session, XWayland test window), package install on a clean VM | pending |
| 6 | Site: Linux card on /download, home button (behind `<!-- linux -->` until release.json has `linux`) | written |
| later | Fcitx5 engine, apt repo for updates, browser extension for per-site memory | |
