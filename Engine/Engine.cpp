//
//  Engine.cpp
//  Vikey (based on OpenKey)
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//
#include <iostream>
#include <algorithm>
#include "Engine.h"
#include <string.h>
#include <list>
#include "AutoSwitchData.h"

static vector<Uint8> _charKeyCode = {
    KEY_BACKQUOTE, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_MINUS, KEY_EQUALS,
    KEY_LEFT_BRACKET, KEY_RIGHT_BRACKET, KEY_BACK_SLASH,
    KEY_SEMICOLON, KEY_QUOTE, KEY_COMMA, KEY_DOT, KEY_SLASH
};

static vector<Uint8> _breakCode = {
    KEY_ESC, KEY_TAB, KEY_ENTER, KEY_RETURN, KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_COMMA, KEY_DOT,
    KEY_SLASH, KEY_SEMICOLON, KEY_QUOTE, KEY_BACK_SLASH, KEY_MINUS, KEY_EQUALS, KEY_BACKQUOTE, KEY_TAB
#if _WIN32
	, VK_INSERT, VK_HOME, VK_END, VK_DELETE, VK_PRIOR, VK_NEXT, VK_SNAPSHOT, VK_PRINT, VK_SELECT, VK_HELP,
	VK_EXECUTE, VK_NUMLOCK, VK_SCROLL
#endif
};


//Telex keys: tones s f r x j, doubled a o e (circumflex), w (horn/breve), d (đ), z (remove tone)
static const Uint16 TelexKey[11] = {KEY_S, KEY_F, KEY_R, KEY_X, KEY_J, KEY_A, KEY_O, KEY_E, KEY_W, KEY_D, KEY_Z};

#define IS_KEY_Z(key) (TelexKey[10] == key)
#define IS_KEY_D(key) (TelexKey[9] == key)
#define IS_KEY_W(key) (TelexKey[8] == key)
#define IS_KEY_DOUBLE(key) (TelexKey[5] == key || TelexKey[6] == key || TelexKey[7] == key)
#define IS_KEY_S(key) (TelexKey[0] == key)
#define IS_KEY_F(key) (TelexKey[1] == key)
#define IS_KEY_R(key) (TelexKey[2] == key)
#define IS_KEY_X(key) (TelexKey[3] == key)
#define IS_KEY_J(key) (TelexKey[4] == key)

#define IS_MARK_KEY(keyCode) (keyCode == KEY_S || keyCode == KEY_F || keyCode == KEY_R || keyCode == KEY_J || keyCode == KEY_X)
#define IS_BRACKET_KEY(key) (key == KEY_LEFT_BRACKET || key == KEY_RIGHT_BRACKET)

#define VSI vowelStartIndex
#define VEI vowelEndIndex
#define VWSM vowelWillSetMark
#define hBPC HookState.backspaceCount
#define hNCC HookState.newCharCount
#define hCode HookState.code
#define hExt HookState.extCode
#define hData HookState.charData
#define GET getCharacterCode

//Data to sendback to main program
vKeyHookState HookState;

//private data
/**
 * data structure of each element in TypingWord (Uint64)
 * first 2 byte is character code or key code.
 * bit 16: has caps or not
 * bit 17: has tone ^ or not
 * bit 18: has tone w or not
 * bit 19 - > 23: has mark or not (Sắc, huyền, hỏi, ngã, nặng)
 * bit 24: is standalone key? (w, [, ])
 * bit 25: is character code or keyboard code; 1: character code; 0: keycode
 */
static Uint32 TypingWord[MAX_BUFF];
static Byte _index = 0;
static vector<Uint32> _longWordHelper; //save the word when _index >= MAX_BUFF
static list<vector<Uint32>> _typingStates; //Aug 28th, 2019: typing helper, save long state of Typing word, can go back and modify the word
vector<Uint32> _typingStatesData;

/**
 * Use for restore key if invalid word
 */
static Uint32 KeyStates[MAX_BUFF];
static int _asDropPos = -1;      //auto switch: a key Telex undid and dropped from the key states ("eee" -> "ee"), and where it was
static Uint32 _asDropKey = 0;
static Byte _stateIndex = 0;

static bool tempDisableKey = false;
static int capsElem;
static int key;
static int markElem;
static bool isCorect = false;
static bool isChanged = false;
static Byte vowelCount = 0;
static Byte vowelStartIndex = 0;
static Byte vowelEndIndex = 0;
static Byte vowelWillSetMark = 0;
static int i, ii, iii;
static int j;
static int k, kk;
static int l;
static bool isRestoredW;
static Uint16 keyForAEO;
static bool isCheckedGrammar;
static bool _isCaps = false;
static int _spaceCount = 0; //add: July 30th, 2019
static bool _isCharKeyCode;
static vector<Uint32> _specialChar;
static bool _useSpellCheckingBefore;

//function prototype
void findAndCalculateVowel(const bool& forGrammar=false);
void insertMark(const Uint32& markMask, const bool& canModifyFlag=true);

static std::wstring_convert<std::codecvt_utf8_utf16<wchar_t>> converter;
wstring utf8ToWideString(const string& str) {
    return converter.from_bytes(str.c_str());
}

string wideStringToUtf8(const wstring& str) {
    return converter.to_bytes(str.c_str());
}

void* vKeyInit() {
    _index = 0;
    _stateIndex = 0;
    _useSpellCheckingBefore = vCheckSpelling;
    _typingStatesData.clear();
    _typingStates.clear();
    _longWordHelper.clear();
    return &HookState;
}

bool isWordBreak(const vKeyEvent& event, const vKeyEventState& state, const Uint16& data) {
    if (event == vKeyEvent::Mouse)
        return true;
    for (i = 0; i < _breakCode.size(); i++) {
        if (_breakCode[i] == data) {
            return true;
        }
    }
    return false;
}


void setKeyData(const Byte& index, const Uint16& keyCode, const bool& isCaps) {
    if (index < 0 || index >= MAX_BUFF)
        return;
    TypingWord[index] = keyCode | (isCaps ? CAPS_MASK : 0);
}

bool _spellingOK = false;
bool _spellingFlag = false;
bool _spellingVowelOK = false;
Byte _spellingEndIndex = 0;

void checkSpelling(const bool& forceCheckVowel=false) {
    _spellingOK = false;
    _spellingVowelOK = true;
    _spellingEndIndex = _index;
    
    if (_index > 0 && CHR(_index-1) == KEY_RIGHT_BRACKET) {
        _spellingEndIndex = _index-1;
    }
    
    if (_spellingEndIndex > 0) {
        j = 0;
        //Check first consonant
        if (IS_CONSONANT(CHR(0))) {
            for (i = 0; i < _consonantTable.size(); i++) {
                _spellingFlag = false;
                if (_spellingEndIndex < _consonantTable[i].size())
                    _spellingFlag = true;
                for (j = 0; j < _consonantTable[i].size(); j++) {
                    if (_spellingEndIndex > j &&
                        _consonantTable[i][j] != CHR(j)) {
                        _spellingFlag = true;
                        break;
                    }
                }
                if (_spellingFlag)
                    continue;
                
                break;
            }
        }
        
        if (j == _spellingEndIndex){ //for "d" case
            _spellingOK = true;
        }
        
        //check next vowel
        k = j;
        VSI = k;
        //August 23rd, 2019: fix case "que't"
        if (CHR(VSI) == KEY_U && k > 0 && k < _spellingEndIndex-1 && CHR(VSI-1) == KEY_Q) {
            k = k + 1;
            j = k;
            VSI = k;
        } else if (_index >= 2 && CHR(0) == KEY_G && CHR(1) == KEY_I && IS_CONSONANT(CHR(2))) {
            VSI = k = j = 1; //Sep 28th: fix gìn
        }
        for (l = 0; l < 3; l++) {
            if (k < _spellingEndIndex && !IS_CONSONANT(CHR(k))) {
                k++;
                VEI = k;
            }
        }
        if (k > j) { //has vowel,
            _spellingVowelOK = false;
            //check correct combined vowel
            if (k - j > 1 && forceCheckVowel) {
                vector<vector<Uint32>>& vowelSet = _vowelCombine[CHR(j)];
                for (l = 0; l < vowelSet.size(); l++) {
                    _spellingFlag = false;
                    for (ii = 1; ii < vowelSet[l].size(); ii++) {
                        if (j + ii - 1 < _spellingEndIndex && vowelSet[l][ii] != ((CHR(j + ii - 1) | (TypingWord[j + ii - 1] & TONEW_MASK) | (TypingWord[j + ii - 1] & TONE_MASK)))) {
                            _spellingFlag = true;
                            break;
                        }
                    }
                    if (_spellingFlag || (k < _spellingEndIndex && !vowelSet[l][0]) || (j + ii - 1 < _spellingEndIndex && !IS_CONSONANT(CHR(j + ii - 1))))
                        continue;
                    
                    _spellingVowelOK = true;
                    break;
                }
            } else if (!IS_CONSONANT(CHR(j))) {
                _spellingVowelOK = true;
            }
            
            //continue check last consonant
            for (ii = 0; ii < _endConsonantTable.size(); ii++) {
                _spellingFlag = false;
   
                for (j = 0; j < _endConsonantTable[ii].size(); j++) {
                    if (_spellingEndIndex > k+j &&
                        _endConsonantTable[ii][j] != CHR(k + j)) {
                        _spellingFlag = true;
                        break;
                    }
                }
                if (_spellingFlag)
                    continue;
                
                if (k + j >= _spellingEndIndex) {
                    _spellingOK = true;
                    break;
                }
            }
            
            //limit: end consonant "ch", "t" can not use with "~", "`", "?"
            if (_spellingOK) {
                if (_index >= 3 && CHR(_index-1) == KEY_H && CHR(_index-2) == KEY_C && !((TypingWord[_index-3] & MARK1_MASK) || (TypingWord[_index-3] & MARK5_MASK) || !(TypingWord[_index-3] & MARK_MASK))) {
                    _spellingOK = false;
                } else if (_index >= 2 && CHR(_index-1) == KEY_T && !((TypingWord[_index-2] & MARK1_MASK) || (TypingWord[_index-2] & MARK5_MASK) || !(TypingWord[_index-2] & MARK_MASK))) {
                    _spellingOK = false;
                }
            }
        }
    } else {
        _spellingOK = true;
    }
    tempDisableKey = !(_spellingOK && _spellingVowelOK);
    
    //cout<<"spelling vowel: "<<(_spellingVowelOK ? "OK": "Err")<<endl;
    //cout<<"spelling: "<<(_spellingOK ? "OK": "Err")<<endl<<endl;
}

