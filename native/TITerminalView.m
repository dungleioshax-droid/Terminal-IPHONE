//
//  TITerminalView.m
//  Draws the visible slice of the terminal grid with CoreGraphics.
//
#import "TITerminalView.h"

@interface TITerminalView () <UIScrollViewDelegate> {
	UIFont *_font;
	UIFont *_boldFont;
	UIFont *_italicFont;
	UIFont *_boldItalicFont;
	BOOL _pinning;
}
@end

@implementation TITerminalView

#pragma mark - Setup

- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.backgroundColor = [UIColor blackColor];
		self.opaque = YES;
		self.alwaysBounceVertical = NO;
		self.showsVerticalScrollIndicator = YES;
		self.showsHorizontalScrollIndicator = NO;
		self.delaysContentTouches = NO;
		if (@available(iOS 11.0, *)) {
			self.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
		}
		self.delegate = self;
		self.followsOutput = YES;
		_defaultForegroundColor = [UIColor colorWithRed:0.85 green:0.87 blue:0.87 alpha:1.0];
		_defaultBackgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1.0];
		[self applyFontNamed:@"Menlo"];
	}
	return self;
}

- (void)applyFontNamed:(NSString *)family {
	CGFloat size = 12.0;
	_font = [UIFont fontWithName:[family stringByAppendingString:@"-Regular"] size:size];
	if (!_font) {
		if (@available(iOS 13.0, *)) {
			_font = [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular];
		} else {
			_font = [UIFont fontWithName:@"Courier" size:size];
		}
	}
	_boldFont = [UIFont fontWithName:[family stringByAppendingString:@"-Bold"] size:size] ?: _font;
	_italicFont = [UIFont fontWithName:[family stringByAppendingString:@"-Italic"] size:size] ?: _font;
	_boldItalicFont = [UIFont fontWithName:[family stringByAppendingString:@"-BoldItalic"] size:size] ?: _boldFont;

	NSString *probe = @"M";
	CGSize sizeProbe = [probe sizeWithAttributes:@{NSFontAttributeName : _font}];
	_charWidth = sizeProbe.width;
	if (_charWidth <= 0) _charWidth = size * 0.6;
	_rowHeight = ceil(_font.lineHeight);
	if (_rowHeight < 1) _rowHeight = size + 4;
	[self setNeedsDisplay];
}

#pragma mark - Layout helpers

- (void)setBuffer:(TITerminalBuffer *)buffer {
	_buffer = buffer;
	[self reload];
}

- (void)reload {
	// Coalesced display; this is what finally triggers drawRect().
	[self refreshContentSize];
	if (self.followsOutput) [self pinToBottom];
	[self setNeedsDisplay];
}

- (void)didMoveToWindow {
	[super didMoveToWindow];
	// Ensure font metrics exist even if reload ran before the view was sized.
	if (_rowHeight <= 0) [self applyFontNamed:@"Menlo"];
}

- (void)pinToBottom {
	if (self.bounds.size.height <= 0) return;
	CGFloat visible = self.bounds.size.height - self.contentInset.bottom;
	CGFloat target = MAX(0, self.contentSize.height - visible);
	if (fabs(self.contentOffset.y - target) < 0.5) return;
	_pinning = YES;
	[self setContentOffset:CGPointMake(self.contentOffset.x, target) animated:NO];
	_pinning = NO;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
	(void)scrollView;
	// Only user-driven scrolling changes the follow state; our own pinning does not.
	if (_pinning || self.isDragging || self.isDecelerating) {
		self.followsOutput = [self isAtBottom];
	}
}

- (void)refreshContentSize {
	NSInteger lines = self.buffer ? self.buffer.displayLineCount : 0;
	CGFloat width = MAX(self.bounds.size.width, 1);
	self.contentSize = CGSizeMake(width, lines * _rowHeight);
}

- (BOOL)isAtBottom {
	if (_rowHeight <= 0) return YES;
	CGFloat visibleBottom = self.contentOffset.y + self.bounds.size.height - self.contentInset.bottom;
	CGFloat maxOffset = self.contentSize.height - self.contentInset.bottom;
	CGFloat target = MAX(0, maxOffset);
	return visibleBottom >= target - 1.5 * _rowHeight;
}

- (void)scrollToBottomAnimated:(BOOL)animated {
	CGFloat target = MAX(0, self.contentSize.height - (self.bounds.size.height - self.contentInset.bottom));
	[self setContentOffset:CGPointMake(self.contentOffset.x, target) animated:animated];
}

- (void)layoutSubviews {
	[super layoutSubviews];
}

