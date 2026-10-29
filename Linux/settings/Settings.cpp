// vikey-settings: the Vikey window on Linux (GTK4 + libadwaita), 1:1 with the Mac app's MainView:
// header (icon, Vikey, hotkey hint, Tiếng Việt / English), grouped rows with switches and (?) tips.
// Also the typing-log window (--log) and About (--about). Settings live in ~/.config/vikey/settings.json;
// the IBus engine watches that file.
#include <adwaita.h>
#include <string>
#include <vector>
#include <map>
#include <fstream>
#include <cstring>
#include "../ibus/Prefs.h"
#ifndef VIKEY_VERSION
#define VIKEY_VERSION "0.0.0"
#endif
using namespace vikey;

// ---- hotkey bits (same layout as the Mac/Windows apps) -----------------------------------------------
static int currentHotkey() { int hk = prefs::getInt("SwitchKeyStatus", 0); return hk ? hk : 0x7A000206; }
static std::string keyName(int key) {
    static const struct { int k; const char* n; } N[] = {{0,"A"},{11,"B"},{8,"C"},{2,"D"},{14,"E"},{3,"F"},{5,"G"},{4,"H"},{34,"I"},{38,"J"},{40,"K"},{37,"L"},{46,"M"},{45,"N"},{31,"O"},{35,"P"},{12,"Q"},{15,"R"},{1,"S"},{17,"T"},{32,"U"},{9,"V"},{13,"W"},{7,"X"},{16,"Y"},{6,"Z"},
        {18,"1"},{19,"2"},{20,"3"},{21,"4"},{23,"5"},{22,"6"},{26,"7"},{28,"8"},{25,"9"},{29,"0"},{49,"Space"},{36,"Enter"},{48,"Tab"},{50,"`"},{27,"-"},{24,"="},{33,"["},{30,"]"},{42,"\\"},{41,";"},{39,"'"},{43,","},{47,"."},{44,"/"}};
    for (auto& e : N) if (e.k == key) return e.n; return "?";
}
static std::string hotkeyDisplay(int hk) {
    std::string s; if (hk & 0x100) s += "Ctrl+"; if (hk & 0x200) s += "Alt+"; if (hk & 0x800) s += "Shift+"; if (hk & 0x400) s += "Super+";
    int k = hk & 0xFF; if (k != 0xFE) s += keyName(k); else if (!s.empty()) s.pop_back();
    return s.empty() ? "—" : s;
}
static int engineKeyOfKeyval(guint kv) {
    if (kv >= GDK_KEY_a && kv <= GDK_KEY_z) kv -= 32;
    static const int L[] = {0,11,8,2,14,3,5,4,34,38,40,37,46,45,31,35,12,15,1,17,32,9,13,7,16,6};
    if (kv >= GDK_KEY_A && kv <= GDK_KEY_Z) return L[kv - GDK_KEY_A];
    static const struct { guint kv; int k; } M[] = {{GDK_KEY_1,18},{GDK_KEY_2,19},{GDK_KEY_3,20},{GDK_KEY_4,21},{GDK_KEY_5,23},{GDK_KEY_6,22},{GDK_KEY_7,26},{GDK_KEY_8,28},{GDK_KEY_9,25},{GDK_KEY_0,29},{GDK_KEY_space,49},{GDK_KEY_Return,36},{GDK_KEY_Tab,48},{GDK_KEY_grave,50},{GDK_KEY_minus,27},{GDK_KEY_equal,24},{GDK_KEY_bracketleft,33},{GDK_KEY_bracketright,30},{GDK_KEY_backslash,42},{GDK_KEY_semicolon,41},{GDK_KEY_apostrophe,39},{GDK_KEY_comma,43},{GDK_KEY_period,47},{GDK_KEY_slash,44}};
    for (auto& m : M) if (m.kv == kv) return m.k; return -1;
}

