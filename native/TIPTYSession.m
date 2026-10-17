//
//  TIPTYSession.m
//  PTY session: posix_openpt + fork/setsid/TIOCSCTTY + reader thread.
//
#import "TIPTYSession.h"

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>

@interface TIPTYSession () {
	int _master;
	pid_t _pid;
	NSInteger _columns, _rows;
	NSThread *_readerThread;
	NSTimer *_reapTimer;
	NSMutableData *_pending;
	BOOL _stopping;
	BOOL _exitNotified;
}
@property (nonatomic, readwrite, getter=isRunning) BOOL running;
@end

@implementation TIPTYSession

- (instancetype)init {
	if ((self = [super init])) {
		_master = -1;
		_pid = -1;
	}
	return self;
}

- (void)dealloc {
	[_reapTimer invalidate];
	if (_master >= 0) close(_master);
	if (_pid > 0 && !_exitNotified) {
		kill(_pid, SIGHUP);
		kill(-_pid, SIGHUP);
	}
}

- (pid_t)processId {
	return _pid;
}

#pragma mark - Jailbreak path resolution

+ (NSString *)jailbreakRoot {
	static NSString *cached = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSString *exe = NSBundle.mainBundle.executablePath; // <root>/Applications/<Name>.app/<bin>
		NSString *dir = [[exe stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
		if ([dir.lastPathComponent isEqualToString:@"Applications"] &&
		    dir.length > @"@/Applications".length) {
			cached = dir;
		} else {
			// Rootful prefix (or not running from an /Applications bundle).
			cached = @"";
		}
	});
	return cached;
}

+ (nullable NSString *)resolveShell:(NSString * __autoreleasing _Nullable * _Nullable)rootOut {
	NSString *root = [self jailbreakRoot];
	if (rootOut) *rootOut = root;

	NSMutableArray<NSString *> *roots = [NSMutableArray array];
	if (root.length > 0) [roots addObject:root];
	if (![root isEqualToString:@"/var/jb"]) [roots addObject:@"/var/jb"];
	[roots addObject:@""];

	// Preferred shells inside the jailbreak, then the system.
	NSArray<NSString *> *subs = @[
		@"usr/bin/zsh", @"bin/zsh",
		@"usr/bin/bash", @"bin/bash",
		@"usr/bin/dash", @"bin/dash",
	];
	for (NSString *r in roots) {
		for (NSString *sub in subs) {
			NSString *path = r.length > 0
				? [r stringByAppendingPathComponent:sub]
				: [@"///" stringByAppendingString:sub]; // -> /usr/bin/zsh
			path = [path stringByStandardizingPath];
			if (access(path.fileSystemRepresentation, X_OK) == 0) return path;
		}
	}
	// The mobile user's passwd shell (usually the system /bin/sh).
	struct passwd *pw = getpwuid(getuid());
	if (pw && pw->pw_shell && pw->pw_shell[0] == '/' &&
	    access(pw->pw_shell, X_OK) == 0) {
		return [NSString stringWithUTF8String:pw->pw_shell];
	}
	// Last resort: every iOS ships /bin/sh.
	if (access("/bin/sh", X_OK) == 0) return @"/bin/sh";
	return nil;
}

