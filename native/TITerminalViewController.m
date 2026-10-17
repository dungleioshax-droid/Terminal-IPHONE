//
//  TITerminalViewController.m
//  Wires buffer + parser + PTY session + renderer + keyboard together.
//
#import "TITerminalViewController.h"
#import "TITerminalBuffer.h"
#import "TITerminalParser.h"
#import "TITerminalView.h"
#import "TIPTYSession.h"
#import "TIKeyboardInput.h"
#import "TILaunchLog.h"

@interface TITerminalViewController () <TITerminalParserDelegate, TIPTYSessionDelegate>
@property (nonatomic, strong) TITerminalView *terminalView;
@property (nonatomic, strong) TIKeyboardInput *keyboard;
@property (nonatomic, strong) TITerminalBuffer *buffer;
@property (nonatomic, strong) TITerminalParser *parser;
@property (nonatomic, strong) TIPTYSession *session;
@property (nonatomic, strong) NSArray<UIKeyCommand *> *hardwareKeyCommands;
@property (nonatomic, assign) CGFloat keyboardOverlap;
@property (nonatomic, assign) BOOL sessionStarted;
@property (nonatomic, assign) BOOL ctrlLatch;
// Ugly but decisive diagnostics: the navigation bar is drawn by UIKit, so it
// proves whether keys arrive even if our own renderer is broken.
@property (nonatomic, copy) NSString *statusDetail;
@property (nonatomic, assign) NSInteger keyCount;
@property (nonatomic, assign) BOOL titleFromShell;
@end

@implementation TITerminalViewController

#pragma mark - View lifecycle

- (void)updateStatus:(NSString *)detail {
	self.statusDetail = detail ?: @"";
	if (self.titleFromShell) return;
	self.navigationItem.title =
		[NSString stringWithFormat:@"%@ k%ld", self.statusDetail, (long)self.keyCount];
}

- (void)loadView {
	TILaunchLogMark(@"loadView");
	TITerminalView *view = [[TITerminalView alloc] initWithFrame:UIScreen.mainScreen.bounds];
	self.terminalView = view;
	self.view = view;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	TILaunchLogMark(@"viewDidLoad");

	self.buffer = [[TITerminalBuffer alloc] initWithColumns:40 rows:12];
	self.parser = [[TITerminalParser alloc] init];
	self.parser.buffer = self.buffer;
	self.parser.delegate = self;

	self.session = [[TIPTYSession alloc] init];
	self.session.delegate = self;

	self.terminalView.buffer = self.buffer;

	self.keyboard = [[TIKeyboardInput alloc] initWithFrame:CGRectMake(0, 0, 1, 1)];
	__weak typeof(self) weakSelf = self;
	self.keyboard.textHandler = ^(NSString *text) {
		[weakSelf sendText:text];
	};
	self.keyboard.backspaceHandler = ^{
		[weakSelf sendBytes:"\x7f" length:1];
	};
	self.keyboard.returnHandler = ^{
		[weakSelf sendBytes:"\r" length:1];
	};
	self.keyboard.actionHandler = ^(NSInteger key) {
		[weakSelf handleKey:key];
	};
	[self.view addSubview:self.keyboard];

	self.title = @"Terminal";
	[self updateStatus:@"boot"];
	self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
		initWithTitle:@"⌨"
		style:UIBarButtonItemStylePlain
		target:self
		action:@selector(showKeyboard)];
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
		initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
		target:self
		action:@selector(restartSession)];

	NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
	[center addObserver:self
		   selector:@selector(keyboardFrameWillChange:)
		       name:UIKeyboardWillChangeFrameNotification
		     object:nil];
	[center addObserver:self
		   selector:@selector(keyboardFrameWillHide:)
		       name:UIKeyboardWillHideNotification
		     object:nil];

	UITapGestureRecognizer *tap =
		[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(viewTapped:)];
	[self.view addGestureRecognizer:tap];

	// Visible breadcrumb: if this line never shows up, rendering is the problem,
	// not the shell. It also confirms which build is installed.
	[self appendLocalMessage:@"Terminal 2.0.3\r\n"];

	// First keystroke arrives as soon as the app opens.
	[self.keyboard becomeFirstResponder];
}

