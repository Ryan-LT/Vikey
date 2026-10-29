// Per-website memory: the host of the active tab of the browser in front, read through UI Automation.
#pragma once
#include <string>
namespace vikey { namespace site {
bool isBrowser(const std::wstring& exe);
/// Reads the address bar of the foreground browser; empty when not a browser or no URL.
std::wstring currentHost();
/// Call every second while a browser is in front (and shortly after clicks / tab shortcuts).
void poll();
}}
