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

/// Recompute contentSize and redraw everything.
- (void)reload;
- (BOOL)isAtBottom;
- (void)scrollToBottomAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END