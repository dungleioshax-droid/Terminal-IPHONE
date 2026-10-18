//
//  TITerminalParser.m
//  VT100/xterm-style escape sequence parser (state machine + UTF-8 decoder).
//
#import "TITerminalParser.h"

typedef NS_ENUM(NSInteger, TIParserState) {
	TIParseGround,
	TIParseEsc,          // after ESC
	TIParseEscCharset,   // ESC ( ) * + " / ESC SP / ESC #: consume 1 more
	TIParseCharsetHash,  // ESC # x, where x = 8 is DECALN
	TIParseCsi,          // ESC [
	TIParseOsc,          // ESC ] ... string
	TIParseOscEsc,       // ESC ] ... ESC  (await \)
	TIParseString,       // DCS/SOS/PM/APC
	TIParseStringEsc,    // ... ESC (await \)
};

static const NSInteger kMaxParams = 32;

@interface TITerminalParser () {
	TIParserState _state;
	int _params[kMaxParams];
	NSInteger _nparams;
	int _curParam;
	BOOL _curValid;
	char _privateMarker;   // '?', '>', '<', '=' or 0
	char _intermediate;    // last 0x20-0x2F byte
	NSMutableData *_strBuf; // OSC / DCS payload
	// UTF-8 decoding
	uint32_t _utf8CP;
	NSInteger _utf8Need;
	uint32_t _lastPrinted;
}
@end

@implementation TITerminalParser

- (instancetype)init {
	if ((self = [super init])) {
		_state = TIParseGround;
		_strBuf = [NSMutableData data];
		[self resetParserState];
	}
	return self;
}

- (void)resetParserState {
	_state = TIParseGround;
	_nparams = 0;
	_curParam = 0;
	_curValid = NO;
	_privateMarker = 0;
	_intermediate = 0;
	[_strBuf setLength:0];
	_utf8CP = 0;
	_utf8Need = 0;
	_lastPrinted = ' ';
}

- (void)reset {
	[self resetParserState];
	[self.buffer reset];
}

#pragma mark - Feed loop

- (void)feed:(NSData *)data {
	if (!self.buffer || data.length == 0) return;
	const uint8_t *bytes = data.bytes;
	NSUInteger len = data.length;

	for (NSUInteger i = 0; i < len; i++) {
		uint8_t c = bytes[i];

		if (_state == TIParseGround && _utf8Need > 0) {
			if ((c & 0xC0) == 0x80) {
				_utf8CP = (_utf8CP << 6) | (c & 0x3F);
				if (--_utf8Need == 0) {
					[self printChar:_utf8CP];
					_utf8CP = 0;
				}
				continue;
			}
			// Invalid continuation: drop the sequence and reprocess this byte.
			_utf8Need = 0;
			_utf8CP = 0;
			i--;
			continue;
		}

		switch (_state) {
			case TIParseGround:
				if (c < 0x80) {
					if (c == 0x1B) {
						_state = TIParseEsc;
					} else if (c < 0x20) {
						[self executeControl:c];
					} else {
						[self printChar:c];
					}
				} else if (c >= 0xC0 && c < 0xFE) {
					// Start of a multi-byte UTF-8 sequence.
					_utf8CP = (c >= 0xF0) ? (c & 0x07) : (c & 0x1F);
					_utf8Need = (c >= 0xF0) ? ((c >= 0xF8) ? 5 : 4) : ((c >= 0xE0) ? 3 : 2);
					_utf8Need -= 1;
				} else if (c == 0xFE || c == 0xFF) {
					// Stray byte; ignore.
				}
				// 0x80-0xBF stray continuation: ignore.
				break;

			case TIParseEsc:
				[self handleEsc:c];
				break;

			case TIParseEscCharset:
				[self consumeEscCharset:c];
				break;

			case TIParseCharsetHash:
				[self consumeEscHash:c];
				break;

			case TIParseCsi:
				[self handleCsiByte:c];
				break;

			case TIParseOsc:
				if (c == 0x07) {
					[self executeOsc];
					_state = TIParseGround;
				} else if (c == 0x1B) {
					_state = TIParseOscEsc;
				} else {
					[_strBuf appendBytes:&c length:1];
				}
				break;

			case TIParseOscEsc:
				if (c == '\\') {
					[self executeOsc];
					_state = TIParseGround;
				} else {
					// Not a string terminator: end OSC and reprocess as ESC.
					_state = TIParseEsc;
					i--;
				}
				break;

			case TIParseString:
				if (c == 0x07) {
					[_strBuf setLength:0];
					_state = TIParseGround;
				} else if (c == 0x1B) {
					_state = TIParseStringEsc;
				}
				// Payload otherwise discarded.
				break;

			case TIParseStringEsc:
				if (c == '\\' || c == 0x07) {
					[_strBuf setLength:0];
					_state = TIParseGround;
				} else {
					_state = TIParseEsc;
					i--;
				}
				break;
		}
	}
}

