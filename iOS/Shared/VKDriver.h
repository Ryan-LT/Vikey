// Objective-C face of Engine/Driver for the keyboard extension.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface VKEditResult : NSObject
@property (nonatomic) NSInteger deleteCount;     // characters to delete before the cursor
@property (nonatomic, copy) NSString *text;      // then insert this
@property (nonatomic) BOOL languageChanged;
@end

@interface VKDriver : NSObject
/** 1 = Tiếng Việt, 0 = English. */
@property (nonatomic) NSInteger language;
@property (nonatomic) BOOL autoSwitch;
@property (nonatomic) double pauseAfterManual;
@property (nonatomic) BOOL spelling;
@property (nonatomic) BOOL restoreIfInvalid;
@property (nonatomic) BOOL modernOrthography;

/** One typed character: a letter, digit, punctuation, space or "\n". */
- (VKEditResult *)typeCharacter:(NSString *)character now:(double)now;
- (VKEditResult *)backspaceAt:(double)now;
/** The VI/EN key. */
- (void)manualSwitchAt:(double)now;
/** The cursor moved or the field changed. */
- (void)resetContext;
@end

NS_ASSUME_NONNULL_END
