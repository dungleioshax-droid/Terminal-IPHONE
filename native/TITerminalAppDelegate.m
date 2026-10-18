#import <UIKit/UIKit.h>
#import "TITerminalViewController.h"
#import "TILaunchLog.h"

@interface TITerminalAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation TITerminalAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	(void)application;
	(void)launchOptions;
	TILaunchLogMark(@"didFinishLaunching, iOS %@", UIDevice.currentDevice.systemVersion);
	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
	TITerminalViewController *terminal = [[TITerminalViewController alloc] init];
	UINavigationController *navigation =
		[[UINavigationController alloc] initWithRootViewController:terminal];
	self.window.rootViewController = navigation;
	[self.window makeKeyAndVisible];
	TILaunchLogMark(@"window visible, log at %@", TILaunchLogPath());
	return YES;
}

@end