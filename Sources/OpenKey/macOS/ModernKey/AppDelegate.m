//
//  AppDelegate.m
//  ModernKey
//
//  Created by Tuyen on 1/18/19.
//  Copyright © 2019 Tuyen Mai. All rights reserved.
//

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <libproc.h>
#include <sys/proc_info.h>
#import "AppDelegate.h"
#import "ViewController.h"
#import "OpenKeyManager.h"
#import "MJAccessibilityUtils.h"

AppDelegate* appDelegate;
extern ViewController* viewController;
extern void OnTableCodeChange(void);
extern void OnInputMethodChanged(void);
extern void RequestNewSession(void);
extern void OnActiveAppChanged(void);
extern void TLAppChanged(void);
extern void OnFocusChanged(void);
extern void TLManual(NSString* via, int to);
extern void TLFlush(void);
extern void TLClear(void);
extern NSString* TLLogPath(void);
extern NSDictionary* TLStatsSnapshot(void);
extern int vTypingLogKeys;

#pragma mark - Typing log window
/// Shows manual vs automatic switch counts and the latest log lines.
@interface TypingLogWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation TypingLogWindowController {
    NSGridView* _grid;
    NSTableView* _table;
    NSArray<NSDictionary*>* _rows;
    NSButton* _recordKeys;
    NSTextField* _summary;
}

- (instancetype)init {
    NSWindow* w = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 620)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    w.title = @"Nhật ký gõ";
    w.minSize = NSMakeSize(720, 480);
    self = [super initWithWindow:w];
    [self build];
    return self;
}

- (NSTextField*)label:(NSString*)text bold:(BOOL)bold {
    NSTextField* l = [NSTextField labelWithString:text];
    l.font = bold ? [NSFont boldSystemFontOfSize:13] : [NSFont systemFontOfSize:13];
    return l;
}

- (void)build {
    NSView* root = self.window.contentView;

    _summary = [NSTextField wrappingLabelWithString:@""];
    _summary.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];

    _grid = [NSGridView gridViewWithNumberOfColumns:4 rows:0];
    _grid.rowSpacing = 6;
    _grid.columnSpacing = 24;

    _recordKeys = [NSButton checkboxWithTitle:@"Ghi lại phím gõ của từng từ (không ghi trong ô mật khẩu, trình quản lý mật khẩu và Terminal)"
                                       target:self action:@selector(toggleRecord:)];
    _recordKeys.state = vTypingLogKeys ? NSControlStateValueOn : NSControlStateValueOff;

    _table = [[NSTableView alloc] init];
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    NSArray* cols = @[@[@"time", @"Thời gian", @150], @[@"app", @"Ứng dụng / trang", @220], @[@"event", @"Sự kiện", @150], @[@"detail", @"Chi tiết", @240]];
    for (NSArray* c in cols) {
        NSTableColumn* col = [[NSTableColumn alloc] initWithIdentifier:c[0]];
        col.title = c[1];
        col.width = [c[2] doubleValue];
        [_table addTableColumn:col];
    }
    _table.dataSource = self;
    _table.delegate = self;
    NSScrollView* scroll = [[NSScrollView alloc] init];
    scroll.documentView = _table;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;

    NSButton* refresh = [NSButton buttonWithTitle:@"Làm mới" target:self action:@selector(reload)];
    NSButton* reveal = [NSButton buttonWithTitle:@"Mở file log" target:self action:@selector(reveal)];
    NSButton* clear = [NSButton buttonWithTitle:@"Xoá log…" target:self action:@selector(clearLog)];
    NSStackView* buttons = [NSStackView stackViewWithViews:@[refresh, reveal, [NSView new], clear]];
    [buttons setHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSTextField* recent = [self label:@"Sự kiện gần đây" bold:YES];
    NSStackView* stack = [NSStackView stackViewWithViews:@[_summary, _grid, _recordKeys, recent, scroll, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 14;
    stack.edgeInsets = NSEdgeInsetsMake(20, 20, 20, 20);
    [stack setCustomSpacing:20 afterView:_grid];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:root.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20],
        [scroll.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20],
        [buttons.leadingAnchor constraintEqualToAnchor:stack.leadingAnchor constant:20],
        [buttons.trailingAnchor constraintEqualToAnchor:stack.trailingAnchor constant:-20],
        [_summary.trailingAnchor constraintLessThanOrEqualToAnchor:stack.trailingAnchor constant:-20],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:200],
    ]];
}

