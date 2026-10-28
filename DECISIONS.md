# Fork decisions log

Product decisions for this fork (tonyminibot/OpenKey), written as user stories.
Each entry records what was asked, what was decided, and its status. Newest first.

Status values: **Shipped** (in a build Tony has), **Agreed** (decided, not built yet), **Rejected**.

---

## 5. Auto-switch language from correction behavior

**Status:** Agreed, waiting for "go" (2026-10-28)

**User story.** As someone who types Vietnamese and English all day, I want OpenKey to notice when I'm typing in the wrong mode and switch for me, so I rarely press the switch hotkey.

**Rules**

1. **Double modifier key, VN → EN.** When I press a tone or mark key twice inside a word (for example, e r r), OpenKey switches to English immediately.
   - The output stays the normal Telex result ("er", not "err"). Telex has a good reason for that, so keep it.
2. **Word boundary in VN mode, VN → EN.** At space or punctuation, OpenKey restores the raw keys and switches to English when both of these hold:
   - the raw keys, exactly as typed and in that order, form an English word;
   - the Vietnamese result is not a real Vietnamese syllable.
   - Key order matters. Typing m-o-r-e means "more", so restore and switch. Typing m-o-e-r means the odd Vietnamese "mỏe", so leave it.
   - If the raw keys are English but the result is a real syllable (box → bõ, tax → tã), it's ambiguous. Leave it.
   - If the raw keys aren't English either (a typo), don't switch.
3. **Word boundary in EN mode, EN → VN.** OpenKey converts the word and switches to Vietnamese when all three hold:
   - the raw keys are not an English word;
   - replaying them through OpenKey's own Telex engine gives a real Vietnamese syllable;
   - that result differs from the raw keys.
   - Telex modifiers can sit anywhere in the word, so don't parse markers by hand. "truowfng", "truongwf" and "truwownfg" must all give "trường".
   - Plain words that look the same in both modes ("con", "ban") never trigger.

**Scope.** Good enough for day-to-day use, not every edge case.

**Proposed defaults (not yet confirmed)**

- Add a list of real Vietnamese syllables (about 7k) and a common English word list.
- Add a settings toggle, on by default.
- Pressing the switch hotkey right after an auto-fix undoes that fix.
- An auto-switch updates the per-app and per-site smart-switch memory.
- Runs in all apps except ignored ones.

**Known limits.** A word that is valid in both languages ("as" → á, "or" → ỏ) can't be caught on its own. The next word usually corrects the mode.

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
