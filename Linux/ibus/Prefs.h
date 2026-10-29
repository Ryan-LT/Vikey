// Settings on Linux: a flat JSON file at $XDG_CONFIG_HOME/vikey/settings.json with the same keys as the
// macOS UserDefaults / Windows registry (InputMethod, SwitchKeyStatus, AutoSwitchByTyping, ...).
#pragma once
#include <string>
#include <vector>
namespace vikey { namespace prefs {
std::string configDir();                                  // ~/.config/vikey
std::string dataDir();                                    // ~/.local/share/vikey
std::string settingsPath();
void reload();                                            // re-read the file (after a change from the settings app)
int getInt(const char* key, int fallback);
void setInt(const char* key, int value);
std::string getString(const char* key, const std::string& fallback);
void setString(const char* key, const std::string& value);
std::vector<unsigned char> getBinary(const char* key);    // base64 string in the file
void setBinary(const char* key, const unsigned char* data, size_t n);
bool has(const char* key);
void remove(const char* key);
std::vector<std::string> keys();
}}