// ---- widgets ----------------------------------------------------------------------------------------------
static GtkWidget* _hint; static GtkWidget* _seg[2]; static GtkWidget* _hotkeyBtn; static bool _recording = false; static unsigned _recMods = 0;
static std::map<std::string, GtkWidget*> _sw;
static void setHint() { gtk_label_set_text(GTK_LABEL(_hint), ("Bấm " + hotkeyDisplay(currentHotkey()) + " để chuyển").c_str()); gtk_button_set_label(GTK_BUTTON(_hotkeyBtn), _recording ? "Bấm phím tắt…" : hotkeyDisplay(currentHotkey()).c_str()); }
static void refreshEnabled() {
    gtk_widget_set_sensitive(_sw["PauseAutoAfterManual"], gtk_switch_get_active(GTK_SWITCH(_sw["AutoSwitchByTyping"])));
    gtk_widget_set_sensitive(_sw["RestoreIfInvalidWord"], gtk_switch_get_active(GTK_SWITCH(_sw["Spelling"])));
}
static void syncSeg() { int vi = prefs::getInt("InputMethod", 1); gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(_seg[0]), vi); gtk_toggle_button_set_active(GTK_TOGGLE_BUTTON(_seg[1]), !vi); }
static gboolean onSwitch(GtkSwitch* s, gboolean state, gpointer key) { prefs::setInt((const char*)key, state ? 1 : 0); gtk_switch_set_state(s, state); refreshEnabled(); return TRUE; }
static void onSeg(GtkToggleButton* b, gpointer which) { if (!gtk_toggle_button_get_active(b)) return; prefs::sendCommand(GPOINTER_TO_INT(which) == 0 ? "lang vi user" : "lang en user"); }
static void onMark(GObject* dd, GParamSpec*, gpointer) { prefs::setInt("ModernOrthography", gtk_drop_down_get_selected(GTK_DROP_DOWN(dd)) == 0 ? 1 : 0); }
static void onBeep(GtkSwitch* s, gboolean state, gpointer) { int hk = (currentHotkey() & ~0x8000) | (state ? 0x8000 : 0); prefs::setInt("SwitchKeyStatus", hk); gtk_switch_set_state(s, state); }
static gboolean onRecordKey(GtkEventControllerKey*, guint keyval, guint, GdkModifierType state, gpointer) {
    if (!_recording) return FALSE;
    if (keyval == GDK_KEY_Escape) { _recording = false; setHint(); return TRUE; }
    bool isMod = keyval == GDK_KEY_Shift_L || keyval == GDK_KEY_Shift_R || keyval == GDK_KEY_Control_L || keyval == GDK_KEY_Control_R || keyval == GDK_KEY_Alt_L || keyval == GDK_KEY_Alt_R || keyval == GDK_KEY_Super_L || keyval == GDK_KEY_Super_R || keyval == GDK_KEY_Meta_L || keyval == GDK_KEY_Meta_R;
    unsigned mods = (state & GDK_CONTROL_MASK ? 0x100 : 0) | (state & GDK_ALT_MASK ? 0x200 : 0) | (state & GDK_SUPER_MASK ? 0x400 : 0) | (state & GDK_SHIFT_MASK ? 0x800 : 0);
    if (isMod) { if (keyval == GDK_KEY_Control_L || keyval == GDK_KEY_Control_R) mods |= 0x100; if (keyval == GDK_KEY_Alt_L || keyval == GDK_KEY_Alt_R || keyval == GDK_KEY_Meta_L || keyval == GDK_KEY_Meta_R) mods |= 0x200; if (keyval == GDK_KEY_Super_L || keyval == GDK_KEY_Super_R) mods |= 0x400; if (keyval == GDK_KEY_Shift_L || keyval == GDK_KEY_Shift_R) mods |= 0x800; _recMods = mods; return TRUE; }
    int key = engineKeyOfKeyval(keyval); if (key < 0) return TRUE;
    prefs::setInt("SwitchKeyStatus", key | mods | (currentHotkey() & 0x8000)); _recording = false; _recMods = 0; setHint(); return TRUE;
}
static gboolean onRecordRelease(GtkEventControllerKey*, guint keyval, guint, GdkModifierType, gpointer) {
    if (!_recording || !_recMods) return FALSE;
    prefs::setInt("SwitchKeyStatus", 0xFE | _recMods | (currentHotkey() & 0x8000)); _recording = false; _recMods = 0; setHint(); return TRUE;   // modifiers only
}
static void onHotkeyClick(GtkButton*, gpointer) { _recording = true; _recMods = 0; setHint(); gtk_widget_grab_focus(_hotkeyBtn); }

