//
//  TITerminalBuffer.m
//  Terminal screen model (fixed cell grid + scrollback).
//
#import "TITerminalBuffer.h"
#include <string.h>

static const NSUInteger kScrollbackCap = 2000;

static TICell TIBlankCell(uint32_t bg) {
	TICell c;
	memset(&c, 0, sizeof(c));
	c.width = 1;
	c.bg = bg;
	return c;
}

#pragma mark - Character width

unsigned TICharWidth(uint32_t cp) {
	if (cp < 0x20) return 1;
	// Combining marks / zero-width (covers Latin + Vietnamese diacritics,
	// variation selectors, joiners and Hangul tone marks).
	static const struct { uint32_t lo, hi; } zero[] = {
		{0x0300, 0x036F}, {0x0483, 0x0489}, {0x0591, 0x05BD}, {0x05BF, 0x05BF},
		{0x05C1, 0x05C2}, {0x05C4, 0x05C5}, {0x05C7, 0x05C7}, {0x0610, 0x061A},
		{0x064B, 0x065F}, {0x0670, 0x0670}, {0x06D6, 0x06DC}, {0x06DF, 0x06E4},
		{0x06E7, 0x06E8}, {0x06EA, 0x06ED}, {0x0711, 0x0711}, {0x0730, 0x074A},
		{0x07A6, 0x07B0}, {0x07EB, 0x07F3}, {0x0816, 0x0823}, {0x0825, 0x082D},
		{0x0859, 0x085B}, {0x0E31, 0x0E31}, {0x0E34, 0x0E3A}, {0x0E47, 0x0E4E},
		{0x135D, 0x135F}, {0x1A7F, 0x1A7F}, {0x1AB0, 0x1AFF}, {0x1DC0, 0x1DFF},
		{0x200C, 0x200D}, {0x2060, 0x2064}, {0x20D0, 0x20FF}, {0x2CEF, 0x2CF1},
		{0x302A, 0x302F}, {0x3099, 0x309A}, {0xA66F, 0xA672}, {0xA674, 0xA67D},
		{0xFE00, 0xFE0F}, {0xFE20, 0xFE2F}, {0xFEFF, 0xFEFF}, {0xE0100, 0xE01EF},
	};
	for (size_t i = 0; i < sizeof(zero) / sizeof(zero[0]); i++) {
		if (cp >= zero[i].lo && cp <= zero[i].hi) return 0;
	}
	// Wide: CJK, Hangul, fullwidth, most emoji and flag pairs.
	static const struct { uint32_t lo, hi; } wide[] = {
		{0x1100, 0x115F}, {0x2329, 0x232A}, {0x2E80, 0xA4CF}, {0xA960, 0xA97F},
		{0xAC00, 0xD7A3}, {0xF900, 0xFAFF}, {0xFE10, 0xFE19}, {0xFE30, 0xFE6F},
		{0xFF00, 0xFF60}, {0xFFE0, 0xFFE6}, {0x16FE0, 0x16FE4}, {0x17000, 0x18AFF},
		{0x1B000, 0x1B2FF}, {0x1F004, 0x1F004}, {0x1F0CF, 0x1F0CF},
		{0x1F18E, 0x1F18E}, {0x1F191, 0x1F19A}, {0x1F1E6, 0x1F1FF},
		{0x1F200, 0x1F2FF}, {0x1F300, 0x1F64F}, {0x1F680, 0x1F6FF},
		{0x1F7E0, 0x1F7FF}, {0x1F900, 0x1F9FF}, {0x1FA70, 0x1FAFF},
		{0x20000, 0x3FFFD},
	};
	for (size_t i = 0; i < sizeof(wide) / sizeof(wide[0]); i++) {
		if (cp >= wide[i].lo && cp <= wide[i].hi) return 2;
	}
	return 1;
}

#pragma mark - TILine

@implementation TILine {
	TICell *_cells;
	NSUInteger _capacity;
}

+ (instancetype)lineWithColumns:(NSUInteger)columns {
	TILine *line = [[TILine alloc] init];
	[line ensureCapacity:columns];
	return line;
}

- (NSUInteger)capacity {
	return _capacity;
}

