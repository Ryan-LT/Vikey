// Vikey's windows on Windows, 1:1 with the macOS app (App/Views): the main window (header with
// icon, wordmark, hotkey hint and the Tiếng Việt / English switch, then a grouped form), the
// onboarding "ready" page, the About panel and the typing-log window. Drawn with GDI+ so the
// toggles, segmented control and rounded groups look like the macOS ones.
#define _HAS_STD_BYTE 0
#include "Settings.h"
#include "Core.h"
#include "Prefs.h"
#include "KeyMap.h"
#include "resource.h"
#include <commctrl.h>
#include <windowsx.h>
#include <shellapi.h>
#include <objidl.h>
#define GDIPVER 0x0110
namespace Gdiplus { using std::min; using std::max; }
#include <gdiplus.h>
#include <algorithm>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <functional>
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "gdiplus.lib")
using namespace Gdiplus;

namespace vikey { namespace ui {

// ---- shared look ---------------------------------------------------------------------------
static HFONT fBody, fBodyBold, fSmall, fWordmark, fTitle, fMono;
static const COLORREF BG = RGB(246, 246, 246), GROUP = RGB(255, 255, 255), BORDER = RGB(226, 226, 226), SEP = RGB(236, 236, 236);
static const COLORREF TEXT = RGB(0, 0, 0), SECONDARY = RGB(110, 110, 115), ACCENT = RGB(10, 124, 255), GREEN = RGB(52, 199, 89), TOGGLE_OFF = RGB(233, 233, 235);
static const int W = 460, MARGIN = 20, ROW = 38, RADIUS = 10;
static ULONG_PTR gdipToken = 0;
static void initLook() {
    if (fBody) return;
    GdiplusStartupInput in; GdiplusStartup(&gdipToken, &in, nullptr);
    auto mk = [](int px, int weight, const wchar_t* face = L"Segoe UI") { return CreateFontW(-px, 0, 0, 0, weight, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, face); };
    fBody = mk(15, FW_NORMAL); fBodyBold = mk(15, FW_SEMIBOLD); fSmall = mk(13, FW_NORMAL); fWordmark = mk(24, FW_BOLD); fTitle = mk(17, FW_SEMIBOLD); fMono = mk(13, FW_NORMAL, L"Consolas");
    INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES | ICC_LINK_CLASS | ICC_BAR_CLASSES}; InitCommonControlsEx(&icc);
}
static Color gp(COLORREF c, BYTE a = 255) { return Color(a, GetRValue(c), GetGValue(c), GetBValue(c)); }
static void roundRect(Graphics& g, RectF r, float radius, Color fill, Color stroke, float strokeW = 1) {
    GraphicsPath p; float d = radius * 2;
    p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.X + r.Width - d, r.Y, d, d, 270, 90);
    p.AddArc(r.X + r.Width - d, r.Y + r.Height - d, d, d, 0, 90); p.AddArc(r.X, r.Y + r.Height - d, d, d, 90, 90); p.CloseFigure();
    SolidBrush b(fill); g.FillPath(&b, &p);
    if (stroke.GetA()) { Pen pen(stroke, strokeW); g.DrawPath(&pen, &p); }
}
static std::wstring hotkeyDisplay(int hk) {
    std::wstring s;
    if (HAS_CONTROL(hk)) s += L"Ctrl+"; if (HAS_OPTION(hk)) s += L"Alt+"; if (HAS_SHIFT(hk)) s += L"Shift+"; if (HAS_COMMAND(hk)) s += L"Win+";
    int k = GET_SWITCH_KEY(hk);
    if (k != 0xFE) {
        Uint16 ch = keyCodeToCharacter(k | CAPS_MASK);
        if (k == KEY_SPACE) s += L"Space"; else if (k == KEY_RETURN) s += L"Enter"; else if (k == KEY_TAB) s += L"Tab"; else if (ch) s += (wchar_t)ch; else s += L"?";
    } else if (!s.empty()) s.pop_back();
    return s.empty() ? L"—" : s;
}
static int currentHotkey() { int hk = prefs::getInt(L"SwitchKeyStatus", 0); return hk ? hk : 0x7A000206; }

// ---- custom controls -----------------------------------------------------------------------
// Toggle switch: GWLP_USERDATA = on/off; BN_CLICKED to the parent on change; disabled = grayed.
static LRESULT CALLBACK toggleProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HDC mem = CreateCompatibleDC(dc); HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom); HGDIOBJ old = SelectObject(mem, bmp);
        HBRUSH bg = CreateSolidBrush(GROUP); FillRect(mem, &rc, bg); DeleteObject(bg);
        Graphics g(mem); g.SetSmoothingMode(SmoothingModeAntiAlias);
        bool on = GetWindowLongPtrW(h, GWLP_USERDATA) != 0, enabled = IsWindowEnabled(h);
        Color fill = on ? gp(ACCENT, enabled ? 255 : 110) : gp(TOGGLE_OFF);   // macOS toggles use the accent colour
        roundRect(g, RectF(0.5f, 0.5f, 39, 22), 11, fill, Color(0, 0, 0, 0));
        SolidBrush knob(Color(255, 255, 255, 255)); float kx = on ? 19.5f : 2.5f;
        SolidBrush shadow(Color(40, 0, 0, 0)); g.FillEllipse(&shadow, kx, 3.0f, 18.0f, 18.0f);
        g.FillEllipse(&knob, kx, 2.5f, 18.0f, 18.0f);
        BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY); SelectObject(mem, old); DeleteObject(bmp); DeleteDC(mem); EndPaint(h, &ps); return 0; }
    case WM_LBUTTONUP: case WM_KEYUP:
        if (m == WM_KEYUP && w != VK_SPACE) break;
        if (!IsWindowEnabled(h)) return 0;
        SetWindowLongPtrW(h, GWLP_USERDATA, !GetWindowLongPtrW(h, GWLP_USERDATA)); InvalidateRect(h, nullptr, FALSE);
        SendMessageW(GetParent(h), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(h), BN_CLICKED), (LPARAM)h); return 0;
    case WM_ERASEBKGND: return 1;
    case WM_ENABLE: InvalidateRect(h, nullptr, FALSE); break;
    case WM_SETCURSOR: SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE;
    }
    return DefWindowProcW(h, m, w, l);
}
static bool toggleOn(HWND h) { return GetWindowLongPtrW(h, GWLP_USERDATA) != 0; }
static void setToggle(HWND h, bool on) { SetWindowLongPtrW(h, GWLP_USERDATA, on); InvalidateRect(h, nullptr, FALSE); }

