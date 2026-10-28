//
//  TouchModel.h
//  Vikey
//
//  Fat-finger model for touch keyboards: which key did a touch mean? Combines where the finger
//  landed (2D Gaussian around each key's center) with how likely each key is next given the letters
//  of the word so far (vAutoSwitchNextKeyMass), mixed by the current language mode. A touch well
//  inside a key always types that key; the model only decides touches near key borders.
//

#ifndef VikeyTouchModel_h
#define VikeyTouchModel_h

struct TMKey {
    char letter;          // 'a'..'z'
    float x, y, w, h;     // frame, any unit (points)
};

class TouchModel {
public:
    /** The letter for a touch at (x, y). prefix: letters typed so far in this word (lowercase).
     *  vietnamese: current mode. keys: the letter keys of the layout. */
    static char pick(float x, float y, const char* prefix, int vietnamese, const TMKey* keys, int n);
    // tuning (see Tools/autoswitch/touch: chosen by simulation)
    static float sigma;        // finger spread, in key widths
    static float weight;       // how much the prior counts (0 = nearest key only)
    static float sureZone;     // inside this fraction of a key, the key wins outright
    static float modeShare;    // share of the current mode's language in the prior (the rest: the other language)
};

#endif
