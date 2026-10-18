//
//  TITerminalBuffer.h
//  Terminal screen model: a fixed cell grid with scrollback, cursor, scroll
//  region and alternate screen state. All coordinates are 0-based.
//
#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

// Per-cell attribute flags.
enum {
	TIFlagBold      = 1 << 0,
	TIFlagDim       = 1 << 1,
	TIFlagItalic    = 1 << 2,
	TIFlagUnderline = 1 << 3,
	TIFlagInverse   = 1 << 4,
};

// Color packing: top byte selects the kind, low bits carry the value.
static inline uint32_t TIColorPalette(uint32_t idx) {
	return 0x01000000u | (idx & 0xFFu);
}
static inline uint32_t TIColorRGB(uint32_t r, uint32_t g, uint32_t b) {
	return 0x02000000u | ((r & 0xFFu) << 16) | ((g & 0xFFu) << 8) | (b & 0xFFu);
}
static inline int TIColorIsDefault(uint32_t c) { return c == 0; }
static inline int TIColorIsPalette(uint32_t c) { return (c >> 24) == 1; }
static inline uint32_t TIColorPaletteIndex(uint32_t c) { return c & 0xFFu; }
static inline int TIColorIsRGB(uint32_t c) { return (c >> 24) == 2; }

typedef struct {
	uint32_t ch;    // codepoint, 0 = empty
	uint32_t mark;  // one combining mark, 0 = none
	uint32_t fg;
	uint32_t bg;
	uint8_t width;  // 0 = continuation of a wide char, 1 or 2
	uint8_t flags;  // TIFlag*
} TICell;

/// Character width for terminal layout: 0 (combining), 1 or 2 (wide/CJK/emoji).
unsigned TICharWidth(uint32_t cp);

/// One row of the grid; storage never shrinks.
@interface TILine : NSObject

+ (instancetype)lineWithColumns:(NSUInteger)columns;

/// Allocated storage length (>= logical columns of the buffer).
@property (nonatomic, readonly) NSUInteger capacity;

- (TICell *)cells;
- (void)reset;
- (void)ensureCapacity:(NSUInteger)columns;
- (void)eraseRange:(NSRange)range withBackground:(uint32_t)bg;
- (void)insertCellsAt:(NSUInteger)idx count:(NSUInteger)count;
- (void)deleteCellsAt:(NSUInteger)idx count:(NSUInteger)count;

@end

@interface TITerminalBuffer : NSObject

- (instancetype)initWithColumns:(NSInteger)columns rows:(NSInteger)rows;

@property (nonatomic, readonly) NSInteger columns;
@property (nonatomic, readonly) NSInteger rows;

- (void)resizeColumns:(NSInteger)columns rows:(NSInteger)rows;
- (void)reset;  // RIS: primary screen, cleared modes, no scrollback

// Cursor (read-only to callers; mutate through the methods below).
@property (nonatomic, readonly) NSInteger cursorRow;
@property (nonatomic, readonly) NSInteger cursorCol;
// Current SGR state; the parser writes these directly.
@property (nonatomic, assign) uint32_t curFg;
@property (nonatomic, assign) uint32_t curBg;
@property (nonatomic, assign) uint32_t curFlags;
// Terminal modes.
@property (nonatomic, assign) BOOL autoWrap;
@property (nonatomic, assign) BOOL cursorVisible;
@property (nonatomic, assign) BOOL insertMode;
@property (nonatomic, assign) BOOL originMode;
@property (nonatomic, assign) BOOL appCursorKeys;
@property (nonatomic, assign) BOOL newLineMode;
// Scroll region (screen coordinates, inclusive).
@property (nonatomic, readonly) NSInteger scrollTop;
@property (nonatomic, readonly) NSInteger scrollBottom;

- (void)setScrollRegionTop:(NSInteger)top bottom:(NSInteger)bottom; // valid top<bottom, else full screen

// Cursor movement -----------------------------------------------------------
- (void)setCursorRow:(NSInteger)row col:(NSInteger)col;  // origin-aware (DECOM)
- (void)setCursorColumn:(NSInteger)col;
- (void)cursorUp:(NSInteger)n;      // region-clamped
- (void)cursorDown:(NSInteger)n;    // region-clamped
- (void)cursorLeft:(NSInteger)n;
- (void)cursorRight:(NSInteger)n;
- (void)nextLines:(NSInteger)n;     // CNL: down n + column 0
- (void)previousLines:(NSInteger)n; // CPL
- (void)tabForward:(NSInteger)n;
- (void)tabBackward:(NSInteger)n;
- (void)carriageReturn;
- (void)backspace;
- (void)lineFeed;       // LF (region scroll at the bottom)
- (void)reverseIndex;   // ESC M

// Printing ------------------------------------------------------------------
- (void)putChar:(uint32_t)ch width:(NSInteger)width;
- (void)putCombiningMark:(uint32_t)mark;
- (void)fillWithChar:(uint32_t)ch;  // DECALN

// Erase / edit --------------------------------------------------------------
- (void)eraseInLine:(NSInteger)mode;    // 0 from cursor, 1 to cursor, 2 whole
- (void)eraseInDisplay:(NSInteger)mode; // 0,1,2, 3 = also clear scrollback
- (void)insertLines:(NSInteger)n;
- (void)deleteLines:(NSInteger)n;
- (void)insertCells:(NSInteger)n;
- (void)deleteCells:(NSInteger)n;
- (void)eraseCells:(NSInteger)n;

// Scrolling -----------------------------------------------------------------
- (void)scrollUp:(NSInteger)n;
- (void)scrollDown:(NSInteger)n;

// Saved cursor (DECSC/DECRC) ------------------------------------------------
- (void)saveCursor;
- (void)restoreCursor;

// Alternate screen ----------------------------------------------------------
@property (nonatomic, readonly) BOOL altScreen;
- (void)enterAltScreen;
- (void)leaveAltScreen;

// Delivery ------------------------------------------------------------------
@property (nonatomic, readonly) NSInteger historyLineCount;
@property (nonatomic, readonly) NSInteger displayLineCount; // history + rows
- (nullable TILine *)displayLineAt:(NSInteger)index;        // 0 = oldest

@end

NS_ASSUME_NONNULL_END