void checkGrammar(const int& deltaBackSpace) {
    if (_index <= 1 || _index >= MAX_BUFF)
        return;
    
    findAndCalculateVowel(true);
    if (vowelCount == 0)
        return;
    
    isCheckedGrammar = false;
    
    l = VSI;
    
    //if N key for case: "thuơn", "ưoi", "ưom", "ưoc"
    if (_index >= 3) {
        for (i = _index-1; i >= 0; i--) {
            if (CHR(i) == KEY_N || CHR(i) == KEY_C || CHR(i) == KEY_I ||
                CHR(i) == KEY_M || CHR(i) == KEY_P || CHR(i) == KEY_T) {
                if (i - 2 >= 0 && CHR(i - 1) == KEY_O && CHR(i - 2) == KEY_U) {
                    if ((TypingWord[i-1] & TONEW_MASK) ^ (TypingWord[i-2] & TONEW_MASK)) {
                        TypingWord[i - 2] |= TONEW_MASK;
                        TypingWord[i - 1] |= TONEW_MASK;
                        isCheckedGrammar = true;
                        break;
                    }
                }
            }
        }
    }
    
    //check mark
    if (_index >= 2) {
        for (i = l; i <= VEI; i++) {
            if (TypingWord[i] & MARK_MASK) {
                Uint32 mark = TypingWord[i] & MARK_MASK;
                TypingWord[i] &= ~MARK_MASK;
                insertMark(mark, false);
                if (i != vowelWillSetMark)
                    isCheckedGrammar = true;
                break;
            }
        }
    }
    
    //re-arrange data to sendback
    if (isCheckedGrammar) {
        if (hCode ==vDoNothing)
            hCode = vWillProcess;
        hBPC = 0;
        
        for (i = _index - 1; i >= l; i--) {
            hBPC++;
            hData[_index - 1 - i] = GET(TypingWord[i]);
        }
        hNCC = hBPC;
        hBPC += deltaBackSpace;
        hExt = 4;
    }
}

void insertKey(const Uint16& keyCode, const bool& isCaps, const bool& isCheckSpelling=true) {
    if (_index >= MAX_BUFF) {
        _longWordHelper.push_back(TypingWord[0]); //save long word
        //left shift
        for (iii = 0; iii < MAX_BUFF - 1; iii++) {
            TypingWord[iii] = TypingWord[iii + 1];
        }
        setKeyData(_index-1, keyCode, isCaps);
    } else {
        setKeyData(_index++, keyCode, isCaps);
    }
    
    if (vCheckSpelling && isCheckSpelling)
        checkSpelling();
    
    //allow d after consonant
    if (keyCode == KEY_D && _index - 2 >= 0 && IS_CONSONANT(CHR(_index - 2)))
        tempDisableKey = false;
}

void insertState(const Uint16& keyCode, const bool& isCaps) {
    if (_stateIndex >= MAX_BUFF) {
        //left shift
        for (iii = 0; iii < MAX_BUFF - 1; iii++) {
            KeyStates[iii] = KeyStates[iii + 1];
        }
        KeyStates[_stateIndex-1] = keyCode | (isCaps ? CAPS_MASK : 0);
    } else {
        KeyStates[_stateIndex++] = keyCode | (isCaps ? CAPS_MASK : 0);
    }
}

void saveWord() {
    //save word history
    {
        if (_index > 0) {
            if (_longWordHelper.size() > 0) { //save long word first
                _typingStatesData.clear();
                for (i = 0; i < _longWordHelper.size(); i++) {
                    if (i != 0 && i % MAX_BUFF == 0) { //save if overflow
                        _typingStates.push_back(_typingStatesData);
                        _typingStatesData.clear();
                    }
                    _typingStatesData.push_back(_longWordHelper[i]);
                }
                _typingStates.push_back(_typingStatesData);
                _longWordHelper.clear();
            }
            
            //save current word
            _typingStatesData.clear();
            for (i = 0; i < _index; i++) {
                _typingStatesData.push_back(TypingWord[i]);
            }
            _typingStates.push_back(_typingStatesData);
        }
    }
}

void saveWord(const Uint32& keyCode, const int& count) {
    _typingStatesData.clear();
    for (i = 0; i < count; i++) {
        _typingStatesData.push_back(keyCode);
    }
    _typingStates.push_back(_typingStatesData);
}

void saveSpecialChar() {
    _typingStatesData.clear();
    for (i = 0; i < _specialChar.size(); i++) {
        _typingStatesData.push_back(_specialChar[i]);
    }
    _typingStates.push_back(_typingStatesData);
    _specialChar.clear();
}

void restoreLastTypingState() {
    if (_typingStates.size() > 0) {
        _typingStatesData = _typingStates.back();
        _typingStates.pop_back();
        if (_typingStatesData.size() > 0){
            if (_typingStatesData[0] == KEY_SPACE) {
                _spaceCount = (int)_typingStatesData.size();
                _index = 0;
            } else if (std::find(_charKeyCode.begin(), _charKeyCode.end(), (Uint16)_typingStatesData[0]) != _charKeyCode.end()) {
                _index = 0;
                _specialChar = _typingStatesData;
                checkSpelling();
            } else {
                for (i = 0; i < _typingStatesData.size(); i++) {
                    TypingWord[i] = _typingStatesData[i];
                }
                _index = (Byte)_typingStatesData.size();
            }
        }
    }
}

void startNewSession() {
    _asDropPos = -1;
    _index = 0;
    hBPC = 0;
    hNCC = 0;
    tempDisableKey = false;
    _stateIndex = 0;
    _longWordHelper.clear();
}

void checkCorrectVowel(vector<vector<Uint16>>& charset, int& i, int& k, const Uint16& markKey) {
    //ignore "qu" case
    if (_index >= 2 && CHR(_index-1) == KEY_U && CHR(_index-2) == KEY_Q) {
        isCorect = false;
        return;
    }
    k = _index - 1;
    for (j = (int)charset[i].size() - 1; j >= 0; j--) {
        if (charset[i][j] != CHR(k)) {
            isCorect = false;
            return;
        }
        k--;
        if (k < 0)
            break;
    }
    
    //limit mark for end consonant: "C", "T"
    if (isCorect && charset[i].size() > 1 && (IS_KEY_F(markKey) || IS_KEY_X(markKey) || IS_KEY_R(markKey))) {
        if (charset[i][1] == KEY_C || charset[i][1] == KEY_T) {
            isCorect = false;
        } else if (charset[i].size() > 2 && (charset[i][2] == KEY_T)) {
            isCorect = false;
        }
    }
    
    if (isCorect && k >= 0) {
        if (CHR(k) == CHR(k+1)) {
            isCorect = false;
        }
    }
}

Uint32 getCharacterCode(const Uint32& data) {
    capsElem = (data & CAPS_MASK) ? 0 : 1;
    key = data & CHAR_MASK;
    if (data & MARK_MASK) { //has mark
        markElem = -2;
        switch (data & MARK_MASK) {
            case MARK1_MASK:
                markElem = 0;
                break;
            case MARK2_MASK:
                markElem = 2;
                break;
            case MARK3_MASK:
                markElem = 4;
                break;
            case MARK4_MASK:
                markElem = 6;
                break;
            case MARK5_MASK:
                markElem = 8;
                break;
        }
        markElem += capsElem;
        
        switch (key) {
            case KEY_A:
            case KEY_O:
            case KEY_U:
            case KEY_E:
                if ((data & TONE_MASK) == 0 && (data & TONEW_MASK) == 0)
                    markElem += 4;
                break;
        }
        
        if (data & TONE_MASK) {
            key |= TONE_MASK;
        } else if (data & TONEW_MASK) {
            key |= TONEW_MASK;
        }
        if (_unicodeTable.find(key) == _unicodeTable.end())
            return data & ~STANDALONE_MASK; //not found (a standalone w that lost its ư is just u, never a raw flagged code)
        
        return _unicodeTable[key][markElem] | CHAR_CODE_MASK;
    } else { //doesn't has mark
        if (_unicodeTable.find(key) == _unicodeTable.end())
            return data & ~STANDALONE_MASK; //not found (a standalone w that lost its ư is just u, never a raw flagged code)
        
        if (data & TONE_MASK) {
            return _unicodeTable[key][capsElem] | CHAR_CODE_MASK;
        } else if (data & TONEW_MASK) {
            return _unicodeTable[key][capsElem + 2] | CHAR_CODE_MASK;
        } else {
            return data & ~STANDALONE_MASK; //not found (a standalone w that lost its ư is just u, never a raw flagged code)
        }
    }
    
    return 0;
}