- (NSDictionary*)sumStats:(NSDictionary*)stats days:(NSInteger)days {
    NSMutableDictionary* total = [NSMutableDictionary dictionary];
    NSDateFormatter* f = [NSDateFormatter new];
    f.dateFormat = @"yyyy-MM-dd";
    f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSString* from = days > 0 ? [f stringFromDate:[NSDate dateWithTimeIntervalSinceNow:-(days - 1) * 86400]] : @"0000";
    for (NSString* day in stats) {
        if ([day compare:from] == NSOrderedAscending) continue;
        NSDictionary* d = stats[day];
        for (NSString* k in d) total[k] = @([total[k] integerValue] + [d[k] integerValue]);
    }
    return total;
}

- (void)reload {
    TLFlush();
    NSDictionary* stats = TLStatsSnapshot();
    NSArray* periods = @[[self sumStats:stats days:1], [self sumStats:stats days:7], [self sumStats:stats days:0]];

    while (_grid.numberOfRows > 0) [_grid removeRowAtIndex:0];
    [_grid addRowWithViews:@[[self label:@"" bold:NO], [self label:@"Hôm nay" bold:YES], [self label:@"7 ngày" bold:YES], [self label:@"Tất cả" bold:YES]]];
    NSArray* rows = @[@[@"Từ đã gõ", @"words"], @[@"Chuyển tay", @"manual"], @[@"Tự chuyển", @"auto"],
                      @[@"    Tiếng Việt → Anh (cả từ)", @"auto_vi_word_to_en"], @[@"    Anh → Tiếng Việt (cả từ)", @"auto_en_word_to_vi"],
                      @[@"    Gõ dấu hai lần → Anh", @"auto_double_key"], @[@"Hoàn tác bằng Delete", @"undo"],
                      @[@"Đổi theo ứng dụng / trang web", @"context"], @[@"Chuyển tay mỗi 100 từ", @"rate"]];
    for (NSArray* r in rows) {
        NSMutableArray* views = [NSMutableArray arrayWithObject:[self label:r[0] bold:NO]];
        for (NSDictionary* p in periods) {
            NSInteger words = [p[@"words_vi"] integerValue] + [p[@"words_en"] integerValue];
            NSInteger autoTotal = [p[@"auto_vi_word_to_en"] integerValue] + [p[@"auto_en_word_to_vi"] integerValue] + [p[@"auto_double_key"] integerValue];
            NSString* v;
            if ([r[1] isEqualToString:@"words"]) v = [NSString stringWithFormat:@"%ld", (long)words];
            else if ([r[1] isEqualToString:@"auto"]) v = [NSString stringWithFormat:@"%ld", (long)autoTotal];
            else if ([r[1] isEqualToString:@"rate"]) v = words > 0 ? [NSString stringWithFormat:@"%.1f", 100.0 * [p[@"manual"] integerValue] / words] : @"–";
            else v = [NSString stringWithFormat:@"%ld", (long)[p[r[1]] integerValue]];
            NSTextField* l = [self label:v bold:NO];
            l.alignment = NSTextAlignmentRight;
            l.font = [NSFont monospacedDigitSystemFontOfSize:13 weight:NSFontWeightRegular];
            [views addObject:l];
        }
        [_grid addRowWithViews:views];
    }
    for (NSInteger c = 1; c < 4; c++) [_grid columnAtIndex:c].xPlacement = NSGridCellPlacementTrailing;

    NSDictionary* today = periods[0];
    NSInteger manual = [today[@"manual"] integerValue];
    NSInteger autoToday = [today[@"auto_vi_word_to_en"] integerValue] + [today[@"auto_en_word_to_vi"] integerValue] + [today[@"auto_double_key"] integerValue];
    _summary.stringValue = [NSString stringWithFormat:@"Hôm nay: %ld lần chuyển tay, %ld lần tự chuyển", (long)manual, (long)autoToday];

    // last 300 lines of the log, newest first
    NSMutableArray* rowsOut = [NSMutableArray array];
    NSString* content = [NSString stringWithContentsOfFile:TLLogPath() encoding:NSUTF8StringEncoding error:nil];
    NSArray* lines = [content componentsSeparatedByString:@"\n"];
    for (NSInteger i = (NSInteger)lines.count - 1; i >= 0 && rowsOut.count < 300; i--) {
        NSData* data = [lines[i] dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length == 0) continue;
        NSDictionary* d = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([d isKindOfClass:[NSDictionary class]]) [rowsOut addObject:d];
    }
    _rows = rowsOut;
    [_table reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView*)tableView { return _rows.count; }

- (NSView*)tableView:(NSTableView*)tableView viewForTableColumn:(NSTableColumn*)col row:(NSInteger)row {
    NSDictionary* d = _rows[row];
    NSString* e = d[@"e"];
    NSString* to = [d[@"to"] isEqualToString:@"vi"] ? @"Tiếng Việt" : @"Anh";
    NSString* text = @"";
    NSString* ident = col.identifier;
    if ([ident isEqualToString:@"time"]) {
        NSString* t = d[@"t"] ?: @"";
        text = t.length >= 19 ? [[t substringWithRange:NSMakeRange(5, 14)] stringByReplacingOccurrencesOfString:@"T" withString:@"  "] : t;
    } else if ([ident isEqualToString:@"app"]) {
        text = d[@"site"] ? [NSString stringWithFormat:@"%@ · %@", d[@"app"], d[@"site"]] : (d[@"app"] ?: @"");
    } else if ([ident isEqualToString:@"event"]) {
        if ([e isEqualToString:@"word"]) text = [d[@"lang"] isEqualToString:@"vi"] ? @"Từ (Việt)" : @"Từ (Anh)";
        else if ([e isEqualToString:@"auto"]) text = [@"Tự chuyển → " stringByAppendingString:to];
        else if ([e isEqualToString:@"manual"]) text = [@"Chuyển tay → " stringByAppendingString:to];
        else if ([e isEqualToString:@"undo"]) text = [@"Hoàn tác → " stringByAppendingString:to];
        else if ([e isEqualToString:@"context"]) text = [@"Theo app/web → " stringByAppendingString:to];
        else text = e ?: @"";
    } else {
        if ([e isEqualToString:@"word"]) text = [NSString stringWithFormat:@"%@   [%@]", d[@"keys"] ?: @"", d[@"end"] ?: @""];
        else if ([e isEqualToString:@"auto"]) {
            NSDictionary* names = @{@"vi_word_to_en": @"từ tiếng Anh gõ khi đang ở Tiếng Việt",
                                    @"en_word_to_vi": @"từ tiếng Việt gõ khi đang ở Anh",
                                    @"double_key": @"gõ dấu hai lần"};
            text = names[d[@"rule"]] ?: (d[@"rule"] ?: @"");
        } else if ([e isEqualToString:@"manual"] || [e isEqualToString:@"undo"]) {
            if ([e isEqualToString:@"undo"]) text = @"bằng Delete";
            else text = [NSString stringWithFormat:@"%@%@", [d[@"via"] isEqualToString:@"menu"] ? @"bằng menu" : @"bằng phím tắt",
                         [d[@"after_auto"] boolValue] ? @", ngay sau tự chuyển" : @""];
        }
    }
    NSTextField* cell = [tableView makeViewWithIdentifier:ident owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = ident;
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
    }
    cell.stringValue = text;
    BOOL highlight = [e isEqualToString:@"manual"] || [e isEqualToString:@"undo"];
    cell.textColor = highlight ? [NSColor systemOrangeColor] : ([e isEqualToString:@"word"] ? [NSColor labelColor] : [NSColor systemBlueColor]);
    return cell;
}

- (void)toggleRecord:(NSButton*)b {
    vTypingLogKeys = b.state == NSControlStateValueOn ? 1 : 0;
    [[NSUserDefaults standardUserDefaults] setInteger:vTypingLogKeys forKey:@"TypingLogKeys"];
}

- (void)reveal {
    TLFlush();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSString* path = TLLogPath();
        if ([[NSFileManager defaultManager] fileExistsAtPath:path])
            [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
        else
            [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:[path stringByDeletingLastPathComponent]]];
    });
}