+ (nullable NSString *)latestNvmBinPath {
	NSString *dir = [NSHomeDirectory() stringByAppendingPathComponent:@".nvm/versions/node"];
	NSArray<NSString *> *versions =
		[[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
	if (versions.count == 0) return nil;
	NSArray<NSString *> *sorted = [versions sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
		return [a compare:b options:NSNumericSearch];
	}];
	NSString *bin = [[dir stringByAppendingPathComponent:sorted.lastObject]
				stringByAppendingPathComponent:@"bin"];
	return [[NSFileManager defaultManager] fileExistsAtPath:bin] ? bin : nil;
}

+ (NSString *)defaultPathWithRoot:(NSString *)root {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	NSMutableSet<NSString *> *seen = [NSMutableSet set];
	void (^addPath)(NSString *) = ^(NSString *p) {
		if (p.length > 0 && ![seen containsObject:p]) {
			[seen addObject:p];
			[parts addObject:p];
		}
	};
	void (^addPrefixed)(NSString *) = ^(NSString *prefix) {
		for (NSString *d in @[ @"/usr/local/bin", @"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin" ]) {
			NSString *entry = prefix.length > 0
				? [prefix stringByAppendingPathComponent:[d substringFromIndex:1]]
				: d;
			addPath(entry);
		}
	};
	if (root.length > 0) addPrefixed(root);
	NSString *nvmBin = [self latestNvmBinPath];
	if (nvmBin) addPath(nvmBin);
	NSString *localBin = [NSHomeDirectory() stringByAppendingPathComponent:@".local/bin"];
	addPath(localBin);
	addPrefixed(@"");  // system dirs last
	return [parts componentsJoinedByString:@":"];
}

#pragma mark - Lifecycle

- (BOOL)startWithShell:(NSString *)shell
	   environment:(NSArray<NSString *> *)environment
			  cwd:(NSString *)cwd
			columns:(NSInteger)columns
			  rows:(NSInteger)rows
			 error:(NSError **)error {
	if (self.isRunning) {
		if (error) {
			*error = [NSError errorWithDomain:@"TIPTYSession" code:1
						     userInfo:@{NSLocalizedDescriptionKey : @"A session is already running."}];
		}
		return NO;
	}

	int intCols = (int)MAX(2, columns);
	int intRows = (int)MAX(2, rows);

	int master = open("/dev/ptmx", O_RDWR | O_NOCTTY);
	if (master < 0) {
		if (error) {
			*error = [NSError errorWithDomain:@"TIPTYSession" code:errno
						     userInfo:@{NSLocalizedDescriptionKey :
								       [NSString stringWithFormat:@"open(/dev/ptmx): %s", strerror(errno)]}];
		}
		return NO;
	}
	if (grantpt(master) != 0 || unlockpt(master) != 0) {
		int savedErrno = errno;
		close(master);
		if (error) {
			*error = [NSError errorWithDomain:@"TIPTYSession" code:savedErrno
						     userInfo:@{NSLocalizedDescriptionKey :
								       [NSString stringWithFormat:@"grantpt/unlockpt: %s", strerror(savedErrno)]}];
		}
		return NO;
	}
	char *slaveName = ptsname(master);
	int slave = slaveName ? open(slaveName, O_RDWR | O_NOCTTY) : -1;
	if (slave < 0) {
		int savedErrno = errno;
		close(master);
		if (error) {
			*error = [NSError errorWithDomain:@"TIPTYSession" code:savedErrno
						     userInfo:@{NSLocalizedDescriptionKey :
								       [NSString stringWithFormat:@"open(slave): %s", strerror(savedErrno)]}];
		}
		return NO;
	}

	struct winsize ws;
	memset(&ws, 0, sizeof(ws));
	ws.ws_row = (unsigned short)intRows;
	ws.ws_col = (unsigned short)intCols;
	ioctl(master, TIOCSWINSZ, &ws);

	// Everything the child needs is materialized before fork(): after fork
	// the child may only call async-signal-safe functions before execve.
	const char *shellPath = strdup(shell.fileSystemRepresentation ?: shell.UTF8String ?: "/bin/sh");
	const char *slash = strrchr(shellPath, '/');
	const char *argv0 = strdup(slash ? slash + 1 : shellPath);
	char *argv[2] = { (char *)argv0, NULL };
	NSInteger envCount = (NSInteger)environment.count;
	char **envp = calloc((size_t)envCount + 1, sizeof(char *));
	for (NSInteger i = 0; i < envCount; i++) {
		envp[i] = strdup(environment[i].UTF8String ?: "");
	}
	const char *cwdStr = strdup(cwd.fileSystemRepresentation ?: "/");

	pid_t pid = fork();
	if (pid == 0) {
		// ---- child -------------------------------------------------
		close(master);
		setsid();
		ioctl(slave, TIOCSCTTY, 0);      // make the pty our controlling terminal
		dup2(slave, 0);
		dup2(slave, 1);
		dup2(slave, 2);
		if (slave > 2) close(slave);
		chdir(cwdStr);
		execve(shellPath, argv, envp);
		_exit(127);
	}
	// ---- parent -------------------------------------------------
	free((void *)shellPath);
	free((void *)argv0);
	free((void *)cwdStr);
	for (NSInteger i = 0; i < envCount; i++) free(envp[i]);
	free(envp);
	close(slave);

	if (pid < 0) {
		int savedErrno = errno;
		close(master);
		if (error) {
			*error = [NSError errorWithDomain:@"TIPTYSession" code:savedErrno
						     userInfo:@{NSLocalizedDescriptionKey :
								       [NSString stringWithFormat:@"fork: %s", strerror(savedErrno)]}];
		}
		return NO;
	}

	_master = master;
	_pid = pid;
	_columns = intCols;
	_rows = intRows;
	_stopping = NO;
	_exitNotified = NO;
	_pending = [NSMutableData data];
	self.running = YES;

	[self startReader];
	[self startReaper];
	return YES;
}

#pragma mark - I/O

- (void)sendData:(NSData *)data {
	if (_master < 0 || data.length == 0) return;
	const uint8_t *bytes = data.bytes;
	NSUInteger offset = 0;
	while (offset < data.length) {
		ssize_t n = write(_master, bytes + offset, data.length - offset);
		if (n < 0) {
			if (errno == EINTR) continue;
			break; // EIO/EBADF: session gone
		}
		offset += (NSUInteger)n;
	}
}

- (void)resizeColumns:(NSInteger)columns rows:(NSInteger)rows {
	_columns = MAX(1, columns);
	_rows = MAX(1, rows);
	if (_master < 0) return;
	struct winsize ws;
	memset(&ws, 0, sizeof(ws));
	ws.ws_row = (unsigned short)_rows;
	ws.ws_col = (unsigned short)_columns;
	if (ioctl(_master, TIOCSWINSZ, &ws) == 0) {
		// The kernel delivers SIGWINCH to the foreground process group.
	}
}

- (void)terminate {
	_stopping = YES;
	if (_pid > 0 && !_exitNotified) {
		kill(_pid, SIGHUP);
		kill(-_pid, SIGHUP); // process group: the child called setsid()
	}
	[self closeMaster];
	// Reader thread notices _stopping within its 100ms poll interval.
}

- (void)closeMaster {
	int fd = _master;
	_master = -1;
	if (fd >= 0) close(fd);
}

#pragma mark - Reader thread

- (void)startReader {
	__weak TIPTYSession *weakSelf = self;
	_readerThread = [[NSThread alloc] initWithBlock:^{
		@autoreleasepool {
			TIPTYSession *session = weakSelf;
			[session readerLoop];
		}
	}];
	[_readerThread start];
}

- (void)readerLoop {
	unsigned char buf[8192];
	for (;;) {
		if (_stopping || _master < 0) break;
		struct pollfd pfd;
		memset(&pfd, 0, sizeof(pfd));
		pfd.fd = _master;
		pfd.events = POLLIN;
		int rc = poll(&pfd, 1, 100);
		if (rc < 0) {
			if (errno == EINTR) continue;
			break; // EBADF: closed by terminate()
		}
		if (rc == 0) continue; // timeout: loop to re-check _stopping
		if (_stopping || _master < 0) break;
		ssize_t n = read(_master, buf, sizeof(buf));
		if (n > 0) {
			@synchronized(self) {
				[_pending appendBytes:buf length:(NSUInteger)n];
			}
			[self scheduleFlush];
		} else if (n < 0 && errno == EINTR) {
			continue;
		} else {
			break; // EOF/EIO: every holder of the slave side is gone
		}
	}
	[self readerFinished];
}

- (void)scheduleFlush {
	// Coalesce: each queued block drains whatever has arrived; late blocks are
	// cheap no-ops, so bursts of output render at runloop cadence.
	dispatch_async(dispatch_get_main_queue(), ^{
		[self flushPending];
	});
}

- (void)flushPending {
	NSData *chunk = nil;
	@synchronized(self) {
		if (_pending.length == 0) return;
		chunk = _pending;
		_pending = [NSMutableData data];
	}
	if (chunk.length == 0) return;
	id<TIPTYSessionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(session:didReceiveData:)]) {
		[delegate session:self didReceiveData:chunk];
	}
}

