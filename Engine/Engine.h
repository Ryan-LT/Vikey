//
//  Engine.h
//  Vikey (based on OpenKey)
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#ifndef Engine_h
#define Engine_h

#include <locale>
#include <codecvt>

#include "DataType.h"
#include "Vietnamese.h"
#include "SmartSwitchKey.h"

#define IS_DEBUG 1

#ifndef LOBYTE
#define LOBYTE(data) (data & 0xFF)
#endif // !LOBYTE
#ifndef HIBYTE
#define HIBYTE(data) ((data>>8) & 0xFF)
#endif // !HIBYTE

#define GET_SWITCH_KEY(data) (data & 0xFF)
#define HAS_CONTROL(data) ((data & 0x100) ? 1 : 0)
#define HAS_OPTION(data) ((data & 0x200) ? 1 : 0)
#define HAS_COMMAND(data) ((data & 0x400) ? 1 : 0)
#define HAS_SHIFT(data) ((data & 0x800) ? 1 : 0)
#define GET_BOOL(data) (data ? 1 : 0)
#define HAS_BEEP(data) (data & 0x8000)
#define SET_SWITCH_KEY(data, key) data = (data & 0xFF) | key
#define SET_CONTROL_KEY(data, val) data|=val<<8;
#define SET_OPTION_KEY(data, val) data|=val<<9;
#define SET_COMMAND_KEY(data, val) data|=val<<10;

//define these variable in your application
//API
/*
 * 0: English
 * 1: Vietnamese
 */
extern int vLanguage;

/*
 * first 8 bit: keycode
 * bit 8: Control on/off
 * bit 9: Option on/off
 * bit 10: Command on/off
 */
extern int vSwitchKeyStatus;

/**
 * 0: No
 * 1: Yes
 */
extern int vCheckSpelling;

/*
 * 0: òa, úy
 * 1: oà uý
*/
extern int vUseModernOrthography;

/**
 * Work together with vCheckSpelling
 * 0: No
 * 1: Yes
 *
 */
extern int vRestoreIfWrongSpelling;

/*
 * Fix recommend browser's address, excel,...
 * 0: No
 * 1: Yes
 */
extern int vFixRecommendBrowser;

/**
 * auto switch language when switch app
 * 0: No
 * 1: Yes
 */
extern int vUseSmartSwitchKey;

/**
 * 0: No; 1: Yes
 * Turn off Vietnamese when typing in another language.
 */
extern int vOtherLanguage;

/**
 * Auto switch language from typing behavior (Telex family only).
 * 0: No; 1: Yes
 */
extern int vAutoSwitchByTyping;

/**
 * Set by the engine when a keystroke should switch the language:
 * -1: no request, 0: switch to English, 1: switch to Vietnamese.
 * The platform layer applies it after sending the key's output, then resets it to -1.
 */
extern int vAutoSwitchRequest;

/**
 * What was on screen before the last automatic correction (engine character data),
 * so the platform can put it back when the user immediately presses the switch hotkey.
 */
extern Uint32 vAutoSwitchUndoData[MAX_BUFF];
extern int vAutoSwitchUndoCount;

/**
 * English mode, at a word break: if the raw keys of the finished word are clearly a
 * Vietnamese word typed in Telex, fills the hook state (code vRestore) with that word and
 * returns true. The platform then replaces the word and switches to Vietnamese.
 * keys: key codes with CAPS_MASK, count: number of keys.
 */
bool vAutoSwitchCheckEnglishWord(const Uint32* keys, const int& count);

/**
 * Same, with the words typed just before it (most recent first, separated by single spaces):
 * ambiguous ones are converted together with it (look-back).
 */
bool vAutoSwitchCheckEnglishWord(const Uint32* keys, const int& count,
                                 const Uint32* const* previous, const int* previousCounts, const int& previousN);

/**
 * Forget the words remembered for look-back (language switched by hand, app changed...).
 */
void vAutoSwitchForget();

/**
 * Call this function first to receive data pointer
 */
void* vKeyInit();

/**
 * Convert engine character to real character
 */
Uint32 getCharacterCode(const Uint32& data);

/**
 * MAIN entry point for each key
 * event: mouse or keyboard event
 * state: additional state for event
 * data: key code
 * isCaps: caplock is on or shift key is pressing
 * otherControlKey: ctrl, option,... is pressing
 */
void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus=0,
                     const bool& otherControlKey=false);

/**
 * Start a new word
 */
void startNewSession();

/**
 * reset spelling value
 */
void vSetCheckSpelling();

/**
 * some utils function
 */
wstring utf8ToWideString(const string& str);
string wideStringToUtf8(const wstring& str);

#endif /* Engine_h */