- (void)dealloc {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[self.session terminate];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];

	CGSize size = self.terminalView.bounds.size;
	if (size.width <= 0) return;

	CGFloat visibleHeight = size.height - self.keyboardOverlap;
	NSInteger columns = MAX(20, (NSInteger)floor(size.width / self.terminalView.charWidth));
	NSInteger rows = MAX(4, (NSInteger)floor(visibleHeight / self.terminalView.rowHeight));

	BOOL changed = (columns != self.buffer.columns || rows != self.buffer.rows);
	if (changed) {
		[self.buffer resizeColumns:columns rows:rows];
		[self.terminalView reload];
		if (self.sessionStarted && self.session.isRunning) {
			[self.session resizeColumns:columns rows:rows];
		}
	}
	if (!self.sessionStarted && self.terminalView.charWidth > 0) {
		self.sessionStarted = YES;
		[self startSession];
	}
}

#pragma mark - Session

- (void)startSession {
	NSString *root = nil;
	NSString *shell = [TIPTYSession resolveShell:&root];
	TILaunchLogMark(@"startSession: shell=%@ root=%@", shell ?: @"(none)", root ?: @"(rootful)");
	[self updateStatus:[NSString stringWithFormat:@"sh:%@", shell.lastPathComponent ?: @"?"]];
	if (!shell) {
		[self updateStatus:@"no shell"];
		[self appendLocalMessage:
			@"\r\nNo shell found on this device.\r\n"
			 @"Install zsh/bash (apt) or run \"terminal-iphone\" to bootstrap\r\n"
			 @"the Linux environment (Node.js via nvm, git, python3, ...).\r\n"];
		return;
	}

	NSString *home = NSHomeDirectory();
	NSString *user = NSUserName().length > 0 ? NSUserName() : @"mobile";
	if ([user hasPrefix:@"/"]) user = @"mobile"; // deny userns-style values
	NSArray<NSString *> *environment = @[
		[NSString stringWithFormat:@"PATH=%@", [TIPTYSession defaultPathWithRoot:root]],
		[NSString stringWithFormat:@"HOME=%@", home],
		[NSString stringWithFormat:@"USER=%@", user],
		[NSString stringWithFormat:@"LOGNAME=%@", user],
		[NSString stringWithFormat:@"SHELL=%@", shell],
		@"TERM=xterm-256color",
		@"COLORTERM=truecolor",
		@"LANG=en_US.UTF-8",
		@"TERM_PROGRAM=TerminalIPHONE",
		@"TMPDIR=/tmp",
	];

	NSError *error = nil;
	BOOL ok = [self.session startWithShell:shell
			       environment:					      environment
					      cwd:home
					    columns:self.buffer.columns
					      rows:self.buffer.rows
					     error:&error];
	if (!ok) {
		TILaunchLogMark(@"startSession FAILED: %@", error.localizedDescription ?: @"unknown");
		[self updateStatus:@"start failed"];
		[self appendLocalMessage:[NSString stringWithFormat:@"\r\nFailed to start shell: %@\r\n",
					    error.localizedDescription ?: @"unknown error"]];
		return;
	}
	TILaunchLogMark(@"session started pid=%d shell=%@", (int)self.session.processId, shell);
	[self updateStatus:[NSString stringWithFormat:@"%@ pid%d",
				  shell.lastPathComponent, (int)self.session.processId]];
	[self.terminalView scrollToBottomAnimated:NO];
}

- (void)restartSession {
	// Silence the old session completely before starting a fresh one.
	self.session.delegate = nil;
	[self.session terminate];
	self.session = [[TIPTYSession alloc] init];
	self.session.delegate = self;
	[self.parser reset];
	[self.terminalView reload];
	[self startSession];
}

#pragma mark - TIPTYSessionDelegate

- (void)session:(TIPTYSession *)session didReceiveData:(NSData *)data {
	(void)session;
	static BOOL loggedFirstChunk = NO;
	if (!loggedFirstChunk) {
		loggedFirstChunk = YES;
		TILaunchLogMark(@"first output chunk: %lu bytes", (unsigned long)data.length);
		[self updateStatus:[NSString stringWithFormat:@"%@ rx%lu",
				  self.statusDetail, (unsigned long)data.length]];
	}
	[self.parser feed:data];
	// reload() re-pins to the bottom while the user has not scrolled up.
	[self.terminalView reload];
}

