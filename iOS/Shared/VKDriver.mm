#import "VKDriver.h"
#include "Driver.h"
#include "TouchModel.h"
#include <vector>

// Engine settings (the macOS app defines these in VikeyCore.mm)
int vLanguage = 1, vSwitchKeyStatus = 0, vCheckSpelling = 1, vUseModernOrthography = 1, vRestoreIfWrongSpelling = 1,
    vFixRecommendBrowser = 1, vUseSmartSwitchKey = 0, vOtherLanguage = 0, vAutoSwitchByTyping = 1;

@implementation VKEditResult
@end

static bool KeyFor(unichar c, Uint16 &key, bool &shift) {
    static const Uint16 letters[26] = {KEY_A,KEY_B,KEY_C,KEY_D,KEY_E,KEY_F,KEY_G,KEY_H,KEY_I,KEY_J,KEY_K,KEY_L,KEY_M,KEY_N,
                                       KEY_O,KEY_P,KEY_Q,KEY_R,KEY_S,KEY_T,KEY_U,KEY_V,KEY_W,KEY_X,KEY_Y,KEY_Z};
    static const Uint16 digits[10] = {KEY_0,KEY_1,KEY_2,KEY_3,KEY_4,KEY_5,KEY_6,KEY_7,KEY_8,KEY_9};
    shift = false;
    if (c >= 'a' && c <= 'z') { key = letters[c - 'a']; return true; }
    if (c >= 'A' && c <= 'Z') { key = letters[c - 'A']; shift = true; return true; }
    if (c >= '0' && c <= '9') { key = digits[c - '0']; return true; }
    switch (c) {
        case ' ': key = KEY_SPACE; return true;
        case '\n': key = KEY_RETURN; return true;
        case ',': key = KEY_COMMA; return true;
        case '.': key = KEY_DOT; return true;
        case ';': key = KEY_SEMICOLON; return true;
        case ':': key = KEY_SEMICOLON; shift = true; return true;
        case '?': key = KEY_SLASH; shift = true; return true;
        case '/': key = KEY_SLASH; return true;
        case '!': key = KEY_1; shift = true; return true;
        case '\'': key = KEY_QUOTE; return true;
        case '"': key = KEY_QUOTE; shift = true; return true;
        case '(': key = KEY_9; shift = true; return true;
        case ')': key = KEY_0; shift = true; return true;
        case '-': key = KEY_MINUS; return true;
    }
    return false;
}

@implementation VKDriver {
    VikeyDriver *_d;
}

- (instancetype)init {
    if ((self = [super init])) { _d = new VikeyDriver(); _d->pauseAfterManual = 5; }
    return self;
}
- (void)dealloc { delete _d; }

- (NSInteger)language { return vLanguage; }
- (void)setLanguage:(NSInteger)language { _d->setLanguage((int)language); }
- (BOOL)autoSwitch { return _d->autoSwitch; }
- (void)setAutoSwitch:(BOOL)on { _d->autoSwitch = on; vAutoSwitchByTyping = on; }
- (double)pauseAfterManual { return _d->pauseAfterManual; }
- (void)setPauseAfterManual:(double)s { _d->pauseAfterManual = s; }
- (BOOL)spelling { return vCheckSpelling; }
- (void)setSpelling:(BOOL)on { vCheckSpelling = on; vSetCheckSpelling(); }
- (BOOL)restoreIfInvalid { return vRestoreIfWrongSpelling; }
- (void)setRestoreIfInvalid:(BOOL)on { vRestoreIfWrongSpelling = on; }
- (BOOL)modernOrthography { return vUseModernOrthography; }
- (void)setModernOrthography:(BOOL)on { vUseModernOrthography = on; }


- (VKEditResult *)convert:(const ::VKEdit &)e {
    VKEditResult *r = [VKEditResult new];
    r.deleteCount = e.deleteCount;
    r.text = [NSString stringWithCharacters:(const unichar *)e.text.data() length:e.text.size()];
    r.languageChanged = e.languageChanged;
    return r;
}

- (VKEditResult *)typeCharacter:(NSString *)character now:(double)now {
    Uint16 key; bool shift;
    if (character.length != 1 || !KeyFor([character characterAtIndex:0], key, shift)) {
        // not a key the engine knows (emoji, other symbols): a word break that passes through
        _d->resetContext();
        VKEditResult *r = [VKEditResult new]; r.text = character; return r;
    }
    return [self convert:_d->press(key, shift, now)];
}

- (VKEditResult *)backspaceAt:(double)now { return [self convert:_d->press(KEY_DELETE, false, now)]; }
- (void)manualSwitchAt:(double)now { _d->manualSwitch(now); }
- (void)resetContext { _d->resetContext(); }
@end

char VKPickLetter(float x, float y, const char *prefix, int vietnamese, const VKKeyRect *keys, int n) {
    std::vector<TMKey> k((size_t)n);
    for (int i = 0; i < n; i++) k[i] = {keys[i].letter, keys[i].x, keys[i].y, keys[i].w, keys[i].h};
    return TouchModel::pick(x, y, prefix, vietnamese, k.data(), n);
}