- (void)clearLog {
    NSAlert* a = [NSAlert new];
    a.messageText = @"Xoá toàn bộ nhật ký gõ?";
    a.informativeText = @"Số liệu thống kê và file log sẽ bị xoá.";
    [a addButtonWithTitle:@"Xoá"];
    [a addButtonWithTitle:@"Huỷ"];
    if ([a runModal] != NSAlertFirstButtonReturn) return;
    TLClear();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self reload]; });
}
@end

//see document in Engine.h
int vLanguage = 1;
int vInputType = 0;
int vFreeMark = 0;
int vCodeTable = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 1;
int vQuickTelex = 0;
#define DEFAULT_SWITCH_STATUS 0x7A000206 //default option + z
int vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
int vRestoreIfWrongSpelling = 0;
int vFixRecommendBrowser = 1;
int vUseMacro = 1;
int vUseMacroInEnglishMode = 1;
int vAutoCapsMacro = 0;
int vSendKeyStepByStep = 0;
int vUseSmartSwitchKey = 1;
int vUpperCaseFirstChar = 0;
int vTempOffSpelling = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
int vRememberCode = 1; //new on version 2.0
int vOtherLanguage = 1; //new on version 2.0
int vTempOffOpenKey = 0; //new on version 2.0

int vShowIconOnDock = 0; //new on version 2.0