static GtkWidget* tipLabel(const char* text, const char* tip) {
    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
    GtkWidget* l = gtk_label_new(text); gtk_box_append(GTK_BOX(box), l);
    GtkWidget* i = gtk_image_new_from_icon_name("help-about-symbolic"); gtk_widget_add_css_class(i, "dim-label"); gtk_widget_set_tooltip_text(i, tip); gtk_box_append(GTK_BOX(box), i);
    return box;
}
static GtkWidget* switchRow(GtkWidget* group, const char* label, const char* tip, const char* key, int def, GCallback cb = nullptr) {
    GtkWidget* row = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(row), label); gtk_widget_set_tooltip_text(row, tip);
    GtkWidget* sw = gtk_switch_new(); gtk_widget_set_valign(sw, GTK_ALIGN_CENTER); gtk_switch_set_active(GTK_SWITCH(sw), key[0] == '!' ? ((currentHotkey() & 0x8000) != 0) : prefs::getInt(key, def) != 0);
    g_signal_connect(sw, "state-set", cb ? cb : G_CALLBACK(onSwitch), (gpointer)key);
    adw_action_row_add_suffix(ADW_ACTION_ROW(row), sw); adw_action_row_set_activatable_widget(ADW_ACTION_ROW(row), sw);
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(group), row); if (key[0] != '!') _sw[key] = sw; return sw;
}
static GtkWidget* group(GtkWidget* page, const char* title) { GtkWidget* g = adw_preferences_group_new(); if (title) adw_preferences_group_set_title(ADW_PREFERENCES_GROUP(g), title); adw_preferences_page_add(ADW_PREFERENCES_PAGE(page), ADW_PREFERENCES_GROUP(g)); return g; }