#pragma mark - Controls (C0)

- (void)executeControl:(uint8_t)c {
	TITerminalBuffer *b = self.buffer;
	switch (c) {
		case 0x08: [b backspace]; break;
		case 0x09: [b tabForward:1]; break;
		case 0x0A:
		case 0x0B:
		case 0x0C:
			[b lineFeed];
			if (b.newLineMode) [b carriageReturn];
			break;
		case 0x0D: [b carriageReturn]; break;
		case 0x0E:
		case 0x0F:
		case 0x00:
		case 0x07: // BEL
		default: break;
	}
}

#pragma mark - ESC

- (void)handleEsc:(uint8_t)c {
	TITerminalBuffer *b = self.buffer;
	switch (c) {
		case '[':
			_state = TIParseCsi;
			_nparams = 0;
			_curParam = 0;
			_curValid = NO;
			_privateMarker = 0;
			_intermediate = 0;
			break;
		case ']':
			_state = TIParseOsc;
			[_strBuf setLength:0];
			break;
		case 'P': // DCS
		case 'X': // SOS
		case '^': // PM
		case '_': // APC
			_state = TIParseString;
			[_strBuf setLength:0];
			break;
		case '7': [b saveCursor]; _state = TIParseGround; break;
		case '8': [b restoreCursor]; _state = TIParseGround; break;
		case 'D': [b lineFeed]; _state = TIParseGround; break;                 // IND
		case 'E': [b nextLines:1]; _state = TIParseGround; break;              // NEL
		case 'M': [b reverseIndex]; _state = TIParseGround; break;             // RI
		case 'H': [b setCursorColumn:b.cursorCol]; _state = TIParseGround; break; // HTS (tabs are fixed every 8)
		case 'c': [self reset]; _state = TIParseGround; break;                 // RIS
		case '=':
		case '>':
		case '\\': // ST alone
			_state = TIParseGround;
			break;
		case '(':
		case ')':
		case '*':
		case '+':
		case '"':
		case ' ':
			_state = TIParseEscCharset;
			break;
		case '#':
			_state = TIParseCharsetHash;
			break;
		default:
			_state = TIParseGround;
			break;
	}
}

- (void)consumeEscCharset:(uint8_t)c {
	(void)c;
	// Designated graphic character sets are accepted and ignored; the terminal
	// always renders UTF-8/US-ASCII.
	_state = TIParseGround;
}

- (void)consumeEscHash:(uint8_t)c {
	if (c == '8') {
		[self.buffer fillWithChar:'E']; // DECALN alignment test
	}
	_state = TIParseGround;
}

#pragma mark - OSC

- (void)executeOsc {
	NSString *payload = [[NSString alloc] initWithData:_strBuf encoding:NSUTF8StringEncoding];
	if (!payload) payload = @"";
	[_strBuf setLength:0];
	NSUInteger sep = [payload rangeOfString:@";"].location;
	if (sep == NSNotFound) return;
	NSString *code = [payload substringToIndex:sep];
	if ([code isEqualToString:@"0"] || [code isEqualToString:@"2"]) {
		NSString *title = [payload substringFromIndex:sep + 1];
		if ([self.delegate respondsToSelector:@selector(terminalParserDidReceiveTitle:)]) {
			[self.delegate terminalParserDidReceiveTitle:title];
		}
	}
}

#pragma mark - CSI

- (void)handleCsiByte:(uint8_t)c {
	// Parameter bytes 0x30-0x3F (digits, ; : and private markers).
	if ((c >= '0' && c <= '9')) {
		int digit = c - '0';
		if (!_curValid) {
			_curValid = YES;
			_curParam = digit;
		} else {
			_curParam = _curParam * 10 + digit;
			if (_curParam > 99999) _curParam = 99999;
		}
		return;
	}
	if (c == ';' || c == ':') {
		[self pushParam:_curValid ? _curParam : -1];
		_curValid = NO;
		_curParam = 0;
		return;
	}
	if (c >= 0x3C && c <= 0x3F && _nparams == 0 && !_curValid && _privateMarker == 0) {
		_privateMarker = (char)c;
		return;
	}
	// Intermediate bytes 0x20-0x2F.
	if (c >= 0x20 && c <= 0x2F) {
		_intermediate = (char)c;
		[self pushParam:_curValid ? _curParam : -1];
		_curValid = NO;
		return;
	}
	if (c >= 0x40 && c <= 0x7E) {
		if (_curValid) [self pushParam:_curParam];
		_curValid = NO;
		[self dispatchCsi:(uint8_t)c];
		_state = TIParseGround;
		return;
	}
	// Unknown byte inside CSI: abandon the sequence.
	_state = TIParseGround;
}

