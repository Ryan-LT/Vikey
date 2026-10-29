#include "Settings.h"
#include "Core.h"
#include "Prefs.h"
#include "KeyMap.h"
#include "resource.h"
#include <commctrl.h>
#include <shellapi.h>
#include <string>
#include <vector>
#include <fstream>
#pragma comment(lib, "comctl32.lib")

namespace vikey { namespace ui {

enum { C_VIET = 200, C_ENG, C_HOTKEY, C_BEEP, C_AUTO, C_PAUSE, C_SMART, C_SITE, C_SPELL, C_RESTORE, C_MODERN, C_LOGIN, C_LOG, C_LOGKEYS, C_LOGBTN, C_SITE_BTN, C_CLOSE,
       L_REFRESH = 300, L_OPEN, L_CLEAR };
static HWND _win, _hotkeyEdit, _viet, _eng, _logWin, _logList, _logStats;
static HFONT _font, _bold;
static int _hotkey = 0x7A000206;
static WNDPROC _editProc;

static std::wstring hotkeyText(int hk) {
    std::wstring s;
    if (HAS_CONTROL(hk)) s += L"Ctrl+"; if (HAS_OPTION(hk)) s += L"Alt+"; if (HAS_SHIFT(hk)) s += L"Shift+"; if (HAS_COMMAND(hk)) s += L"Win+";
    int k = GET_SWITCH_KEY(hk);
    if (k == 0xFE) { if (!s.empty()) s.pop_back(); return s.empty() ? L"(chưa đặt)" : s; }
    Uint16 ch = keyCodeToCharacter(k | CAPS_MASK);
    if (ch) s += (wchar_t)ch; else if (k == KEY_SPACE) s += L"Space"; else s += L"?";
    return s;
}

/// The hotkey box: records the next key combination pressed in it.
static LRESULT CALLBACK hotkeyEditProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN) {
        DWORD vk = (DWORD)wp;
        bool ctrl = GetKeyState(VK_CONTROL) < 0, alt = GetKeyState(VK_MENU) < 0, shift = GetKeyState(VK_SHIFT) < 0, win = GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0;
        bool isMod = vk == VK_CONTROL || vk == VK_MENU || vk == VK_SHIFT || vk == VK_LWIN || vk == VK_RWIN || vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_LMENU || vk == VK_RMENU || vk == VK_LSHIFT || vk == VK_RSHIFT;
        int key = isMod ? 0xFE : (int)engineKey(vk);
        if (key == KEY_EMPTY) return 0;
        int hk = key | (ctrl ? 0x100 : 0) | (alt ? 0x200 : 0) | (win ? 0x400 : 0) | (shift ? 0x800 : 0) | (_hotkey & 0x8000);
        if (key == 0xFE && !(ctrl || alt || shift || win)) return 0;
        _hotkey = hk;
        if (!isMod || true) { SetWindowTextW(h, hotkeyText(hk).c_str()); }
        if (!isMod) { prefs::setInt(L"SwitchKeyStatus", hk); core::reloadSettings(); }
        return 0;
    }
    if (msg == WM_KEYUP || msg == WM_SYSKEYUP) {
        // modifiers-only hotkey is committed when the last modifier goes up
        if (GET_SWITCH_KEY(_hotkey) == 0xFE && GetKeyState(VK_CONTROL) >= 0 && GetKeyState(VK_MENU) >= 0 && GetKeyState(VK_SHIFT) >= 0) { prefs::setInt(L"SwitchKeyStatus", _hotkey); core::reloadSettings(); }
        return 0;
    }
    if (msg == WM_CHAR) return 0;
    return CallWindowProcW(_editProc, h, msg, wp, lp);
}