int vPerformLayoutCompat = 0;

//beta feature
int vFixChromiumBrowser = 0; //new on version 2.0
int vAutoSwitchByTyping = 1; //switch language from typing behavior

extern int convertToolHotKey;
extern bool convertToolDontAlertWhenCompleted;

@interface AppDelegate ()

@end


@implementation AppDelegate {
    NSWindowController *_mainWC;
    NSWindowController *_macroWC;
    NSWindowController *_convertWC;
    NSWindowController *_aboutWC;
    TypingLogWindowController *_logWC;
    
    NSStatusItem *statusItem;
    NSMenu *theMenu;
    
    NSMenuItem* menuInputMethod;
    
    NSMenuItem* mnuTelex;
    NSMenuItem* mnuVNI;
    NSMenuItem* mnuSimpleTelex1;
    NSMenuItem* mnuSimpleTelex2;
    
    NSMenuItem* mnuUnicode;
    NSMenuItem* mnuTCVN;
    NSMenuItem* mnuVNIWindows;
    
    NSMenuItem* mnuUnicodeComposite;
    NSMenuItem* mnuVietnameseLocaleCP1258;
    
    NSMenuItem* mnuQuickConvert;
    NSMenuItem* mnuAutoSwitch;
}

-(void)askPermission {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText: [NSString stringWithFormat:@"OpenKey cần bạn cấp quyền để có thể hoạt động!"]];
    [alert setInformativeText:@"Vui lòng chạy lại ứng dụng sau khi cấp quyền."];

    [alert addButtonWithTitle:@"Không"];
    [alert addButtonWithTitle:@"Cấp quyền"];

    [alert.window makeKeyAndOrderFront:nil];
    [alert.window setLevel:NSStatusWindowLevel];

    NSModalResponse res = [alert runModal];

    if (res == 1001) {
        MJAccessibilityOpenPanel();
    }

    [NSApp terminate:0];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    appDelegate = self;
    
    [self registerSupportedNotification];
    
    //set quick tooltip
    [[NSUserDefaults standardUserDefaults] setObject: [NSNumber numberWithInt: 50]
                                              forKey: @"NSInitialToolTipDelay"];
    
    //check whether this app has been launched before that or not
    //Only check instances owned by current user (for multi-user/Fast User Switching support)
    uid_t currentUID = getuid();
    NSArray<NSRunningApplication *>* runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
    pid_t myPID = [[NSProcessInfo processInfo] processIdentifier];
    BOOL alreadyRunning = NO;

    for (NSRunningApplication *app in runningApps) {
        if ([app.bundleIdentifier isEqualToString:OPENKEY_BUNDLE] &&
            app.processIdentifier != myPID) {
            pid_t pid = app.processIdentifier;
            struct proc_bsdinfo proc;
            int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &proc, sizeof(proc));
            if (size == sizeof(proc) && proc.pbi_uid == currentUID) {
                alreadyRunning = YES;
                break;
            }
        }
    }

    if (alreadyRunning) {
        [NSApp terminate:nil];
        return;
    }
    
    // check if user granted Accessabilty permission
    if (!MJAccessibilityIsEnabled()) {
        [self askPermission];
        return;
    }
    
    vShowIconOnDock = (int)[[NSUserDefaults standardUserDefaults] integerForKey:@"vShowIconOnDock"];
    if (vShowIconOnDock)
        [NSApp setActivationPolicy: NSApplicationActivationPolicyRegular];
    
    if (vSwitchKeyStatus & 0x8000)
        NSBeep();

    [self createStatusBarMenu];
    
    //init
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![OpenKeyManager initEventTap]) {
            [self onControlPanelSelected];
        } else {
            NSInteger showui = [[NSUserDefaults standardUserDefaults] integerForKey:@"ShowUIOnStartup"];
            if (showui == 1) {
                [self onControlPanelSelected];
            }
        }
        [self setQuickConvertString];
    });
    
    //load default config if is first launch
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NonFirstTime"] == 0) {
        [self loadDefaultConfig];
    }
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"NonFirstTime"];
    
    //check update if enable
    NSInteger dontCheckUpdate = [[NSUserDefaults standardUserDefaults] integerForKey:@"DontCheckUpdate"];
    if (!dontCheckUpdate)
        [OpenKeyManager checkNewVersion:nil callbackFunc:nil];
    
    //correct run on startup
    NSInteger val = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [appDelegate setRunOnStartup:val];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    [self onControlPanelSelected];
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    TLFlush();
}