- (TICell *)cells {
	return _cells;
}

- (void)ensureCapacity:(NSUInteger)columns {
	if (columns <= _capacity) return;
	_cells = realloc(_cells, columns * sizeof(TICell));
	for (NSUInteger i = _capacity; i < columns; i++) {
		_cells[i] = TIBlankCell(0);
	}
	_capacity = columns;
}

- (void)reset {
	for (NSUInteger i = 0; i < _capacity; i++) {
		_cells[i] = TIBlankCell(0);
	}
}

- (void)eraseRange:(NSRange)range withBackground:(uint32_t)bg {
	NSUInteger start = MIN(range.location, _capacity);
	NSUInteger end = MIN(range.location + range.length, _capacity);
	for (NSUInteger i = start; i < end; i++) {
		_cells[i] = TIBlankCell(bg);
	}
}

- (void)insertCellsAt:(NSUInteger)idx count:(NSUInteger)count {
	if (idx >= _capacity) return;
	NSUInteger n = MIN(count, _capacity - idx);
	NSUInteger movable = _capacity - idx - n;
	if (movable > 0) {
		memmove(_cells + idx + n, _cells + idx, movable * sizeof(TICell));
	}
	for (NSUInteger i = 0; i < n; i++) {
		_cells[idx + i] = TIBlankCell(0);
	}
}

- (void)deleteCellsAt:(NSUInteger)idx count:(NSUInteger)count {
	if (idx >= _capacity) return;
	NSUInteger n = MIN(count, _capacity - idx);
	NSUInteger movable = _capacity - idx - n;
	if (movable > 0) {
		memmove(_cells + idx, _cells + idx + n, movable * sizeof(TICell));
	}
	for (NSUInteger i = _capacity - n; i < _capacity; i++) {
		_cells[i] = TIBlankCell(0);
	}
}

- (void)dealloc {
	free(_cells);
}

@end

#pragma mark - TITerminalBuffer

@interface TITerminalBuffer () {
	NSMutableArray<TILine *> *_history;      // scrollback (primary screen only)
	NSMutableArray<TILine *> *_screen;
	NSMutableArray<TILine *> *_stashHistory; // alternate screen swap
	NSMutableArray<TILine *> *_stashScreen;
	NSInteger _columns, _rows;
	NSInteger _scrollTop, _scrollBottom;
	NSInteger _cursorRow, _cursorCol;
	NSInteger _lastRow, _lastCol;   // last printed cell (combining marks)
	NSInteger _savedRow, _savedCol;
	uint32_t _savedFg, _savedBg, _savedFlags;
	BOOL _savedOrigin;
	BOOL _pendingWrap;
}
@property (nonatomic, readwrite) NSInteger scrollTop;
@property (nonatomic, readwrite) NSInteger scrollBottom;
- (void)scrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom up:(NSInteger)n intoHistory:(BOOL)intoHistory;
- (void)scrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom down:(NSInteger)n;
@end

@implementation TITerminalBuffer

- (instancetype)initWithColumns:(NSInteger)columns rows:(NSInteger)rows {
	if ((self = [super init])) {
		_columns = MAX(1, columns);
		_rows = MAX(1, rows);
		_history = [NSMutableArray array];
		_screen = [NSMutableArray array];
		_lastRow = -1;
		[self reset];
	}
	return self;
}

#pragma mark Reset & resize

- (BOOL)altScreen {
	return _stashScreen != nil;
}

- (void)reset {
	if ([self altScreen]) {  // RIS always returns to the primary screen
		_stashHistory = nil;
		_stashScreen = nil;
		_history = [NSMutableArray array];
		_screen = [NSMutableArray array];
	}
	[_history removeAllObjects];
	[_screen removeAllObjects];
	for (NSInteger i = 0; i < _rows; i++) {
		[_screen addObject:[TILine lineWithColumns:(NSUInteger)MAX(2, _columns)]];
	}
	_cursorRow = 0;
	_cursorCol = 0;
	_lastRow = -1;
	_pendingWrap = NO;
	_scrollTop = 0;
	_scrollBottom = _rows - 1;
	_curFg = 0;
	_curBg = 0;
	_curFlags = 0;
	_autoWrap = YES;
	_cursorVisible = YES;
	_insertMode = NO;
	_originMode = NO;
	_appCursorKeys = NO;
	_newLineMode = NO;
	_savedRow = _savedCol = 0;
	_savedFg = _savedBg = _savedFlags = 0;
	_savedOrigin = NO;
}

