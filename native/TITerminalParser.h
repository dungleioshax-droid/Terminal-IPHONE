//
//  TITerminalParser.h
//  Incremental VT100/xterm-style escape sequence parser. Decodes UTF-8 and
//  drives a TITerminalBuffer.
//
#import <Foundation/Foundation.h>
#import "TITerminalBuffer.h"

NS_ASSUME_NONNULL_BEGIN

@protocol TITerminalParserDelegate <NSObject>
@required
/// The terminal asked the host something (DSR/DA); must be written to the PTY.
- (void)terminalParserRespond:(NSData *)response;
@optional
/// OSC 0/2 window title.
- (void)terminalParserDidReceiveTitle:(NSString *)title;
@end

@interface TITerminalParser : NSObject

@property (nonatomic, strong) TITerminalBuffer *buffer;
@property (nonatomic, weak) id<TITerminalParserDelegate> delegate;

/// Reset parser-internal state (after a session restart). Buffer resets too.
- (void)reset;

/// Feed raw PTY output; may be any byte boundary.
- (void)feed:(NSData *)data;

@end

NS_ASSUME_NONNULL_END