// Segmented control with two segments; GWLP_USERDATA = selected index; BN_CLICKED on change.
static LRESULT CALLBACK segProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    static const wchar_t* labels[2] = {L"Tiếng Việt", L"English"};
    switch (m) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HDC mem = CreateCompatibleDC(dc); HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom); HGDIOBJ old = SelectObject(mem, bmp);
        HBRUSH bg = CreateSolidBrush(BG); FillRect(mem, &rc, bg); DeleteObject(bg);
        Graphics g(mem); g.SetSmoothingMode(SmoothingModeAntiAlias);
        roundRect(g, RectF(0.5f, 0.5f, (float)rc.right - 1, (float)rc.bottom - 1), 8, gp(TOGGLE_OFF), Color(0, 0, 0, 0));
        int sel = (int)GetWindowLongPtrW(h, GWLP_USERDATA); float half = rc.right / 2.0f;
        roundRect(g, RectF(sel * half + 2, 2, half - 4, (float)rc.bottom - 4), 7, gp(ACCENT), Color(0, 0, 0, 0));
        SelectObject(mem, fBody); SetBkMode(mem, TRANSPARENT);
        for (int i = 0; i < 2; i++) { RECT r = {(LONG)(i * half), 0, (LONG)((i + 1) * half), rc.bottom}; SetTextColor(mem, i == sel ? RGB(255, 255, 255) : TEXT); DrawTextW(mem, labels[i], -1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE); }
        BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY); SelectObject(mem, old); DeleteObject(bmp); DeleteDC(mem); EndPaint(h, &ps); return 0; }
    case WM_LBUTTONUP: { RECT rc; GetClientRect(h, &rc); int i = GET_X_LPARAM(l) < rc.right / 2 ? 0 : 1;
        if (i != (int)GetWindowLongPtrW(h, GWLP_USERDATA)) { SetWindowLongPtrW(h, GWLP_USERDATA, i); InvalidateRect(h, nullptr, FALSE); SendMessageW(GetParent(h), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(h), BN_CLICKED), (LPARAM)h); }
        return 0; }
    case WM_ERASEBKGND: return 1;
    case WM_SETCURSOR: SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE;
    }
    return DefWindowProcW(h, m, w, l);
}

// Hotkey recorder: a rounded gray box; click it, press a combination (or modifiers only).
static int _recHotkey = 0; static bool _recording = false;
static LRESULT CALLBACK hotkeyProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HDC mem = CreateCompatibleDC(dc); HBITMAP bmp = CreateCompatibleBitmap(dc, rc.right, rc.bottom); HGDIOBJ old = SelectObject(mem, bmp);
        HBRUSH bg = CreateSolidBrush(GROUP); FillRect(mem, &rc, bg); DeleteObject(bg);
        Graphics g(mem); g.SetSmoothingMode(SmoothingModeAntiAlias);
        roundRect(g, RectF(0.5f, 0.5f, (float)rc.right - 1, (float)rc.bottom - 1), 7, gp(RGB(230, 230, 230)), _recording ? gp(ACCENT) : Color(0, 0, 0, 0), 1.5f);
        SelectObject(mem, fBody); SetBkMode(mem, TRANSPARENT); SetTextColor(mem, _recording ? SECONDARY : TEXT);
        std::wstring t = _recording ? L"Bấm phím tắt…" : hotkeyDisplay(_recHotkey);
        DrawTextW(mem, t.c_str(), -1, &rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        BitBlt(dc, 0, 0, rc.right, rc.bottom, mem, 0, 0, SRCCOPY); SelectObject(mem, old); DeleteObject(bmp); DeleteDC(mem); EndPaint(h, &ps); return 0; }
    case WM_LBUTTONUP: SetFocus(h); _recording = true; InvalidateRect(h, nullptr, FALSE); return 0;
    case WM_KILLFOCUS: _recording = false; InvalidateRect(h, nullptr, FALSE); return 0;
    case WM_GETDLGCODE: return DLGC_WANTALLKEYS;
    case WM_KEYDOWN: case WM_SYSKEYDOWN: {
        if (!_recording) return 0;
        DWORD vk = (DWORD)w;
        bool ctrl = GetKeyState(VK_CONTROL) < 0, alt = GetKeyState(VK_MENU) < 0, shift = GetKeyState(VK_SHIFT) < 0, win = GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0;
        bool isMod = vk == VK_CONTROL || vk == VK_MENU || vk == VK_SHIFT || vk == VK_LWIN || vk == VK_RWIN || vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_LMENU || vk == VK_RMENU || vk == VK_LSHIFT || vk == VK_RSHIFT;
        if (vk == VK_ESCAPE) { _recording = false; InvalidateRect(h, nullptr, FALSE); return 0; }
        int key = isMod ? 0xFE : (int)engineKey(vk);
        if (key == KEY_EMPTY) return 0;
        if (isMod) return 0;   // committed on key-up when nothing else was pressed
        _recHotkey = key | (ctrl ? 0x100 : 0) | (alt ? 0x200 : 0) | (win ? 0x400 : 0) | (shift ? 0x800 : 0) | (_recHotkey & 0x8000);
        _recording = false; prefs::setInt(L"SwitchKeyStatus", _recHotkey); core::reloadSettings(); InvalidateRect(h, nullptr, FALSE);
        SendMessageW(GetParent(h), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(h), BN_CLICKED), (LPARAM)h); return 0; }
    case WM_KEYUP: case WM_SYSKEYUP: {
        if (!_recording) return 0;
        DWORD vk = (DWORD)w;
        bool isMod = vk == VK_CONTROL || vk == VK_MENU || vk == VK_SHIFT || vk == VK_LWIN || vk == VK_RWIN || vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_LMENU || vk == VK_RMENU || vk == VK_LSHIFT || vk == VK_RSHIFT;
        if (!isMod) return 0;
        // modifiers only: the combination that was held when the first one is released
        int mods = (vk == VK_LCONTROL || vk == VK_RCONTROL || vk == VK_CONTROL || GetKeyState(VK_CONTROL) < 0 ? 0x100 : 0) | (vk == VK_LMENU || vk == VK_RMENU || vk == VK_MENU || GetKeyState(VK_MENU) < 0 ? 0x200 : 0) |
                   (vk == VK_LWIN || vk == VK_RWIN || GetKeyState(VK_LWIN) < 0 || GetKeyState(VK_RWIN) < 0 ? 0x400 : 0) | (vk == VK_LSHIFT || vk == VK_RSHIFT || vk == VK_SHIFT || GetKeyState(VK_SHIFT) < 0 ? 0x800 : 0);
        if (!mods) return 0;
        _recHotkey = 0xFE | mods | (_recHotkey & 0x8000);
        _recording = false; prefs::setInt(L"SwitchKeyStatus", _recHotkey); core::reloadSettings(); InvalidateRect(h, nullptr, FALSE);
        SendMessageW(GetParent(h), WM_COMMAND, MAKEWPARAM(GetDlgCtrlID(h), BN_CLICKED), (LPARAM)h); return 0; }
    case WM_ERASEBKGND: return 1;
    case WM_SETCURSOR: SetCursor(LoadCursor(nullptr, IDC_HAND)); return TRUE;
    }
    return DefWindowProcW(h, m, w, l);
}

