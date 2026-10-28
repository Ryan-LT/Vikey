# Vikey decisions log

Product decisions for Vikey (tonyminibot/Vikey, based on OpenKey by Tuyen Mai), written as user stories.
Each entry records what was asked, what was decided, and its status. Newest first.

Status values: **Shipped** (in a build Tony has), **Agreed** (decided, not built yet), **Rejected**.

## How behavior is locked down

Every engine rule decided here has test cases in `Tools/autoswitch/rules/rules.tsv`, tagged with its decision (D5.2, D8.1, ...). Run before and after any rule change:

```sh
Tools/autoswitch/check.sh
```

It checks:
1. **Rule cases.** A failure names the decision it breaks, e.g. "FAIL D5.2: common Vietnamese word (tô) is never switched away from".
2. **Golden snapshot of typing.** The chat corpus, with and without typos, is typed with no manual switching. Every changed line is printed: intended, before, now.
3. **Telex lock.** Every Vietnamese syllable, typed in 3 tone orders in Vietnamese mode, must keep its output.
4. **Metrics.** Manual switches and wrong words must not get worse.

If every listed change is intended, accept them with `Tools/autoswitch/check.sh update`. Add a case for the new decision to `rules.tsv`. GitHub Actions runs the same check on every push.

---

## 13. Catch "thí makes" one word sooner

**Status:** Done 2026-10-28. In the engine and on the website demo.

**Asked by Tony.** "Can we detect this sooner? Ideally correct at 'thí makes'. Currently I type 'thí makes' and 'thí' is still not changed."

**Rule (D13).** A word that looks the same in both modes but is English-only ("makes"), right after an ambiguous word that stayed Vietnamese ("thí", which reads as "this"), means the pair is English. Vikey switches at "makes" and fixes "thí" → "this".
- It fires only when the immediately preceding word is ambiguous and its English reading is at least AS_PLAIN_MARGIN = 15 points (about 30×) more common than its Vietnamese one. "this" vs "thí" clears that by 20.

**Measured**

| Setting | Chat: wrong words with no manual switching | Viblo: manual switches |
|---|---|---|
| Margin 0 | 0.49% → 0.42% | 16 more (Vietnamese words before a tech term like "… token", "… file") |
| Margin 15 (chosen) | 0.49% → 0.46% | 2,116 → 2,117 |

**Bug found and fixed.** After leaving Vietnamese mode at a comma, the engine's "the next word starts after punctuation" flag survived the round trip through English mode. So the first word after switching back was not checked ("em đang tét"). `vAutoSwitchForget()` now resets it.

**Rule lock.** D13 cases were added. The golden diffs were reviewed:
- six chat lines improve: "call thí Sunday" → "this Sunday", "há tô many changes" → "has too many changes";
- one line keeps the rare "bừ" typed as keys.

**Website demo examples (Tony: "too many server examples, be creative").** Five scenes, each one broken by plain Telex:
- merge → mẻge;
- issue → isue;
- "this makes sense" → "thí makes sến";
- version → veión;
- test → tét. (Tony: every scene is English typed while in Vietnamese mode, since that is the convincing case.) Highlights appear as soon as a word diverges.

**Known.** "pair" in Vietnamese mode stays "pải", because the subtitle word list contains the misspelling "pải" (of "phải") with a low score. The fix for later is cleaning typo-like rare syllables out of the Vietnamese list.

---

## 12. Typing log is an opt-in debug feature; credits in the About window

**Status:** Done 2026-10-28 and released as 1.0.1.

**Asked by Tony.**
- "Nhật ký gõ is only a debug feature. Make it opt-in from the app and remove mention of it on the website."
- Move the credit line from the main window into the standard macOS About window.

**Decisions**
- **Typing log off by default.** With the log off, nothing is counted or recorded: every log entry point returns immediately, so the log costs nothing on the typing path.
- **Where it lives now:** the menu bar submenu "Gỡ lỗi" → "Ghi nhật ký gõ" turns it on. "Xem nhật ký gõ…" opens the window and is disabled while logging is off. The main window no longer has a log row.
- **Website:** every mention is removed (changelog, FAQ, privacy). The README documents it under "Debug typing log".
- **Credits:** the main window footer is gone. The standard About panel ("Giới thiệu Vikey" in the menu) shows Tony Dinh, the OpenKey/Tuyen Mai credit, GPL-3.0, and links to vikey.app and GitHub. The Info.plist copyright is "© 2026 Tony Dinh".
- **Repo:** the GitHub repo's website is set to https://vikey.app.