-(void) createStatusBarMenu {
    NSStatusBar *statusBar = [NSStatusBar systemStatusBar];
    statusItem = [statusBar statusItemWithLength:NSVariableStatusItemLength];
    statusItem.button.image = [NSImage imageNamed:@"Status"];
    statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    
    theMenu = [[NSMenu alloc] initWithTitle:@""];
    [theMenu setAutoenablesItems:NO];
    
    menuInputMethod = [theMenu addItemWithTitle:@"Bật Tiếng Việt"
                                                     action:@selector(onInputMethodSelected)
                                              keyEquivalent:@""];
    mnuAutoSwitch = [theMenu addItemWithTitle:@"Tự chuyển Anh/Việt khi gõ"
                                       action:@selector(onAutoSwitchSelected)
                                keyEquivalent:@""];
    mnuAutoSwitch.toolTip = @"Gõ nhầm chế độ thì tự sửa từ và chuyển ngôn ngữ. Bấm Delete ngay sau đó để hoàn tác.";
    [theMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem* menuInputType = [theMenu addItemWithTitle:@"Kiểu gõ" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    mnuUnicode = [theMenu addItemWithTitle:@"Unicode dựng sẵn" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicode.tag = 0;
    mnuTCVN = [theMenu addItemWithTitle:@"TCVN3 (ABC)" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuTCVN.tag = 1;
    mnuVNIWindows = [theMenu addItemWithTitle:@"VNI Windows" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVNIWindows.tag = 2;
    NSMenuItem* menuCode = [theMenu addItemWithTitle:@"Bảng mã khác" action:nil keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Công cụ chuyển mã..." action:@selector(onConvertTool) keyEquivalent:@""];
    mnuQuickConvert = [theMenu addItemWithTitle:@"Chuyển mã nhanh" action:@selector(onQuickConvert) keyEquivalent:@""];
    
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Bảng điều khiển..." action:@selector(onControlPanelSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Gõ tắt..." action:@selector(onMacroSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Nhật ký gõ..." action:@selector(onTypingLogSelected) keyEquivalent:@""];
    [theMenu addItemWithTitle:@"Giới thiệu" action:@selector(onAboutSelected) keyEquivalent:@""];
    [theMenu addItem:[NSMenuItem separatorItem]];
    
    [theMenu addItemWithTitle:@"Thoát" action:@selector(terminate:) keyEquivalent:@"q"];
    
    
    [self setInputTypeMenu:menuInputType];
    [self setCodeMenu:menuCode];
    
    //set menu
    [statusItem setMenu:theMenu];
    
    [self fillData];
}

-(void)setQuickConvertString {
    NSMutableString* hotKey = [NSMutableString stringWithString:@""];
    bool hasAdd = false;
    if (convertToolHotKey & 0x100) {
        [hotKey appendString:@"⌃"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x200) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌥"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x400) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⌘"];
        hasAdd = true;
    }
    if (convertToolHotKey & 0x800) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        [hotKey appendString:@"⇧"];
        hasAdd = true;
    }
    
    unsigned short k = ((convertToolHotKey>>24) & 0xFF);
    if (k != 0xFE) {
        if (hasAdd)
            [hotKey appendString:@" + "];
        if (k == kVK_Space)
            [hotKey appendFormat:@"%@", @"␣ "];
        else
            [hotKey appendFormat:@"%c", k];
    }
    [mnuQuickConvert setTitle: hasAdd ? [NSString stringWithFormat:@"Chuyển mã nhanh - [%@]", [hotKey uppercaseString]] : @"Chuyển mã nhanh"];
}

-(void)loadDefaultConfig {
    vLanguage = 1; [[NSUserDefaults standardUserDefaults] setInteger:vLanguage forKey:@"InputMethod"];
    vInputType = 0; [[NSUserDefaults standardUserDefaults] setInteger:vInputType forKey:@"InputType"];
    vFreeMark = 0; [[NSUserDefaults standardUserDefaults] setInteger:vFreeMark forKey:@"FreeMark"];
    vCheckSpelling = 1; [[NSUserDefaults standardUserDefaults] setInteger:vCheckSpelling forKey:@"Spelling"];
    vCodeTable = 0; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"CodeTable"];
    vSwitchKeyStatus = DEFAULT_SWITCH_STATUS; [[NSUserDefaults standardUserDefaults] setInteger:vCodeTable forKey:@"SwitchKeyStatus"];
    vQuickTelex = 0; [[NSUserDefaults standardUserDefaults] setInteger:vQuickTelex forKey:@"QuickTelex"];
    vUseModernOrthography = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseModernOrthography forKey:@"ModernOrthography"];
    vRestoreIfWrongSpelling = 0; [[NSUserDefaults standardUserDefaults] setInteger:vRestoreIfWrongSpelling forKey:@"RestoreIfInvalidWord"];
    vFixRecommendBrowser = 1; [[NSUserDefaults standardUserDefaults] setInteger:vFixRecommendBrowser forKey:@"FixRecommendBrowser"];
    vUseMacro = 1; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacro forKey:@"UseMacro"];
    vUseMacroInEnglishMode = 0; [[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"UseMacroInEnglishMode"];
    vSendKeyStepByStep = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUseMacroInEnglishMode forKey:@"SendKeyStepByStep"];
    vUseSmartSwitchKey = 1;[[NSUserDefaults standardUserDefaults] setInteger:vUseSmartSwitchKey forKey:@"UseSmartSwitchKey"];
    vUpperCaseFirstChar = 0;[[NSUserDefaults standardUserDefaults] setInteger:vUpperCaseFirstChar forKey:@"UpperCaseFirstChar"];
    vTempOffSpelling = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffSpelling forKey:@"vTempOffSpelling"];
    vAllowConsonantZFWJ = 0;[[NSUserDefaults standardUserDefaults] setInteger:vAllowConsonantZFWJ forKey:@"vAllowConsonantZFWJ"];
    vQuickStartConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickStartConsonant forKey:@"vQuickStartConsonant"];
    vQuickEndConsonant = 0;[[NSUserDefaults standardUserDefaults] setInteger:vQuickEndConsonant forKey:@"vQuickEndConsonant"];
    vRememberCode = 1;[[NSUserDefaults standardUserDefaults] setInteger:vRememberCode forKey:@"vRememberCode"];
    vOtherLanguage = 1;[[NSUserDefaults standardUserDefaults] setInteger:vOtherLanguage forKey:@"vOtherLanguage"];
    vTempOffOpenKey = 0;[[NSUserDefaults standardUserDefaults] setInteger:vTempOffOpenKey forKey:@"vTempOffOpenKey"];
    vShowIconOnDock = 0;[[NSUserDefaults standardUserDefaults] setInteger:vShowIconOnDock forKey:@"vShowIconOnDock"];
    vFixChromiumBrowser = 0;[[NSUserDefaults standardUserDefaults] setInteger:vFixChromiumBrowser forKey:@"vFixChromiumBrowser"];
    vPerformLayoutCompat = 0;[[NSUserDefaults standardUserDefaults] setInteger:vPerformLayoutCompat forKey:@"vPerformLayoutCompat"];

    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"GrayIcon"];
    [[NSUserDefaults standardUserDefaults] setInteger:1 forKey:@"RunOnStartup"];

    [self fillData];
    [viewController fillData];
}