- (void)readerFinished {
	int status = 0;
	pid_t reaped = -1;
	if (_pid > 0) {
		reaped = waitpid(_pid, &status, WNOHANG);
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		[self flushPending];
		if (reaped == self->_pid) {
			[self closeMaster];
			[self noteExitedStatus:status];
		} else if (reaped < 0 && errno == ECHILD) {
			[self closeMaster];
			[self noteExitedStatus:status];
		} else {
			// EOF but the child is somehow still alive (detached
			// process holding the pty): the reaper will report it.
			[self closeMaster];
		}
	});
}

#pragma mark - Reaping

- (void)startReaper {
	__weak TIPTYSession *weakSelf = self;
	_reapTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
		TIPTYSession *session = weakSelf;
		if (!session) {
			[timer invalidate];
			return;
		}
		[session reapIfExited];
	}];
	[[NSRunLoop mainRunLoop] addTimer:_reapTimer forMode:NSRunLoopCommonModes];
}

- (void)reapIfExited {
	if (_exitNotified || _pid <= 0) return;
	int status = 0;
	pid_t r = waitpid(_pid, &status, WNOHANG);
	if (r == _pid) {
		[self noteExitedStatus:status];
	} else if (r < 0 && errno == ECHILD) {
		[self noteExitedStatus:status];
	}
}

- (void)noteExitedStatus:(int)status {
	if (_exitNotified) return;
	_exitNotified = YES;
	self.running = NO;
	[_reapTimer invalidate];
	_reapTimer = nil;
	id<TIPTYSessionDelegate> delegate = self.delegate;
	if ([delegate respondsToSelector:@selector(sessionDidExit:status:)]) {
		[delegate sessionDidExit:self status:status];
	}
}

@end