---

## 11. vikey.app, open-source release, compact window

**Status:** Done 2026-10-28. Vikey 1.0.0 is public at https://vikey.app and on GitHub Releases.

**Asked by Tony.**
- Buy vikey.app and make a free, open-source website like clipaudit.app.
- Add the author Tony Dinh, while still crediting OpenKey by Tuyen Mai.
- Opening the app while it runs shows the main window.
- Make the main window smaller and drop the sidebar.
- Put the history in its own window.

**Decisions**

- **Domain.** vikey.app was registered on the Cloudflare dedicated account ($8.20; renews at $14.20).
  - Hosting: Pages project "vikey".
  - www redirects to the apex with a 301.
  - Always-HTTPS is on.
- **Website.** Vietnamese, ClipAudit's layout and style, indigo.
  - **Home hero:** the typing demo is replayed from frames that the real engine produced key by key (`harness frames`), so the site shows exactly what Vikey does.
  - **Screenshots:** 2x, taken on a BetterDisplay HiDPI virtual screen.
  - **Pages:** download (DMG plus checksum), changelog, FAQ, privacy.
  - **Copy review:** reviewed by a subagent (avoid-AI-writing and copywriting rules). That fixed two factual errors: keystroke logging is on by default, and Firefox has no per-site memory.
  - **Phones:** the download button leads to /download, which explains that Vikey is for Mac.
- **Release.** `Tools/release/release.sh <version>` runs:
  1. bump the version;
  2. the engine rule lock;
  3. a universal build (arm64 + x86_64);
  4. sign and notarize the app;
  5. build the DMG (signed, notarized, stapled);
  6. site/downloads and release.json;
  7. the GitHub Release;
  8. deploy.
- **App.**
  - **Window:** one compact window (460 points wide): a language switch on top, then hotkey, auto-switch, typing settings and launch at login, with an author/credit footer.
  - **History:** the typing history opens in its own window.
  - **Reopening:** reopening Vikey shows the main window, and opening it by hand also shows the window.
- **Bug found while taking screenshots.** Letting the window track the SwiftUI content size live crashed AppKit's constraint pass on a HiDPI (Retina) screen. The window is now sized once from the content.

---

## 10. Vikey: new name, new app, fewer features

**Status:** In progress 2026-10-28.

**Asked by Tony.**
- "I want to make this official. Let's call this project Vikey."
- Rename everything, including the repo and package name.
- Rebuild the UI in modern SwiftUI.
- Remove VNI.
- Remove the old, irrelevant features.

He approved Otto's suggested cuts and added: "gõ tắt: remove".

**Decisions**

- **Name.**
  - Repo: tonyminibot/Vikey.
  - App: Vikey.
  - Bundle ID: com.devuap.vikey.
  - Core: VikeyCore.
  - Credit: "based on OpenKey by Tuyen Mai" is kept in the About screen, the file headers and the README, as GPL-3.0 requires.
- **Kept**
  - Telex, with modern or classic tone placement.
  - Spell check, and restore-if-invalid.
  - Switch hotkey and beep.
  - Smart switch per app and per website.
  - Auto-switch and the typing log.
  - Browser autocomplete workarounds, built in.
  - Non-QWERTY layouts (Dvorak etc.), now detected automatically.
  - Turning off for other input languages, now automatic and checked once per input-source change instead of on every keystroke.
  - Launch at login.
- **Removed**
  - VNI, Simple Telex 1 and 2.
  - Code tables other than Unicode (TCVN3, VNI Windows, Unicode compound, CP1258) and remembering a code table per app.
  - The convert tool.
  - Quick Telex (cc → ch…) and quick start/end consonants.
  - Z/F/W/J consonants.
  - Auto-capitalizing the first letter.
  - Macros (gõ tắt).
  - The Ctrl key turning spell check off, and ⌘ turning the app off.
  - Send-keys-one-by-one mode, and the alternative Chromium fix.
  - The update checker (it pointed to upstream).
  - Dock icon and show-on-startup options.
  - Windows and Linux code.
  - The old AppKit/storyboard app.