- (void)sessionDidExit:(TIPTYSession *)session status:(int)status {
	(void)session;
	TILaunchLogMark(@"session exited, status=%d", status);
	int code = 0;
	if (WIFEXITED(status)) {
		code = WEXITSTATUS(status);
		[self appendLocalMessage:[NSString stringWithFormat:@"\r\n[process exited: %d]\r\n", code]];
	} else if (WIFSIGNALED(status)) {
		[self appendLocalMessage:
			[NSString stringWithFormat:@"\r\n[process killed by signal %d]\r\n", WTERMSIG(status)]];
	} else {
		[self appendLocalMessage:@"\r\n[session ended]\r\n"];
	}
	[self appendLocalMessage:@"Tap ↻ to start a new session.\r\n"];
}

#pragma mark - TITerminalParserDelegate

- (void)terminalParserRespond:(NSData *)response {
	[self.session sendData:response];
}

- (void)terminalParserDidReceiveTitle:(NSString *)title {
	if (title.length == 0) return;
	self.titleFromShell = YES;
	self.navigationItem.title = title;
}

#pragma mark - Input

static NSData *TransformWithCtrl(NSString *text) {
	unichar c = [text characterAtIndex:0];
	if (c >= 'a' && c <= 'z') {
		uint8_t byte = (uint8_t)(c & 0x1F);
		return [NSData dataWithBytes:&byte length:1];
	}
	if (c >= 'A' && c <= 'Z') {
		uint8_t byte = (uint8_t)(c & 0x1F);
		return [NSData dataWithBytes:&byte length:1];
	}
	switch (c) {
		case '@': { uint8_t b = 0x00; return [NSData dataWithBytes:&b length:1]; }
		case ' ': { uint8_t b = 0x00; return [NSData dataWithBytes:&b length:1]; }
		case '[': { uint8_t b = 0x1B; return [NSData dataWithBytes:&b length:1]; }
		case '\\': { uint8_t b = 0x1C; return [NSData dataWithBytes:&b length:1]; }
		case ']': { uint8_t b = 0x1D; return [NSData dataWithBytes:&b length:1]; }
		case '^': { uint8_t b = 0x1E; return [NSData dataWithBytes:&b length:1]; }
		case '_': { uint8_t b = 0x1F; return [NSData dataWithBytes:&b length:1]; }
		case '?': { uint8_t b = 0x7F; return [NSData dataWithBytes:&b length:1]; }
		default: return nil; // not a control combo: send unchanged
	}
}

- (void)sendText:(NSString *)text {
	if (text.length == 0) return;
	self.keyCount += 1;
	[self updateStatus:self.statusDetail];
	NSData *payload = nil;
	if (self.ctrlLatch && text.length == 1) {
		payload = TransformWithCtrl(text);
		[self setCtrlLatch:NO];
		if (!payload) payload = [[text substringToIndex:1]
					      dataUsingEncoding:NSUTF8StringEncoding];
	} else {
		// iOS keyboards may compose with combining marks; normalize so the
		// terminal grid sees one precomposed codepoint per cell.
		NSString *normalized = text.precomposedStringWithCanonicalMapping;
		payload = [normalized dataUsingEncoding:NSUTF8StringEncoding];
	}
	if (payload.length > 0) [self.session sendData:payload];
}

- (void)sendBytes:(const char *)bytes length:(NSUInteger)length {
	self.keyCount += 1;
	[self updateStatus:self.statusDetail];
	[self.session sendData:[NSData dataWithBytes:bytes length:length]];
}

- (void)handleKey:(NSInteger)key {
	NSString *sequence = nil;
	BOOL ctrl = self.ctrlLatch;
	switch (key) {
		case TIKeyEscape:
			sequence = @"\e";
			[self setCtrlLatch:NO];
			break;
		case TIKeyControl:
			[self setCtrlLatch:!self.ctrlLatch];
			return;
		case TIKeyTab:
			sequence = @"\t";
			[self setCtrlLatch:NO];
			break;
		case TIKeyUp:
		case TIKeyDown:
		case TIKeyLeft:
		case TIKeyRight: {
			NSString *letter = [self arrowLetterForKey:key];
			if (ctrl) {
				sequence = [NSString stringWithFormat:@"\e[1;5%@", letter];
			} else if (self.buffer.appCursorKeys) {
				sequence = [NSString stringWithFormat:@"\eO%@", letter];
			} else {
				sequence = [NSString stringWithFormat:@"\e[%@", letter];
			}
			[self setCtrlLatch:NO];
			break;
		}
		case TIKeyMinus: sequence = @"-"; break;
		case TIKeyPipe: sequence = @"|"; break;
		case TIKeySlash: sequence = @"/"; break;
		case TIKeyTilde: sequence = @"~"; break;
		default: return;
	}
	if (sequence.length > 0) {
		self.keyCount += 1;
		[self updateStatus:self.statusDetail];
		NSData *data = [sequence dataUsingEncoding:NSUTF8StringEncoding];
		[self.session sendData:data];
	}
}