static HWND add(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, HFONT f = nullptr) {
    HWND c = CreateWindowW(cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, _win, (HMENU)(INT_PTR)id, nullptr, nullptr);
    SendMessageW(c, WM_SETFONT, (WPARAM)(f ? f : _font), TRUE); return c;
}
static HWND check(const wchar_t* text, int y, int id, const wchar_t* pref, int fallback) {
    HWND c = add(L"BUTTON", text, BS_AUTOCHECKBOX, 24, y, 400, 22, id);
    SendMessageW(c, BM_SETCHECK, prefs::getInt(pref, fallback) ? BST_CHECKED : BST_UNCHECKED, 0); return c;
}
static void toggle(HWND c, const wchar_t* pref) { prefs::setInt(pref, SendMessageW(c, BM_GETCHECK, 0, 0) == BST_CHECKED); core::reloadSettings(); }

void languageChanged(int lang) {
    if (!_win) return;
    SendMessageW(_viet, BM_SETCHECK, lang ? BST_CHECKED : BST_UNCHECKED, 0);
    SendMessageW(_eng, BM_SETCHECK, lang ? BST_UNCHECKED : BST_CHECKED, 0);
}

static LRESULT CALLBACK settingsProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_COMMAND: {
        int id = LOWORD(wp); HWND c = (HWND)lp;
        switch (id) {
        case C_VIET: core::setLanguageByUser(1); break;
        case C_ENG: core::setLanguageByUser(0); break;
        case C_BEEP: _hotkey = (_hotkey & ~0x8000) | (SendMessageW(c, BM_GETCHECK, 0, 0) == BST_CHECKED ? 0x8000 : 0); prefs::setInt(L"SwitchKeyStatus", _hotkey); core::reloadSettings(); break;
        case C_AUTO: toggle(c, L"AutoSwitchByTyping"); break;
        case C_PAUSE: toggle(c, L"PauseAutoAfterManual"); break;
        case C_SMART: toggle(c, L"UseSmartSwitchKey"); break;
        case C_SITE: toggle(c, L"SmartSwitchPerSite"); break;
        case C_SPELL: toggle(c, L"Spelling"); break;
        case C_RESTORE: toggle(c, L"RestoreIfInvalidWord"); break;
        case C_MODERN: toggle(c, L"ModernOrthography"); break;
        case C_LOGIN: prefs::setLaunchAtLogin(SendMessageW(c, BM_GETCHECK, 0, 0) == BST_CHECKED); break;
        case C_LOG: toggle(c, L"TypingLogEnabled"); break;
        case C_LOGKEYS: toggle(c, L"TypingLogKeys"); break;
        case C_LOGBTN: showTypingLog(GetModuleHandleW(nullptr)); break;
        case C_CLOSE: DestroyWindow(h); break;
        }
        return 0; }
    case WM_CTLCOLORSTATIC: { SetBkMode((HDC)wp, TRANSPARENT); return (LRESULT)GetSysColorBrush(COLOR_WINDOW); }
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _win = nullptr; return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