- **New app.**
  - SwiftUI menu bar app (MenuBarExtra, macOS 13+), generated with xcodegen.
  - Settings window: General, Typing, Auto switch, About.
  - Accessibility onboarding that starts Vikey as soon as permission is granted.
  - Typing-log window and hotkey recorder.
  - SMAppService for launch at login.
  - OpenKey's settings, per-app/per-site memory and typing log are migrated on first launch.
- **Restore-if-invalid is on by default (it was off in OpenKey).** Measured with the simulator:
  - chat: 0.95 → 0.84 manual switches per 100 words;
  - Viblo: 1.02 → 0.79;
  - chat with typos: 1.18 → 0.96;
  - Viblo with typos: 1.37 → 0.95;
  - wrong words drop too.

  The test harness now runs with the app's real defaults. The Telex lock changes were reviewed: only invalid "syllables" from the subtitle list (âi, bãt, bĩan…) are now kept as typed; no real syllable changed. D9's expected text became the typed keys, while the language still stays Vietnamese. A D10 rule was added.
- **Bug fixed along the way.** An app without a bundle ID no longer makes the per-app memory save to the previous app.

**Verified**
- The rule-lock suite was unchanged after every removal step: 51/51 rules, identical snapshots and metrics.
- The new app passes the live typing suite.

---

## 9. Typos must not flip the language

**Status:** Fixed 2026-10-28 and sent as OpenKey-2.0.4-typo.

**Reported by Tony.** He meant "lắm" but typed "lanwm": "I guess this will happen a lot."

**Findings**

- **EN mode, fixed inside the word:** fine. "lan⌫wsm" converts to "lắm", because the word buffer follows Backspace.
- **VN mode, a typo at the word end:** the "unknown foreign word" rule from decision 8 restored "lănm" to "lanwm" and switched to English. Backspace undo recovers it, but it's wrong.

**Decision.** A word that uses Vietnamese-only modifiers (â ê ô ă ơ ư đ) is never treated as an unknown foreign word. It's a Vietnamese typo and stays in Vietnamese mode. Foreign words like TestFlight and analytics only pick up tone marks, so they still restore.

**Measured.** The simulator now injects realistic typos into 3% of Vietnamese words: a neighbouring key, a dropped letter or a doubled letter.

| Corpus with typos | No guard | Guard |
|---|---|---|
| Chat: manual switches per 100 words | 1.32 | 1.20 |
| Chat: wrong words | 0.33% | 0.13% |
| Viblo: manual switches per 100 words | 1.60 | 1.39 |
| Viblo: wrong words | 0.55% | 0.24% |

On typo-free text the guard costs a little (chat 0.95 → 1.04), but real typing has typos.

**Refined 2026-10-28.** The rule-lock suite caught a conflict: the guard broke D8.2, because "analytics" Telexes to "ânlytics" and the â looked like a Vietnamese mark. The guard now applies only to words whose keys have a single vowel group, since no Vietnamese syllable has more. Result: all 49 rule cases pass; clean chat is back to 0.95 manual switches per 100 words, Viblo 1.02, chat with typos 1.18, Viblo with typos 1.37.

**Also in this build.** The typing log records which shortcut ended a word (⌥⌫, ⌘A…) instead of just "shortcut".

---

## 8. Tuning with a mixed-text typing simulation

**Status:** Built 2026-10-28 and sent as OpenKey-2.0.4-lookback. The double-key change was approved by Tony the same day and shipped in OpenKey-2.0.4-err.

**Reported by Tony.** "I typed 'this makes' in VN mode and got 'thí makes'. Can we correct thí → this?" Then: "Run the engine over a large mixed Vietnamese/English text, key by key, to see how close it gets without manual switching."

**Method.** `Tools/autoswitch/sim` types two corpora into the real engine and mirrors the macOS layer:
- 21k words of chat-style messages;
- 269k words of Viblo tech articles.