// (?) tip: a small circle with a question mark; hover shows the tip, click shows it as a popup.
static HWND _tooltip;
static LRESULT CALLBACK tipProc(HWND h, UINT m, WPARAM w, LPARAM l) {
    switch (m) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HBRUSH bg = CreateSolidBrush(GROUP); FillRect(dc, &rc, bg); DeleteObject(bg);
        Graphics g(dc); g.SetSmoothingMode(SmoothingModeAntiAlias); Pen p(gp(RGB(170, 170, 175)), 1.2f); g.DrawEllipse(&p, 1.5f, 1.5f, 13.0f, 13.0f);
        SelectObject(dc, fSmall); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, RGB(150, 150, 155)); RECT r = {0, -1, 16, 16}; DrawTextW(dc, L"?", 1, &r, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        EndPaint(h, &ps); return 0; }
    case WM_LBUTTONUP: { wchar_t t[512]; GetWindowTextW(h, t, 512); MessageBoxW(GetParent(h), t, L"Vikey", MB_OK | MB_ICONINFORMATION); return 0; }
    case WM_ERASEBKGND: return 1;
    }
    return DefWindowProcW(h, m, w, l);
}

static void registerClasses(HINSTANCE inst) {
    static bool done = false; if (done) return; done = true;
    struct { const wchar_t* name; WNDPROC proc; } cls[] = {{L"VikeyToggle", toggleProc}, {L"VikeySegmented", segProc}, {L"VikeyHotkey", hotkeyProc}, {L"VikeyTip", tipProc}};
    for (auto& c : cls) { WNDCLASSW wc = {}; wc.lpfnWndProc = c.proc; wc.hInstance = inst; wc.lpszClassName = c.name; wc.hCursor = LoadCursor(nullptr, IDC_ARROW); RegisterClassW(&wc); }
}

// ---- main window -----------------------------------------------------------------------------
enum { C_SEG = 200, C_HOTKEY, C_BEEP, C_AUTO, C_PAUSE, C_SMART, C_SITE, C_MARK, C_SPELL, C_RESTORE, C_LOGIN, C_UPDATE, C_LOGKEYS, L_REFRESH = 300, L_OPEN, L_CLEAR, A_LINK = 400, O_DONE = 500 };
static HWND _win, _seg, _hint, _logWin, _logList, _logSummary, _logGrid, _aboutWin, _onbWin;
static std::map<int, HWND> _ctl;
struct Group { int top, bottom; }; static std::vector<Group> _groups; static std::vector<std::pair<int, std::wstring>> _titles;   // y, title
struct RowSep { int y; }; static std::vector<int> _seps;

static HWND child(const wchar_t* cls, const wchar_t* text, DWORD style, int x, int y, int w, int h, int id, HFONT f = nullptr) {
    HWND c = CreateWindowW(cls, text, WS_CHILD | WS_VISIBLE | style, x, y, w, h, _win, (HMENU)(INT_PTR)id, nullptr, nullptr);
    if (f) SendMessageW(c, WM_SETFONT, (WPARAM)f, TRUE); return c;
}
static void addTip(HWND tip, const wchar_t* text) {
    if (!_tooltip) { _tooltip = CreateWindowExW(WS_EX_TOPMOST, TOOLTIPS_CLASS, nullptr, WS_POPUP | TTS_ALWAYSTIP | TTS_NOPREFIX, 0, 0, 0, 0, _win, nullptr, nullptr, nullptr); SendMessageW(_tooltip, TTM_SETMAXTIPWIDTH, 0, 300); }
    TOOLINFOW ti = {sizeof(ti)}; ti.uFlags = TTF_IDISHWND | TTF_SUBCLASS; ti.hwnd = _win; ti.uId = (UINT_PTR)tip; ti.lpszText = (LPWSTR)text; SendMessageW(_tooltip, TTM_ADDTOOLW, 0, (LPARAM)&ti);
}
/// One form row: label (+ tip) on the left, a control on the right. Returns the control.
static int _y; static int _groupTop = -1;
static void beginGroup(const wchar_t* title) { if (title) { _titles.push_back({_y, title}); _y += 30; } _groupTop = _y; }
static void endGroup() { _groups.push_back({_groupTop, _y}); _y += 18; }
static HWND row(const wchar_t* label, const wchar_t* tip, const wchar_t* cls, int id, int cw, int ch, DWORD style = 0) {
    if (_y != _groupTop) _seps.push_back(_y);
    int ly = _y + (ROW - 20) / 2;
    HWND lab = child(L"STATIC", label, SS_LEFT, MARGIN + 16, ly, 300, 20, 0, fBody);
    SIZE sz; HDC dc = GetDC(lab); SelectObject(dc, fBody); GetTextExtentPoint32W(dc, label, (int)wcslen(label), &sz); ReleaseDC(lab, dc);
    if (tip) { HWND t = child(L"VikeyTip", tip, 0, MARGIN + 16 + sz.cx + 6, ly + 2, 16, 16, 0); addTip(t, tip); }
    HWND c = child(cls, L"", style, W - MARGIN - 16 - cw, _y + (ROW - ch) / 2, cw, ch, id, fBody);
    _ctl[id] = c; _y += ROW; return c;
}
static HWND toggleRow(const wchar_t* label, const wchar_t* tip, int id, bool on) { HWND c = row(label, tip, L"VikeyToggle", id, 40, 23); setToggle(c, on); return c; }