- (void)resizeColumns:(NSInteger)columns rows:(NSInteger)rows {
	columns = MAX(1, columns);
	rows = MAX(1, rows);
	if (columns == _columns && rows == _rows) return;
	_columns = columns;
	_rows = rows;

	void (^grow)(TILine *) = ^(TILine *line) { [line ensureCapacity:(NSUInteger)columns]; };
	for (TILine *line in _history) grow(line);
	for (TILine *line in _stashHistory) grow(line);
	for (TILine *line in _screen) grow(line);
	for (TILine *line in _stashScreen) grow(line);

	// Adapt the screen row count, keeping the top anchored; dropped primary
	// rows move into scrollback.
	while ((NSInteger)_screen.count > rows) {
		TILine *line = _screen.firstObject;
		if (![self altScreen]) {
			[_history addObject:line];
			if (_history.count > kScrollbackCap) [_history removeObjectAtIndex:0];
		}
		[_screen removeObjectAtIndex:0];
	}
	while ((NSInteger)_screen.count < rows) {
		[_screen addObject:[TILine lineWithColumns:(NSUInteger)columns]];
	}

	_scrollTop = 0;
	_scrollBottom = _rows - 1;
	_cursorRow = MIN(MAX(_cursorRow, 0), rows - 1);
	_cursorCol = MIN(MAX(_cursorCol, 0), columns - 1);
	_pendingWrap = NO;
	_lastRow = -1;
}

#pragma mark Scroll region

- (void)setScrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom {
	if (top >= 0 && bottom > top && bottom < _rows) {
		_scrollTop = top;
		_scrollBottom = bottom;
	} else {
		_scrollTop = 0;
		_scrollBottom = _rows - 1;
	}
	// DECSTBM homes the cursor (origin-aware).
	_cursorRow = _originMode ? _scrollTop : 0;
	_cursorCol = 0;
	_pendingWrap = NO;
}

#pragma mark Cursor movement

- (void)setCursorRow:(NSInteger)row col:(NSInteger)col {
	NSInteger base = _originMode ? _scrollTop : 0;
	NSInteger limit = _originMode ? _scrollBottom : _rows - 1;
	NSInteger r = base + row;
	_cursorRow = MIN(MAX(r, base), limit);
	_cursorCol = MIN(MAX(col, 0), MAX(0, _columns - 1));
	_pendingWrap = NO;
}

- (void)setCursorColumn:(NSInteger)col {
	_cursorCol = MIN(MAX(col, 0), MAX(0, _columns - 1));
	_pendingWrap = NO;
}

- (void)cursorUp:(NSInteger)n {
	NSInteger floorY = (_cursorRow >= _scrollTop && _cursorRow <= _scrollBottom) ? _scrollTop : 0;
	_cursorRow = MAX(floorY, _cursorRow - MAX(1, n));
	_pendingWrap = NO;
}

- (void)cursorDown:(NSInteger)n {
	NSInteger ceiling = (_cursorRow >= _scrollTop && _cursorRow <= _scrollBottom) ? _scrollBottom : _rows - 1;
	_cursorRow = MIN(ceiling, _cursorRow + MAX(1, n));
	_pendingWrap = NO;
}

- (void)cursorLeft:(NSInteger)n {
	_cursorCol = MAX(0, _cursorCol - MAX(1, n));
	_pendingWrap = NO;
}

- (void)cursorRight:(NSInteger)n {
	_cursorCol = MIN(MAX(0, _columns - 1), _cursorCol + MAX(1, n));
	_pendingWrap = NO;
}

- (void)nextLines:(NSInteger)n {
	[self cursorDown:n];
	_cursorCol = 0;
	_pendingWrap = NO;
}

- (void)previousLines:(NSInteger)n {
	[self cursorUp:n];
	_cursorCol = 0;
	_pendingWrap = NO;
}