static void buildMain(GtkApplication* app) {
    GtkWidget* win = adw_application_window_new(app); gtk_window_set_title(GTK_WINDOW(win), "Vikey"); gtk_window_set_default_size(GTK_WINDOW(win), 480, 640); gtk_window_set_resizable(GTK_WINDOW(win), FALSE);
    GtkWidget* tv = adw_toolbar_view_new(); GtkWidget* hb = adw_header_bar_new(); adw_header_bar_set_show_title(ADW_HEADER_BAR(hb), FALSE); adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(tv), hb);
    GtkWidget* page = adw_preferences_page_new();
    // header: icon, wordmark + hint, segmented Tiếng Việt / English
    GtkWidget* head = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 12); gtk_widget_set_margin_start(head, 12); gtk_widget_set_margin_end(head, 12); gtk_widget_set_margin_bottom(head, 8);
    GtkWidget* icon = gtk_image_new_from_icon_name("vikey"); gtk_image_set_pixel_size(GTK_IMAGE(icon), 44); gtk_box_append(GTK_BOX(head), icon);
    GtkWidget* col = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2); gtk_widget_set_hexpand(col, TRUE); gtk_widget_set_valign(col, GTK_ALIGN_CENTER);
    GtkWidget* name = gtk_label_new("Vikey"); gtk_widget_add_css_class(name, "title-1"); gtk_label_set_xalign(GTK_LABEL(name), 0); gtk_box_append(GTK_BOX(col), name);
    _hint = gtk_label_new(""); gtk_widget_add_css_class(_hint, "dim-label"); gtk_label_set_xalign(GTK_LABEL(_hint), 0); gtk_box_append(GTK_BOX(col), _hint); gtk_box_append(GTK_BOX(head), col);
    GtkWidget* seg = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0); gtk_widget_add_css_class(seg, "linked"); gtk_widget_set_valign(seg, GTK_ALIGN_CENTER);
    _seg[0] = gtk_toggle_button_new_with_label("Tiếng Việt"); _seg[1] = gtk_toggle_button_new_with_label("English"); gtk_toggle_button_set_group(GTK_TOGGLE_BUTTON(_seg[1]), GTK_TOGGLE_BUTTON(_seg[0]));
    gtk_box_append(GTK_BOX(seg), _seg[0]); gtk_box_append(GTK_BOX(seg), _seg[1]); gtk_box_append(GTK_BOX(head), seg); syncSeg();
    g_signal_connect(_seg[0], "toggled", G_CALLBACK(onSeg), GINT_TO_POINTER(0)); g_signal_connect(_seg[1], "toggled", G_CALLBACK(onSeg), GINT_TO_POINTER(1));
    GtkWidget* g0 = adw_preferences_group_new(); adw_preferences_group_set_header_suffix(ADW_PREFERENCES_GROUP(g0), nullptr); adw_preferences_page_add(ADW_PREFERENCES_PAGE(page), ADW_PREFERENCES_GROUP(g0));
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(g0), head);
    // group 1: hotkey + beep
    GtkWidget* g1 = group(page, nullptr);
    GtkWidget* hkRow = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(hkRow), "Phím chuyển Anh/Việt"); gtk_widget_set_tooltip_text(hkRow, "Bấm tổ hợp phím này để chuyển giữa tiếng Việt và tiếng Anh. Bấm vào ô để đặt phím khác.");
    _hotkeyBtn = gtk_button_new_with_label(""); gtk_widget_set_valign(_hotkeyBtn, GTK_ALIGN_CENTER); gtk_widget_set_size_request(_hotkeyBtn, 130, -1);
    GtkEventController* kc = gtk_event_controller_key_new(); g_signal_connect(kc, "key-pressed", G_CALLBACK(onRecordKey), nullptr); g_signal_connect(kc, "key-released", G_CALLBACK(onRecordRelease), nullptr); gtk_widget_add_controller(_hotkeyBtn, kc);
    g_signal_connect(_hotkeyBtn, "clicked", G_CALLBACK(onHotkeyClick), nullptr);
    adw_action_row_add_suffix(ADW_ACTION_ROW(hkRow), _hotkeyBtn); adw_preferences_group_add(ADW_PREFERENCES_GROUP(g1), hkRow);
    switchRow(g1, "Âm báo khi chuyển", "Phát một âm ngắn mỗi lần bạn bấm phím chuyển Anh/Việt.", "!beep", 0, G_CALLBACK(onBeep));
    // group 2: auto switch
    GtkWidget* g2 = group(page, "Tự chuyển");
    switchRow(g2, "Tự chuyển Anh/Việt", "Gõ một từ tiếng Anh khi đang ở tiếng Việt (hoặc ngược lại), Vikey tự sửa từ đó và chuyển chế độ. Bấm Xoá ngay sau đó để hoàn tác.", "AutoSwitchByTyping", 1);
    switchRow(g2, "Tạm dừng 5 giây", "Khi bạn tự bấm chuyển Anh/Việt, Vikey không tự chuyển trong 5 giây, để giữ đúng lựa chọn của bạn.", "PauseAutoAfterManual", 1);
    switchRow(g2, "Nhớ theo ứng dụng", "Vikey nhớ bạn dùng tiếng Anh hay tiếng Việt ở mỗi ứng dụng và tự chuyển lại khi bạn quay về ứng dụng đó (trên Wayland chỉ với ứng dụng X11).", "UseSmartSwitchKey", 1);
    // group 3: Vietnamese typing
    GtkWidget* g3 = group(page, "Gõ tiếng Việt");
    GtkWidget* markRow = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(markRow), "Đặt dấu"); gtk_widget_set_tooltip_text(markRow, "Vị trí dấu thanh với oa, oe, uy: kiểu mới (hoà, thuý) hoặc kiểu cũ (hòa, thúy).");
    const char* marks[] = {"hoà, thuý", "hòa, thúy", nullptr}; GtkWidget* dd = gtk_drop_down_new_from_strings(marks); gtk_widget_set_valign(dd, GTK_ALIGN_CENTER); gtk_drop_down_set_selected(GTK_DROP_DOWN(dd), prefs::getInt("ModernOrthography", 1) ? 0 : 1);
    g_signal_connect(dd, "notify::selected", G_CALLBACK(onMark), nullptr); adw_action_row_add_suffix(ADW_ACTION_ROW(markRow), dd); adw_preferences_group_add(ADW_PREFERENCES_GROUP(g3), markRow);
    switchRow(g3, "Kiểm tra chính tả", "Chỉ bỏ dấu khi từ đang gõ đúng quy tắc chính tả tiếng Việt.", "Spelling", 1);
    switchRow(g3, "Trả lại phím khi sai", "Khi gõ xong một từ sai chính tả tiếng Việt, Vikey trả lại đúng các phím bạn đã gõ.", "RestoreIfInvalidWord", 1);
    // group 4: system
    GtkWidget* g4 = group(page, nullptr);
    GtkWidget* r = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(r), "Mở Vikey khi đăng nhập"); adw_action_row_set_subtitle(ADW_ACTION_ROW(r), "IBus mở Vikey cùng phiên đăng nhập. Chọn Vikey trong Cài đặt › Bàn phím › Nguồn nhập.");
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(g4), r);
    GtkWidget* r2 = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(r2), "Tự động cập nhật"); adw_action_row_set_subtitle(ADW_ACTION_ROW(r2), "Cập nhật cùng hệ thống qua kho gói (apt/dnf) của vikey.app.");
    adw_preferences_group_add(ADW_PREFERENCES_GROUP(g4), r2);
    setHint(); refreshEnabled();
    adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(tv), page); adw_application_window_set_content(ADW_APPLICATION_WINDOW(win), tv);
    gtk_window_present(GTK_WINDOW(win));
}