void findAndCalculateVowel(const bool& forGrammar) {
    vowelCount = 0;
    VSI = VEI = 0;
    for (iii = _index - 1; iii >= 0; iii--) {
        if (IS_CONSONANT(CHR(iii))) {
            if (vowelCount > 0)
                break;
        } else {  //is vowel
            if (vowelCount == 0)
                VEI = iii;
            if (!forGrammar) {
                if ((iii-1 >= 0 && (CHR(iii) == KEY_I && CHR(iii-1) == KEY_G)) ||
                    (iii-1 >= 0 && (CHR(iii) == KEY_U && CHR(iii-1) == KEY_Q))) {
                    break;
                }
            }
            VSI = iii;
            vowelCount++;
        }
    }
    //August 26th, 2019: don't count "u" at "q u" as a vowel
    if (VSI - 1 >= 0 && CHR(VSI) == KEY_U && CHR(VSI-1) == KEY_Q) {
        VSI++;
        vowelCount--;
    }
}

void removeMark() {
    findAndCalculateVowel(true);
    isChanged = false;
    if (_index > 0) {
        for (i = VSI; i <= VEI; i++) {
            if (TypingWord[i] & MARK_MASK) {
                TypingWord[i] &= ~MARK_MASK;
                isChanged = true;
            }
        }
    }
    if (isChanged) {
        hCode = vWillProcess;
        hBPC = 0;
        
        for (i = _index - 1; i >= VSI; i--) {
            hBPC++;
            hData[_index - 1 - i] = GET(TypingWord[i]);
        }
        hNCC = hBPC;
    } else {
        hCode = vDoNothing;
    }
}

bool canHasEndConsonant() {
    vector<vector<Uint32>>& vo = _vowelCombine[CHR(VSI)];
    for (ii = 0; ii < vo.size(); ii++) {
        kk = VSI;
        for (iii = 1; iii < vo[ii].size(); iii++) {
            if (kk > VEI || ((CHR(kk) | (TypingWord[kk] & TONE_MASK) | (TypingWord[kk] & TONEW_MASK)) != vo[ii][iii])) {
                break;
            }
            kk++;
        }
        if (iii >= vo[ii].size()) {
            return vo[ii][0] == 1;
        }
    }
    return false;
}

void handleModernMark() {
    //default
    VWSM = VEI;
    hBPC = (_index - VEI);
    
    //rule 2
    if (vowelCount == 3 && ((CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_A && CHR(VSI+2) == KEY_I) ||
                            (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_Y && CHR(VSI+2) == KEY_U) ||
                            (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_E && CHR(VSI+2) == KEY_O) ||
                            (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_Y && CHR(VSI+2) == KEY_A))) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    } else if ((CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_I) ||
               (CHR(VSI) == KEY_A && CHR(VSI+1) == KEY_I) ||
               (CHR(VSI)== KEY_U && CHR(VSI+1) == KEY_I) ) {
        
        VWSM = VSI;
        hBPC = _index - VWSM;
    } else if (CHR(VEI-1) == KEY_A && CHR(VEI) == KEY_Y) {
        VWSM = VEI - 1;
        hBPC = (_index - VEI) + 1;
    } else if (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_O) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    } else if (CHR(VSI+1) == KEY_O || CHR(VSI+1) == KEY_U) {
        VWSM = VEI - 1;
        hBPC = (_index - VEI) + 1;
    } else if (CHR(VSI) == KEY_O || CHR(VSI) == KEY_U) {
        VWSM = VEI;
        hBPC = (_index - VEI);
    }
    
    //rule 3.1
    if ((CHR(VSI) == KEY_I && (TypingWord[VSI+1] & (KEY_E | TONE_MASK))) ||
        (CHR(VSI) == KEY_Y && (TypingWord[VSI+1] & (KEY_E | TONE_MASK))) ||
        (CHR(VSI) == KEY_U && (TypingWord[VSI+1] == (KEY_O | TONE_MASK))) ||
        ((TypingWord[VSI] == (KEY_U | TONEW_MASK)) && (TypingWord[VSI+1] == (KEY_O | TONEW_MASK)))){
        
        if (VSI+2 < _index) {
            if (CHR(VSI+2) == KEY_P || CHR(VSI+2) == KEY_T ||
                CHR(VSI+2) == KEY_M || CHR(VSI+2) == KEY_N ||
                CHR(VSI+2) == KEY_O || CHR(VSI+2) == KEY_U ||
                CHR(VSI+2) == KEY_I || CHR(VSI+2) == KEY_C ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_C && CHR(VSI+2) == KEY_H) ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_N && CHR(VSI+2) == KEY_H) ||
                (VSI+3 < _index && CHR(VSI+2) == KEY_N && CHR(VSI+2) == KEY_G)) {
                
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            } else {
                VWSM = VSI;
                hBPC = _index - VWSM;
            }
        } else {
            VWSM = VSI;
            hBPC = _index - VWSM;
        }
    }
    //rule 3.2
    else if ((CHR(VSI) == KEY_I && (CHR(VSI) == KEY_A)) ||
             (CHR(VSI) == KEY_Y && (CHR(VSI) == KEY_A)) ||
             (CHR(VSI) == KEY_U && (CHR(VSI) == KEY_A)) ||
             (CHR(VSI) == KEY_U && (TypingWord[VSI+1] == (KEY_U | TONEW_MASK)))){
        
        VWSM = VSI;
        hBPC = _index - VWSM;
    }
    
    //rule 4
    if (vowelCount == 2) {
        if (((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_A)) ||
            ((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_U)) ||
            ((CHR(VSI) == KEY_I) && (CHR(VSI+1) == KEY_O))) {
            
            if (VSI == 0 || (CHR(VSI-1) != KEY_G)) { //dont have G
                VWSM = VSI;
                hBPC = _index - VWSM;
            } else {
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            }
        } else if ((CHR(VSI) == KEY_U) && (CHR(VSI+1) == KEY_A)) {
            if (VSI == 0 || (CHR(VSI-1) != KEY_Q)) { //dont have Q
                if (VEI + 1 >= _index || !canHasEndConsonant()) {
                    VWSM = VSI;
                    hBPC = _index - VWSM;
                }
            } else {
                VWSM = VSI + 1;
                hBPC = _index - VWSM;
            }
        } else if ((CHR(VSI) == KEY_O) && (CHR(VSI+1) == KEY_O)) { //thoong
            VWSM = VEI;
            hBPC = _index - VWSM;
        }
    }
}

void handleOldMark() {
    //default
    if (vowelCount == 0 && CHR(VEI) == KEY_I)
        VWSM = VEI;
    else
        VWSM = VSI;
    hBPC = (_index - VWSM);
    
    //rule 2
    if (vowelCount == 3 || (VEI + 1 < _index && IS_CONSONANT(CHR(VEI + 1)) && canHasEndConsonant())) {
        VWSM = VSI + 1;
        hBPC = _index - VWSM;
    }
    
    //rule 3
    for (ii = VSI; ii <= VEI; ii++) {
        if ((CHR(ii) == KEY_E && TypingWord[ii] & TONE_MASK) || (CHR(ii) == KEY_O && TypingWord[ii] & TONEW_MASK)) {
            VWSM = ii;
            hBPC = _index - VWSM;
            break;
        }
    }
    
    hNCC = hBPC;
}

void insertMark(const Uint32& markMask, const bool& canModifyFlag) {
    vowelCount = 0;
    
    if (canModifyFlag)
        hCode = vWillProcess;
    hBPC = hNCC = 0;
    
    findAndCalculateVowel();
    VWSM = 0;
    
    //detect mark position
    if (vowelCount == 1) {
        VWSM = VEI;
        hBPC = (_index - VEI);
    } else { //vowel = 2 or 3
        if (vUseModernOrthography == 0)
            handleOldMark();
        else
            handleModernMark();
        if (TypingWord[VEI] & TONE_MASK || TypingWord[VEI] & TONEW_MASK)
            vowelWillSetMark = VEI;
    }
    
    //send data
    kk = _index - 1 - VSI;
    //if duplicate same mark -> restore
    if (TypingWord[VWSM] & markMask) {
        
        TypingWord[VWSM] &= ~MARK_MASK;
        if (canModifyFlag)
            hCode = vRestore;
        for (ii = VSI; ii < _index; ii++) {
            TypingWord[ii] &= ~MARK_MASK;
            hData[kk--] = GET(TypingWord[ii]);
        }
        //_index = 0;
        tempDisableKey = true;
    } else {
        //remove other mark
        TypingWord[VWSM] &= ~MARK_MASK;
        
        //add mark
        TypingWord[VWSM] |= markMask;
        for (ii = VSI; ii < _index; ii++) {
            if (ii != VWSM) { //remove mark for other vowel
                TypingWord[ii] &= ~MARK_MASK;
            }
            hData[kk--] = GET(TypingWord[ii]);
        }
        
        hBPC = _index - VSI;
    }
    hNCC = hBPC;
}