void showSettings(HINSTANCE inst, bool firstRun) {
    if (_win) { SetForegroundWindow(_win); return; }
    INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_STANDARD_CLASSES}; InitCommonControlsEx(&icc);
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = settingsProc; wc.hInstance = inst; wc.lpszClassName = L"VikeySettings"; wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); wc.hCursor = LoadCursor(nullptr, IDC_ARROW); wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_APP)); RegisterClassW(&wc); reg = true; }
    if (!_font) { _font = CreateFontW(-15, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI"); _bold = CreateFontW(-15, 0, 0, 0, FW_SEMIBOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI"); }
    int H = firstRun ? 640 : 560;
    _win = CreateWindowExW(WS_EX_DLGMODALFRAME, L"VikeySettings", L"Vikey", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, CW_USEDEFAULT, CW_USEDEFAULT, 476, H, nullptr, nullptr, inst, nullptr);
    int y = 16;
    if (firstRun) {
        add(L"STATIC", L"Chào mừng đến với Vikey", 0, 24, y, 420, 24, 0, _bold); y += 28;
        add(L"STATIC", L"Vikey đã chạy, biểu tượng V/E nằm ở khay hệ thống (góc dưới bên phải, có thể trong mũi tên ^). Gõ Telex như bình thường; Vikey tự chuyển Anh/Việt khi bạn gõ nhầm chế độ. Bấm Delete ngay sau một lần tự sửa để hoàn tác.", 0, 24, y, 420, 64, 0); y += 76;
    }
    add(L"STATIC", L"Ngôn ngữ", 0, 24, y, 120, 22, 0, _bold);
    _viet = add(L"BUTTON", L"Tiếng Việt", BS_AUTORADIOBUTTON | WS_GROUP, 160, y, 120, 22, C_VIET);
    _eng = add(L"BUTTON", L"English", BS_AUTORADIOBUTTON, 300, y, 120, 22, C_ENG);
    languageChanged(core::language()); y += 34;
    add(L"STATIC", L"Phím chuyển", 0, 24, y, 120, 22, 0, _bold);
    _hotkey = prefs::getInt(L"SwitchKeyStatus", 0); if (!_hotkey) _hotkey = 0x7A000206;
    _hotkeyEdit = add(L"EDIT", hotkeyText(_hotkey).c_str(), WS_BORDER | ES_CENTER, 160, y - 2, 140, 26, C_HOTKEY);
    _editProc = (WNDPROC)SetWindowLongPtrW(_hotkeyEdit, GWLP_WNDPROC, (LONG_PTR)hotkeyEditProc);
    HWND beep = add(L"BUTTON", L"Kêu bíp", BS_AUTOCHECKBOX, 316, y, 110, 22, C_BEEP); SendMessageW(beep, BM_SETCHECK, HAS_BEEP(_hotkey) ? BST_CHECKED : BST_UNCHECKED, 0);
    y += 26; add(L"STATIC", L"Bấm vào ô rồi nhấn tổ hợp phím, hoặc chỉ các phím bổ trợ (Ctrl+Shift…).", 0, 160, y, 290, 36, 0); y += 40;
    add(L"STATIC", L"Tự chuyển", 0, 24, y, 200, 22, 0, _bold); y += 26;
    check(L"Tự chuyển Anh/Việt khi gõ", y, C_AUTO, L"AutoSwitchByTyping", 1); y += 24;
    check(L"Tạm dừng tự chuyển 5 giây sau khi chuyển bằng tay", y, C_PAUSE, L"PauseAutoAfterManual", 1); y += 24;
    check(L"Nhớ ngôn ngữ theo ứng dụng", y, C_SMART, L"UseSmartSwitchKey", 1); y += 24;
    check(L"Nhớ ngôn ngữ theo trang web (Chrome, Edge, Brave, Vivaldi, Opera, Firefox)", y, C_SITE, L"SmartSwitchPerSite", 1); y += 34;
    add(L"STATIC", L"Gõ", 0, 24, y, 200, 22, 0, _bold); y += 26;
    check(L"Kiểm tra chính tả", y, C_SPELL, L"Spelling", 1); y += 24;
    check(L"Giữ nguyên phím khi từ không phải tiếng Việt", y, C_RESTORE, L"RestoreIfInvalidWord", 1); y += 24;
    check(L"Bỏ dấu kiểu mới (oà, uý)", y, C_MODERN, L"ModernOrthography", 1); y += 34;
    add(L"STATIC", L"Hệ thống", 0, 24, y, 200, 22, 0, _bold); y += 26;
    HWND login = add(L"BUTTON", L"Khởi động cùng Windows", BS_AUTOCHECKBOX, 24, y, 400, 22, C_LOGIN); SendMessageW(login, BM_SETCHECK, prefs::launchAtLogin() ? BST_CHECKED : BST_UNCHECKED, 0); y += 24;
    check(L"Ghi nhật ký gõ (gỡ lỗi, chỉ lưu trên máy này)", y, C_LOG, L"TypingLogEnabled", 0);
    add(L"BUTTON", L"Nhật ký gõ…", 0, 330, y - 2, 110, 26, C_LOGBTN); y += 40;
    add(L"STATIC", L"Vikey " VIKEY_VERSION_W L" · Tony Dinh · dựa trên OpenKey của Tuyen Mai (GPL-3.0) · vikey.app", 0, 24, y, 420, 20, 0);
    y += 28;
    add(L"BUTTON", firstRun ? L"Bắt đầu" : L"Đóng", BS_DEFPUSHBUTTON, 340, y, 100, 28, C_CLOSE);
    RECT r; GetClientRect(_win, &r); SetWindowPos(_win, nullptr, 0, 0, 476, y + 40 + (H - r.bottom), SWP_NOMOVE | SWP_NOZORDER);
    ShowWindow(_win, SW_SHOW); SetForegroundWindow(_win);
    if (firstRun) prefs::setInt(L"FirstRunDone", 1);
}

