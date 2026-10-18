//
//  TIKeyboardInput.h
//  First responder that receives software-keyboard input, plus a scrollable
//  accessory bar with terminal-only keys (esc, ctrl, tab, arrows…).
//
//  This is a UIView implementing UIKeyInput rather than a UITextField: UIKit
//  routes keystrokes straight to insertText:/deleteBackward: for a UIKeyInput
//  responder, whereas a UITextField keeps its own text machinery (and marked
//  text, which Vietnamese input methods use), so our insertText: could be
//  bypassed and no key ever reached the shell.
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

@interface TIKeyboardInput : UIView <UIKeyInput, UITextInputTraits>

// Declared here (not in a class extension) because the UITextInputTraits
// protocol already declares these; only the primary interface may restate them.
@property (nonatomic, assign) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic, assign) UITextAutocorrectionType autocorrectionType;
@property (nonatomic, assign) UITextSpellCheckingType spellCheckingType;
@property (nonatomic, assign) UITextSmartQuotesType smartQuotesType;
@property (nonatomic, assign) UITextSmartDashesType smartDashesType;
@property (nonatomic, assign) UITextSmartInsertDeleteType smartInsertDeleteType;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, assign) UIKeyboardAppearance keyboardAppearance;
@property (nonatomic, assign) UIReturnKeyType returnKeyType;
@property (nonatomic, assign, getter=isSecureTextEntry) BOOL secureTextEntry;
@property (nonatomic, assign) BOOL enablesReturnKeyAutomatically;
@property (nonatomic, copy, nullable) UITextContentType textContentType;

/// Raw text typed on the software keyboard (NFC applied by the controller).
@property (nonatomic, copy, nullable) void (^textHandler)(NSString *text);
@property (nonatomic, copy, nullable) void (^backspaceHandler)(void);
@property (nonatomic, copy, nullable) void (^returnHandler)(void);
/// Accessory bar button pressed; key is a TIKey value.
@property (nonatomic, copy, nullable) void (^actionHandler)(NSInteger key);

- (void)setCtrlLatchActive:(BOOL)active;
- (void)refreshFirstResponder;

@end

NS_ASSUME_NONNULL_END