- (void)tabForward:(NSInteger)n {
	NSInteger count = MAX(1, n);
	while (count-- > 0) {
		if (_cursorCol >= _columns - 1) {
			_cursorCol = MAX(0, _columns - 1);
			break;
		}
		_cursorCol = MIN(_columns - 1, ((_cursorCol / 8) + 1) * 8);
	}
	_pendingWrap = NO;
}

- (void)tabBackward:(NSInteger)n {
	NSInteger count = MAX(1, n);
	while (count-- > 0 && _cursorCol > 0) {
		_cursorCol = MAX(0, ((_cursorCol - 1) / 8) * 8);
	}
	_pendingWrap = NO;
}

- (void)carriageReturn {
	_cursorCol = 0;
	_pendingWrap = NO;
}

- (void)backspace {
	if (_cursorCol > 0) _cursorCol--;
	_pendingWrap = NO;
}

- (void)lineFeed {
	if (_cursorRow < _scrollBottom) {
		_cursorRow++;
	} else if (_cursorRow == _scrollBottom) {
		[self scrollRegionTop:_scrollTop bottom:_scrollBottom up:1
				 intoHistory:(!_stashScreen && _scrollTop == 0)];
	} else if (_cursorRow < _rows - 1) {
		_cursorRow++;
	}
	_pendingWrap = NO;
}

- (void)reverseIndex {
	if (_cursorRow == _scrollTop) {
		[self scrollRegionTop:_scrollTop bottom:_scrollBottom down:1];
	} else if (_cursorRow > 0) {
		_cursorRow--;
	}
	_pendingWrap = NO;
}

#pragma mark Scrolling core

// Discard n lines at the top of [top..bottom], pulling blanks in at the bottom.
- (void)scrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom up:(NSInteger)n intoHistory:(BOOL)intoHistory {
	for (NSInteger i = 0; i < n; i++) {
		TILine *line = _screen[top];
		if (intoHistory && top == 0) {
			[_history addObject:line];
			if (_history.count > kScrollbackCap) [_history removeObjectAtIndex:0];
		}
		[_screen removeObjectAtIndex:top];
		[_screen insertObject:[TILine lineWithColumns:(NSUInteger)MAX(2, _columns)] atIndex:bottom];
	}
}

- (void)scrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom down:(NSInteger)n {
	for (NSInteger i = 0; i < n; i++) {
		[_screen insertObject:[TILine lineWithColumns:(NSUInteger)MAX(2, _columns)] atIndex:top];
		if (bottom + 1 < (NSInteger)_screen.count) {
			[_screen removeObjectAtIndex:bottom + 1];
		} else {
			[_screen removeLastObject];
		}
	}
}

- (void)scrollUp:(NSInteger)n {
	[self scrollRegionTop:_scrollTop bottom:_scrollBottom up:MAX(1, n)
			 intoHistory:(!_stashScreen && _scrollTop == 0)];
}

- (void)scrollDown:(NSInteger)n {
	[self scrollRegionTop:_scrollTop bottom:_scrollBottom down:MAX(1, n)];
}

#pragma mark Printing

