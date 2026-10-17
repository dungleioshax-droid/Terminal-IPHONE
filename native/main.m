#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <signal.h>
#import "TITerminalAppDelegate.h"

int main(int argc, char *argv[]) {
	@autoreleasepool {
		// A closed PTY must never kill the app with SIGPIPE.
		signal(SIGPIPE, SIG_IGN);
		return UIApplicationMain(argc, argv, nil,
					  NSStringFromClass(TITerminalAppDelegate.class));
	}
}