// ---- Typing log window --------------------------------------------------------------------
static std::wstring fromUtf8(const std::string& s) { int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0); std::wstring w(n, 0); MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n); return w; }
static void refreshLog() {
    std::wstring path = core::typingLogPath();
    std::ifstream f(path, std::ios::binary); std::vector<std::string> lines; std::string l;
    while (std::getline(f, l)) { if (!l.empty()) lines.push_back(l); if (lines.size() > 2000) lines.erase(lines.begin(), lines.begin() + 1000); }
    size_t start = lines.size() > 300 ? lines.size() - 300 : 0;
    std::wstring text; for (size_t i = start; i < lines.size(); i++) { text += fromUtf8(lines[i]); text += L"\r\n"; }
    SetWindowTextW(_logList, text.c_str());
    // counters live in the registry as TLStat_<day>_<name>
    SYSTEMTIME st; GetLocalTime(&st); wchar_t day[16]; swprintf_s(day, L"%04d-%02d-%02d", st.wYear, st.wMonth, st.wDay);
    auto cnt = [&](const wchar_t* name) { std::wstring k = std::wstring(L"TLStat_") + day + L"_" + name; return prefs::getInt(k.c_str(), 0); };
    int words = cnt(L"words_vi") + cnt(L"words_en"), manual = cnt(L"manual"), undo = cnt(L"undo");
    wchar_t s[256]; swprintf_s(s, L"Hôm nay: %d từ, %d lần chuyển tay (%.2f / 100 từ), %d hoàn tác. Tệp: %s", words, manual, words ? manual * 100.0 / words : 0.0, undo, path.c_str());
    SetWindowTextW(_logStats, s);
}
static LRESULT CALLBACK logProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_COMMAND:
        if (LOWORD(wp) == L_REFRESH) refreshLog();
        else if (LOWORD(wp) == L_OPEN) ShellExecuteW(nullptr, L"open", prefs::appDataDir().c_str(), nullptr, nullptr, SW_SHOW);
        else if (LOWORD(wp) == L_CLEAR) { core::clearTypingLog(); refreshLog(); }
        return 0;
    case WM_SIZE: { RECT r; GetClientRect(h, &r); MoveWindow(_logList, 12, 48, r.right - 24, r.bottom - 100, TRUE); MoveWindow(_logStats, 12, r.bottom - 44, r.right - 24, 36, TRUE); return 0; }
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _logWin = nullptr; return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}
void showTypingLog(HINSTANCE inst) {
    if (_logWin) { SetForegroundWindow(_logWin); refreshLog(); return; }
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = logProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyLog"; wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); wc.hCursor = LoadCursor(nullptr, IDC_ARROW); RegisterClassW(&wc); reg = true; }
    core::flushTypingLog();
    _logWin = CreateWindowExW(0, L"VikeyLog", L"Nhật ký gõ", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, 760, 520, nullptr, nullptr, inst, nullptr);
    HWND old = _win; _win = _logWin;
    add(L"BUTTON", L"Làm mới", 0, 12, 12, 90, 26, L_REFRESH); add(L"BUTTON", L"Mở thư mục", 0, 110, 12, 110, 26, L_OPEN); add(L"BUTTON", L"Xoá nhật ký", 0, 228, 12, 110, 26, L_CLEAR);
    _logList = add(L"EDIT", L"", WS_BORDER | WS_VSCROLL | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL, 12, 48, 712, 380, 0, CreateFontW(-13, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Consolas"));
    _logStats = add(L"STATIC", L"", 0, 12, 436, 712, 36, 0);
    _win = old;
    refreshLog(); ShowWindow(_logWin, SW_SHOW);
}

}} // namespace
