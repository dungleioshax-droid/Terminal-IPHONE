//
//  TILaunchLog.m
//
#import "TILaunchLog.h"

#include <fcntl.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

// Kept open so the fatal-signal handler can write with write(2) only.
static int TILogFD = -1;
static char TILogPathBuf[512];

static const char *TILogCandidatePaths[] = {
	"/var/mobile/Library/Logs/terminal-iphone/launch.log",
	"/tmp/terminal-iphone-launch.log",
};

static void TIOpenLog(void) {
	if (TILogFD >= 0) return;
	for (size_t i = 0; i < sizeof(TILogCandidatePaths) / sizeof(*TILogCandidatePaths); i++) {
		const char *path = TILogCandidatePaths[i];
		int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
		if (fd >= 0) {
			TILogFD = fd;
			strncpy(TILogPathBuf, path, sizeof(TILogPathBuf) - 1);
			return;
		}
	}
}

static void TIWriteRaw(const char *text) {
	if (TILogFD < 0 || !text) return;
	write(TILogFD, text, strlen(text));
}

void TILaunchLogMark(NSString *format, ...) {
	if (!format) return;
	@autoreleasepool {
		TIOpenLog();
		if (TILogFD < 0) return;
		va_list args;
		va_start(args, format);
		NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
		va_end(args);
		NSString *line = [NSString stringWithFormat:@"[%@] %@\n", NSDate.date, body];
		TIWriteRaw(line.UTF8String);
	}
}

NSString *_Nullable TILaunchLogPath(void) {
	TIOpenLog();
	return TILogFD >= 0 ? @(TILogPathBuf) : nil;
}

static void TIUncaughtExceptionHandler(NSException *exception) {
	@autoreleasepool {
		TILaunchLogMark(@"UNCAUGHT EXCEPTION %@: %@", exception.name, exception.reason);
		NSArray<NSString *> *symbols = exception.callStackSymbols;
		if (symbols.count > 0) {
			TILaunchLogMark(@"call stack:\n%@", [symbols componentsJoinedByString:@"\n"]);
		}
	}
}

static void TISignalHandler(int signalNumber) {
	static const char *names[] = {"?", "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP",
		"SIGABRT", "SIGBUS", "SIGFPE", "SIGKILL", "SIGUSR1", "SIGSEGV"};
	const char *name = (signalNumber > 0 && signalNumber < 12) ? names[signalNumber] : "SIG?";
	char line[96];
	int length = snprintf(line, sizeof(line), "FATAL SIGNAL %d (%s)\n", signalNumber, name);
	if (length > 0 && TILogFD >= 0) write(TILogFD, line, (size_t)length);
	signal(signalNumber, SIG_DFL);
	raise(signalNumber);
}

void TILaunchLogInstallHandlers(void) {
	// The directory does not exist on a fresh install, and it has to be created
	// before opening the log, otherwise we silently fall back to /tmp.
	[NSFileManager.defaultManager createDirectoryAtPath:@"/var/mobile/Library/Logs/terminal-iphone"
	                        withIntermediateDirectories:YES
	                                         attributes:nil
	                                              error:NULL];
	TIOpenLog();
	NSSetUncaughtExceptionHandler(&TIUncaughtExceptionHandler);
	int fatal[] = {SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGFPE, SIGSEGV};
	for (size_t i = 0; i < sizeof(fatal) / sizeof(*fatal); i++) {
		signal(fatal[i], TISignalHandler);
	}
}
