//
//  VikeyCore.h
//  The bridge between the SwiftUI app and the keyboard core (event tap + Telex engine).
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Posted on the main thread whenever the typing language changes (hotkey, auto switch, smart switch, menu).
extern NSNotificationName const VikeyLanguageDidChangeNotification;

@interface VikeyCore : NSObject

/// Vikey needs Accessibility permission to read and rewrite keystrokes.
+ (BOOL)isAccessibilityTrusted;
/// Asks macOS for Accessibility permission (shows the system prompt the first time).
+ (void)requestAccessibility;

/// Starts the event tap. Returns NO if macOS refused (permission missing).
+ (BOOL)start;
+ (void)stop;
+ (BOOL)isRunning;
+ (void)reenableEventTap;

/// 1 = Vietnamese, 0 = English.
+ (int)language;
/// A language change made by the user from Vikey's UI (menu bar or settings).
+ (void)setLanguageByUser:(int)language;

/// Re-reads settings from UserDefaults into the engine after the UI changed one.
+ (void)reloadSettings;

/// App and space changes, forwarded from NSWorkspace notifications.
+ (void)frontmostAppChanged;
+ (void)activeSpaceChanged;

/// Typing log.
+ (NSString *)typingLogPath;
+ (NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *)typingLogStats;
+ (void)flushTypingLog;
+ (void)clearTypingLog;

@end

NS_ASSUME_NONNULL_END
