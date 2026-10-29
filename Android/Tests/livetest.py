#!/usr/bin/env python3
"""Live typing test on the Android emulator: taps the Vikey keyboard through the real touch path and reads
the field back. Same cases as Windows/Tests/cases.tsv and Linux/Tests/livetest.py. Needs a DEBUG build
installed, the Vikey IME selected, and the app's main screen open (the "Try the keyboard" field).
Exit code = number of failures."""
import subprocess, sys, os, re, time, html
sys.path.insert(0, os.path.dirname(__file__))
from tap_type import type_text, sh, ime_top, layout
CASES = os.path.join(os.path.dirname(__file__), "..", "..", "Windows", "Tests", "cases.tsv")
FIELD_Y = None

def field_text():
    sh("uiautomator dump /sdcard/ui.xml >/dev/null"); x = sh("cat /sdcard/ui.xml")
    m = re.search(r'class="android.widget.EditText"[^>]*text="([^"]*)"', x) or re.search(r'text="([^"]*)"[^>]*class="android.widget.EditText"', x)
    return html.unescape(m.group(1)) if m else None

def find_field():
    sh("uiautomator dump /sdcard/ui.xml >/dev/null"); x = sh("cat /sdcard/ui.xml")
    m = re.search(r'<node[^>]*class="android.widget.EditText"[^>]*bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', x)
    if not m: raise SystemExit("no EditText on screen")
    l, t, r, b = map(int, m.groups()); return (l + r) // 2, (t + b) // 2

def clear_field():
    # key events from adb go to the app, not the keyboard: an outside change, which resets the engine
    sh("input keyevent " + " ".join(["112"] * 40) + "; input keyevent " + " ".join(["67"] * 80))   # forward-delete, then delete
    time.sleep(0.4)

def main():
    fx, fy = find_field()
    sh("input tap %d %d" % (fx, fy)); time.sleep(1)
    sh("am broadcast -a app.vikey.DEBUG -p app.vikey --ez autocap false >/dev/null"); time.sleep(0.8)
    sh("input tap %d %d" % (fx, fy)); time.sleep(0.6)
    top = ime_top(); L = layout()
    fails = 0; total = 0
    for line in open(CASES, encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        name, start, keys, expected = line.rstrip("\n").split("\t")[:4]
        total += 1
        clear_field()
        sh("am broadcast -a app.vikey.DEBUG -p app.vikey --ei lang %d >/dev/null" % (1 if start == "vi" else 0)); time.sleep(0.4)
        for part in re.split(r"(\{alt\+z\}|\\b|\\n)", keys):
            if not part: continue
            if part == "{alt+z}": vx, vy = L["\x01"]; sh("input tap %d %d" % (vx, top + vy)); time.sleep(0.2)
            elif part == "\\b": type_text("\b", top)
            elif part == "\\n": type_text("\n", top)
            else: type_text(part, top)
        time.sleep(0.5)
        got = field_text()
        ok = got == expected
        if not ok: fails += 1
        print("%-4s %-28s got=%r expected=%r" % ("ok" if ok else "FAIL", name, got, expected))
    sh("am broadcast -a app.vikey.DEBUG -p app.vikey --ez autocap true >/dev/null")
    print("%d/%d passed" % (total - fails, total))
    sys.exit(fails)
if __name__ == "__main__": main()