-(void)setRunOnStartup:(BOOL)val {
    CFStringRef appId = (__bridge CFStringRef)@"com.tuyenmai.OpenKeyHelper";
    SMLoginItemSetEnabled(appId, val);
}

-(void)setGrayIcon:(BOOL)val {
    [self fillData];
}

-(void)showIconOnDock:(BOOL)val {
    [NSApp setActivationPolicy: val ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
}

#pragma mark -StatusBar menu data

- (void)setInputTypeMenu:(NSMenuItem*) parent {
    //sub for Kieu Go
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuTelex = [sub addItemWithTitle:@"Telex" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuTelex.tag = 0;
    mnuVNI = [sub addItemWithTitle:@"VNI" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuVNI.tag = 1;
    mnuSimpleTelex1 = [sub addItemWithTitle:@"Simple Telex 1" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex1.tag = 2;
    mnuSimpleTelex2 = [sub addItemWithTitle:@"Simple Telex 2" action:@selector(onInputTypeSelected:) keyEquivalent:@""];
    mnuSimpleTelex2.tag = 3;
    [theMenu setSubmenu:sub forItem:parent];
}

- (void)setCodeMenu:(NSMenuItem*) parent {
    //sub for Code
    NSMenu *sub = [[NSMenu alloc] initWithTitle:@""];
    [sub setAutoenablesItems:NO];
    mnuUnicodeComposite = [sub addItemWithTitle:@"Unicode tổ hợp" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuUnicodeComposite.tag = 3;
    mnuVietnameseLocaleCP1258 = [sub addItemWithTitle:@"Vietnamese Locale CP 1258" action:@selector(onCodeSelected:) keyEquivalent:@""];
    mnuVietnameseLocaleCP1258.tag = 4;
    
    [theMenu setSubmenu:sub forItem:parent];
}

- (void) fillData {
    //fill data
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    NSInteger grayIcon = [[NSUserDefaults standardUserDefaults] integerForKey:@"GrayIcon"];
    if (intInputMethod == 1) {
        [menuInputMethod setState:NSControlStateValueOn];
        statusItem.button.image = [NSImage imageNamed:@"Status"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlighted"];
    } else {
        [menuInputMethod setState:NSControlStateValueOff];
        statusItem.button.image = [NSImage imageNamed:@"StatusEng"];
        [statusItem.button.image setTemplate:(grayIcon ? YES : NO)];
        statusItem.button.alternateImage = [NSImage imageNamed:@"StatusHighlightedEng"];
    }
    vLanguage = (int)intInputMethod;
    id autoSwitch = [[NSUserDefaults standardUserDefaults] objectForKey:@"AutoSwitchByTyping"];
    vAutoSwitchByTyping = autoSwitch == nil ? 1 : [autoSwitch intValue];
    [mnuAutoSwitch setState:(vAutoSwitchByTyping ? NSControlStateValueOn : NSControlStateValueOff)];
    [mnuAutoSwitch setEnabled:(vInputType != 1)]; // Telex family only
    
    NSInteger intInputType = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputType"];
    [mnuTelex setState:NSControlStateValueOff];
    [mnuVNI setState:NSControlStateValueOff];
    [mnuSimpleTelex1 setState:NSControlStateValueOff];
    [mnuSimpleTelex2 setState:NSControlStateValueOff];
    if (intInputType == 0) {
        [mnuTelex setState:NSControlStateValueOn];
    } else if (intInputType == 1) {
        [mnuVNI setState:NSControlStateValueOn];
    } else if (intInputType == 2) {
        [mnuSimpleTelex1 setState:NSControlStateValueOn];
    } else if (intInputType == 3) {
        [mnuSimpleTelex2 setState:NSControlStateValueOn];
    }
    vInputType = (int)intInputType;
    
    NSInteger intSwitchKeyStatus = [[NSUserDefaults standardUserDefaults] integerForKey:@"SwitchKeyStatus"];
    vSwitchKeyStatus = (int)intSwitchKeyStatus;
    if (vSwitchKeyStatus == 0)
        vSwitchKeyStatus = DEFAULT_SWITCH_STATUS;
    
    NSInteger intCode = [[NSUserDefaults standardUserDefaults] integerForKey:@"CodeTable"];
    [mnuUnicode setState:NSControlStateValueOff];
    [mnuTCVN setState:NSControlStateValueOff];
    [mnuVNIWindows setState:NSControlStateValueOff];
    [mnuUnicodeComposite setState:NSControlStateValueOff];
    [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOff];
    if (intCode == 0) {
        [mnuUnicode setState:NSControlStateValueOn];
    } else if (intCode == 1) {
        [mnuTCVN setState:NSControlStateValueOn];
    } else if (intCode == 2) {
        [mnuVNIWindows setState:NSControlStateValueOn];
    } else if (intCode == 3) {
        [mnuUnicodeComposite setState:NSControlStateValueOn];
    } else if (intCode == 4) {
        [mnuVietnameseLocaleCP1258 setState:NSControlStateValueOn];
    }
    vCodeTable = (int)intCode;
    
    //
    NSInteger intRunOnStartup = [[NSUserDefaults standardUserDefaults] integerForKey:@"RunOnStartup"];
    [self setRunOnStartup:intRunOnStartup ? YES : NO];

}

-(void)onImputMethodChanged:(BOOL)willNotify {
    NSInteger intInputMethod = [[NSUserDefaults standardUserDefaults] integerForKey:@"InputMethod"];
    if (intInputMethod == 0)
        intInputMethod = 1;
    else
        intInputMethod = 0;
    vLanguage = (int)intInputMethod;
    [[NSUserDefaults standardUserDefaults] setInteger:intInputMethod forKey:@"InputMethod"];

    [self fillData];
    [viewController fillData];
    
    if (willNotify)
        OnInputMethodChanged();
}

#pragma mark -StatusBar menu action
- (void)onAutoSwitchSelected {
    vAutoSwitchByTyping = vAutoSwitchByTyping ? 0 : 1;
    [[NSUserDefaults standardUserDefaults] setInteger:vAutoSwitchByTyping forKey:@"AutoSwitchByTyping"];
    [self fillData];
}

- (void)onInputMethodSelected {
    [self onImputMethodChanged:YES];
    TLManual(@"menu", vLanguage);
}

- (void)onInputTypeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onInputTypeSelectedIndex:(int)menuItem.tag];
}

- (void)onInputTypeSelectedIndex:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"InputType"];
    vInputType = index;
    [self fillData];
    [viewController fillData];
}

- (void)onCodeTableChanged:(int)index {
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"CodeTable"];
    vCodeTable = index;
    [self fillData];
    [viewController fillData];
    OnTableCodeChange();
}

- (void)onCodeSelected:(id)sender {
    NSMenuItem *menuItem = (NSMenuItem*) sender;
    [self onCodeTableChanged:(int)menuItem.tag];
}

-(void)onConvertTool {
    if (_convertWC == nil) {
        _convertWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"ConvertWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_convertWC.window isVisible])
        return;
    [_convertWC.window makeKeyAndOrderFront:nil];
    [_convertWC.window setLevel:NSFloatingWindowLevel];
}

-(void)onQuickConvert {
    if ([OpenKeyManager quickConvert]) {
        if (!convertToolDontAlertWhenCompleted) {
            [OpenKeyManager showMessage: nil message:@"Chuyển mã thành công!" subMsg:@"Kết quả đã được lưu trong clipboard."];
        }
    } else {
        [OpenKeyManager showMessage: nil message:@"Không có dữ liệu trong clipboard!" subMsg:@"Hãy sao chép một đoạn text để chuyển đổi!"];
    }
}

-(void) onControlPanelSelected {
    if (_mainWC == nil) {
        _mainWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"OpenKey"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_mainWC.window isVisible]) {
        return;
    }
    [_mainWC.window makeKeyAndOrderFront:nil];
    [_mainWC.window setLevel:NSFloatingWindowLevel];
}

-(void) onTypingLogSelected {
    if (_logWC == nil) _logWC = [[TypingLogWindowController alloc] init];
    [_logWC reload];
    [_logWC.window center];
    [_logWC.window makeKeyAndOrderFront:nil];
    [_logWC.window setLevel:NSFloatingWindowLevel];
    [NSApp activateIgnoringOtherApps:YES];
}

-(void) onMacroSelected {
    if (_macroWC == nil) {
        _macroWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"MacroWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_macroWC.window isVisible])
        return;
    
    [_macroWC.window makeKeyAndOrderFront:nil];
    [_macroWC.window setLevel:NSFloatingWindowLevel];
}

-(void) onAboutSelected {
    if (_aboutWC == nil) {
        _aboutWC = [[NSStoryboard storyboardWithName:@"Main" bundle:nil] instantiateControllerWithIdentifier:@"AboutWindow"];
    }
    //[OpenKeyManager showDockIcon:YES];
    if ([_aboutWC.window isVisible])
        return;

    [_aboutWC.window makeKeyAndOrderFront:nil];
    [_aboutWC.window setLevel:NSFloatingWindowLevel];
}

#pragma mark -Short key event
-(void)onSwitchLanguage {
    [self onInputMethodSelected];
    [viewController fillData];
}

#pragma mark Reset OpenKey after mac computer awake
-(void)receiveWakeNote: (NSNotification*)note {
    [OpenKeyManager initEventTap];
}

-(void)receiveSleepNote: (NSNotification*)note {
    [OpenKeyManager stopEventTap];
}

-(void)receiveActiveSpaceChanged: (NSNotification*)note {
    RequestNewSession();
}

-(void)activeAppChanged: (NSNotification*)note {
    TLAppChanged();
    OnFocusChanged();
    RequestNewSession();
    if (vUseSmartSwitchKey && [OpenKeyManager isInited]) {
        OnActiveAppChanged();
    }
}

-(void)registerSupportedNotification {
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveWakeNote:)
                                                               name: NSWorkspaceDidWakeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveSleepNote:)
                                                               name: NSWorkspaceWillSleepNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(receiveActiveSpaceChanged:)
                                                               name: NSWorkspaceActiveSpaceDidChangeNotification object: NULL];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                           selector: @selector(activeAppChanged:)
                                                               name: NSWorkspaceDidActivateApplicationNotification object: NULL];
}
@end