void insertD(const Uint16& data, const bool& isCaps) {
    hCode = vWillProcess;
    hBPC = 0;
    for (ii = _index - 1; ii >= 0; ii--) {
        hBPC++;
        if (CHR(ii) == KEY_D) { //reverse unicode char
            if (TypingWord[ii] & TONE_MASK) {
                //restore and disable temporary
                hCode = vRestore;
                TypingWord[ii] &= ~TONE_MASK;
                hData[_index - 1 - ii] = TypingWord[ii];
                tempDisableKey = true;
                break;
            } else {
                TypingWord[ii] |= TONE_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
            }
            break;
        } else { //preresent old char
            hData[_index - 1 - ii] = GET(TypingWord[ii]);
        }
    }
    hNCC = hBPC;
}

void insertAOE(const Uint16& data, const bool& isCaps) {
    findAndCalculateVowel();
    
    //remove W tone
    for (ii = VSI; ii <= VEI; ii++) {
        TypingWord[ii] &= ~TONEW_MASK;
    }
    
    hCode = vWillProcess;
    hBPC = 0;
    
    for (ii = _index - 1; ii >= 0; ii--) {
        hBPC++;
        if (CHR(ii) == data) { //reverse unicode char
            if (TypingWord[ii] & TONE_MASK) {
                //restore and disable temporary
                hCode = vRestore;
                TypingWord[ii] &= ~TONE_MASK;
                hData[_index - 1 - ii] = TypingWord[ii];
                //_index = 0;
                if (data != KEY_O) //case thoòng
                    tempDisableKey = true;
                break;
            } else {
                TypingWord[ii] |= TONE_MASK;
                if (!IS_KEY_D(data))
                    TypingWord[ii] &= ~TONEW_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
                
            }
            break;
        } else { //preresent old char
            hData[_index - 1 - ii] = GET(TypingWord[ii]);
        }
    }
    hNCC = hBPC;
}

void insertW(const Uint16& data, const bool& isCaps) {
    isRestoredW = false;
    
    findAndCalculateVowel();
    
    //remove ^ tone
    for (ii = VSI; ii <= VEI; ii++) {
        TypingWord[ii] &= ~TONE_MASK;
    }
    
    if (vowelCount > 1) {
        hBPC = _index - VSI;
        hNCC = hBPC;
        
        if (((TypingWord[VSI] & TONEW_MASK) && (TypingWord[VSI+1] & TONEW_MASK)) ||
            ((TypingWord[VSI] & TONEW_MASK) && CHR(VSI+1) == KEY_I) ||
            ((TypingWord[VSI] & TONEW_MASK) && CHR(VSI+1) == KEY_A)){
            //restore and disable temporary
            hCode = vRestore;
            
            for (ii = VSI; ii < _index; ii++) {
                TypingWord[ii] &= ~TONEW_MASK;
                hData[_index - 1 - ii] = GET(TypingWord[ii]) & ~STANDALONE_MASK;
            }
            isRestoredW = true;
            tempDisableKey = true;
        } else {
            hCode = vWillProcess;
            
            if ((CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_O)) {
                if (VSI - 2 >= 0 && TypingWord[VSI - 2] == KEY_T && TypingWord[VSI - 1] == KEY_H) {
                    TypingWord[VSI+1] |= TONEW_MASK;
                    if (VSI + 2 < _index && CHR(VSI+2) == KEY_N) {
                        TypingWord[VSI] |= TONEW_MASK;
                    }
                } else if (VSI - 1 >= 0 && TypingWord[VSI - 1] == KEY_Q) {
                    TypingWord[VSI+1] |= TONEW_MASK;
                } else {
                    TypingWord[VSI] |= TONEW_MASK;
                    TypingWord[VSI+1] |= TONEW_MASK;
                }
            } else if ((CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_A) ||
                       (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_I) ||
                       (CHR(VSI) == KEY_U && CHR(VSI+1) == KEY_U) ||
                       (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_I)) {
                TypingWord[VSI] |= TONEW_MASK;
            } else if ((CHR(VSI) == KEY_I && CHR(VSI+1) == KEY_O) ||
                       (CHR(VSI) == KEY_O && CHR(VSI+1) == KEY_A)) {
                TypingWord[VSI+1] |= TONEW_MASK;
            } else {
                //don't do anything
                tempDisableKey = true;
                isChanged = false;
                hCode = vDoNothing;
            }
            
            for (ii = VSI; ii < _index; ii++) {
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
            }
        }
        
        return;
    }
    
    hCode = vWillProcess;
    hBPC = 0;
    
    for (ii = _index - 1; ii >= 0; ii--) {
        if (ii < VSI)
            break;
        hBPC++;
        switch (CHR(ii)) {
            case KEY_A:
            case KEY_U:
            case KEY_O:
                if (TypingWord[ii] & TONEW_MASK) {
                    //restore and disable temporary
                    if (TypingWord[ii] & STANDALONE_MASK) {
                        hCode = vWillProcess;
                        if (CHR(ii) == KEY_U){
                            TypingWord[ii] = KEY_W | ((TypingWord[ii] & CAPS_MASK) ? CAPS_MASK : 0);
                        } else if (CHR(ii) == KEY_O) {
                            hCode = vRestore;
                            TypingWord[ii] = KEY_O | ((TypingWord[ii] & CAPS_MASK) ? CAPS_MASK : 0);
                            isRestoredW = true;
                        }
                        hData[_index - 1 - ii] = TypingWord[ii];
                    } else {
                        hCode = vRestore;
                        TypingWord[ii] &= ~TONEW_MASK;
                        hData[_index - 1 - ii] = TypingWord[ii];
                        isRestoredW = true;
                        //_index++;
                    }
                    
                    tempDisableKey = true;
                } else {
                    TypingWord[ii] |= TONEW_MASK;
                    TypingWord[ii] &= ~TONE_MASK;
                    hData[_index - 1 - ii] = GET(TypingWord[ii]);
                }
                break;
                
            default:
                hData[_index - 1 - ii] = GET(TypingWord[ii]);
                break;
        }
    }
    hNCC = hBPC;
    
    if (isRestoredW) {
        //_index = 0;
    }
}

void reverseLastStandaloneChar(const Uint32& keyCode, const bool& isCaps) {
    hCode = vWillProcess;
    hBPC = 0;
    hNCC = 1;
    hExt = 4;
    TypingWord[_index - 1] = (keyCode | TONEW_MASK | STANDALONE_MASK | (isCaps ? CAPS_MASK : 0));
    hData[0] = GET(TypingWord[_index - 1]);
}

void checkForStandaloneChar(const Uint16& data, const bool& isCaps, const Uint32& keyWillReverse) {
    if (CHR(_index - 1) == keyWillReverse && TypingWord[_index - 1] & TONEW_MASK) {
        hCode = vWillProcess;
        hBPC = 1;
        hNCC = 1;
        TypingWord[_index - 1] = data | (isCaps ? CAPS_MASK : 0);
        hData[0] = GET(TypingWord[_index - 1]);
        return;
    }
    
    //check standalone w -> ư
    
    if (_index > 0 && CHR(_index-1) == KEY_U && keyWillReverse == KEY_O) {
        insertKey(keyWillReverse, isCaps);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    }
    
    if (_index == 0) { //zero char
        insertKey(data, isCaps, false);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    } else if (_index == 1) { //1 char
        for (i = 0; i < _standaloneWbad.size(); i++) {
            if (CHR(0) == _standaloneWbad[i]) {
                insertKey(data, isCaps);
                return;
            }
        }
        insertKey(data, isCaps, false);
        reverseLastStandaloneChar(keyWillReverse, isCaps);
        return;
    } else if (_index == 2) {
        for (i = 0; i < _doubleWAllowed.size(); i++) {
            if (CHR(0) == _doubleWAllowed[i][0] && CHR(1) == _doubleWAllowed[i][1]) {
                insertKey(data, isCaps, false);
                reverseLastStandaloneChar(keyWillReverse, isCaps);
                return;
            }
        }
        insertKey(data, isCaps);
        return;
    }
    
    insertKey(data, isCaps);
}


