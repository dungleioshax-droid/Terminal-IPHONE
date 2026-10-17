//
//  TIKeyboardInput.h
//  Hidden UITextField that stays first responder while the user types, plus a
//  scrollable accessory bar with terminal-only keys (esc, ctrl, tab, arrows…).
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, TIKey) {
	TIKeyEscape = 1,
	TIKeyControl,
	TIKeyTab,
	TIKeyUp,
	TIKeyDown,
	TIKeyLeft,
	TIKeyRight,
	TIKeyMinus,
	TIKeyPipe,
	TIKeySlash,
	TIKeyTilde,
};

@interface TIKeyboardInput : UITextField

/// Raw text typed on the software keyboard (NFC applied by the controller).
@property (nonatomic, copy, nullable) void (^textHandler)(NSString *text);
@property (nonatomic, copy, nullable) void (^backspaceHandler)(void);
@property (nonatomic, copy, nullable) void (^returnHandler)(void);
/// Accessory bar button pressed; key is a TIKey value.
@property (nonatomic, copy, nullable) void (^actionHandler)(NSInteger key);

- (void)setCtrlLatchActive:(BOOL)active;

@end

NS_ASSUME_NONNULL_END