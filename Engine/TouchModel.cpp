//
//  TouchModel.cpp
//  Vikey
//

#include "TouchModel.h"
#include "Engine.h"
#include <cmath>
#include <cstring>

float TouchModel::sigma = 0.35f;
float TouchModel::weight = 0.8f;
float TouchModel::sureZone = 0.6f;
float TouchModel::modeShare = 0.8f;

/** P(next letter | prefix), mixing both languages by mode; smoothed so no letter is impossible. */
static void prior(const char* prefix, int vietnamese, double p[26]) {
    double vn[27], en[27];
    vAutoSwitchNextKeyMass(1, prefix, vn);
    vAutoSwitchNextKeyMass(0, prefix, en);
    double tv = 0, te = 0;
    for (int i = 0; i < 26; i++) { tv += vn[i]; te += en[i]; }
    double wv = vietnamese ? TouchModel::modeShare : 1 - TouchModel::modeShare, we = 1 - wv;
    if (tv <= 0) { wv = 0; we = 1; }
    if (te <= 0) { we = 0; wv = tv > 0 ? 1 : 0; }
    double total = 0;
    for (int i = 0; i < 26; i++) {
        double v = (tv > 0 ? vn[i] / tv : 0) * wv + (te > 0 ? en[i] / te : 0) * we;
        p[i] = v * 0.97 + 0.03 / 26;                       // smoothing: typos and unknown words stay possible
        total += p[i];
    }
    for (int i = 0; i < 26; i++) p[i] /= total;
}

char TouchModel::pick(float x, float y, const char* prefix, int vietnamese, const TMKey* keys, int n) {
    int nearest = -1; float bestD = 1e30f;
    for (int i = 0; i < n; i++) {
        const TMKey& k = keys[i];
        float cx = k.x + k.w / 2, cy = k.y + k.h / 2;
        float dx = (x - cx) / k.w, dy = (y - cy) / k.h;
        if (fabsf(dx) * 2 <= sureZone && fabsf(dy) * 2 <= sureZone) return k.letter;   // clearly this key
        float d = dx * dx + dy * dy;
        if (d < bestD) { bestD = d; nearest = i; }
    }
    if (nearest < 0) return 0;
    if (weight <= 0) return keys[nearest].letter;
    double p[26];
    prior(prefix, vietnamese, p);
    double best = -1e300; char letter = keys[nearest].letter;
    for (int i = 0; i < n; i++) {
        const TMKey& k = keys[i];
        float cx = k.x + k.w / 2, cy = k.y + k.h / 2;
        float dx = (x - cx) / (k.w * sigma), dy = (y - cy) / (k.h * sigma);
        double spatial = -0.5 * (dx * dx + dy * dy);          // log of a 2D Gaussian
        if (spatial < -8) continue;                            // far keys never win
        int li = k.letter - 'a';
        if (li < 0 || li >= 26) continue;
        double score = spatial + weight * log(p[li]);
        if (score > best) { best = score; letter = k.letter; }
    }
    return letter;
}