- (NSString *)arrowLetterForKey:(NSInteger)key {
	switch (key) {
		case TIKeyUp: return @"A";
		case TIKeyDown: return @"B";
		case TIKeyRight: return @"C";
		case TIKeyLeft: return @"D";
		default: return @"A";
	}
}

- (void)setCtrlLatch:(BOOL)active {
	_ctrlLatch = active;
	[self.keyboard setCtrlLatchActive:active];
}

#pragma mark - Hardware keyboard

- (NSArray<UIKeyCommand *> *)keyCommands {
	if (!self.hardwareKeyCommands) {
		self.hardwareKeyCommands = @[
			[UIKeyCommand keyCommandWithInput:UIKeyInputUpArrow
					    modifierFlags:0
						   action:@selector(hardwareArrow:)],
			[UIKeyCommand keyCommandWithInput:UIKeyInputDownArrow
					    modifierFlags:0
						   action:@selector(hardwareArrow:)],
			[UIKeyCommand keyCommandWithInput:UIKeyInputLeftArrow
					    modifierFlags:0
						   action:@selector(hardwareArrow:)],
			[UIKeyCommand keyCommandWithInput:UIKeyInputRightArrow
					    modifierFlags:0
						   action:@selector(hardwareArrow:)],
		];
	}
	return self.hardwareKeyCommands;
}

- (void)hardwareArrow:(UIKeyCommand *)command {
	if ([command.input isEqualToString:UIKeyInputUpArrow]) [self handleKey:TIKeyUp];
	else if ([command.input isEqualToString:UIKeyInputDownArrow]) [self handleKey:TIKeyDown];
	else if ([command.input isEqualToString:UIKeyInputLeftArrow]) [self handleKey:TIKeyLeft];
	else if ([command.input isEqualToString:UIKeyInputRightArrow]) [self handleKey:TIKeyRight];
}

#pragma mark - Keyboard frame tracking

- (void)keyboardFrameWillChange:(NSNotification *)notification {
	[self applyKeyboardFrame:notification.userInfo[UIKeyboardFrameEndUserInfoKey]
		    notification:notification];
}

- (void)keyboardFrameWillHide:(NSNotification *)notification {
	[self applyKeyboardFrame:notification.userInfo[UIKeyboardFrameEndUserInfoKey]
		    notification:notification];
}

- (void)applyKeyboardFrame:(NSValue *)frameValue notification:(NSNotification *)notification {
	if (!frameValue) return;
	CGRect endFrame = [frameValue CGRectValue];
	CGRect frameInView = [self.view convertRect:endFrame fromView:nil];
	CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(frameInView));
	// Keep at least four rows visible under the keyboard.
	CGFloat maxOverlap = CGRectGetHeight(self.view.bounds) - 4 * self.terminalView.rowHeight;
	self.keyboardOverlap = MIN(overlap, maxOverlap);

	self.terminalView.contentInset = UIEdgeInsetsMake(0, 0, self.keyboardOverlap, 0);

	NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
	UIViewAnimationOptions curve =
		[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] unsignedIntegerValue] << 16;
	[UIView animateWithDuration:duration
			      delay:0
			    options:curve | UIViewAnimationOptionBeginFromCurrentState
			 animations:^{
				 [self.view setNeedsLayout];
				 [self.view layoutIfNeeded];
			 }
			 completion:^(BOOL finished) {
				 (void)finished;
				 if ([self.terminalView isAtBottom]) {
					 [self.terminalView scrollToBottomAnimated:NO];
				 }
			 }];
}

#pragma mark - Actions

- (void)showKeyboard {
	[self.keyboard becomeFirstResponder];
}

- (void)viewTapped:(UITapGestureRecognizer *)recognizer {
	(void)recognizer;
	if (!self.keyboard.isFirstResponder) [self.keyboard becomeFirstResponder];
}

- (void)appendLocalMessage:(NSString *)message {
	NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
	[self.parser feed:data];
	[self.terminalView reload];
	if ([self.terminalView isAtBottom]) [self.terminalView scrollToBottomAnimated:NO];
}

@end