static void refreshEnabled() {
    EnableWindow(_ctl[C_PAUSE], toggleOn(_ctl[C_AUTO]));
    EnableWindow(_ctl[C_SITE], toggleOn(_ctl[C_SMART]));
    EnableWindow(_ctl[C_RESTORE], toggleOn(_ctl[C_SPELL]));
}
static void setHint() { if (_hint) SetWindowTextW(_hint, (L"Bấm " + hotkeyDisplay(currentHotkey()) + L" để chuyển").c_str()); }
void languageChanged(int lang) { if (_seg) { SetWindowLongPtrW(_seg, GWLP_USERDATA, lang ? 0 : 1); InvalidateRect(_seg, nullptr, FALSE); } }

static void paintMain(HWND h) {
    PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
    HBRUSH bg = CreateSolidBrush(BG); FillRect(dc, &rc, bg); DeleteObject(bg);
    Graphics g(dc); g.SetSmoothingMode(SmoothingModeAntiAlias);
    for (auto& gr : _groups) roundRect(g, RectF((float)MARGIN, (float)gr.top, (float)(W - 2 * MARGIN), (float)(gr.bottom - gr.top)), RADIUS, gp(GROUP), gp(BORDER));
    Pen sep(gp(SEP), 1); for (int y : _seps) g.DrawLine(&sep, MARGIN + 16, y, W - MARGIN - 16, y);
    SetBkMode(dc, TRANSPARENT); SetTextColor(dc, TEXT);
    SelectObject(dc, fBodyBold); for (auto& t : _titles) { RECT r = {MARGIN + 16, t.first + 4, W, t.first + 26}; DrawTextW(dc, t.second.c_str(), -1, &r, DT_LEFT | DT_SINGLELINE); }
    // header: icon, wordmark
    HICON icon = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, 44, 44, LR_DEFAULTCOLOR);
    if (icon) { DrawIconEx(dc, MARGIN, 14, icon, 44, 44, 0, nullptr, DI_NORMAL); DestroyIcon(icon); }
    SelectObject(dc, fWordmark); RECT wr = {MARGIN + 56, 12, 300, 40}; DrawTextW(dc, L"Vikey", -1, &wr, DT_LEFT | DT_SINGLELINE);
    EndPaint(h, &ps);
}
static LRESULT CALLBACK mainProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_PAINT: paintMain(h); return 0;
    case WM_CTLCOLORSTATIC: { static HBRUSH bgBrush = CreateSolidBrush(BG), groupBrush = CreateSolidBrush(GROUP); SetBkMode((HDC)wp, TRANSPARENT); HWND c = (HWND)lp; SetTextColor((HDC)wp, c == _hint ? SECONDARY : TEXT); return (LRESULT)(c == _hint ? bgBrush : groupBrush); }
    case WM_COMMAND: {
        int id = LOWORD(wp); HWND c = (HWND)lp;
        auto flag = [&](const wchar_t* pref) { prefs::setInt(pref, toggleOn(c)); core::reloadSettings(); refreshEnabled(); };
        switch (id) {
        case C_SEG: core::setLanguageByUser(GetWindowLongPtrW(_seg, GWLP_USERDATA) == 0 ? 1 : 0); break;
        case C_HOTKEY: setHint(); break;
        case C_BEEP: { int hk = (currentHotkey() & ~0x8000) | (toggleOn(c) ? 0x8000 : 0); prefs::setInt(L"SwitchKeyStatus", hk); _recHotkey = hk; core::reloadSettings(); break; }
        case C_AUTO: flag(L"AutoSwitchByTyping"); break;
        case C_PAUSE: flag(L"PauseAutoAfterManual"); break;
        case C_SMART: flag(L"UseSmartSwitchKey"); break;
        case C_SITE: flag(L"SmartSwitchPerSite"); break;
        case C_MARK: if (HIWORD(wp) == CBN_SELCHANGE) { prefs::setInt(L"ModernOrthography", SendMessageW(c, CB_GETCURSEL, 0, 0) == 0 ? 1 : 0); core::reloadSettings(); } break;
        case C_SPELL: flag(L"Spelling"); break;
        case C_RESTORE: flag(L"RestoreIfInvalidWord"); break;
        case C_LOGIN: prefs::setLaunchAtLogin(toggleOn(c)); setToggle(c, prefs::launchAtLogin()); break;
        case C_UPDATE: prefs::setInt(L"AutoUpdate", toggleOn(c)); break;
        }
        return 0; }
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _win = nullptr; _seg = nullptr; _hint = nullptr; _tooltip = nullptr; _ctl.clear(); _groups.clear(); _titles.clear(); _seps.clear(); return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}