Vietnamese words are typed in Telex with varied tone positions: 60% at the end, 25% after the vowel, 15% after the vowel cluster. Two user models:
- **Ideal:** switches by hand only when the next word would come out wrong. Metric: manual switches per 100 words.
- **Lazy:** never switches. Metric: wrong words, and the share of messages typed perfectly.

**Results, manual switches per 100 words (chat / Viblo)**

| Build | Chat | Viblo |
|---|---|---|
| Auto-switch off | 11.98 | 5.41 |
| First auto-switch build | 1.82 | 1.41 |
| This build | 1.51 | 1.12 |
| This build + keep both letters on the double key | 0.95 | 1.00 |

With no manual switching at all, wrong words go 9.8% → 1.2% (chat) and 3.2% → 1.0% (Viblo). With the double-key change, 94% of chat messages are typed perfectly.

### Decisions

- **Look-back.** When a word confidently switches the language, the 1–2 words just before it are fixed too, if they were ambiguous and joined by single spaces. "this makes sense" no longer leaves "thí"; "check mail cos theer" becomes "check mail có thể". Words that look the same in both modes ("makes", "cho") are passed through. It helps most when nobody switches by hand.
- **Unknown foreign words.** In VN mode, a word that is neither a real syllable nor in the English list, and fails the engine's own spelling rules, is restored and switches to English: TestFlight, analytics, workflow, postgresql. Without the spelling-rule check, rare real syllables like riệt and chịt were wrongly restored. Minimum 3 letters.
- **Undo moved to Backspace.** This changes decision 5. The simulation showed the hotkey can't mean both "undo that fix" and "the next word is in the other language": after "wifi" was correctly fixed, pressing the hotkey to type "tốt" reverted it to "ừii". Backspace right after an auto-fix now restores the original word and language, like macOS autocorrect. The hotkey is always a plain switch.
- **"cors gif" in EN mode now becomes "có gì".** Look-back judges the common Vietnamese phrase more likely.
- **Decided by Tony, 2026-10-28: keep both letters on a double key ("let's switch to 'err', I want to try it out").** Doubled-letter English words (issue, miss, sorry, pass, office, error, password, traffic) cause about a third of the remaining manual switches, because Telex drops one letter. Keeping both letters when the double key switches to English cuts chat manual switches from 1.51 to 0.95 per 100 words. This replaces rule 1's earlier "er" output: when the doubled tone key switches to English, it now outputs both letters (err, issue, sorry). Default on, controlled by `AS_DOUBLE_KEEP`.
- **Bug fixed along the way.** Look-back history is now cleared when the language changes from the menu and on every app switch, so a rewrite can never use stale word lengths.

---

## 7. Typing log to measure and tune auto-switch

**Status:** Built 2026-10-28 and sent as OpenKey-2.0.4-log. Tony uses it and sends the log for tuning.

**User story.** As the user, I want Vikey to record how often I switch language by hand versus how often it switches for me, plus what I typed, so the engine can be tuned. The goal is the fewest manual switches.

**What is recorded.** The log is `~/Library/Application Support/Vikey/typing-log.jsonl`, one JSON object per line. The file is user-only (0600) and rotates at 20 MB, keeping one old file.

| Event | When | Fields |
|---|---|---|
| word | each word | raw keys as typed (⌫ = Backspace), starting language, the key that ended it, app, website |
| auto | automatic switch | rule: vi_word_to_en, en_word_to_vi or double_key |
| manual | switch hotkey or menu | — |
| undo | the switch hotkey pressed right after an automatic switch, with no other key in between | counted separately from manual |
| context | smart switch changed the language for an app or website | — |

- Words are logged as raw keys, not output. Replaying the keys through the test harness reproduces exactly what the engine did, so new rules can be evaluated on real typing.
- Daily counters cover words (VN or EN), manual switches, each auto rule, undos and context switches.

**Privacy.** Switch counts are always kept. Word keys are never recorded:
- while macOS secure input is on (password fields);
- in password managers: 1Password, Bitwarden, Apple Passwords, Keychain Access, LastPass, Dashlane, Enpass, KeePassXC, NordPass;
- in terminals: Terminal, iTerm2, Warp, Ghostty, Alacritty, kitty, WezTerm, Hyper, Termius. sudo and ssh passwords there are typed without secure input.

