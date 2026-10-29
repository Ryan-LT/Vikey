// Settings window (the macOS app's compact main window), first-run welcome, typing-log window.
#pragma once
#include <windows.h>
namespace vikey { namespace ui {
void showSettings(HINSTANCE inst, bool firstRun);
void showTypingLog(HINSTANCE inst);
void languageChanged(int lang);   // refresh the language switch if the window is open
}}
