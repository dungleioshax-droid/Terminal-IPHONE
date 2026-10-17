//
//  TILaunchLog.h
//  Writes launch milestones to a file on disk so a crash on a device we cannot
//  debug directly still tells us how far the process got.
//
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Appends `format` plus a timestamp to the launch log (no-op if it fails).
void TILaunchLogMark(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

/// Installs an uncaught-exception handler and fatal-signal handlers that write
/// their reason to the same log before the process dies.
void TILaunchLogInstallHandlers(void);

/// Absolute path of the log actually in use (for display in Settings/UI).
NSString *_Nullable TILaunchLogPath(void);

NS_ASSUME_NONNULL_END
