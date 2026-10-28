# Fork decisions log

Product decisions for this fork (tonyminibot/OpenKey), written as user stories.
Each entry records what was asked, what was decided, and its status. Newest first.

Status values: **Shipped** (in a build Tony has), **Agreed** (decided, not built yet), **Rejected**.

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

**User story.** As someone who types Vietnamese and English all day, I want OpenKey to notice when I'm typing in the wrong mode and switch for me, so I rarely press the switch hotkey.

### Tony's rules (2026-10-28)

1. **Double modifier key, VN → EN.** Pressing a tone or mark key twice inside a word (e r r) switches to English immediately. The output stays the normal Telex result ("er", not "err"). Telex has a good reason for that.
2. **Word end in VN mode, VN → EN.** If the raw keys, exactly as typed and in that order, are an English word, and the Vietnamese result isn't a real syllable, restore the keys and switch.
   - m-o-r-e means "more", so it switches.
   - m-o-e-r is meant as the odd Vietnamese "mỏe", so it stays.
3. **Word end in EN mode, EN → VN.** If the raw keys aren't English, and replaying them through OpenKey's own Telex engine gives a real Vietnamese syllable, convert and switch.
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
- Tagging OpenKey's own synthesized events.

**Skipped.** The forced-English app list. That is a behavior change Tony didn't ask for.

---

## 1. OpenKey stops typing until restarted

**Status:** Shipped, commit d755b50. Tony is testing on his MacBook for a few weeks from 2026-10-27.

**User story.** As a daily user, I want OpenKey to keep working without quitting and reopening it.

**Cause.** macOS disables the event tap when it times out or on user input (a slow Mac, secure input), and OpenKey never turned it back on.

**Fix.** Re-enable the tap when macOS reports it was disabled. A 2-second watchdog also re-enables it if needed.