void handleMainKey(const Uint16& data, const bool& isCaps) {
    //if is Z key, remove mark
    if (IS_KEY_Z(data)) {
        removeMark();
        if (!isChanged) {
            insertKey(data, isCaps);
        }
        return;
    }
    
    if (data == KEY_LEFT_BRACKET) { //standalone key [
        checkForStandaloneChar(data, isCaps, KEY_O);
        return;
    }
    
    if (data == KEY_RIGHT_BRACKET) { //standalone key }
        checkForStandaloneChar(data, isCaps, KEY_U);
        return;
    }
    
    //if is D key
    if (IS_KEY_D(data)) {
        isCorect = false;
        isChanged = false;
        k = _index;
        for (i = 0; i < _consonantD.size(); i++) {
            if (_index < _consonantD[i].size())
                continue;
            isCorect = true;
            checkCorrectVowel(_consonantD, i, k, data);
            
            //allow d after consonant
            if (!isCorect && _index - 2 >= 0 && CHR(_index-1) == KEY_D && IS_CONSONANT(CHR(_index-2))) {
                isCorect = true;
            }
            if (isCorect) {
                isChanged = true;
                insertD(data, isCaps);
                break;
            }
        }
    
        if (!isChanged) {
            insertKey(data, isCaps);
        }
        return;
    }
    
    //if is mark key
    if (IS_MARK_KEY(data)) {
        for (auto& vowelEntry : _vowelForMark) {
            vector<vector<Uint16>>& charset = vowelEntry.second;
            isCorect = false;
            isChanged = false;
            k = _index;
            for (l = 0; l < charset.size(); l++) {
                if (_index < charset[l].size())
                    continue;
                isCorect = true;
                checkCorrectVowel(charset, l, k, data);

                if (isCorect) {
                    isChanged = true;
                    if (IS_KEY_S(data))
                        insertMark(MARK1_MASK);
                    else if (IS_KEY_F(data))
                        insertMark(MARK2_MASK);
                    else if (IS_KEY_R(data))
                        insertMark(MARK3_MASK);
                    else if (IS_KEY_X(data))
                        insertMark(MARK4_MASK);
                    else if (IS_KEY_J(data))
                        insertMark(MARK5_MASK);
                    break;
                }
            }

            if (isCorect) {
                break;
            }
        }

        if (!isChanged) {
            insertKey(data, isCaps);
        }

        return;
    }
    
    //check Vowel
    keyForAEO = data;
    vector<vector<Uint16>>& charset = _vowel[keyForAEO];
    isCorect = false;
    isChanged = false;
    k = _index;
    for (i = 0; i < charset.size(); i++) {
        if (_index < charset[i].size())
            continue;
        isCorect = true;
        checkCorrectVowel(charset, i, k, data);
        
        if (isCorect) {
            isChanged = true;
            if (IS_KEY_DOUBLE(data)) {
                insertAOE(keyForAEO, isCaps);
            } else if (IS_KEY_W(data)) {
                insertW(keyForAEO, isCaps);
            }
            break;
        }
    }
    
    if (!isChanged) {
        if (data == KEY_W) {
            checkForStandaloneChar(data, isCaps, KEY_U);
        } else {
            insertKey(data, isCaps);
        }
    }
}


bool checkRestoreIfWrongSpelling(const int& handleCode) {
    for (ii = 0; ii < _index; ii++) {
        if (!IS_CONSONANT(CHR(ii)) &&
            (TypingWord[ii] & MARK_MASK || TypingWord[ii] & TONE_MASK || TypingWord[ii] & TONEW_MASK)) {
            
            hCode = handleCode;
            hBPC = _index;
            hNCC = _stateIndex;
            for (i = 0; i < _stateIndex; i++) {
                TypingWord[i] = KeyStates[i];
                hData[_stateIndex - 1 - i] = TypingWord[i];
            }
            _index = _stateIndex;
            return true;
        }
    }
    return false;
}

void vSetCheckSpelling() {
    _useSpellCheckingBefore = vCheckSpelling;
}


/*==========================================================================================================*/
/* Auto switch language from typing behavior.
 * Everything here runs only at a word break (or on a doubled mark key), never per letter, and
 * uses fixed tables compiled into the binary: no allocation, no file or system calls.
 *
 * Words are compared as a Telex-normalized ASCII key: circumflex -> doubled vowel (aa ee oo),
 * breve/horn -> letter + w (aw ow uw), đ -> dd, tone letter (s f r x j) at the end.
 * That makes the check independent of the code table and of old/new tone placement.
 */
#define AS_MISSING (-1000)
#define AS_KEY_LEN 40
//Scores are 10*log10(occurrences per million). When the keys read as a word in both languages,
//leave the current language only if the word in the current language is rare (below its floor)
//and the other reading is at least AS_PREFER points (AS_PREFER/10 orders of magnitude) more common.
#ifndef AS_PREFER
#define AS_PREFER 10
#endif
#ifndef AS_VN_FLOOR
#define AS_VN_FLOOR 10      //Vietnamese words used at least ~10 per million are never switched away from
#endif
#ifndef AS_EN_FLOOR
#define AS_EN_FLOOR 0       //any English word used at least ~1 per million is never converted
#endif

int vAutoSwitchRequest = -1;
Uint32 vAutoSwitchUndoData[MAX_BUFF];
int vAutoSwitchUndoCount = 0;

static char _asLetter[256];
static bool _asLetterReady = false;
static bool _asWordStartOk = true;   //the current word began after a space, Enter, Tab or a fresh start (not inside foo.bar or my_var)

/* Look-back: when a word confidently switches the language, the 1-2 words typed just before it
 * (separated by single spaces) are fixed too if they were ambiguous, e.g. "thí make" -> "this make".
 * An earlier word follows the switch unless its current reading is AS_LOOKBACK_MARGIN points more common. */
#ifndef AS_LOOKBACK_WORDS
#define AS_LOOKBACK_WORDS 2
#endif
#ifndef AS_PLAIN_MARGIN
#define AS_PLAIN_MARGIN 15    //"thí makes": the earlier word must read English ~30x more often than Vietnamese (this vs thí)
#endif
#ifndef AS_LOOKBACK_MARGIN
#define AS_LOOKBACK_MARGIN 10
#endif
struct AsWord {
    Uint32 raw[MAX_BUFF];   //keys as typed
    int rawCount;
    Uint32 shown[MAX_BUFF]; //what is on screen (engine character data)
    int shownCount;
    int en, vn;             //scores of the raw keys as English and of the Vietnamese reading
    bool lookbackOk;        //could follow a switch to English
    bool same;              //looks the same in both modes (nothing to fix)
};
static AsWord _asPrev[AS_LOOKBACK_WORDS];
static int _asPrevCount = 0;

void vAutoSwitchForget() {
    _asPrevCount = 0;
    _asWordStartOk = true;   //a fresh context (language switched, app changed): the next word stands on its own
}

static void asInitLetters() {
    if (_asLetterReady) return;
    memset(_asLetter, 0, sizeof(_asLetter));
    const Uint16 keys[26] = {KEY_A, KEY_B, KEY_C, KEY_D, KEY_E, KEY_F, KEY_G, KEY_H, KEY_I, KEY_J, KEY_K, KEY_L, KEY_M,
                             KEY_N, KEY_O, KEY_P, KEY_Q, KEY_R, KEY_S, KEY_T, KEY_U, KEY_V, KEY_W, KEY_X, KEY_Y, KEY_Z};
    for (int n = 0; n < 26; n++) _asLetter[keys[n] & 0xFF] = (char)('a' + n);
    _asLetterReady = true;
}

static inline char asLetterOf(const Uint32& data) {
    Uint32 code = data & CHAR_MASK;
    return code < 256 ? _asLetter[code] : 0;
}

static int asLookup(const char* words, const unsigned int* offsets, const signed char* scores, const int& count, const char* word) {
    int lo = 0, hi = count - 1;
    while (lo <= hi) {
        int mid = (lo + hi) >> 1;
        int c = strcmp(words + offsets[mid], word);
        if (c == 0) return scores[mid];
        if (c < 0) lo = mid + 1; else hi = mid - 1;
    }
    return AS_MISSING;
}

static inline int asVietnameseScore(const char* key) {
    return asLookup(kAutoSwitchVnWords, kAutoSwitchVnOffsets, kAutoSwitchVnScores, kAutoSwitchVnCount, key);
}

static inline int asEnglishScore(const char* word) {
    return asLookup(kAutoSwitchEnWords, kAutoSwitchEnOffsets, kAutoSwitchEnScores, kAutoSwitchEnCount, word);
}

/** Normalized key of the word in TypingWord; transformed = it has a tone, ^, w-horn/breve or đ. */
static bool asWordKey(char* out, bool& transformed) {
    transformed = false;
    if (_index == 0 || _longWordHelper.size() > 0) return false;
    int n = 0;
    char tone = 0;
    for (int x = 0; x < _index; x++) {
        Uint32 t = TypingWord[x];
        char c = asLetterOf(t);
        if (c == 0 || n + 3 >= AS_KEY_LEN) return false;
        out[n++] = c;
        if ((t & TONE_MASK) && (c == 'a' || c == 'e' || c == 'o' || c == 'd')) {
            out[n++] = c;
            transformed = true;
        } else if ((t & TONEW_MASK) && (c == 'a' || c == 'o' || c == 'u')) {
            out[n++] = 'w';
            transformed = true;
        }
        switch (t & MARK_MASK) {
            case MARK1_MASK: tone = 's'; break;
            case MARK2_MASK: tone = 'f'; break;
            case MARK3_MASK: tone = 'r'; break;
            case MARK4_MASK: tone = 'x'; break;
            case MARK5_MASK: tone = 'j'; break;
        }
    }
    if (tone) {
        out[n++] = tone;
        transformed = true;
    }
    out[n] = 0;
    return true;
}

/** Lowercase letters of raw key codes; false if any key isn't a letter. */
static bool asRawWord(const Uint32* keys, const int& count, char* out) {
    if (count <= 0 || count >= AS_KEY_LEN) return false;
    for (int x = 0; x < count; x++) {
        out[x] = asLetterOf(keys[x]);
        if (out[x] == 0) return false;
    }
    out[count] = 0;
    return true;
}