// ---- typing log window ---------------------------------------------------------------------------------------
static std::string tlDataDir() { return prefs::dataDir(); }
static int statSum(int days, const char* name) {
    time_t now = time(nullptr); int total = 0;
    for (auto& k : prefs::keys()) {
        if (k.rfind("TLStat_", 0) != 0 || k.size() < 19) continue;
        std::string day = k.substr(7, 10), n = k.substr(18); if (n != name) continue;
        if (days > 0) { struct tm t = {}; strptime(day.c_str(), "%Y-%m-%d", &t); if (difftime(now, mktime(&t)) > (double)days * 86400) continue; }
        total += prefs::getInt(k.c_str(), 0);
    }
    return total;
}
static std::string jget(const std::string& j, const char* key) { std::string k = std::string("\"") + key + "\":"; size_t p = j.find(k); if (p == std::string::npos) return ""; p += k.size(); if (j[p] == '"') { size_t e = p + 1; std::string o; while (e < j.size() && j[e] != '"') { if (j[e] == '\\' && e + 1 < j.size()) { e++; } o += j[e]; e++; } return o; } size_t e = j.find_first_of(",}", p); return j.substr(p, e - p); }
static void onOpenLog(GtkButton*, gpointer) { std::string d = tlDataDir(); gchar* argv[] = {(gchar*)"xdg-open", (gchar*)d.c_str(), nullptr}; g_spawn_async(nullptr, argv, nullptr, (GSpawnFlags)G_SPAWN_SEARCH_PATH, nullptr, nullptr, nullptr, nullptr); }
static void onClearLog(GtkButton*, gpointer) { ::remove((tlDataDir() + "/typing-log.jsonl").c_str()); ::remove((tlDataDir() + "/typing-log.1.jsonl").c_str()); for (auto& k : prefs::keys()) if (k.rfind("TLStat_", 0) == 0) prefs::remove(k.c_str()); }
static void onAboutClosed(AdwDialog*, gpointer w) { gtk_window_destroy(GTK_WINDOW(w)); }
static void buildLog(GtkApplication* app) {
    GtkWidget* win = adw_application_window_new(app); gtk_window_set_title(GTK_WINDOW(win), "Nhật ký gõ"); gtk_window_set_default_size(GTK_WINDOW(win), 720, 560);
    GtkWidget* tv = adw_toolbar_view_new(); adw_toolbar_view_add_top_bar(ADW_TOOLBAR_VIEW(tv), adw_header_bar_new());
    GtkWidget* box = gtk_box_new(GTK_ORIENTATION_VERTICAL, 12); for (auto f : {gtk_widget_set_margin_start, gtk_widget_set_margin_end, gtk_widget_set_margin_top, gtk_widget_set_margin_bottom}) f(box, 16);
    auto autoN = [](int d) { return statSum(d, "auto_vi_word_to_en") + statSum(d, "auto_en_word_to_vi") + statSum(d, "auto_double_key"); };
    char s[200]; snprintf(s, sizeof s, "Hôm nay: %d lần chuyển tay, %d lần tự chuyển", statSum(1, "manual"), autoN(1));
    GtkWidget* title = gtk_label_new(s); gtk_widget_add_css_class(title, "title-3"); gtk_label_set_xalign(GTK_LABEL(title), 0); gtk_box_append(GTK_BOX(box), title);
    GtkWidget* grid = gtk_grid_new(); gtk_grid_set_column_spacing(GTK_GRID(grid), 24); gtk_grid_set_row_spacing(GTK_GRID(grid), 4);
    const char* heads[] = {"", "Hôm nay", "7 ngày", "Tất cả"}; for (int c = 0; c < 4; c++) { GtkWidget* l = gtk_label_new(heads[c]); gtk_widget_add_css_class(l, "heading"); gtk_label_set_xalign(GTK_LABEL(l), c ? 1 : 0); gtk_grid_attach(GTK_GRID(grid), l, c, 0, 1, 1); }
    const char* rows[][2] = {{"Từ đã gõ","words"},{"Chuyển tay","manual"},{"Tự chuyển","auto"},{"    Tiếng Việt → Anh (cả từ)","auto_vi_word_to_en"},{"    Anh → Tiếng Việt (cả từ)","auto_en_word_to_vi"},{"    Gõ dấu hai lần → Anh","auto_double_key"},{"Hoàn tác bằng Delete","undo"},{"Đổi theo ứng dụng","context"},{"Chuyển tay mỗi 100 từ","rate"}};
    int periods[] = {1, 7, 0};
    for (int r = 0; r < 9; r++) {
        GtkWidget* l = gtk_label_new(rows[r][0]); gtk_label_set_xalign(GTK_LABEL(l), 0); gtk_widget_set_hexpand(l, TRUE); gtk_grid_attach(GTK_GRID(grid), l, 0, r + 1, 1, 1);
        for (int c = 0; c < 3; c++) { int d = periods[c]; std::string key = rows[r][1]; std::string v; int words = statSum(d, "words_vi") + statSum(d, "words_en");
            if (key == "words") v = std::to_string(words); else if (key == "auto") v = std::to_string(autoN(d)); else if (key == "rate") { if (words) { char b[32]; snprintf(b, 32, "%.1f", 100.0 * statSum(d, "manual") / words); v = b; } else v = "–"; } else v = std::to_string(statSum(d, key.c_str()));
            GtkWidget* vl = gtk_label_new(v.c_str()); gtk_label_set_xalign(GTK_LABEL(vl), 1); gtk_grid_attach(GTK_GRID(grid), vl, c + 1, r + 1, 1, 1); }
    }
    gtk_box_append(GTK_BOX(box), grid);
    GtkWidget* keysRow = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 10); GtkWidget* sw = gtk_switch_new(); gtk_switch_set_active(GTK_SWITCH(sw), prefs::getInt("TypingLogKeys", 1) != 0); g_signal_connect(sw, "state-set", G_CALLBACK(onSwitch), (gpointer)"TypingLogKeys");
    GtkWidget* kcol = gtk_box_new(GTK_ORIENTATION_VERTICAL, 2); GtkWidget* k1 = gtk_label_new("Ghi lại phím gõ của từng từ"); gtk_label_set_xalign(GTK_LABEL(k1), 0); GtkWidget* k2 = gtk_label_new("Không bao giờ ghi trong trình quản lý mật khẩu và Terminal."); gtk_widget_add_css_class(k2, "dim-label"); gtk_label_set_xalign(GTK_LABEL(k2), 0);
    gtk_box_append(GTK_BOX(kcol), k1); gtk_box_append(GTK_BOX(kcol), k2); gtk_box_append(GTK_BOX(keysRow), sw); gtk_box_append(GTK_BOX(keysRow), kcol); gtk_box_append(GTK_BOX(box), keysRow);
    GtkWidget* h = gtk_label_new("Sự kiện gần đây"); gtk_widget_add_css_class(h, "heading"); gtk_label_set_xalign(GTK_LABEL(h), 0); gtk_box_append(GTK_BOX(box), h);
    GtkWidget* list = gtk_list_box_new(); gtk_widget_add_css_class(list, "boxed-list"); gtk_list_box_set_selection_mode(GTK_LIST_BOX(list), GTK_SELECTION_NONE);
    std::ifstream f(tlDataDir() + "/typing-log.jsonl"); std::vector<std::string> lines; std::string l; while (std::getline(f, l)) if (!l.empty()) lines.push_back(l);
    int n = 0;
    for (auto it = lines.rbegin(); it != lines.rend() && n < 200; ++it, ++n) {
        std::string e = jget(*it, "e"), to = jget(*it, "to") == "vi" ? "Tiếng Việt" : "Anh", t = jget(*it, "t"), app = jget(*it, "app"); std::string time = t.size() >= 19 ? t.substr(5, 14) : t; for (auto& ch : time) if (ch == 'T') ch = ' ';
        std::string title, detail;
        if (e == "word") { title = jget(*it, "lang") == "vi" ? "Từ (Việt)" : "Từ (Anh)"; detail = jget(*it, "keys") + "   [" + jget(*it, "end") + "]"; }
        else if (e == "auto") { title = "Tự chuyển → " + to; std::string r = jget(*it, "rule"); detail = r == "vi_word_to_en" ? "từ tiếng Anh gõ khi đang ở Tiếng Việt" : r == "en_word_to_vi" ? "từ tiếng Việt gõ khi đang ở Anh" : "gõ dấu hai lần"; }
        else if (e == "manual") { title = "Chuyển tay → " + to; detail = jget(*it, "via") == "menu" ? "bằng menu" : "bằng phím tắt"; }
        else if (e == "undo") { title = "Hoàn tác → " + to; detail = "bằng Delete"; } else if (e == "context") title = "Theo ứng dụng → " + to; else title = e;
        GtkWidget* row = adw_action_row_new(); adw_preferences_row_set_title(ADW_PREFERENCES_ROW(row), (time + "  ·  " + app + "  ·  " + title).c_str()); adw_action_row_set_subtitle(ADW_ACTION_ROW(row), detail.c_str()); gtk_list_box_append(GTK_LIST_BOX(list), row);
    }
    GtkWidget* sc = gtk_scrolled_window_new(); gtk_widget_set_vexpand(sc, TRUE); gtk_scrolled_window_set_child(GTK_SCROLLED_WINDOW(sc), list); gtk_box_append(GTK_BOX(box), sc);
    GtkWidget* btns = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 8); GtkWidget* open = gtk_button_new_with_label("Mở file log"); GtkWidget* clear = gtk_button_new_with_label("Xoá log…"); gtk_widget_add_css_class(clear, "destructive-action"); gtk_widget_set_hexpand(open, TRUE); gtk_widget_set_halign(open, GTK_ALIGN_START);
    g_signal_connect(open, "clicked", G_CALLBACK(onOpenLog), nullptr);
    g_signal_connect(clear, "clicked", G_CALLBACK(onClearLog), nullptr);
    gtk_box_append(GTK_BOX(btns), open); gtk_box_append(GTK_BOX(btns), clear); gtk_box_append(GTK_BOX(box), btns);
    adw_toolbar_view_set_content(ADW_TOOLBAR_VIEW(tv), box); adw_application_window_set_content(ADW_APPLICATION_WINDOW(win), tv); gtk_window_present(GTK_WINDOW(win));
}
static void buildAbout(GtkApplication* app) {
    GtkWidget* win = adw_application_window_new(app); gtk_window_set_default_size(GTK_WINDOW(win), 300, 200);
    AdwDialog* d = adw_about_dialog_new();
    adw_about_dialog_set_application_name(ADW_ABOUT_DIALOG(d), "Vikey"); adw_about_dialog_set_application_icon(ADW_ABOUT_DIALOG(d), "vikey"); adw_about_dialog_set_version(ADW_ABOUT_DIALOG(d), VIKEY_VERSION);
    adw_about_dialog_set_developer_name(ADW_ABOUT_DIALOG(d), "Tony Dinh"); adw_about_dialog_set_website(ADW_ABOUT_DIALOG(d), "https://vikey.app"); adw_about_dialog_set_license_type(ADW_ABOUT_DIALOG(d), GTK_LICENSE_GPL_3_0);
    adw_about_dialog_set_comments(ADW_ABOUT_DIALOG(d), "Gõ tiếng Việt, tự chuyển Anh/Việt cho bạn.\nDựa trên OpenKey của Tuyen Mai (GPL-3.0).");
    g_signal_connect(d, "closed", G_CALLBACK(onAboutClosed), win);
    gtk_window_present(GTK_WINDOW(win)); adw_dialog_present(d, win);
}
static const char* _mode = "";
static void onActivate(GtkApplication* app, gpointer) { if (!strcmp(_mode, "--log")) buildLog(app); else if (!strcmp(_mode, "--about")) buildAbout(app); else buildMain(app); }
int main(int argc, char** argv) {
    for (int i = 1; i < argc; i++) if (!strncmp(argv[i], "--", 2)) _mode = argv[i];
    AdwApplication* app = adw_application_new("app.vikey.Settings", G_APPLICATION_NON_UNIQUE);
    g_signal_connect(app, "activate", G_CALLBACK(onActivate), nullptr);
    return g_application_run(G_APPLICATION(app), 0, nullptr);
}