void showSettings(HINSTANCE inst, bool firstRun) {
    initLook(); registerClasses(inst);
    if (firstRun) { showOnboarding(inst); return; }
    if (_win) { SetForegroundWindow(_win); return; }
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = mainProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyMain"; wc.hbrBackground = nullptr; wc.hCursor = LoadCursor(nullptr, IDC_ARROW); wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_APP)); RegisterClassW(&wc); reg = true; }
    _win = CreateWindowExW(0, L"VikeyMain", L"Vikey", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, W, 600, nullptr, nullptr, inst, nullptr);
    _groups.clear(); _titles.clear(); _seps.clear(); _ctl.clear();
    // header
    _hint = child(L"STATIC", L"", SS_LEFT, MARGIN + 56, 40, 220, 20, 0, fSmall); setHint();
    _seg = child(L"VikeySegmented", L"", 0, W - MARGIN - 164, 22, 164, 30, C_SEG); languageChanged(core::language());
    _y = 74;
    int hk = currentHotkey(); _recHotkey = hk;
    beginGroup(nullptr);
    row(L"Phím chuyển Anh/Việt", L"Bấm tổ hợp phím này để chuyển giữa tiếng Việt và tiếng Anh. Bấm vào ô để đặt phím khác.", L"VikeyHotkey", C_HOTKEY, 134, 30);
    toggleRow(L"Âm báo khi chuyển", L"Phát một âm ngắn mỗi lần bạn bấm phím chuyển Anh/Việt.", C_BEEP, HAS_BEEP(hk) != 0);
    endGroup();
    beginGroup(L"Tự chuyển");
    toggleRow(L"Tự chuyển Anh/Việt", L"Gõ một từ tiếng Anh khi đang ở tiếng Việt (hoặc ngược lại), Vikey tự sửa từ đó và chuyển chế độ. Bấm Xoá ngay sau đó để hoàn tác.", C_AUTO, prefs::getInt(L"AutoSwitchByTyping", 1) != 0);
    toggleRow(L"Tạm dừng 5 giây", L"Khi bạn tự bấm chuyển Anh/Việt, Vikey không tự chuyển trong 5 giây, để giữ đúng lựa chọn của bạn.", C_PAUSE, prefs::getInt(L"PauseAutoAfterManual", 1) != 0);
    toggleRow(L"Nhớ theo ứng dụng", L"Vikey nhớ bạn dùng tiếng Anh hay tiếng Việt ở mỗi ứng dụng và tự chuyển lại khi bạn quay về ứng dụng đó.", C_SMART, prefs::getInt(L"UseSmartSwitchKey", 1) != 0);
    toggleRow(L"Nhớ theo trang web", L"Trong Chrome, Edge, Brave, Vivaldi, Opera, Firefox: nhớ tiếng Anh hay tiếng Việt cho từng trang web. Chỉ đọc địa chỉ tab đang mở, ngay trên máy bạn.", C_SITE, prefs::getInt(L"SmartSwitchPerSite", 1) != 0);
    endGroup();
    beginGroup(L"Gõ tiếng Việt");
    HWND mark = row(L"Đặt dấu", L"Vị trí dấu thanh với oa, oe, uy: kiểu mới (hoà, thuý) hoặc kiểu cũ (hòa, thúy).", L"COMBOBOX", C_MARK, 130, 200, CBS_DROPDOWNLIST | WS_TABSTOP);
    SendMessageW(mark, CB_ADDSTRING, 0, (LPARAM)L"hoà, thuý"); SendMessageW(mark, CB_ADDSTRING, 0, (LPARAM)L"hòa, thúy"); SendMessageW(mark, CB_SETCURSEL, prefs::getInt(L"ModernOrthography", 1) ? 0 : 1, 0);
    SetWindowPos(mark, nullptr, W - MARGIN - 16 - 130, _y - ROW + 5, 130, 200, SWP_NOZORDER);
    toggleRow(L"Kiểm tra chính tả", L"Chỉ bỏ dấu khi từ đang gõ đúng quy tắc chính tả tiếng Việt.", C_SPELL, prefs::getInt(L"Spelling", 1) != 0);
    toggleRow(L"Trả lại phím khi sai", L"Khi gõ xong một từ sai chính tả tiếng Việt, Vikey trả lại đúng các phím bạn đã gõ.", C_RESTORE, prefs::getInt(L"RestoreIfInvalidWord", 1) != 0);
    endGroup();
    beginGroup(nullptr);
    toggleRow(L"Mở Vikey khi đăng nhập", L"Tự mở Vikey mỗi khi bạn đăng nhập vào Windows.", C_LOGIN, prefs::launchAtLogin());
    toggleRow(L"Tự động cập nhật", L"Mỗi ngày Vikey kiểm tra bản mới trên vikey.app, tự tải về và cài khi bạn thoát Vikey hoặc tắt máy.", C_UPDATE, prefs::getInt(L"AutoUpdate", 1) != 0);
    endGroup();
    refreshEnabled();
    RECT wr = {0, 0, W, _y}; AdjustWindowRectEx(&wr, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE, 0);
    SetWindowPos(_win, nullptr, 0, 0, wr.right - wr.left, wr.bottom - wr.top, SWP_NOMOVE | SWP_NOZORDER);
    ShowWindow(_win, SW_SHOW); SetForegroundWindow(_win);
}

// ---- onboarding ("Vikey đã sẵn sàng") ---------------------------------------------------------
static LRESULT CALLBACK onbProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HBRUSH bg = CreateSolidBrush(GROUP); FillRect(dc, &rc, bg); DeleteObject(bg);
        HICON icon = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, 56, 56, LR_DEFAULTCOLOR);
        if (icon) { DrawIconEx(dc, 28, 28, icon, 56, 56, 0, nullptr, DI_NORMAL); DestroyIcon(icon); }
        SetBkMode(dc, TRANSPARENT); SelectObject(dc, fWordmark); SetTextColor(dc, TEXT); RECT r = {98, 26, 480, 56}; DrawTextW(dc, L"Vikey", -1, &r, DT_LEFT | DT_SINGLELINE);
        SelectObject(dc, fBody); SetTextColor(dc, SECONDARY); RECT r2 = {98, 58, 480, 80}; DrawTextW(dc, L"Gõ tiếng Việt, tự chuyển Anh/Việt cho bạn.", -1, &r2, DT_LEFT | DT_SINGLELINE);
        Graphics g(dc); g.SetSmoothingMode(SmoothingModeAntiAlias); SolidBrush gb(gp(GREEN)); g.FillEllipse(&gb, 28.0f, 112.0f, 20.0f, 20.0f);
        Pen pen(Color(255, 255, 255, 255), 2.5f); g.DrawLine(&pen, 33.0f, 122.0f, 37.0f, 126.0f); g.DrawLine(&pen, 37.0f, 126.0f, 44.0f, 117.0f);
        SelectObject(dc, fTitle); SetTextColor(dc, GREEN); RECT r3 = {56, 110, 480, 136}; DrawTextW(dc, L"Vikey đã sẵn sàng", -1, &r3, DT_LEFT | DT_SINGLELINE);
        SelectObject(dc, fBody); SetTextColor(dc, TEXT); RECT r4 = {28, 150, 472, 230};
        std::wstring t = L"Bấm " + hotkeyDisplay(currentHotkey()) + L" để chuyển Anh/Việt. Khi bạn gõ nhầm chế độ, Vikey tự sửa từ và chuyển giúp bạn. Bấm Delete ngay sau đó nếu muốn hoàn tác.";
        DrawTextW(dc, t.c_str(), -1, &r4, DT_LEFT | DT_WORDBREAK);
        EndPaint(h, &ps); return 0; }
    case WM_COMMAND: if (LOWORD(wp) == O_DONE) DestroyWindow(h); return 0;
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _onbWin = nullptr; return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}
void showOnboarding(HINSTANCE inst) {
    initLook();
    if (_onbWin) { SetForegroundWindow(_onbWin); return; }
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = onbProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyOnboarding"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW); wc.hIcon = LoadIconW(inst, MAKEINTRESOURCEW(IDI_APP)); RegisterClassW(&wc); reg = true; }
    RECT wr = {0, 0, 500, 288}; AdjustWindowRectEx(&wr, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0);
    _onbWin = CreateWindowExW(0, L"VikeyOnboarding", L"Vikey", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, wr.right - wr.left, wr.bottom - wr.top, nullptr, nullptr, inst, nullptr);
    HWND b = CreateWindowW(L"BUTTON", L"Xong", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 500 - 28 - 96, 288 - 28 - 32, 96, 32, _onbWin, (HMENU)O_DONE, inst, nullptr);
    SendMessageW(b, WM_SETFONT, (WPARAM)fBody, TRUE);
    ShowWindow(_onbWin, SW_SHOW); SetForegroundWindow(_onbWin);
    prefs::setInt(L"FirstRunDone", 1);
}