- (void)pushParam:(int)value {
	if (_nparams < kMaxParams) {
		_params[_nparams++] = value;
	}
}

static int Value(NSInteger nparams, const int *params, NSInteger idx, int def) {
	if (idx < nparams && params[idx] >= 0) return params[idx];
	return def;
}

// Default 1 (movement counts) with empty params treated as 1.
static int Value1(NSInteger nparams, const int *params, NSInteger idx) {
	if (idx < nparams && params[idx] == 0) return 1;
	return Value(nparams, params, idx, 1);
}

// Default 0 (erase/etc counts).
static int Value0(NSInteger nparams, const int *params, NSInteger idx) {
	return Value(nparams, params, idx, 0);
}

- (void)dispatchCsi:(uint8_t)finalByte {
	TITerminalBuffer *b = self.buffer;
	const int *p = _params;
	NSInteger n = _nparams;

	switch (finalByte) {
		case 'A': [b cursorUp:Value1(n, p, 0)]; break;
		case 'B':
		case 'e': [b cursorDown:Value1(n, p, 0)]; break;
		case 'C':
		case 'a': [b cursorRight:Value1(n, p, 0)]; break;
		case 'D': [b cursorLeft:Value1(n, p, 0)]; break;
		case 'E': [b nextLines:Value1(n, p, 0)]; break;
		case 'F': [b previousLines:Value1(n, p, 0)]; break;
		case 'G':
		case '`': [b setCursorColumn:Value1(n, p, 0) - 1]; break;
		case 'H':
		case 'f': [b setCursorRow:Value1(n, p, 0) - 1 col:Value1(n, p, 1) - 1]; break;
		case 'I': [b tabForward:Value1(n, p, 0)]; break;
		case 'Z': [b tabBackward:Value1(n, p, 0)]; break;
		case 'J': [b eraseInDisplay:Value0(n, p, 0)]; break;
		case 'K': [b eraseInLine:Value0(n, p, 0)]; break;
		case 'L': [b insertLines:Value1(n, p, 0)]; break;
		case 'M': [b deleteLines:Value1(n, p, 0)]; break;
		case 'P': [b deleteCells:Value1(n, p, 0)]; break;
		case '@': [b insertCells:Value1(n, p, 0)]; break;
		case 'X': [b eraseCells:Value1(n, p, 0)]; break;
		case 'S': [b scrollUp:Value1(n, p, 0)]; break;
		case 'T': [b scrollDown:Value1(n, p, 0)]; break;
		case 'd': [b setCursorRow:Value1(n, p, 0) - 1 col:b.cursorCol]; break;
		case 'b': { // REP: repeat last printed character
			NSInteger count = Value1(n, p, 0);
			unsigned width = TICharWidth(_lastPrinted);
			while (count-- > 0) [b putChar:_lastPrinted width:(NSInteger)width];
			break;
		}
		case 'g': break; // tab clears: fixed stops, nothing to do
		case 'h': [self setModes:YES]; break;
		case 'l': [self setModes:NO]; break;
		case 'm': [self applySgr]; break;
		case 'r': { // DECSTBM
			NSInteger rows = b.rows;
			NSInteger top = Value1(n, p, 0) - 1;
			NSInteger bottom = (n > 1 && p[1] != -1) ? p[1] : (int)rows - 1;
			[b setScrollRegionTop:top bottom:bottom];
			break;
		}
		case 's': [b saveCursor]; break; // save (ANSI.SYS style)
		case 'u': [b restoreCursor]; break;
		case 'n': [self respondTo:n]; break;
		case 'c': [self respondWithData:[@"\e[?6c" dataUsingEncoding:NSASCIIStringEncoding]]; break; // DA
		case 't': break; // window manipulation: ignored
		default: break;  // never answer with an error (avoids echo loops)
	}
}