static inline bool asEnabled() {
    return vAutoSwitchByTyping;
}

/** Vietnamese mode: a word was ended by a single space and stays Vietnamese. Keep it for look-back. */
static void asRememberWord() {
#ifdef AS_NO_LOOKBACK
    _asPrevCount = 0; return;
#endif
    if (!asEnabled()) return;
    asInitLetters();
    AsWord w;
    w.lookbackOk = false;
    w.same = false;
    w.rawCount = _stateIndex;
    w.shownCount = _index;
    if (_stateIndex <= 0 || _index <= 0 || _stateIndex >= MAX_BUFF || _longWordHelper.size() > 0) { _asPrevCount = 0; return; }
    for (int x = 0; x < _stateIndex; x++) w.raw[x] = KeyStates[x];
    for (int x = 0; x < _index; x++) w.shown[x] = GET(TypingWord[x]);
    char word[AS_KEY_LEN], raw[AS_KEY_LEN];
    bool transformed;
    w.en = w.vn = AS_MISSING;
    if (_asWordStartOk && _stateIndex >= _index && asWordKey(word, transformed) && asRawWord(KeyStates, _stateIndex, raw)) {
        w.en = asEnglishScore(raw);
        if (transformed) {        //ambiguous: a real word both ways, and English not much rarer
            w.vn = asVietnameseScore(word);
            w.lookbackOk = w.en != AS_MISSING && w.vn != AS_MISSING && w.en >= w.vn - AS_LOOKBACK_MARGIN;
        } else {                  //looks the same in both modes: look-back passes through English-only words ("makes")
            w.lookbackOk = w.en != AS_MISSING && asVietnameseScore(raw) == AS_MISSING;
            w.same = true;
        }
    }
    for (int x = AS_LOOKBACK_WORDS - 1; x > 0; x--) _asPrev[x] = _asPrev[x - 1];
    _asPrev[0] = w;
    if (_asPrevCount < AS_LOOKBACK_WORDS) _asPrevCount++;
}

/** Vietnamese mode, at a word break: are the raw keys an English word the user clearly meant? */
static Uint32 _asDoubleKeys[MAX_BUFF];   //the keys of the word a doubled tone key switched to English, both presses last
static int _asDoubleCount = 0;
static bool _asApostrophe = false;   //the word ends at an apostrophe: allow contraction stems

static bool asShouldRestoreToEnglish() {
    if (!asEnabled() || !_asWordStartOk) return false;
    asInitLetters();
    if (_stateIndex < 2 || _stateIndex < _index) return false;
    char word[AS_KEY_LEN], raw[AS_KEY_LEN];
    bool transformed;
    bool wordOk = asWordKey(word, transformed);
    //Telex dropped a key on the way ("seemed" -> "semed", "cheese" -> "chees"): with it back, an English word?
    if (_asDropPos >= 0 && _asDropPos <= _stateIndex && _stateIndex >= 3 && _stateIndex < MAX_BUFF - 1) {   //4+ keys: "aaa" stays Telex "aa"
        Uint32 full[MAX_BUFF];
        int n = 0;
        for (int x = 0; x <= _stateIndex; x++) {
            if (x == _asDropPos) full[n++] = _asDropKey;
            if (x < _stateIndex) full[n++] = KeyStates[x];
        }
            bool savedTemp = tempDisableKey;
        checkSpelling(true);
        bool invalid = tempDisableKey;   //the shown word is no syllable ("chée")
        tempDisableKey = savedTemp;
        if (asRawWord(full, n, raw) && asEnglishScore(raw) != AS_MISSING && (!wordOk || !transformed || invalid || asVietnameseScore(word) == AS_MISSING)) {
            memcpy(KeyStates, full, n * sizeof(Uint32));   //restore puts these keys back
            _stateIndex = n;
            _asDropPos = -1;
            return true;
        }
    }
    if (!wordOk) return false;
    if (!transformed) {
        //no marks left, but Telex ate a key on the way ("seemed" -> "semed", "cheese" -> "chees"): put back an English word
        if (asRawWord(KeyStates, _stateIndex, raw) && strcmp(raw, word) != 0 && asEnglishScore(raw) != AS_MISSING)
            return true;
#ifndef AS_PLAIN_AFTER_AMBIGUOUS
#define AS_PLAIN_AFTER_AMBIGUOUS 1
#endif
#if AS_PLAIN_AFTER_AMBIGUOUS
        //An English-only word that looks the same in both modes ("makes") right after an ambiguous word that
        //stayed Vietnamese ("thí" = this): together they are English. Switch now and fix the earlier word.
        if (_asPrevCount < 1 || !_asPrev[0].lookbackOk || _asPrev[0].same) return false;
        if (_asPrev[0].en < _asPrev[0].vn + AS_PLAIN_MARGIN) return false;   //the earlier word must lean English
        if (!asRawWord(KeyStates, _stateIndex, raw)) return false;
        return asEnglishScore(raw) != AS_MISSING && asVietnameseScore(raw) == AS_MISSING;
#else
        return false;
#endif
    }
    if (!asRawWord(KeyStates, _stateIndex, raw)) return false;
    int en = asEnglishScore(raw);
    int vn = asVietnameseScore(word);
    if (en == AS_MISSING && _asApostrophe) {             //a contraction stem: doesn't, isn't, wasn't -> is it "does" + n?
        size_t n = strlen(raw);
        if (n >= 3 && raw[n - 1] == 'n') { raw[n - 1] = 0; en = asEnglishScore(raw); raw[n - 1] = 'n'; }
    }
#ifndef AS_DOUBLE_KEEP
#define AS_DOUBLE_KEEP 1       //a doubled tone key that switches to English keeps both letters: e r r -> "err" (Tony 2026-10-28)
#endif
#ifndef AS_RESTORE_UNKNOWN
#define AS_RESTORE_UNKNOWN 3   //min letters for restoring a word that is neither Vietnamese nor in the English list
#endif
#if AS_RESTORE_UNKNOWN > 0
    //not a Vietnamese syllable and not a known English word either: a foreign word (TestFlight, analytics)
    if (en == AS_MISSING) {
        if (vn != AS_MISSING || _stateIndex < AS_RESTORE_UNKNOWN) return false;
#ifndef AS_UNKNOWN_ALLOW_MODIFIERS
        //Vietnamese-only modifiers (â ê ô ă ơ ư đ) mean the user was writing Vietnamese: a typo, not a foreign
        //word. Unless the keys have several vowel groups: no single syllable has that (analytics -> "ânlytics").
        int vowelGroups = 0;
        bool inVowel = false;
        for (int x = 0; x < _stateIndex; x++) {
            char c = asLetterOf(KeyStates[x]);
            bool v = c == 'a' || c == 'e' || c == 'i' || c == 'o' || c == 'u' || c == 'y';
            if (v && !inVowel) vowelGroups++;
            inVowel = v;
        }
        if (vowelGroups <= 1)
            for (int x = 0; x < _index; x++) if (TypingWord[x] & (TONE_MASK | TONEW_MASK)) return false;
#endif
        //rare but valid syllables (riệt, chịt) are not in the list: require the spelling rules to fail too
        bool savedTemp = tempDisableKey;
        checkSpelling(true);
        bool invalid = tempDisableKey;
        tempDisableKey = savedTemp;
        return invalid;
    }
#else
    if (en == AS_MISSING) return false;
#endif
    return vn == AS_MISSING || (vn < AS_VN_FLOOR && en - vn >= AS_PREFER);
}

/** Puts the raw keys back (like "restore if wrong spelling") and asks for English.
 *  Ambiguous words just before it (look-back) are put back to their keys too. */
static void asRestoreToEnglish(const int& handleCode) {
    //how many earlier words follow the switch: consecutive, ambiguous, and fitting in the output buffer
    int back = 0, newCount = _stateIndex, deleteCount = _index;
    while (back < _asPrevCount && _asPrev[back].lookbackOk &&
           newCount + _asPrev[back].rawCount + 1 < MAX_BUFF && deleteCount + _asPrev[back].shownCount + 1 < MAX_BUFF) {
        newCount += _asPrev[back].rawCount + 1;
        deleteCount += _asPrev[back].shownCount + 1;
        back++;
    }
    while (back > 0 && _asPrev[back - 1].same) {         //no need to retype unchanged words at the far end
        back--;
        newCount -= _asPrev[back].rawCount + 1;
        deleteCount -= _asPrev[back].shownCount + 1;
    }
    Uint32 out[MAX_BUFF];
    int n = 0;
    vAutoSwitchUndoCount = 0;
    for (int b = back - 1; b >= 0; b--) {
        for (int x = 0; x < _asPrev[b].rawCount; x++) out[n++] = _asPrev[b].raw[x];
        out[n++] = KEY_SPACE;
        for (int x = 0; x < _asPrev[b].shownCount; x++) vAutoSwitchUndoData[vAutoSwitchUndoCount++] = _asPrev[b].shown[x];
        vAutoSwitchUndoData[vAutoSwitchUndoCount++] = KEY_SPACE;
    }
    for (int x = 0; x < _index && vAutoSwitchUndoCount < MAX_BUFF; x++) {
        vAutoSwitchUndoData[vAutoSwitchUndoCount++] = GET(TypingWord[x]);
    }
    for (i = 0; i < _stateIndex; i++) {
        TypingWord[i] = KeyStates[i];
        out[n++] = KeyStates[i];
    }
    hCode = handleCode;
    hBPC = deleteCount;
    hNCC = n;
    for (int x = 0; x < n; x++) hData[n - 1 - x] = out[x];
    _index = _stateIndex;
    _asPrevCount = 0;
    vAutoSwitchRequest = 0;
}

