// Vikey for Windows: tray icon (V / E), menu, and the message loop the hooks need.
#include <windows.h>
#include <shellapi.h>
#include <string>
#include "Core.h"
#include "Prefs.h"
#include "Site.h"
#include "resource.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "advapi32.lib")

static const UINT WM_TRAY = WM_APP + 1;
static const UINT TIMER_FLUSH = 1, TIMER_SITE = 2;
enum { ID_VIET = 100, ID_ENG, ID_AUTOSWITCH, ID_SMART, ID_SITE, ID_SPELL, ID_RESTORE, ID_MODERN, ID_LOGIN, ID_LOG, ID_ABOUT, ID_QUIT };

static HWND _hwnd; static NOTIFYICONDATAW _nid = {};
static HICON _iconV, _iconE;

/// Draws the menu-bar glyph: a rounded square with a V or E cut out, like the macOS icon.
static HICON makeIcon(wchar_t letter, bool dark) {
    const int S = 32;
    HDC dc = CreateCompatibleDC(nullptr);
    BITMAPINFO bi = {}; bi.bmiHeader.biSize = sizeof(bi.bmiHeader); bi.bmiHeader.biWidth = S; bi.bmiHeader.biHeight = -S; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32;
    void* bits = nullptr; HBITMAP color = CreateDIBSection(dc, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    HGDIOBJ old = SelectObject(dc, color);
    DWORD* px = (DWORD*)bits; for (int i = 0; i < S * S; i++) px[i] = 0;
    COLORREF fg = dark ? RGB(255, 255, 255) : RGB(0, 0, 0);
    HBRUSH b = CreateSolidBrush(fg); HPEN p = CreatePen(PS_NULL, 0, 0);
    SelectObject(dc, b); SelectObject(dc, p);
    RoundRect(dc, 2, 3, S - 2, S - 3, 10, 10);
    HFONT f = CreateFontW(-22, 0, 0, 0, FW_BOLD, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, L"Segoe UI");
    SelectObject(dc, f); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(1, 2, 3));
    RECT r = {0, 1, S, S}; DrawTextW(dc, &letter, 1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
    // punch the letter out: pixels drawn in the marker color become transparent; the rest opaque
    for (int i = 0; i < S * S; i++) { DWORD c = px[i] & 0xFFFFFF; if (c == 0x030201) px[i] = 0; else if (c != 0) px[i] |= 0xFF000000; else px[i] = 0; }
    SelectObject(dc, old); DeleteObject(f); DeleteObject(b); DeleteObject(p); DeleteDC(dc);
    HBITMAP mask = CreateBitmap(S, S, 1, 1, nullptr);
    ICONINFO ii = {TRUE, 0, 0, mask, color}; HICON h = CreateIconIndirect(&ii);
    DeleteObject(mask); DeleteObject(color); return h;
}
static bool darkTaskbar() {
    HKEY h; DWORD v = 1, s = sizeof(v);
    if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", 0, KEY_READ, &h) == ERROR_SUCCESS) { RegQueryValueExW(h, L"SystemUsesLightTheme", nullptr, nullptr, (LPBYTE)&v, &s); RegCloseKey(h); }
    return v == 0;
}
static void updateTray(int lang) {
    _nid.hIcon = lang ? _iconV : _iconE;
    wcscpy_s(_nid.szTip, lang ? L"Vikey – Tiếng Việt" : L"Vikey – English");
    Shell_NotifyIconW(NIM_MODIFY, &_nid);
}
static void toggle(const wchar_t* key, int fallback) { vikey::prefs::setInt(key, !vikey::prefs::getInt(key, fallback)); vikey::core::reloadSettings(); }
static void showMenu() {
    using namespace vikey;
    HMENU m = CreatePopupMenu();
    int lang = core::language();
    AppendMenuW(m, MF_STRING | (lang ? MF_CHECKED : 0), ID_VIET, L"Tiếng Việt");
    AppendMenuW(m, MF_STRING | (!lang ? MF_CHECKED : 0), ID_ENG, L"English");
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"AutoSwitchByTyping", 1) ? MF_CHECKED : 0), ID_AUTOSWITCH, L"Tự chuyển Anh/Việt khi gõ");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"UseSmartSwitchKey", 1) ? MF_CHECKED : 0), ID_SMART, L"Nhớ ngôn ngữ theo ứng dụng");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"SmartSwitchPerSite", 1) ? MF_CHECKED : 0), ID_SITE, L"Nhớ ngôn ngữ theo trang web");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"Spelling", 1) ? MF_CHECKED : 0), ID_SPELL, L"Kiểm tra chính tả");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"RestoreIfInvalidWord", 1) ? MF_CHECKED : 0), ID_RESTORE, L"Giữ nguyên phím khi từ sai");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"ModernOrthography", 1) ? MF_CHECKED : 0), ID_MODERN, L"Bỏ dấu kiểu mới (oà, uý)");
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING | (prefs::launchAtLogin() ? MF_CHECKED : 0), ID_LOGIN, L"Khởi động cùng Windows");
    AppendMenuW(m, MF_STRING | (prefs::getInt(L"TypingLogEnabled", 0) ? MF_CHECKED : 0), ID_LOG, L"Ghi nhật ký gõ (gỡ lỗi)");
    AppendMenuW(m, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(m, MF_STRING, ID_ABOUT, L"Giới thiệu Vikey");
    AppendMenuW(m, MF_STRING, ID_QUIT, L"Thoát");
    POINT pt; GetCursorPos(&pt); SetForegroundWindow(_hwnd);
    TrackPopupMenu(m, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, pt.x, pt.y, 0, _hwnd, nullptr);
    DestroyMenu(m);
}
static LRESULT CALLBACK wndProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    using namespace vikey;
    switch (msg) {
    case WM_TRAY:
        if (LOWORD(lp) == WM_LBUTTONUP) core::setLanguageByUser(!core::language());
        else if (LOWORD(lp) == WM_RBUTTONUP || LOWORD(lp) == WM_CONTEXTMENU) showMenu();
        return 0;
    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case ID_VIET: core::setLanguageByUser(1); break;
        case ID_ENG: core::setLanguageByUser(0); break;
        case ID_AUTOSWITCH: toggle(L"AutoSwitchByTyping", 1); break;
        case ID_SMART: toggle(L"UseSmartSwitchKey", 1); break;
        case ID_SITE: toggle(L"SmartSwitchPerSite", 1); break;
        case ID_SPELL: toggle(L"Spelling", 1); break;
        case ID_RESTORE: toggle(L"RestoreIfInvalidWord", 1); break;
        case ID_MODERN: toggle(L"ModernOrthography", 1); break;
        case ID_LOGIN: prefs::setLaunchAtLogin(!prefs::launchAtLogin()); break;
        case ID_LOG: toggle(L"TypingLogEnabled", 0); break;
        case ID_ABOUT: MessageBoxW(h, L"Vikey " VIKEY_VERSION_W L"\nGõ tiếng Việt, tự chuyển Anh/Việt khi gõ.\n\nTác giả: Tony Dinh. Dựa trên OpenKey của Tuyen Mai (GPL-3.0).\nhttps://vikey.app", L"Vikey", MB_OK | MB_ICONINFORMATION); break;
        case ID_QUIT: DestroyWindow(h); break;
        }
        return 0;
    case WM_TIMER: if (wp == TIMER_FLUSH) core::flushTypingLog(); else if (wp == TIMER_SITE) vikey::site::poll(); return 0;
    case WM_SETTINGCHANGE: { bool dark = darkTaskbar(); DestroyIcon(_iconV); DestroyIcon(_iconE); _iconV = makeIcon(L'V', dark); _iconE = makeIcon(L'E', dark); updateTray(core::language()); return 0; }
    case WM_DESTROY: core::stop(); Shell_NotifyIconW(NIM_DELETE, &_nid); PostQuitMessage(0); return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE, PWSTR, int) {
    HANDLE single = CreateMutexW(nullptr, TRUE, L"Local\\VikeyRunning");
    if (GetLastError() == ERROR_ALREADY_EXISTS) return 0;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    vikey::prefs::migrateFromOpenKey();
    WNDCLASSW wc = {}; wc.lpfnWndProc = wndProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyTray";
    RegisterClassW(&wc);
    _hwnd = CreateWindowW(L"VikeyTray", L"Vikey", 0, 0, 0, 0, 0, HWND_MESSAGE, nullptr, inst, nullptr);
    bool dark = darkTaskbar(); _iconV = makeIcon(L'V', dark); _iconE = makeIcon(L'E', dark);
    _nid.cbSize = sizeof(_nid); _nid.hWnd = _hwnd; _nid.uID = 1; _nid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP; _nid.uCallbackMessage = WM_TRAY; _nid.hIcon = _iconV;
    wcscpy_s(_nid.szTip, L"Vikey");
    Shell_NotifyIconW(NIM_ADD, &_nid);
    vikey::core::setLanguageObserver([](int lang) { updateTray(lang); });
    if (!vikey::core::start()) { MessageBoxW(nullptr, L"Không cài được bộ bắt phím (SetWindowsHookEx).", L"Vikey", MB_ICONERROR); return 1; }
    updateTray(vikey::core::language());
    SetTimer(_hwnd, TIMER_FLUSH, 10000, nullptr);
    SetTimer(_hwnd, TIMER_SITE, 1000, nullptr);   // per-website memory: the active tab can change without any event we see
    MSG msg; while (GetMessageW(&msg, nullptr, 0, 0)) { TranslateMessage(&msg); DispatchMessageW(&msg); }
    ReleaseMutex(single); CloseHandle(single);
    return 0;
}
