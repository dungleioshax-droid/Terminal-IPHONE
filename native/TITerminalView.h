//
//  TITerminalView.h
//  CoreGraphics grid renderer hosted in a UIScrollView (pan = scrollback).
//
#import <UIKit/UIKit.h>
#import "TITerminalBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@interface TITerminalView : UIScrollView

@property (nonatomic, strong, nullable) TITerminalBuffer *buffer;

@property (nonatomic, strong) UIColor *defaultForegroundColor;
@property (nonatomic, strong) UIColor *defaultBackgroundColor;

/// Cell metrics (measured from the font).
@property (nonatomic, readonly) CGFloat charWidth;
@property (nonatomic, readonly) CGFloat rowHeight;

/// Recompute contentSize and redraw everything. While `followsOutput` is YES
/// the view keeps itself pinned to the bottom, so new shell output stays visible
/// instead of being appended below the fold.
- (void)reload;
- (BOOL)isAtBottom;
- (void)scrollToBottomAnimated:(BOOL)animated;

/// YES until the user scrolls up; reload() re-pins to the bottom while it holds.
@property (nonatomic, assign) BOOL followsOutput;

@end

NS_ASSUME_NONNULL_END