/** Break keys that end a word for auto switch (not arrows, tab, esc, mouse or shortcuts). */
static bool asIsSwitchBreak(const vKeyEvent& event, const Uint16& data, const Uint8& capsStatus, const bool& otherControlKey) {
    if (event != vKeyEvent::Keyboard || otherControlKey) return false;
    return data == KEY_COMMA || data == KEY_DOT || data == KEY_SEMICOLON || data == KEY_ENTER || data == KEY_RETURN ||
           data == KEY_QUOTE ||                                 //closing quote, or an apostrophe: doesn't, we're
           (data == KEY_SLASH && capsStatus == 1) || (data == KEY_1 && capsStatus == 1) || (data == KEY_0 && capsStatus == 1);
}

/** Everything the engine keeps between keys, so a word can be replayed on a scratch session. */
struct AsEngineState {
    Uint32 word[MAX_BUFF], states[MAX_BUFF];
    Byte index, stateIndex;
    bool tempDisable, useSpellingBefore, wordStartOk;
    int dropPos; Uint32 dropKey;
    int spaceCount, checkSpelling, language;
    vector<Uint32> longWord, special, statesData;
    list<vector<Uint32>> typing;
    vKeyHookState hook;
};

static void asSaveState(AsEngineState& st) {
    memcpy(st.word, TypingWord, sizeof(TypingWord));
    memcpy(st.states, KeyStates, sizeof(KeyStates));
    st.index = _index; st.stateIndex = _stateIndex;
    st.tempDisable = tempDisableKey; st.useSpellingBefore = _useSpellCheckingBefore;
    st.wordStartOk = _asWordStartOk;
    st.dropPos = _asDropPos; st.dropKey = _asDropKey;
    st.spaceCount = _spaceCount; st.checkSpelling = vCheckSpelling;
    st.language = vLanguage;
    st.longWord.swap(_longWordHelper);
    st.special.swap(_specialChar);
    st.statesData.swap(_typingStatesData);
    st.typing.swap(_typingStates);
    st.hook = std::move(HookState);
}

static void asRestoreState(AsEngineState& st) {
    memcpy(TypingWord, st.word, sizeof(TypingWord));
    memcpy(KeyStates, st.states, sizeof(KeyStates));
    _index = st.index; _stateIndex = st.stateIndex;
    tempDisableKey = st.tempDisable; _useSpellCheckingBefore = st.useSpellingBefore;
    _asWordStartOk = st.wordStartOk;
    _asDropPos = st.dropPos; _asDropKey = st.dropKey;
    _spaceCount = st.spaceCount; vCheckSpelling = st.checkSpelling;
    vLanguage = st.language;
    _longWordHelper.swap(st.longWord);
    _specialChar.swap(st.special);
    _typingStatesData.swap(st.statesData);
    _typingStates.swap(st.typing);
    HookState = std::move(st.hook);
}

#ifdef AS_TESTING
//test harness only: snapshot the whole engine so a word can be tried and taken back
void* vTestSaveState() { AsEngineState* st = new AsEngineState(); asSaveState(*st); return st; }
void vTestRestoreState(void* p) { AsEngineState* st = (AsEngineState*)p; asRestoreState(*st); delete st; }
void vTestFreeState(void* p) { delete (AsEngineState*)p; }
#endif

/** Replays raw keys through the Telex engine on a scratch session. Returns the Vietnamese score of
 *  the result (AS_MISSING if it isn't a real syllable or nothing changed) and the result characters. */
static int asReplay(const Uint32* keys, const int& count, Uint32* result, int& resultCount, bool* changed = NULL) {
    resultCount = 0;
    AsEngineState saved;
    asSaveState(saved);
    _spaceCount = 0;
    startNewSession();
    for (int x = 0; x < count; x++) {
        vKeyHandleEvent(vKeyEvent::Keyboard, vKeyEventState::KeyDown, (Uint16)(keys[x] & CHAR_MASK), (keys[x] & CAPS_MASK) ? 1 : 0, false);
    }
    int vn = AS_MISSING;
    char word[AS_KEY_LEN];
    bool transformed;
    bool keyOk = asWordKey(word, transformed);
    if (changed) *changed = keyOk ? transformed : true;
    if (keyOk && transformed) {
        vn = asVietnameseScore(word);
        if (vn != AS_MISSING) {
            for (int x = 0; x < _index; x++) result[resultCount++] = GET(TypingWord[x]);
        }
    }
    asRestoreState(saved);
    return vn;
}

static bool asFewCapitals(const Uint32* keys, const int& count) {
    int capitals = 0;
    for (int x = 0; x < count; x++) if (keys[x] & CAPS_MASK) capitals++;
    return capitals < 2;   //USA, EST, IRS, camelCase: acronyms and identifiers stay as typed
}

bool vAutoSwitchCheckEnglishWord(const Uint32* keys, const int& count,
                                 const Uint32* const* previous, const int* previousCounts, const int& previousN) {
    if (!asEnabled() || count < 2 || count >= MAX_BUFF - 1) return false;
    asInitLetters();
    char raw[AS_KEY_LEN];
    if (!asRawWord(keys, count, raw) || !asFewCapitals(keys, count)) return false;
    int en = asEnglishScore(raw);

    Uint32 result[MAX_BUFF];
    int resultCount;
    int vn = asReplay(keys, count, result, resultCount);
    if (vn == AS_MISSING || !(en == AS_MISSING || (en < AS_EN_FLOOR && vn - en >= AS_PREFER))) return false;

    //look-back: ambiguous words just before it (kept English because they are English words too)
    Uint32 out[MAX_BUFF];
    int n = 0, deleteCount = count, back = 0;
    Uint32 earlier[AS_LOOKBACK_WORDS][MAX_BUFF];
    int earlierCount[AS_LOOKBACK_WORDS];
    bool earlierSame[AS_LOOKBACK_WORDS];
    for (; back < previousN && back < AS_LOOKBACK_WORDS; back++) {
        const Uint32* pk = previous[back];
        int pc = previousCounts[back];
        char praw[AS_KEY_LEN];
        if (pc < 2 || !asRawWord(pk, pc, praw) || !asFewCapitals(pk, pc)) break;
        int pen = asEnglishScore(praw);
        bool changed;
        int pvn = asReplay(pk, pc, earlier[back], earlierCount[back], &changed);
        earlierSame[back] = !changed;
        if (!changed) {           //looks the same in both modes: pass through Vietnamese-only words ("cho")
            if (pen != AS_MISSING || asVietnameseScore(praw) == AS_MISSING) break;
            earlierCount[back] = pc;
            for (int x = 0; x < pc; x++) earlier[back][x] = pk[x];
        } else if (pen == AS_MISSING || pvn == AS_MISSING || pvn < pen - AS_LOOKBACK_MARGIN) {
            break;                //only ambiguous words that were kept English follow the switch
        }
        if (resultCount + n + earlierCount[back] + 1 >= MAX_BUFF || deleteCount + pc + 1 >= MAX_BUFF) break;
        n += earlierCount[back] + 1;
        deleteCount += pc + 1;
    }
    while (back > 0 && earlierSame[back - 1]) {          //no need to retype unchanged words at the far end
        back--;
        deleteCount -= previousCounts[back] + 1;
    }
    n = 0;
    vAutoSwitchUndoCount = 0;
    for (int b = back - 1; b >= 0; b--) {
        for (int x = 0; x < earlierCount[b]; x++) out[n++] = earlier[b][x];
        out[n++] = KEY_SPACE;
        for (int x = 0; x < previousCounts[b]; x++) vAutoSwitchUndoData[vAutoSwitchUndoCount++] = previous[b][x];
        vAutoSwitchUndoData[vAutoSwitchUndoCount++] = KEY_SPACE;
    }
    for (int x = 0; x < resultCount; x++) out[n++] = result[x];
    for (int x = 0; x < count; x++) vAutoSwitchUndoData[vAutoSwitchUndoCount++] = keys[x];

    hCode = vRestore;          //platform sends the new text, then the break key itself
    hBPC = (Byte)deleteCount;
    hNCC = (Byte)n;
    hExt = 3;
    for (int x = 0; x < n; x++) hData[n - 1 - x] = out[x];
    return true;
}

bool vAutoSwitchCheckEnglishWord(const Uint32* keys, const int& count) {
    return vAutoSwitchCheckEnglishWord(keys, count, NULL, NULL, 0);
}
/*==========================================================================================================*/