// ---- about -----------------------------------------------------------------------------------
static LRESULT CALLBACK aboutProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_PAINT: {
        PAINTSTRUCT ps; HDC dc = BeginPaint(h, &ps); RECT rc; GetClientRect(h, &rc);
        HBRUSH bg = CreateSolidBrush(GROUP); FillRect(dc, &rc, bg); DeleteObject(bg);
        HICON icon = (HICON)LoadImageW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP), IMAGE_ICON, 96, 96, LR_DEFAULTCOLOR);
        if (icon) { DrawIconEx(dc, (rc.right - 96) / 2, 24, icon, 96, 96, 0, nullptr, DI_NORMAL); DestroyIcon(icon); }
        SetBkMode(dc, TRANSPARENT); SelectObject(dc, fWordmark); SetTextColor(dc, TEXT); RECT r = {0, 130, rc.right, 160}; DrawTextW(dc, L"Vikey", -1, &r, DT_CENTER | DT_SINGLELINE);
        SelectObject(dc, fSmall); SetTextColor(dc, SECONDARY); RECT r2 = {0, 162, rc.right, 182}; DrawTextW(dc, L"Phiên bản " VIKEY_VERSION_W, -1, &r2, DT_CENTER | DT_SINGLELINE);
        EndPaint(h, &ps); return 0; }
    case WM_NOTIFY: { NMHDR* n = (NMHDR*)lp; if (n->code == NM_CLICK || n->code == NM_RETURN) { NMLINK* l = (NMLINK*)lp; ShellExecuteW(nullptr, L"open", l->item.szUrl, nullptr, nullptr, SW_SHOW); } return 0; }
    case WM_CTLCOLORSTATIC: SetBkMode((HDC)wp, TRANSPARENT); return (LRESULT)GetStockObject(WHITE_BRUSH);
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _aboutWin = nullptr; return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}
void showAbout(HINSTANCE inst) {
    initLook();
    if (_aboutWin) { SetForegroundWindow(_aboutWin); return; }
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = aboutProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyAbout"; wc.hCursor = LoadCursor(nullptr, IDC_ARROW); RegisterClassW(&wc); reg = true; }
    RECT wr = {0, 0, 300, 290}; AdjustWindowRectEx(&wr, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, FALSE, 0);
    _aboutWin = CreateWindowExW(0, L"VikeyAbout", L"Giới thiệu Vikey", WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU, CW_USEDEFAULT, CW_USEDEFAULT, wr.right - wr.left, wr.bottom - wr.top, nullptr, nullptr, inst, nullptr);
    HWND link = CreateWindowExW(0, WC_LINK, L"Tác giả: <a href=\"https://tonydinh.com\">Tony Dinh</a>\nDựa trên <a href=\"https://github.com/tuyenvm/OpenKey\">OpenKey</a> của Tuyen Mai, GPL-3.0\n<a href=\"https://vikey.app\">vikey.app</a>", WS_CHILD | WS_VISIBLE, 20, 196, 260, 80, _aboutWin, (HMENU)A_LINK, inst, nullptr);
    SendMessageW(link, WM_SETFONT, (WPARAM)fSmall, TRUE);
    ShowWindow(_aboutWin, SW_SHOW); SetForegroundWindow(_aboutWin);
}

