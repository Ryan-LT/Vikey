#include "Site.h"
#include "Core.h"
#include "Prefs.h"
#undef WIN32_LEAN_AND_MEAN   // UIAutomation needs the OLE/RPC types windows.h leaves out
#include <windows.h>
#include <objbase.h>
#include <oleauto.h>
#include <uiautomation.h>
#include <algorithm>
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "oleaut32.lib")

namespace vikey { namespace site {

static IUIAutomation* _uia = nullptr;

bool isBrowser(const std::wstring& exeIn) {
    std::wstring exe = exeIn; std::transform(exe.begin(), exe.end(), exe.begin(), ::towlower);
    static const wchar_t* list[] = {L"chrome.exe", L"msedge.exe", L"brave.exe", L"vivaldi.exe", L"opera.exe", L"opera_gx.exe", L"firefox.exe", L"chromium.exe", L"arc.exe"};
    for (auto b : list) if (exe == b) return true;
    return false;
}

static bool looksLikeUrl(const std::wstring& v) {
    if (v.empty() || v.size() > 2048) return false;
    if (v.rfind(L"http://", 0) == 0 || v.rfind(L"https://", 0) == 0) return true;
    if (v.find(L' ') != std::wstring::npos) return false;
    size_t dot = v.find(L'.');
    return dot != std::wstring::npos && dot > 0 && dot + 1 < v.size();
}

static std::wstring hostOf(std::wstring v) {
    size_t p = v.find(L"://"); if (p != std::wstring::npos) v = v.substr(p + 3);
    size_t e = v.find_first_of(L"/?#:"); if (e != std::wstring::npos) v = v.substr(0, e);
    std::transform(v.begin(), v.end(), v.begin(), ::towlower);
    if (v.rfind(L"www.", 0) == 0) v = v.substr(4);
    return v;
}

std::wstring currentHost() {
    if (!isBrowser(core::frontAppName())) return L"";
    if (!_uia) { CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED); if (FAILED(CoCreateInstance(CLSID_CUIAutomation, nullptr, CLSCTX_INPROC_SERVER, IID_IUIAutomation, (void**)&_uia))) return L""; }
    HWND w = GetForegroundWindow(); if (!w) return L"";
    IUIAutomationElement* root = nullptr; if (FAILED(_uia->ElementFromHandle(w, &root)) || !root) return L"";
    std::wstring host;
    VARIANT vt; vt.vt = VT_I4; vt.lVal = UIA_EditControlTypeId;
    IUIAutomationCondition* cond = nullptr;
    if (SUCCEEDED(_uia->CreatePropertyCondition(UIA_ControlTypePropertyId, vt, &cond)) && cond) {
        IUIAutomationElementArray* arr = nullptr;
        if (SUCCEEDED(root->FindAll(TreeScope_Descendants, cond, &arr)) && arr) {
            int n = 0; arr->get_Length(&n);
            for (int i = 0; i < n && n < 200 && host.empty(); i++) {
                IUIAutomationElement* el = nullptr; if (FAILED(arr->GetElement(i, &el)) || !el) continue;
                IUIAutomationValuePattern* vp = nullptr;
                if (SUCCEEDED(el->GetCurrentPatternAs(UIA_ValuePatternId, IID_IUIAutomationValuePattern, (void**)&vp)) && vp) {
                    BSTR b = nullptr; if (SUCCEEDED(vp->get_CurrentValue(&b)) && b) { std::wstring v(b, SysStringLen(b)); SysFreeString(b); if (looksLikeUrl(v)) host = hostOf(v); }
                    vp->Release();
                }
                el->Release();
            }
            arr->Release();
        }
        cond->Release();
    }
    root->Release();
    return host;
}

void poll() {
    if (!prefs::getInt(L"SmartSwitchPerSite", 1)) { core::onSiteChanged(L""); return; }
    core::onSiteChanged(currentHost());
}

}}
