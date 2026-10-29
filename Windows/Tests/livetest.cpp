// Live test for Vikey on Windows. Opens a window with an edit control, brings it to the front,
// types each case's keys with SendInput (as a user would; Vikey's hooks see them), and compares
// the text that ends up in the control with the expected text. Cases: cases.tsv (name<TAB>start
// language vi|en<TAB>keys<TAB>expected). Keys: letters, digits, space, punctuation as typed;
// \b Backspace, \n Enter, \t Tab, {alt+z} hotkey (default). Exit code = number of failures.
#include <windows.h>
#include <string>
#include <vector>
#include <fstream>
#include <sstream>
#include <cstdio>
#include "Prefs.h"

static HWND _edit;
static void key(WORD vk, bool shift = false) {
    INPUT in[4] = {}; int n = 0;
    if (shift) { in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = VK_SHIFT; n++; }
    in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = vk; n++;
    in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = vk; in[n].ki.dwFlags = KEYEVENTF_KEYUP; n++;
    if (shift) { in[n].type = INPUT_KEYBOARD; in[n].ki.wVk = VK_SHIFT; in[n].ki.dwFlags = KEYEVENTF_KEYUP; n++; }
    SendInput(n, in, sizeof(INPUT));
    Sleep(12);
}
static void typeKeys(const std::wstring& s) {
    for (size_t i = 0; i < s.size(); i++) {
        wchar_t c = s[i];
        if (c == L'\\' && i + 1 < s.size()) { wchar_t d = s[++i]; if (d == L'b') key(VK_BACK); else if (d == L'n') key(VK_RETURN); else if (d == L't') key(VK_TAB); continue; }
        if (c == L'{') { size_t e = s.find(L'}', i); std::wstring cmd = s.substr(i + 1, e - i - 1); i = e;
            if (cmd == L"alt+z") { INPUT in[4] = {}; in[0].type = in[1].type = in[2].type = in[3].type = INPUT_KEYBOARD; in[0].ki.wVk = VK_MENU; in[1].ki.wVk = 'Z'; in[2].ki.wVk = 'Z'; in[2].ki.dwFlags = KEYEVENTF_KEYUP; in[3].ki.wVk = VK_MENU; in[3].ki.dwFlags = KEYEVENTF_KEYUP; SendInput(4, in, sizeof(INPUT)); Sleep(30); }
            else if (cmd == L"wait") Sleep(1500);
            continue; }
        SHORT v = VkKeyScanW(c);
        if (v == -1) continue;
        key(LOBYTE(v), (HIBYTE(v) & 1) != 0);
    }
}
static std::wstring editText() { int n = GetWindowTextLengthW(_edit); std::wstring s(n, 0); GetWindowTextW(_edit, &s[0], n + 1); return s; }
static std::wstring fromUtf8(const std::string& s) { int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0); std::wstring w(n, 0); MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n); return w; }
static std::string toUtf8(const std::wstring& w) { int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr); std::string s(n, 0); WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr); return s; }

int wmain(int argc, wchar_t** argv) {
    SetConsoleOutputCP(CP_UTF8);
    std::wstring casesPath = argc > 1 ? argv[1] : L"cases.tsv";
    std::ifstream f(casesPath); if (!f) { printf("cannot open cases file\n"); return 99; }
    HINSTANCE inst = GetModuleHandleW(nullptr);
    HWND win = CreateWindowExW(WS_EX_TOPMOST, L"STATIC", L"Vikey live test", WS_OVERLAPPEDWINDOW | WS_VISIBLE, 100, 100, 600, 300, nullptr, nullptr, inst, nullptr);
    _edit = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE | WS_BORDER | ES_MULTILINE | ES_AUTOVSCROLL, 10, 10, 560, 240, win, nullptr, inst, nullptr);
    SendMessageW(_edit, WM_SETFONT, (WPARAM)GetStockObject(DEFAULT_GUI_FONT), TRUE);
    // Bring our window to the front even when started from a console (foreground lock): the Alt-key trick.
    auto toFront = [&]() {
        INPUT alt[2] = {}; alt[0].type = alt[1].type = INPUT_KEYBOARD; alt[0].ki.wVk = alt[1].ki.wVk = VK_MENU; alt[1].ki.dwFlags = KEYEVENTF_KEYUP;
        SendInput(2, alt, sizeof(INPUT));
        SetForegroundWindow(win); BringWindowToTop(win); SetActiveWindow(win); SetFocus(_edit);
    };
    for (int i = 0; i < 10 && GetForegroundWindow() != win; i++) { toFront(); Sleep(200); }
    printf("foreground is %s\n", GetForegroundWindow() == win ? "the test window" : "ANOTHER window");
    Sleep(300);
    int fails = 0, total = 0; std::string line;
    while (std::getline(f, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::vector<std::string> col; std::stringstream ss(line); std::string c; while (std::getline(ss, c, '\t')) col.push_back(c);
        if (col.size() < 4) continue;
        total++;
        // set the start language through the registry + a hotkey-free path: the tray app re-reads InputMethod on reloadSettings;
        // the simplest robust way is to toggle with the hotkey until the tray state matches, so we read it back from the registry.
        int want = col[1] == "vi" ? 1 : 0;
        HWND tray = FindWindowW(L"VikeyTray", nullptr);
        if (!tray) { printf("Vikey is not running\n"); return 98; }
        SendMessageTimeoutW(tray, WM_APP + 2, want, 0, SMTO_NORMAL, 2000, nullptr);   // no hotkey: the hotkey pauses auto switch for 5 s
        Sleep(100);
        if (GetForegroundWindow() != win) toFront();
        SetWindowTextW(_edit, L""); SetFocus(_edit); SendMessageW(_edit, EM_SETSEL, 0, 0); Sleep(150);
        key(VK_ESCAPE);   // Esc: a word break, resets the engine's session like a click would
        typeKeys(fromUtf8(col[2]));
        Sleep(200);
        std::wstring got = editText(); std::wstring exp = fromUtf8(col[3]);
        // the edit control uses \r\n
        std::wstring g2; for (wchar_t ch : got) if (ch != L'\r') g2 += ch;
        bool ok = g2 == exp;
        if (!ok) fails++;
        printf("%s %s: got \"%s\" expected \"%s\"\n", ok ? "ok  " : "FAIL", col[0].c_str(), toUtf8(g2).c_str(), toUtf8(exp).c_str());
        key(VK_ESCAPE);
    }
    printf("%d/%d passed\n", total - fails, total);
    DestroyWindow(win);
    return fails;
}
