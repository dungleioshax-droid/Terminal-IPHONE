//
//  TIKeyboardInput.m
//
#import "TIKeyboardInput.h"

@implementation TIKeyboardInput {
	UIView *_accessory;
	UIButton *_ctrlButton;
	BOOL _ctrlActive;
}

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.backgroundColor = UIColor.clearColor;
		// Traits that keep the keyboard suitable for a terminal: no smart
		// punctuation, no autocorrect, no autocapitalisation.
		self.autocapitalizationType = UITextAutocapitalizationTypeNone;
		self.autocorrectionType = UITextAutocorrectionTypeNo;
		self.spellCheckingType = UITextSpellCheckingTypeNo;
		self.keyboardType = UIKeyboardTypeASCIICapable;
		self.keyboardAppearance = UIKeyboardAppearanceDark;
		self.returnKeyType = UIReturnKeyDefault;
		self.secureTextEntry = NO;
		self.enablesReturnKeyAutomatically = NO;
		self.textContentType = nil;
		if (@available(iOS 11.0, *)) {
			self.smartQuotesType = UITextSmartQuotesTypeNo;
			self.smartDashesType = UITextSmartDashesTypeNo;
			self.smartInsertDeleteType = UITextSmartInsertDeleteTypeNo;
		}
	}
	return self;
}

- (void)refreshFirstResponder {
	if (!self.isFirstResponder) [self becomeFirstResponder];
}

#pragma mark - Responder

- (BOOL)canBecomeFirstResponder {
	return YES;
}

#pragma mark - UIKeyInput

- (BOOL)hasText {
	// Always claim content so backspace keeps arriving as deleteBackward.
	return YES;
}

- (void)insertText:(NSString *)text {
	if (text.length == 0) return;
	// The return key delivers "\n" through this path.
	if ([text isEqualToString:@"\n"]) {
		if (self.returnHandler) self.returnHandler();
		return;
	}
	if (self.textHandler) self.textHandler(text);
}

- (void)deleteBackward {
	if (self.backspaceHandler) self.backspaceHandler();
}

#pragma mark - Editing actions

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
	// Paste is the only system action a terminal benefits from.
	return action == @selector(paste:);
}

- (void)paste:(id)sender {
	(void)sender;
	NSString *text = UIPasteboard.generalPasteboard.string;
	if (text.length > 0 && self.textHandler) self.textHandler(text);
}

#pragma mark - Ctrl latch

- (void)setCtrlLatchActive:(BOOL)active {
	_ctrlActive = active;
	_ctrlButton.backgroundColor = active
		? [UIColor colorWithRed:0.10 green:0.45 blue:0.95 alpha:1.0]
		: [UIColor colorWithWhite:0.22 alpha:1.0];
}

#pragma mark - Accessory bar

- (UIView *)inputAccessoryView {
	if (!_accessory) [self buildAccessory];
	return _accessory;
}

- (void)buildAccessory {
	CGRect screen = UIScreen.mainScreen.bounds;
	_accessory = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screen.size.width, 44)];
	_accessory.backgroundColor = [UIColor colorWithWhite:0.10 alpha:1.0];
	_accessory.autoresizingMask = UIViewAutoresizingFlexibleWidth;

	UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:_accessory.bounds];
	scroll.showsHorizontalScrollIndicator = NO;
	scroll.alwaysBounceHorizontal = YES;
	scroll.backgroundColor = _accessory.backgroundColor;
	scroll.autoresizingMask =
		UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[_accessory addSubview:scroll];

	CGFloat x = 6;
	x = [self addKeyTo:scroll title:@"esc" key:TIKeyEscape x:x width:38];
	_ctrlButton = nil;
	x = [self addKeyTo:scroll title:@"ctrl" key:TIKeyControl x:x width:46];
	_ctrlButton = (UIButton *)[scroll viewWithTag:TIKeyControl];
	x = [self addKeyTo:scroll title:@"tab" key:TIKeyTab x:x width:40];
	x = [self addKeyTo:scroll title:@"↑" key:TIKeyUp x:x width:32];
	x = [self addKeyTo:scroll title:@"↓" key:TIKeyDown x:x width:32];
	x = [self addKeyTo:scroll title:@"←" key:TIKeyLeft x:x width:32];
	x = [self addKeyTo:scroll title:@"→" key:TIKeyRight x:x width:32];
	x = [self addKeyTo:scroll title:@"-" key:TIKeyMinus x:x width:28];
	x = [self addKeyTo:scroll title:@"|" key:TIKeyPipe x:x width:28];
	x = [self addKeyTo:scroll title:@"/" key:TIKeySlash x:x width:28];
	x = [self addKeyTo:scroll title:@"~" key:TIKeyTilde x:x width:30];
	scroll.contentSize = CGSizeMake(x + 6, 44);
	[self setCtrlLatchActive:NO];
}

- (CGFloat)addKeyTo:(UIScrollView *)scroll
	       title:(NSString *)title
		 key:(NSInteger)key
		   x:(CGFloat)x
	      width:(CGFloat)width {
	UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
	button.frame = CGRectMake(x, 5, width, 34);
	[button setTitle:title forState:UIControlStateNormal];
	button.titleLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightMedium];
	[button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	button.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
	button.layer.cornerRadius = 5;
	button.tag = key;
	[button addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
	[scroll addSubview:button];
	return x + width + 5;
}

- (void)keyTapped:(UIButton *)sender {
	if (self.actionHandler) self.actionHandler(sender.tag);
}

@end