Word recording can be turned off in the log window. Nothing leaves the Mac; Tony sends the file himself.

**Screen.** The status menu gets "Nhật ký gõ...". The window shows:
- counts for today, 7 days and all time, including manual switches per 100 words;
- the latest 300 events, with manual switches and undos in orange;
- the word-recording checkbox;
- Refresh, Open log file and Clear log buttons.

**Performance.** Each key appends one character to an in-memory buffer. Each word creates one JSON line in memory. The file is written on a background queue every 10 s or every 8 KB.

**Analysis.** `Tools/autoswitch/analyze_log.py` prints the counts and every manual switch or undo with the words around it. Those are the cases to fix.

---

## 6. Auto-switch must not touch programming words

**Status:** Fixed 2026-10-28 and sent as OpenKey-2.0.4-autoswitch2.

**Reported by Tony.** "I typed `var`, a popular short form for variable. We probably need to handle a lot of things for developers too."

**Cause.** "var" isn't in the English dictionary, and its Telex replay "vả" is a real Vietnamese word, so English mode converted it.

**Decisions**

- **Programming words count as English.** About 250 terms were added: keywords, CLI tools, file types and common short forms like var, const, def, args, ctx, deps, refs, uri. Identifier words that collided with Vietnamese were also added. These were found by splitting camelCase/snake_case identifiers across real projects and replaying each through the engine, then reviewed by hand. Only that reviewed list is in the repo.
- **Identifier guard.** Only a word that starts after a space, Enter, Tab, click or shortcut is ever checked. Text after . _ - / ( and similar is never touched, so obj.dir, os.path, my_var and image.gif stay as typed. This applies in both modes.
- **Not added.** "gif" and "conf" type the very common Vietnamese "gì" and "còn". Those win in English mode when the word stands alone. File names are covered by the guard.
- **Vietnamese mode keeps Vietnamese.** I tried letting programming words beat moderately common Vietnamese words in VN mode, and rejected it: it broke "mô tả" (tar) and "vả lại" (var). In VN mode, "var" stays "vả".
- **Known limit, from Tony's double-key rule.** In VN mode, err, error and less lose one letter (er, eror, les) and switch to English, because Telex consumes the doubled key.

**Result.** In English mode, 0 of the ~250 programming words are changed except "gif", which is deliberate. All regression cases and live cases pass.

---

## 5. Auto-switch language from correction behavior

**Status:** Built 2026-10-28 and sent as OpenKey-2.0.4-autoswitch. Tony is testing.

**User story.** As someone who types Vietnamese and English all day, I want Vikey to notice when I'm typing in the wrong mode and switch for me, so I rarely press the switch hotkey.

### Tony's rules (2026-10-28)

1. **Double modifier key, VN → EN.** Pressing a tone or mark key twice inside a word (e r r) switches to English immediately. The output stays the normal Telex result ("er", not "err"). Telex has a good reason for that.
2. **Word end in VN mode, VN → EN.** If the raw keys, exactly as typed and in that order, are an English word, and the Vietnamese result isn't a real syllable, restore the keys and switch.
   - m-o-r-e means "more", so it switches.
   - m-o-e-r is meant as the odd Vietnamese "mỏe", so it stays.
3. **Word end in EN mode, EN → VN.** If the raw keys aren't English, and replaying them through the engine's own Telex rules gives a real Vietnamese syllable, convert and switch.
   - Modifiers can sit anywhere: "truowfng", "truongwf" and "truwownfg" all give "trường".
   - Plain words that look the same in both languages never trigger.
4. **Scope.** Good enough for day-to-day use, not every edge case.
5. **Performance.** Nothing we add may affect the app's performance.

### Decisions made while building (Otto)

- **Word lists.** Two lists are compiled into the binary, so nothing is loaded or parsed at runtime:
  - about 6.9k real Vietnamese syllables;
  - about 41k English words, with subtitle frequencies (FrequencyWords, CC BY-SA 4.0).
  - The English list keeps only words the macOS spell checker accepts, lowercase or capitalized. It also gets chat shorthand without apostrophes (dont, hes, im, lol) and developer words (rust, json, repo).
- **When both readings are real words.** The keys could be an English word and also give a real syllable (box → bõ, last → lát). Then the current language is kept unless both of these hold:
  - its word is rare: under about 10 per million for Vietnamese, or under about 1 per million for English;
  - the other reading is at least 10x more common.
- **What that means in practice:**
  - In VN mode, "best", "must", "test", "most", "rest", "list", "now", "how", "his", "is", "of" all restore to English.
  - "last" and "lost" stay "lát" and "lót", because those are common Vietnamese words. The point is to protect tô, thí, á, sê.
  - In EN mode, real English words like "theme", "rust", "sex", "car" and "been" are never converted.
- **Acronyms and identifiers.** A word with 2 or more capital letters is never converted (USA, EST, camelCase).
- **Word ends.** The checks run on space, comma, period, semicolon, Enter, ? and !. They don't run on arrows, Tab, Esc, clicks, shortcuts or apostrophes, so "hasn" in "hasn't" is never checked.
- **Undo.** Pressing the switch hotkey right after an auto-fix puts the original word and language back. Any other key or click cancels the undo. Text undo works in the Unicode code table; in other code tables the hotkey only switches the language.
- **Smart switch memory.** An auto-switch behaves like the hotkey, so it updates the per-app and per-site memory.
- **Setting.** The menu item "Tự chuyển Anh/Việt khi gõ" is on by default. It works in the Telex family only; it's disabled for VNI.
- **Performance, measured.**
  - Nothing runs per letter.
  - At a word end in EN mode, the check is a replay of up to 30 keys plus two binary searches, about 1 µs.
  - In VN mode, the check is two binary searches.
  - No allocation, file access or system calls on the typing path.
- **Platform.** macOS only. The Windows build would need `vAutoSwitchByTyping` defined.

### Tests

- `Tools/autoswitch/test`: 28 regression cases on the real engine, plus a bulk accuracy test.
- Live tests on the real app with synthetic keystrokes: 18 cases in a native text view and 8 in a Chrome textarea, all passing, including undo.

---

## 4. Learned (neural-network) switching

**Status:** Rejected (2026-10-27)

**User story.** As a user, I want a model trained on my own behavior to predict the right language for each new context, so manual switches go down over time.

**Decision.** Tony decided it's overkill and dropped it. Nothing was built.

---

## 3. Smart switch remembers the language per website

**Status:** Shipped in build OpenKey-2.0.4-site, commit e68b851 (2026-10-27)

**User story.** As a browser user, I want smart switch to remember my language per website, not just per browser. Then github.com stays English and facebook.com stays Vietnamese.

**How it works**

- Supported browsers: Chrome (stable, beta, canary), Brave, Edge, Arc, Vivaldi, Chromium, Opera, Safari and Safari Technology Preview.
- The memory key becomes `bundle|host`. A leading "www." is dropped.
- The tab URL is read with AppleScript, off the main thread.
  - It is polled every second while a browser is frontmost.
  - It is re-checked shortly after a click or a ⌘/⌃ key.
- A new site keeps the current language until I switch there.
- Non-web tabs (new tab, chrome://) use the browser's app-level memory.
- The setting is `SmartSwitchPerSite` and defaults to on.
- The first use of each browser asks for Automation permission.

**Not supported.** Firefox has no AppleScript tab URL.

**Related fix.** The restored language value is now masked to the language bit, so it works when "remember code table" is on.

---

## 2. Take the good parts of upstream PR #333

**Status:** Shipped, commit c126604 (2026-10-27)

**User story.** As a user, I want the reliability fixes from upstream PR #333, but not its behavior changes.

**Taken**

- Input-source over-release and leak fix.
- No longer tapping mouse-drag events.
- Tagging the app's own synthesized events.

**Skipped.** The forced-English app list. That is a behavior change Tony didn't ask for.

---

## 1. The app stops typing until restarted

**Status:** Shipped, commit d755b50. Tony is testing on his MacBook for a few weeks from 2026-10-27.

**User story.** As a daily user, I want Vikey to keep working without quitting and reopening it.

**Cause.** macOS disables the event tap when it times out or on user input (a slow Mac, secure input), and the app never turned it back on.

**Fix.** Re-enable the tap when macOS reports it was disabled. A 2-second watchdog also re-enables it if needed.