#pragma mark - Colors

static UIColor *TIColorFromIndex(uint32_t idx) {
	static UIColor *palette[256];
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		// xterm default palette.
		static const uint32_t base16[16] = {
			0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
			0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF,
		};
		for (uint32_t i = 0; i < 16; i++) {
			palette[i] = [UIColor colorWithRed:((base16[i] >> 16) & 0xFF) / 255.0
						     green:((base16[i] >> 8) & 0xFF) / 255.0
						      blue:(base16[i] & 0xFF) / 255.0
						     alpha:1.0];
		}
		static const uint32_t levels[6] = {0, 95, 135, 175, 215, 255};
		for (uint32_t i = 16; i < 232; i++) {
			uint32_t idx0 = i - 16;
			palette[i] = [UIColor colorWithRed:levels[idx0 / 36] / 255.0
						     green:levels[(idx0 / 6) % 6] / 255.0
						      blue:levels[idx0 % 6] / 255.0
						     alpha:1.0];
		}
		for (uint32_t i = 232; i < 256; i++) {
			CGFloat v = (8 + (i - 232) * 10) / 255.0;
			palette[i] = [UIColor colorWithRed:v green:v blue:v alpha:1.0];
		}
	});
	return palette[idx % 256];
}

- (UIColor *)colorForCode:(uint32_t)code isForeground:(BOOL)isForeground {
	if (TIColorIsDefault(code)) {
		return isForeground ? _defaultForegroundColor : _defaultBackgroundColor;
	}
	if (TIColorIsPalette(code)) {
		return TIColorFromIndex(TIColorPaletteIndex(code));
	}
	if (TIColorIsRGB(code)) {
		return [UIColor colorWithRed:((code >> 16) & 0xFF) / 255.0
					     green:((code >> 8) & 0xFF) / 255.0
					      blue:(code & 0xFF) / 255.0
					     alpha:1.0];
	}
	return isForeground ? _defaultForegroundColor : _defaultBackgroundColor;
}

- (UIFont *)fontForFlags:(uint8_t)flags {
	BOOL bold = (flags & TIFlagBold) != 0;
	BOOL italic = (flags & TIFlagItalic) != 0;
	if (bold && italic) return _boldItalicFont;
	if (bold) return _boldFont;
	if (italic) return _italicFont;
	return _font;
}

#pragma mark - Drawing

static void AppendUTF32(NSMutableString *string, uint32_t cp) {
	if (cp == 0) return;
	if (cp <= 0xFFFF) {
		[string appendFormat:@"%C", (unichar)cp];
	} else if (cp <= 0x10FFFF) {
		unichar hi = (unichar)(0xD800 + ((cp - 0x10000) >> 10));
		unichar lo = (unichar)(0xDC00 + ((cp - 0x10000) & 0x3FF));
		[string appendFormat:@"%C%C", hi, lo];
	}
}

- (void)drawRect:(CGRect)rect {
	if (_rowHeight <= 0) {
		// Guard against any code path that skipped font setup.
		if (!_font) [self applyFontNamed:@"Menlo"];
		if (_rowHeight <= 0) return;
	}
	[_defaultBackgroundColor setFill];
	UIRectFill(rect);

	TITerminalBuffer *buffer = self.buffer;
	if (!buffer) return;

	NSInteger total = buffer.displayLineCount;
	NSInteger first = (NSInteger)floor(CGRectGetMinY(rect) / _rowHeight);
	NSInteger last = (NSInteger)ceil(CGRectGetMaxY(rect) / _rowHeight);
	first = MAX(0, first);
	last = MIN(total, last);

	for (NSInteger index = first; index < last; index++) {
		[self drawDisplayLineAt:index];
	}

	// Cursor overlay.
	NSInteger cursorIndex = buffer.historyLineCount + buffer.cursorRow;
	if (buffer.cursorVisible && cursorIndex >= first && cursorIndex < last && buffer.columns > 0) {
		CGFloat x = buffer.cursorCol * _charWidth;
		if (x + _charWidth > CGRectGetMaxX(rect) + _charWidth) return;
		CGRect cursorRect = CGRectMake(x, cursorIndex * _rowHeight, _charWidth, _rowHeight);
		[[UIColor colorWithWhite:1.0 alpha:0.75] setFill];
		UIRectFill(cursorRect);
	}
}