void vKeyHandleEvent(const vKeyEvent& event,
                     const vKeyEventState& state,
                     const Uint16& data,
                     const Uint8& capsStatus,
                     const bool& otherControlKey) {
    _isCaps = (capsStatus == 1 || //shift
               capsStatus == 2); //caps lock
    if ((IS_NUMBER_KEY(data) && capsStatus == 1)
        || otherControlKey || isWordBreak(event, state, data) || (_index == 0 && IS_NUMBER_KEY(data))) {
        hCode = vDoNothing;
        hBPC = 0;
        hNCC = 0;
        hExt = 1; //word break
        
        _asApostrophe = data == KEY_QUOTE && capsStatus != 1;
        bool asSwitch = asIsSwitchBreak(event, data, capsStatus, otherControlKey) && asShouldRestoreToEnglish();
        _asApostrophe = false;
        if (asSwitch) {
            asRestoreToEnglish(vRestoreAndStartNewSession); //auto switch: an English word typed in Vietnamese mode
        } else if (vRestoreIfWrongSpelling && isWordBreak(event, state, data)) { //restore key if wrong spelling with break-key
            if (!tempDisableKey && vCheckSpelling) {
                checkSpelling(true); //force check spelling
            }
            if (tempDisableKey && !checkRestoreIfWrongSpelling(vRestoreAndStartNewSession)) {
                hCode = vDoNothing;
            }
        }
        
        _isCharKeyCode = state == KeyDown && std::find(_charKeyCode.begin(), _charKeyCode.end(), data) != _charKeyCode.end();
        if (!_isCharKeyCode) { //clear all line cache
            _specialChar.clear();
            _typingStates.clear();
        } else { //check and save current word
            if (_spaceCount > 0) {
                saveWord(KEY_SPACE, _spaceCount);
                _spaceCount = 0;
            } else {
                saveWord();
            }
            _specialChar.push_back(data | (_isCaps ? CAPS_MASK : 0));
            hExt = 3;//normal word
        }
        
        if (hCode == vDoNothing) {
            startNewSession();
            vCheckSpelling = _useSpellCheckingBefore;
        }
        _asPrevCount = 0;
        //the next word is a whole word only after whitespace, a click or a shortcut, not after . _ - / etc.
        _asWordStartOk = event == vKeyEvent::Mouse || otherControlKey || data == KEY_ENTER || data == KEY_RETURN || data == KEY_TAB;
    } else if (data == KEY_SPACE) {
        if (!tempDisableKey && vCheckSpelling) {
            checkSpelling(true); //force check spelling
        }
        if (asShouldRestoreToEnglish()) { //auto switch: an English word typed in Vietnamese mode
            asRestoreToEnglish(vRestore);
            _spaceCount++;
        } else if (vRestoreIfWrongSpelling && tempDisableKey) { //restore key if wrong spelling
            if (!checkRestoreIfWrongSpelling(vRestore)) {
                hCode = vDoNothing;
            }
            _spaceCount++;
        } else { //do nothing with SPACE KEY
            hCode = vDoNothing;
            _spaceCount++;
        }
        //look-back memory: only words separated by a single space count
        if (hCode == vDoNothing && _spaceCount == 1) asRememberWord(); else if (_spaceCount > 1) _asPrevCount = 0;
        //save word
        if (_spaceCount == 1) {
            if (_specialChar.size() > 0) {
                saveSpecialChar();
            } else {
                saveWord();
            }
        }
        vCheckSpelling = _useSpellCheckingBefore;
        _asWordStartOk = true;
    } else if (data == KEY_DELETE) {
        _asPrevCount = 0;
        hCode = vDoNothing;
        hExt = 2; //delete
        if (_specialChar.size() > 0) {
            _specialChar.pop_back();
            if (_specialChar.size() == 0) {
                restoreLastTypingState();
            }
        } else if (_spaceCount > 0) { //previous char is space
            _spaceCount--;
            if (_spaceCount == 0) { //restore word
                restoreLastTypingState();
            }
        } else {
            if (_stateIndex > 0) {
                _stateIndex--;
                if (_stateIndex < _asDropPos) _asDropPos = -1;
            }
            if (_index > 0){
                _index--;
                if (_longWordHelper.size() > 0) {
                    //right shift
                    for (i = MAX_BUFF - 1; i > 0; i--) {
                        TypingWord[i] = TypingWord[i-1];
                    }
                    TypingWord[0] = _longWordHelper.back();
                    _longWordHelper.pop_back();
                    _index++;
                }
                if (vCheckSpelling)
                    checkSpelling();
            }
            hBPC = 0;
            hNCC = 0;
            hExt = 2; //delete key
            if (_index == 0) {
                startNewSession();
                _specialChar.clear();
                restoreLastTypingState();
            } else { //August 23rd continue check grammar
                checkGrammar(1);
            }
        }
    } else { //START AND CHECK KEY
        if (_spaceCount > 0) {
            hBPC = 0;
            hNCC = 0;
            hExt = 0;
            startNewSession();
            //continute save space
            saveWord(KEY_SPACE, _spaceCount);
            _spaceCount = 0;
        } else if (_specialChar.size() > 0) {
            saveSpecialChar();
        }

        insertState(data, _isCaps); //save state
        
        if (!IS_SPECIALKEY(data) || tempDisableKey) { //do nothing
            hCode = vDoNothing;
            hBPC = 0;
            hNCC = 0;
            hExt = 3; //normal key
            insertKey(data, _isCaps);
        } else { //check and update key
            //restore state
            hCode = vDoNothing;
            hExt = 3; //normal key
            handleMainKey(data, _isCaps);
            //auto switch: the same tone key pressed twice undoes the tone, a strong sign of English
            if (hCode == vRestore && asEnabled() && IS_MARK_KEY(data)) {
                vAutoSwitchRequest = 0;
                //switching to English: put the whole word back to the keys typed, not just the undone tone
                //("tomorr", not "tômrr"). The key itself is added after these by the caller (vRestore).
                //Both presses stay ("err", not Telex's "er"): the first is in the keys, the caller adds the second.
                bool rawRestored = false;
                if (_stateIndex >= 1 && _stateIndex <= MAX_BUFF && _index <= MAX_BUFF) {
                    hBPC = _index;
                    hNCC = _stateIndex - 1;
                    for (int x = 0; x < hNCC; x++) hData[hNCC - 1 - x] = KeyStates[x];
                    rawRestored = true;
                    //remember the word for the end-of-word fix ("mixx" -> "mix")
                    _asDoubleCount = _stateIndex;
                    memcpy(_asDoubleKeys, KeyStates, _stateIndex * sizeof(Uint32));
                }
#if AS_DOUBLE_KEEP
                //keep the first press of the key too ("err", not Telex's "er")
                if (!rawRestored && hNCC < MAX_BUFF - 1) {
                    for (int x = hNCC; x > 0; x--) hData[x] = hData[x - 1];
                    hData[0] = data | (_isCaps ? CAPS_MASK : 0);
                    hNCC++;
                }
#endif
            }
        }

        if (!IS_KEY_D(data)) {
            if (hCode == vDoNothing) {
                checkGrammar(-1);
            } else {
                checkGrammar(0);
            }
        }
        
        if (hCode == vRestore) {
            insertKey(data, _isCaps);
            if (_stateIndex > 0 && vAutoSwitchRequest != 0) { _asDropPos = _stateIndex - 1; _asDropKey = KeyStates[_stateIndex - 1]; }
            _stateIndex--;
        }
        
        //case [ ]
        if (IS_BRACKET_KEY(data) && IS_BRACKET_KEY((Uint16)hData[0])) {
            if (_index - (hCode == vWillProcess ? hBPC : 0) > 0) {
                _index--;
                saveWord();
            }
            _index = 0;
            tempDisableKey = false;
            _stateIndex = 0;
            hExt = 3;
            _specialChar.push_back(data | (_isCaps ? CAPS_MASK : 0));
        }
    }
    
    //Debug
    //cout<<"index "<<(int)_index<< ", stateIndex "<<(int)_stateIndex<<", word "<<_typingStates.size()<<", long word "<<_longWordHelper.size()<< endl;
    //cout<<"backspace "<<(int)hBPC<<endl;
    //cout<<"new char "<<(int)hNCC<<endl<<endl;
}

bool vAutoSwitchFixDoubledKey(const Uint32* keys, const int& count) {
    int n = _asDoubleCount;
    _asDoubleCount = 0;
    if (!asEnabled() || n < 2 || count < 0 || n + count >= AS_KEY_LEN || n + count >= MAX_BUFF) return false;
    asInitLetters();
    Uint32 full[MAX_BUFF];
    memcpy(full, _asDoubleKeys, n * sizeof(Uint32));
    for (int x = 0; x < count; x++) full[n + x] = keys[x];
    int total = n + count;
    char raw[AS_KEY_LEN], fewer[AS_KEY_LEN];
    if (!asRawWord(full, total, raw)) return false;
    if (asEnglishScore(raw) != AS_MISSING) return false;            //both presses make a word: err, boss, tomorrow
    Uint32 fixed[MAX_BUFF];
    int m = 0;
    for (int x = 0; x < total; x++) if (x != n - 1) fixed[m++] = full[x];   //drop the second press
    if (m < 2 || !asRawWord(fixed, m, fewer) || asEnglishScore(fewer) == AS_MISSING) return false;
    vAutoSwitchUndoCount = 0;   //Backspace right after puts "mixx" back
    for (int x = 0; x < total; x++) vAutoSwitchUndoData[vAutoSwitchUndoCount++] = full[x];
    hCode = vRestore;          //platform sends the new text, then the break key itself
    hBPC = (Byte)total;
    hNCC = (Byte)m;
    hExt = 3;
    for (int x = 0; x < m; x++) hData[m - 1 - x] = fixed[x];
    return true;
}