- (void)putChar:(uint32_t)ch width:(NSInteger)width {
	if (_columns <= 0) return;
	if (width <= 0) width = 1;

	if (_pendingWrap) {
		_pendingWrap = NO;
		if (_autoWrap) {
			// The last cell hit the right margin: break to a new line now.
			_cursorCol = 0;
			if (_cursorRow < _scrollBottom) {
				_cursorRow++;
			} else if (_cursorRow == _scrollBottom) {
				[self scrollRegionTop:_scrollTop bottom:_scrollBottom up:1
						 intoHistory:(!_stashScreen && _scrollTop == 0)];
			}
		} else if (_cursorCol >= _columns) {
			_cursorCol = _columns - 1;
		}
	}
	if (_cursorCol < 0) _cursorCol = 0;
	if (_cursorCol >= _columns) return;

	if (_cursorCol + width > _columns) {
		if (_autoWrap) {
			// Not enough room for this glyph: break to a fresh line first.
			_cursorCol = 0;
			if (_cursorRow < _scrollBottom) {
				_cursorRow++;
			} else if (_cursorRow == _scrollBottom) {
				[self scrollRegionTop:_scrollTop bottom:_scrollBottom up:1
						 intoHistory:(!_stashScreen && _scrollTop == 0)];
			}
		} else {
			width = _columns - _cursorCol;
			if (width <= 0) return;
		}
	}
	if (_insertMode) {
		[_screen[_cursorRow] insertCellsAt:(NSUInteger)_cursorCol count:(NSUInteger)width];
	}

	TILine *line = _screen[_cursorRow];
	[line ensureCapacity:(NSUInteger)_columns];
	TICell *cells = line.cells;
	TICell cell;
	memset(&cell, 0, sizeof(cell));
	cell.ch = ch;
	cell.fg = _curFg;
	cell.bg = _curBg;
	cell.width = (uint8_t)width;
	cell.flags = (uint8_t)_curFlags;
	cells[_cursorCol] = cell;
	if (width == 2) {
		TICell cont = cell;
		cont.ch = 0;
		cont.mark = 0;
		cont.width = 0;
		cells[_cursorCol + 1] = cont;
	}
	_lastRow = _cursorRow;
	_lastCol = _cursorCol;
	_cursorCol += width;
	if (_cursorCol >= _columns) {
		if (_autoWrap) {
			_pendingWrap = YES;
		} else {
			_cursorCol = _columns - 1;
		}
	}
}

- (void)putCombiningMark:(uint32_t)mark {
	if (_lastRow < 0 || _lastRow >= _rows) return;
	TILine *line = _screen[_lastRow];
	[line ensureCapacity:(NSUInteger)_columns];
	if (_lastCol < 0 || _lastCol >= (NSInteger)line.capacity) return;
	TICell *cell = &line.cells[_lastCol];
	if (cell->mark == 0) cell->mark = mark;
}

- (void)fillWithChar:(uint32_t)ch {
	for (NSInteger r = 0; r < _rows; r++) {
		TILine *line = _screen[r];
		[line ensureCapacity:(NSUInteger)_columns];
		TICell *cells = line.cells;
		for (NSInteger c = 0; c < _columns; c++) {
			memset(&cells[c], 0, sizeof(TICell));
			cells[c].ch = ch;
			cells[c].width = 1;
		}
	}
	_cursorRow = 0;
	_cursorCol = 0;
	_pendingWrap = NO;
}

#pragma mark Erase / edit

- (void)eraseInLine:(NSInteger)mode {
	TILine *line = _screen[_cursorRow];
	[line ensureCapacity:(NSUInteger)_columns];
	switch (mode) {
		case 0:
			if (_cursorCol < _columns) {
				[line eraseRange:NSMakeRange((NSUInteger)_cursorCol,
							     (NSUInteger)(_columns - _cursorCol))
							  withBackground:_curBg];
			}
			break;
		case 1:
			[line eraseRange:NSMakeRange(0, (NSUInteger)MIN(_cursorCol + 1, _columns))
							  withBackground:_curBg];
			break;
		default:
			[line eraseRange:NSMakeRange(0, (NSUInteger)_columns)
							  withBackground:_curBg];
			break;
	}
	_pendingWrap = NO;
}

- (void)eraseInDisplay:(NSInteger)mode {
	switch (mode) {
		case 0:
			[self eraseInLine:0];
			for (NSInteger r = _cursorRow + 1; r < _rows; r++) {
				[_screen[r] ensureCapacity:(NSUInteger)_columns];
				[_screen[r] eraseRange:NSMakeRange(0, (NSUInteger)_columns) withBackground:_curBg];
			}
			break;
		case 1:
			[self eraseInLine:1];
			for (NSInteger r = 0; r < _cursorRow; r++) {
				[_screen[r] ensureCapacity:(NSUInteger)_columns];
				[_screen[r] eraseRange:NSMakeRange(0, (NSUInteger)_columns) withBackground:_curBg];
			}
			break;
		case 3:
			[_history removeAllObjects];
			// fallthrough
		case 2:
		default:
			for (NSInteger r = 0; r < _rows; r++) {
				[_screen[r] ensureCapacity:(NSUInteger)_columns];
				[_screen[r] eraseRange:NSMakeRange(0, (NSUInteger)_columns) withBackground:_curBg];
			}
			break;
	}
	_pendingWrap = NO;
}