- (void)drawDisplayLineAt:(NSInteger)index {
	TITerminalBuffer *buffer = self.buffer;
	TILine *line = [buffer displayLineAt:index];
	if (!line) return;
	NSInteger columns = buffer.columns;
	TICell *cells = line.cells;
	NSUInteger capacity = line.capacity;
	CGFloat originY = index * _rowHeight + [self textTopOffset];
	UIColor *runFg = nil, *runBg = nil;
	UIFont *runFont = nil;
	uint8_t runStyles = 0;
	NSMutableString *run = [NSMutableString string];
	CGFloat runX = 0;

	for (NSInteger col = 0; col < columns; col++) {
		TICell cell;
		if ((NSUInteger)col < capacity) {
			cell = cells[col];
		} else {
			memset(&cell, 0, sizeof(cell));
			cell.width = 1;
		}

		uint8_t width = cell.width;
		if (width == 0) continue; // continuation of a wide char (already drawn)

		UIColor *fg = [self colorForCode:cell.fg isForeground:YES];
		UIColor *bg = [self colorForCode:cell.bg isForeground:NO];
		if (cell.flags & TIFlagInverse) {
			UIColor *swap = fg;
			fg = bg;
			bg = swap;
		}
		if (cell.flags & TIFlagDim) {
			fg = [fg colorWithAlphaComponent:0.55];
		}
		UIFont *font = [self fontForFlags:cell.flags];

		if (width == 2) {
			// Wide glyphs break the run so positions stay exact.
			[self flushRun:run x:runX y:originY fg:runFg bg:runBg font:runFont flags:runStyles];
			[run setString:@""];
			runFg = nil;

			if (cell.ch == 0) {
				col++; // orphan continuation: skip
				continue;
			}
			if (!TIColorIsDefault(cell.bg)) {
				CGRect wide = CGRectMake(col * _charWidth, originY, _charWidth * 2, _rowHeight);
				[bg setFill];
				UIRectFill(wide);
			}
			NSMutableString *wideString = [NSMutableString string];
			AppendUTF32(wideString, cell.ch);
			NSDictionary *attrs = @{
				NSFontAttributeName : font,
				NSForegroundColorAttributeName : fg,
				NSBackgroundColorAttributeName : bg,
			};
			CGSize measured = [wideString sizeWithAttributes:attrs];
			[wideString drawAtPoint:CGPointMake(col * _charWidth, originY) withAttributes:attrs];
			if (cell.flags & TIFlagUnderline) {
				CGFloat underlineY = originY + _rowHeight - 2;
				[[UIColor colorWithWhite:1 alpha:0.9] setFill];
				UIRectFill(CGRectMake(col * _charWidth, underlineY, measured.width, 1));
			}
			col++; // consumes the continuation cell
			continue;
		}

		if (run.length == 0) {
			runX = col * _charWidth;
			runFg = fg;
			runBg = bg;
			runFont = font;
			runStyles = cell.flags & ~(TIFlagDim); // dim applied to color already
		} else if (runFg != fg || runBg != bg || runFont != font ||
			   (cell.flags & ~TIFlagDim) != (runStyles & ~TIFlagDim)) {
			[self flushRun:run x:runX y:originY fg:runFg bg:runBg font:runFont flags:runStyles];
			[run setString:@""];
			runX = col * _charWidth;
			runFg = fg;
			runBg = bg;
			runFont = font;
			runStyles = cell.flags & ~TIFlagDim;
		}
		AppendUTF32(run, cell.ch);
		if (cell.mark) AppendUTF32(run, cell.mark);
	}
	if (run.length > 0) {
		[self flushRun:run x:runX y:originY fg:runFg bg:runBg font:runFont flags:runStyles];
	}
}

- (void)flushRun:(NSString *)run
	       x:(CGFloat)x
		y:(CGFloat)y
	   fg:(UIColor *)fg
	   bg:(UIColor *)bg
	  font:(UIFont *)font
	 flags:(uint8_t)flags {
	if (run.length == 0) return;
	NSDictionary *attrs = @{
		NSFontAttributeName : font ?: _font,
		NSForegroundColorAttributeName : fg ?: _defaultForegroundColor,
		NSBackgroundColorAttributeName : bg ?: _defaultBackgroundColor,
	};
	CGSize measured = [run sizeWithAttributes:attrs];
	[run drawAtPoint:CGPointMake(x, y) withAttributes:attrs];
	if (flags & TIFlagUnderline) {
		CGFloat underlineY = y + _rowHeight - 2;
		[[UIColor colorWithWhite:1 alpha:0.9] setFill];
		UIRectFill(CGRectMake(x + 1, underlineY, MAX(1, measured.width - 1), 1));
	}
}

- (CGFloat)textTopOffset {
	return floor((_rowHeight - _font.lineHeight) / 2.0);
}

@end