- (void)setModes:(BOOL)enable {
	TITerminalBuffer *b = self.buffer;
	NSInteger n = _nparams;
	for (NSInteger i = 0; i < n; i++) {
		int mode = _params[i];
		if (mode < 0) continue;
		if (_privateMarker == '?') {
			switch (mode) {
				case 1: b.appCursorKeys = enable; break;                       // DECCKM
				case 6: b.originMode = enable;                                 // DECOM
					[b setCursorRow:0 col:0];
					break;
				case 7: b.autoWrap = enable; break;                            // DECAWM
				case 25: b.cursorVisible = enable; break;                      // DECTCEM
				case 47:
				case 1047:
					if (enable) [b enterAltScreen]; else [b leaveAltScreen];
					break;
				case 1049:                                                      // alt + save/restore cursor
					if (enable) {
						[b saveCursor];
						[b enterAltScreen];
						[b setCursorRow:0 col:0];
					} else {
						[b leaveAltScreen];
						[b restoreCursor];
					}
					break;
				default: break; // mouse tracking, bracketed paste, ... ignored
			}
		} else {
			switch (mode) {
				case 4: b.insertMode = enable; break;   // IRM
				case 20: b.newLineMode = enable; break; // LNM
				default: break;
			}
		}
	}
}

- (void)applySgr {
	TITerminalBuffer *b = self.buffer;
	NSInteger n = _nparams;
	if (n == 0) {
		b.curFg = 0;
		b.curBg = 0;
		b.curFlags = 0;
		return;
	}
	for (NSInteger i = 0; i < n; i++) {
		int v = _params[i];
		if (v < 0) v = 0; // empty param == 0
		switch (v) {
			case 0:
				b.curFg = 0;
				b.curBg = 0;
				b.curFlags = 0;
				break;
			case 1: b.curFlags |= TIFlagBold; break;
			case 2: b.curFlags |= TIFlagDim; break;
			case 3: b.curFlags |= TIFlagItalic; break;
			case 4:
			case 21:
				b.curFlags |= TIFlagUnderline;
				break;
			case 7: b.curFlags |= TIFlagInverse; break;
			case 22: b.curFlags &= ~(TIFlagBold | TIFlagDim); break;
			case 23: b.curFlags &= ~TIFlagItalic; break;
			case 24: b.curFlags &= ~TIFlagUnderline; break;
			case 27: b.curFlags &= ~TIFlagInverse; break;
			case 39: b.curFg = 0; break;
			case 49: b.curBg = 0; break;
			case 38:
			case 48: {
				if (i + 1 >= n || _params[i + 1] < 0) break;
				int kind = _params[i + 1];
				if (kind == 5 && i + 2 < n && _params[i + 2] >= 0) {
					uint32_t color = TIColorPalette((uint32_t)_params[i + 2]);
					if (v == 38) b.curFg = color; else b.curBg = color;
					i += 2;
				} else if (kind == 2) {
					NSInteger cursor = i + 2;
					NSInteger remaining = n - cursor;
					if (remaining >= 4) cursor++; // optional colorspace id
					int r = (cursor < n) ? MAX(0, _params[cursor]) : 0;
					int g = (cursor + 1 < n) ? MAX(0, _params[cursor + 1]) : 0;
					int bl = (cursor + 2 < n) ? MAX(0, _params[cursor + 2]) : 0;
					uint32_t color = TIColorRGB((uint32_t)r, (uint32_t)g, (uint32_t)bl);
					if (v == 38) b.curFg = color; else b.curBg = color;
					i = MIN(cursor + 2, n - 1);
				}
				break;
			}
			default:
				if (v >= 30 && v <= 37) { b.curFg = TIColorPalette((uint32_t)(v - 30)); break; }
				if (v >= 40 && v <= 47) { b.curBg = TIColorPalette((uint32_t)(v - 40)); break; }
				if (v >= 90 && v <= 97) { b.curFg = TIColorPalette((uint32_t)(v - 90 + 8)); break; }
				if (v >= 100 && v <= 107) { b.curBg = TIColorPalette((uint32_t)(v - 100 + 8)); break; }
				break;
		}
	}
}

- (void)respondTo:(NSInteger)count {
	switch (Value0(_nparams, _params, 0)) {
		case 5: [self respondWithData:[@"\e[0n" dataUsingEncoding:NSASCIIStringEncoding]]; break;
		case 6: {
			TITerminalBuffer *b = self.buffer;
			NSInteger row = b.cursorRow + 1;
			if (b.originMode) row -= b.scrollTop;
			NSString *reply = [NSString stringWithFormat:@"\e[%ld;%ldR", (long)row, (long)(b.cursorCol + 1)];
			[self respondWithData:[reply dataUsingEncoding:NSASCIIStringEncoding]];
			break;
		}
		default: break;
	}
	(void)count;
}

- (void)respondWithData:(NSData *)data {
	[self.delegate terminalParserRespond:data];
}

#pragma mark - Printing

- (void)printChar:(uint32_t)cp {
	unsigned width = TICharWidth(cp);
	TITerminalBuffer *b = self.buffer;
	if (width == 0) {
		[b putCombiningMark:cp];
		return;
	}
	_lastPrinted = cp;
	[b putChar:cp width:(NSInteger)width];
}

@end