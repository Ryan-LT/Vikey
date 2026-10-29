#!/usr/bin/env python3
"""Live typing test on Linux: types each case into a GTK text entry (X11/XWayland) with xdotool while the
Vikey IBus engine is active, reads the text back, compares. Same cases as Windows/Tests/cases.tsv.
usage: GDK_BACKEND=x11 python3 Linux/Tests/livetest.py [cases.tsv]
needs: xdotool, ibus running with vikey as the current engine (ibus engine vikey), python3-gi."""
import gi, sys, os, subprocess, time, json
gi.require_version('Gtk', '4.0'); from gi.repository import Gtk, GLib
cases = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', '..', 'Windows', 'Tests', 'cases.tsv')
SET = os.path.expanduser('~/.config/vikey/settings.json')
def set_lang(vi):
    d = json.load(open(SET)) if os.path.exists(SET) else {}
    d['InputMethod'] = 1 if vi else 0; d['LanguageQuiet'] = 1   # the engine reloads the file and takes the language without the 5 s pause
    os.makedirs(os.path.dirname(SET), exist_ok=True); json.dump(d, open(SET, 'w')); time.sleep(0.4)
def xdo(*a): subprocess.run(['xdotool', *a], check=False)
class App(Gtk.Application):
    def __init__(self): super().__init__(application_id='app.vikey.LiveTest'); self.results = []
    def do_activate(self):
        self.win = Gtk.ApplicationWindow(application=self, title='VikeyLiveTest'); self.win.set_default_size(600, 120)
        self.entry = Gtk.Entry(); self.win.set_child(self.entry); self.win.present()
        GLib.timeout_add(800, self.run)
    def run(self):
        xdo('search', '--name', 'VikeyLiveTest', 'windowactivate', '--sync'); time.sleep(0.3)
        total = fails = 0
        for line in open(cases, encoding='utf-8'):
            if not line.strip() or line.startswith('#'): continue
            name, start, keys, expected = line.rstrip('\n').split('\t')[:4]
            total += 1
            self.entry.set_text(''); self.entry.grab_focus(); set_lang(start == 'vi')
            xdo('key', '--clearmodifiers', 'Escape'); time.sleep(0.1)
            i = 0
            while i < len(keys):
                c = keys[i]
                if c == '\\' and i + 1 < len(keys): d = keys[i+1]; xdo('key', {'b': 'BackSpace', 'n': 'Return', 't': 'Tab'}.get(d, d)); i += 2; continue
                if c == '{': e = keys.index('}', i); cmd = keys[i+1:e]; xdo('key', '--clearmodifiers', cmd.replace('alt+z', 'alt+z')); time.sleep(0.3); i = e + 1; continue
                if c == ' ': xdo('key', 'space')
                else: xdo('type', '--delay', '25', c)
                i += 1
            time.sleep(0.5)
            while GLib.MainContext.default().iteration(False): pass
            got = self.entry.get_text(); ok = got == expected
            if not ok: fails += 1
            print(f"{'ok  ' if ok else 'FAIL'} {name}: got {got!r} expected {expected!r}", flush=True)
            xdo('key', 'Escape')
        print(f"{total - fails}/{total} passed", flush=True)
        self.quit(); os._exit(0 if fails == 0 else 1)
App().run(None)
