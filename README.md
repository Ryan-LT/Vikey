# Vikey

Vietnamese typing for macOS that switches between Vietnamese and English for you.

Type Telex as usual. When you type an English word in Vietnamese mode, or a Vietnamese word in English mode, Vikey fixes the word and switches the language. No more pressing the switch key every few words.

## Features

- **Telex** with modern or classic tone placement (hoà / hòa), spell checking, and keeping your keys as typed when a word isn't Vietnamese.
- **Auto switch:**
  - `more` → stays English;
  - `treen` → `trên`;
  - `truowfng`, `truongwf`, `truwownfg` → `trường`;
  - `this makes sense` comes out right in Vietnamese mode, because ambiguous words are fixed once the context is clear.
- **Programming-aware:**
  - `var`, `const`, `git push`, `obj.dir` and `my_var` are left alone.
- **Undo:** press Delete right after an automatic fix to undo it.
- **Remembers the language** for each app, and for each website in Chrome, Safari, Arc, Brave, Edge, Vivaldi and Opera.
- **Switch hotkey:** a key with modifiers, or modifiers alone (⌃⇧), with an optional beep.
- **Typing log:** see how often you switch by hand versus how often Vikey switches for you. It's stored on your Mac only, and never records password fields, password managers or terminals.
- **Works with Dvorak and other layouts:** Vikey steps aside automatically for other input languages (Japanese, Chinese…).

## Build

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Vikey.xcodeproj -scheme Vikey -configuration Release build
```

Vikey needs Accessibility permission (to read and rewrite keystrokes). On first launch it walks you through granting it.

## Engine tests

Every typing rule is locked down by tests: rule-tagged cases, golden snapshots of typing a mixed Vietnamese/English corpus, and every Vietnamese syllable.

```sh
Tools/autoswitch/check.sh
```

See [DECISIONS.md](DECISIONS.md) for every rule and why it exists.

## License and credits

Vikey is based on [OpenKey](https://github.com/tuyenvm/OpenKey) by Tuyen Mai, and is distributed under the GNU General Public License v3.0. See [LICENSE](LICENSE).
