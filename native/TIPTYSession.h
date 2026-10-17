//
//  TIPTYSession.h
//  Owns a pseudo terminal and a child shell: spawn, I/O, resize, teardown.
//  Also resolves jailbreak-relative paths (rootful / rootless / RootHide).
//
#import <Foundation/Foundation.h>
#include <sys/types.h>

NS_ASSUME_NONNULL_BEGIN

@class TIPTYSession;

@protocol TIPTYSessionDelegate <NSObject>
@required
/// Raw PTY output, coalesced, always on the main thread.
- (void)session:(TIPTYSession *)session didReceiveData:(NSData *)data;
/// The child process exited (main thread). status is a wait(2) status.
- (void)sessionDidExit:(TIPTYSession *)session status:(int)status;
@end

@interface TIPTYSession : NSObject

@property (nonatomic, weak, nullable) id<TIPTYSessionDelegate> delegate;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) pid_t processId;
@property (nonatomic, readonly) NSInteger columns;
@property (nonatomic, readonly) NSInteger rows;

/// The jailbreak root this app was installed into:
/// @"" (rootful), @"/var/jb" (rootless) or a randomized RootHide path.
+ (NSString *)jailbreakRoot;

/// First usable login shell (jbroot zsh/bash, then passwd shell, /bin/sh).
/// Optionally returns the jailbreak root via @c rootOut. nil when none exists.
+ (nullable NSString *)resolveShell:(NSString * __autoreleasing _Nullable * _Nullable)rootOut;

/// PATH: jbroot bin dirs, newest nvm Node, ~/.local/bin, then system dirs.
+ (NSString *)defaultPathWithRoot:(nullable NSString *)root;

- (BOOL)startWithShell:(NSString *)shell
	   environment:(NSArray<NSString *> *)environment
			  cwd:(NSString *)cwd
			columns:(NSInteger)columns
			  rows:(NSInteger)rows
			 error:(NSError **)error;

- (void)sendData:(NSData *)data;
- (void)resizeColumns:(NSInteger)columns rows:(NSInteger)rows;
- (void)terminate;

@end

NS_ASSUME_NONNULL_END