- (void)insertLines:(NSInteger)n {
	if (_cursorRow < _scrollTop || _cursorRow > _scrollBottom) return;
	[self scrollRegionTop:_cursorRow bottom:_scrollBottom down:MAX(1, n)];
	_cursorCol = 0;
	_pendingWrap = NO;
}

- (void)deleteLines:(NSInteger)n {
	if (_cursorRow < _scrollTop || _cursorRow > _scrollBottom) return;
	[self scrollRegionTop:_cursorRow bottom:_scrollBottom up:MAX(1, n) intoHistory:NO];
	_cursorCol = 0;
	_pendingWrap = NO;
}

- (void)insertCells:(NSInteger)n {
	[_screen[_cursorRow] ensureCapacity:(NSUInteger)_columns];
	[_screen[_cursorRow] insertCellsAt:(NSUInteger)_cursorCol count:(NSUInteger)MAX(1, n)];
	_pendingWrap = NO;
}

- (void)deleteCells:(NSInteger)n {
	[_screen[_cursorRow] ensureCapacity:(NSUInteger)_columns];
	[_screen[_cursorRow] deleteCellsAt:(NSUInteger)_cursorCol count:(NSUInteger)MAX(1, n)];
	_pendingWrap = NO;
}

- (void)eraseCells:(NSInteger)n {
	TILine *line = _screen[_cursorRow];
	[line ensureCapacity:(NSUInteger)_columns];
	NSUInteger start = (NSUInteger)MIN(MAX(_cursorCol, 0), _columns);
	NSUInteger len = (NSUInteger)MIN(MAX(1, n), _columns - (NSInteger)start);
	[line eraseRange:NSMakeRange(start, len) withBackground:_curBg];
	_pendingWrap = NO;
}

#pragma mark Saved cursor

- (void)saveCursor {
	_savedRow = _cursorRow;
	_savedCol = _cursorCol;
	_savedFg = _curFg;
	_savedBg = _curBg;
	_savedFlags = _curFlags;
	_savedOrigin = _originMode;
}

- (void)restoreCursor {
	NSInteger limit = _savedOrigin ? _scrollBottom : _rows - 1;
	_cursorRow = MIN(MAX(_savedRow, 0), limit);
	_cursorCol = MIN(MAX(_savedCol, 0), MAX(0, _columns - 1));
	_originMode = _savedOrigin;
	_curFg = _savedFg;
	_curBg = _savedBg;
	_curFlags = _savedFlags;
	_pendingWrap = NO;
}

#pragma mark Alternate screen

- (void)enterAltScreen {
	if ([self altScreen]) return;
	_stashHistory = _history;
	_stashScreen = _screen;
	_history = [NSMutableArray array];
	_screen = [NSMutableArray array];
	for (NSInteger i = 0; i < _rows; i++) {
		[_screen addObject:[TILine lineWithColumns:(NSUInteger)MAX(2, _columns)]];
	}
	_scrollTop = 0;
	_scrollBottom = _rows - 1;
	_pendingWrap = NO;
	_lastRow = -1;
}

- (void)leaveAltScreen {
	if (![self altScreen]) return;
	_history = _stashHistory;
	_screen = _stashScreen;
	_stashHistory = nil;
	_stashScreen = nil;
	while ((NSInteger)_screen.count > _rows) [_screen removeLastObject];
	_scrollTop = 0;
	_scrollBottom = _rows - 1;
	_pendingWrap = NO;
	_lastRow = -1;
}

#pragma mark Delivery

- (NSInteger)historyLineCount {
	return (NSInteger)_history.count;
}

- (NSInteger)displayLineCount {
	return (NSInteger)_history.count + _rows;
}

- (TILine *)displayLineAt:(NSInteger)index {
	if (index < 0) return nil;
	if (index < (NSInteger)_history.count) return _history[index];
	NSInteger screenRow = index - (NSInteger)_history.count;
	if (screenRow >= _rows) return nil;
	return _screen[screenRow];
}

@end