// ---- typing log window ------------------------------------------------------------------------
static std::wstring fromUtf8(const std::string& s) { int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0); std::wstring w(n, 0); MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n); return w; }
static std::wstring jget(const std::wstring& j, const wchar_t* key) {   // flat JSON string field
    std::wstring k = L"\"" + std::wstring(key) + L"\":"; size_t p = j.find(k); if (p == std::wstring::npos) return L"";
    p += k.size(); if (p < j.size() && j[p] == L'"') { size_t e = p + 1; std::wstring out; while (e < j.size() && j[e] != L'"') { if (j[e] == L'\\' && e + 1 < j.size()) { e++; if (j[e] == L'u' && e + 4 < j.size()) { out += (wchar_t)wcstol(j.substr(e + 1, 4).c_str(), nullptr, 16); e += 4; } else out += j[e]; } else out += j[e]; e++; } return out; }
    size_t e = j.find_first_of(L",}", p); return j.substr(p, e - p);
}
struct Period { std::map<std::wstring, int> c; int get(const wchar_t* k) const { auto i = c.find(k); return i == c.end() ? 0 : i->second; } };
static Period sumStats(int days) {   // TLStat_<day>_<name> registry values
    Period p; HKEY h; if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Vikey", 0, KEY_READ, &h) != ERROR_SUCCESS) return p;
    SYSTEMTIME st; GetLocalTime(&st); FILETIME ft; SystemTimeToFileTime(&st, &ft); ULARGE_INTEGER u; u.LowPart = ft.dwLowDateTime; u.HighPart = ft.dwHighDateTime;
    std::wstring from = L"0000";
    if (days > 0) { u.QuadPart -= (ULONGLONG)(days - 1) * 864000000000ULL; ft.dwLowDateTime = u.LowPart; ft.dwHighDateTime = u.HighPart; SYSTEMTIME f; FileTimeToSystemTime(&ft, &f); wchar_t b[16]; swprintf_s(b, L"%04d-%02d-%02d", f.wYear, f.wMonth, f.wDay); from = b; }
    for (DWORD i = 0;; i++) { wchar_t name[256]; DWORD nl = 256, type, v, vs = sizeof(v); if (RegEnumValueW(h, i, name, &nl, nullptr, &type, (LPBYTE)&v, &vs) != ERROR_SUCCESS) break;
        std::wstring n = name; if (n.rfind(L"TLStat_", 0) != 0 || type != REG_DWORD) continue; std::wstring day = n.substr(7, 10); if (day < from) continue; p.c[n.substr(18)] += (int)v; }
    RegCloseKey(h); return p;
}
static void refreshLog() {
    core::flushTypingLog();
    Period p1 = sumStats(1), p7 = sumStats(7), pa = sumStats(0);
    auto autoN = [](const Period& p) { return p.get(L"auto_vi_word_to_en") + p.get(L"auto_en_word_to_vi") + p.get(L"auto_double_key"); };
    wchar_t s[200]; swprintf_s(s, L"Hôm nay: %d lần chuyển tay, %d lần tự chuyển", p1.get(L"manual"), autoN(p1)); SetWindowTextW(_logSummary, s);
    const wchar_t* rows[][2] = {{L"Từ đã gõ", L"words"}, {L"Chuyển tay", L"manual"}, {L"Tự chuyển", L"auto"}, {L"    Tiếng Việt → Anh (cả từ)", L"auto_vi_word_to_en"}, {L"    Anh → Tiếng Việt (cả từ)", L"auto_en_word_to_vi"},
                               {L"    Gõ dấu hai lần → Anh", L"auto_double_key"}, {L"Hoàn tác bằng Delete", L"undo"}, {L"Đổi theo ứng dụng / trang web", L"context"}, {L"Chuyển tay mỗi 100 từ", L"rate"}};
    ListView_DeleteAllItems(_logGrid);
    const Period* ps[3] = {&p1, &p7, &pa};
    for (int r = 0; r < 9; r++) {
        LVITEMW it = {}; it.mask = LVIF_TEXT; it.iItem = r; it.pszText = (LPWSTR)rows[r][0]; ListView_InsertItem(_logGrid, &it);
        for (int c = 0; c < 3; c++) {
            const Period& p = *ps[c]; int words = p.get(L"words_vi") + p.get(L"words_en"); std::wstring v; wchar_t b[32];
            std::wstring key = rows[r][1];
            if (key == L"words") v = std::to_wstring(words); else if (key == L"auto") v = std::to_wstring(autoN(p));
            else if (key == L"rate") { if (words) { swprintf_s(b, L"%.1f", 100.0 * p.get(L"manual") / words); v = b; } else v = L"–"; }
            else v = std::to_wstring(p.get(key.c_str()));
            ListView_SetItemText(_logGrid, r, c + 1, (LPWSTR)v.c_str());
        }
    }
    // events, newest first
    std::ifstream f(core::typingLogPath(), std::ios::binary); std::vector<std::string> lines; std::string l;
    while (std::getline(f, l)) { if (!l.empty()) lines.push_back(l); if (lines.size() > 2000) lines.erase(lines.begin(), lines.begin() + 1000); }
    ListView_DeleteAllItems(_logList);
    int n = 0;
    for (auto li = lines.rbegin(); li != lines.rend() && n < 300; ++li, ++n) {
        std::wstring j = fromUtf8(*li); std::wstring e = jget(j, L"e"), to = jget(j, L"to") == L"vi" ? L"Tiếng Việt" : L"Anh", t = jget(j, L"t");
        std::wstring time = t.size() >= 19 ? t.substr(5, 14) : t; for (auto& ch : time) if (ch == L'T') ch = L' ';
        std::wstring app = jget(j, L"app"), site = jget(j, L"site"); std::wstring place = site.empty() ? app : app + L" · " + site;
        std::wstring title, detail;
        if (e == L"word") { title = jget(j, L"lang") == L"vi" ? L"Từ (Việt)" : L"Từ (Anh)"; detail = jget(j, L"keys") + L"   [" + jget(j, L"end") + L"]"; }
        else if (e == L"auto") { title = L"Tự chuyển → " + to; std::wstring r = jget(j, L"rule"); detail = r == L"vi_word_to_en" ? L"từ tiếng Anh gõ khi đang ở Tiếng Việt" : r == L"en_word_to_vi" ? L"từ tiếng Việt gõ khi đang ở Anh" : L"gõ dấu hai lần"; }
        else if (e == L"manual") { title = L"Chuyển tay → " + to; detail = (jget(j, L"via") == L"menu" ? L"bằng menu" : L"bằng phím tắt") + std::wstring(jget(j, L"after_auto") == L"true" ? L", ngay sau tự chuyển" : L""); }
        else if (e == L"undo") { title = L"Hoàn tác → " + to; detail = L"bằng Delete"; }
        else if (e == L"context") { title = L"Theo app/web → " + to; }
        else { title = e; }
        LVITEMW it = {}; it.mask = LVIF_TEXT | LVIF_PARAM; it.iItem = n; it.pszText = (LPWSTR)time.c_str(); it.lParam = e == L"manual" || e == L"undo" ? 1 : (e == L"word" ? 0 : 2); ListView_InsertItem(_logList, &it);
        ListView_SetItemText(_logList, n, 1, (LPWSTR)place.c_str()); ListView_SetItemText(_logList, n, 2, (LPWSTR)title.c_str()); ListView_SetItemText(_logList, n, 3, (LPWSTR)detail.c_str());
    }
}
static LRESULT CALLBACK logProc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_COMMAND:
        if (LOWORD(wp) == L_REFRESH) refreshLog();
        else if (LOWORD(wp) == L_OPEN) { core::flushTypingLog(); std::wstring p = core::typingLogPath(); if (GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES) ShellExecuteW(nullptr, L"open", L"explorer.exe", (L"/select,\"" + p + L"\"").c_str(), nullptr, SW_SHOW); else ShellExecuteW(nullptr, L"open", prefs::appDataDir().c_str(), nullptr, nullptr, SW_SHOW); }
        else if (LOWORD(wp) == L_CLEAR) { if (MessageBoxW(h, L"Số liệu thống kê và file log sẽ bị xoá.", L"Xoá toàn bộ nhật ký gõ?", MB_OKCANCEL | MB_ICONWARNING | MB_DEFBUTTON2) == IDOK) { core::clearTypingLog(); HKEY k; if (RegOpenKeyExW(HKEY_CURRENT_USER, L"Software\\Vikey", 0, KEY_READ | KEY_WRITE, &k) == ERROR_SUCCESS) { std::vector<std::wstring> del; for (DWORD i = 0;; i++) { wchar_t name[256]; DWORD nl = 256; if (RegEnumValueW(k, i, name, &nl, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break; if (wcsncmp(name, L"TLStat_", 7) == 0) del.push_back(name); } for (auto& d : del) RegDeleteValueW(k, d.c_str()); RegCloseKey(k); } refreshLog(); } }
        else if (LOWORD(wp) == C_LOGKEYS) { prefs::setInt(L"TypingLogKeys", toggleOn((HWND)lp)); core::reloadSettings(); }
        return 0;
    case WM_NOTIFY: { NMHDR* n = (NMHDR*)lp;
        if (n->hwndFrom == _logList && n->code == NM_CUSTOMDRAW) { NMLVCUSTOMDRAW* cd = (NMLVCUSTOMDRAW*)lp;
            if (cd->nmcd.dwDrawStage == CDDS_PREPAINT) return CDRF_NOTIFYITEMDRAW;
            if (cd->nmcd.dwDrawStage == CDDS_ITEMPREPAINT) { cd->clrText = cd->nmcd.lItemlParam == 1 ? RGB(255, 149, 0) : (cd->nmcd.lItemlParam == 2 ? ACCENT : TEXT); return CDRF_NEWFONT; } }
        return 0; }
    case WM_CTLCOLORSTATIC: SetBkMode((HDC)wp, TRANSPARENT); SetTextColor((HDC)wp, (HWND)lp == _logSummary ? TEXT : SECONDARY); return (LRESULT)GetStockObject(WHITE_BRUSH);
    case WM_SIZE: { RECT r; GetClientRect(h, &r); MoveWindow(_logList, 20, 350, r.right - 40, r.bottom - 350 - 60, TRUE); for (int id : {L_REFRESH, L_OPEN, L_CLEAR}) { HWND b = GetDlgItem(h, id); RECT br; GetWindowRect(b, &br); MapWindowPoints(nullptr, h, (POINT*)&br, 2); MoveWindow(b, id == L_CLEAR ? r.right - 20 - 100 : br.left, r.bottom - 44, id == L_CLEAR ? 100 : br.right - br.left, 28, TRUE); } return 0; }
    case WM_CLOSE: DestroyWindow(h); return 0;
    case WM_DESTROY: _logWin = nullptr; return 0;
    }
    return DefWindowProcW(h, msg, wp, lp);
}
void showTypingLog(HINSTANCE inst) {
    initLook(); registerClasses(inst);
    if (_logWin) { SetForegroundWindow(_logWin); refreshLog(); return; }
    static bool reg = false;
    if (!reg) { WNDCLASSW wc = {}; wc.lpfnWndProc = logProc; wc.hInstance = inst; wc.lpszClassName = L"VikeyLog"; wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1); wc.hCursor = LoadCursor(nullptr, IDC_ARROW); RegisterClassW(&wc); reg = true; }
    RECT wr = {0, 0, 760, 600}; AdjustWindowRectEx(&wr, WS_OVERLAPPEDWINDOW, FALSE, 0);
    _logWin = CreateWindowExW(0, L"VikeyLog", L"Nhật ký gõ", WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, wr.right - wr.left, wr.bottom - wr.top, nullptr, nullptr, inst, nullptr);
    HWND old = _win; _win = _logWin;
    _logSummary = child(L"STATIC", L"", SS_LEFT, 20, 20, 700, 24, 0, fTitle);
    _logGrid = child(WC_LISTVIEWW, L"", LVS_REPORT | LVS_NOSORTHEADER | LVS_SINGLESEL, 20, 52, 720, 212, 0, fBody);
    ListView_SetExtendedListViewStyle(_logGrid, LVS_EX_FULLROWSELECT);
    const wchar_t* heads[] = {L"", L"Hôm nay", L"7 ngày", L"Tất cả"}; int widths[] = {330, 120, 120, 120};
    for (int i = 0; i < 4; i++) { LVCOLUMNW c = {}; c.mask = LVCF_TEXT | LVCF_WIDTH | LVCF_FMT; c.pszText = (LPWSTR)heads[i]; c.cx = widths[i]; c.fmt = i ? LVCFMT_RIGHT : LVCFMT_LEFT; ListView_InsertColumn(_logGrid, i, &c); }
    HWND tg = child(L"VikeyToggle", L"", 0, 20, 274, 40, 23, C_LOGKEYS); setToggle(tg, prefs::getInt(L"TypingLogKeys", 1) != 0);
    child(L"STATIC", L"Ghi lại phím gõ của từng từ", SS_LEFT, 68, 276, 500, 20, 0, fBody);
    child(L"STATIC", L"Không bao giờ ghi trong ô mật khẩu, trình quản lý mật khẩu và Terminal.", SS_LEFT, 68, 298, 600, 18, 1, fSmall);
    child(L"STATIC", L"Sự kiện gần đây", SS_LEFT, 20, 326, 300, 20, 0, fBodyBold);
    _logList = child(WC_LISTVIEWW, L"", LVS_REPORT | LVS_NOSORTHEADER | LVS_SINGLESEL, 20, 350, 720, 190, 0, fBody);
    ListView_SetExtendedListViewStyle(_logList, LVS_EX_FULLROWSELECT);
    const wchar_t* eh[] = {L"Thời gian", L"Ứng dụng / trang", L"Sự kiện", L"Chi tiết"}; int ew[] = {110, 160, 140, 290};
    for (int i = 0; i < 4; i++) { LVCOLUMNW c = {}; c.mask = LVCF_TEXT | LVCF_WIDTH; c.pszText = (LPWSTR)eh[i]; c.cx = ew[i]; ListView_InsertColumn(_logList, i, &c); }
    child(L"BUTTON", L"Làm mới", 0, 20, 556, 90, 28, L_REFRESH, fBody); child(L"BUTTON", L"Mở file log", 0, 118, 556, 100, 28, L_OPEN, fBody); child(L"BUTTON", L"Xoá log…", 0, 640, 556, 100, 28, L_CLEAR, fBody);
    _win = old;
    refreshLog(); ShowWindow(_logWin, SW_SHOW);
}

}} // namespace
