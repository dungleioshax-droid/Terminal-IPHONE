#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <signal.h>
#include <unistd.h>
#import "TITerminalAppDelegate.h"
#import "TILaunchLog.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		// A closed PTY must never kill the app with SIGPIPE.
		signal(SIGPIPE, SIG_IGN);
		TILaunchLogInstallHandlers();
		TILaunchLogMark(@"main() entered uid=%d euid=%d", getuid(), geteuid());
		return UIApplicationMain(argc, argv, nil,
					  NSStringFromClass(TITerminalAppDelegate.class));
	}
}
