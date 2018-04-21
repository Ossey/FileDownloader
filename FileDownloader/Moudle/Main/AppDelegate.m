//
//  AppDelegate.m
//  OSFileDownloader
//
//  Created by alpface on 2017/6/10.
//  Copyright © 2017年 alpface. All rights reserved.
//

#import "AppDelegate.h"
#import "MainTabBarController.h"
#import "OSFileDownloader.h"
#import "OSFileDownloaderManager.h"
#import "NetworkTypeUtils.h"
#import "ExceptionUtils.h"
#import "OSAuthenticatorHelper.h"
#import "OSLoaclNotificationHelper.h"
#import "OSFileDownloaderConfiguration.h"

#import "KeyboardHelper.h"
#import "MenuHelper.h"
#import "BrowserViewController.h"
#import "WebServer.h"
#import "ErrorPageHelper.h"
#import "SessionRestoreHelper.h"
#import "TabManager.h"
#import "PreferenceHelper.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import "AppGroupManager.h"
#import "OSSettingViewController.h"
#import "DownloadsViewController.h"

static NSString * const UserAgent = @"Mozilla/5.0 (iPhone; CPU iPhone OS 10_0 like Mac OS X) AppleWebKit/602.1.38 (KHTML, like Gecko) Version/10.0 Mobile/14A300 Safari/602.1";

@interface AppDelegate ()  {
    UIBackgroundTaskIdentifier _bgTask;
}

@property (nonatomic, assign) NSInteger pasteboardChangeCount;

@end

@implementation AppDelegate

- (void)dealloc{
    [Notifier removeObserver:self name:UIPasteboardChangedNotification object:nil];
}

- (void)setAudioPlayInBackgroundMode{
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    
    NSError *setCategoryError = nil;
    BOOL success = [audioSession setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&setCategoryError];
    if (!success) { /* handle the error condition */ }
    
    NSError *activationError = nil;
    success = [audioSession setActive:YES error:&activationError];
    if (!success) { /* handle the error condition */ }
}

- (void)handlePasteboardNotification:(NSNotification *)notify{
    self.pasteboardChangeCount = [ApplicationHelper helper].pasteboard.changeCount;
}

- (void)presentPasteboardChangedAlertWithURL:(NSURL *)url{
    UIAlertControllerStyle alertStyle = UIAlertControllerStyleActionSheet;
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alertStyle = alertStyle;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新窗口打开剪切板网址" message:@"您是否需要在新窗口中打开剪切板中的网址？" preferredStyle:alertStyle];
    
    UIAlertAction *openBrowserAction = [UIAlertAction actionWithTitle:@"打开网页" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        if (![[UIViewController xy_topViewController] isKindOfClass:[BrowserViewController class]]) {
            [UIViewController xy_tabBarController].selectedIndex = 3;
            UINavigationController *nav = (UINavigationController *)[UIViewController xy_tabBarController].selectedViewController;
            if ([nav isKindOfClass:[UINavigationController class]]) {
                OSSettingViewController *settingVc = (OSSettingViewController *)nav.viewControllers.firstObject;
                if ([settingVc isKindOfClass:[OSSettingViewController class]]) {
                    [settingVc openBrowserWebPage];
                }
                
            }
        }
        NSNotification *notify = [NSNotification notificationWithName:kOpenInNewWindowNotification object:self userInfo:@{@"url": url}];
        [Notifier postNotification:notify];
    }];
    UIAlertAction *downloadFileAction = [UIAlertAction actionWithTitle:@"缓存" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        [UIViewController xy_tabBarController].selectedIndex = 3;
        if (![[UIViewController xy_topViewController] isKindOfClass:[DownloadsViewController class]]) {
            [UIViewController xy_tabBarController].selectedIndex = 3;
            UINavigationController *nav = (UINavigationController *)[UIViewController xy_tabBarController].selectedViewController;
            if ([nav isKindOfClass:[UINavigationController class]]) {
                OSSettingViewController *settingVc = (OSSettingViewController *)nav.viewControllers.firstObject;
                if ([settingVc isKindOfClass:[OSSettingViewController class]]) {
                    [settingVc openDownloadPage];
                }
                
            }
            
        }
        [[OSFileDownloaderManager sharedInstance] start:url.absoluteString];
    }];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:openBrowserAction];
    [alert addAction:downloadFileAction];
    [alert addAction:cancelAction];
    [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)applicationStartPrepare {
    [self setAudioPlayInBackgroundMode];
    [[KeyboardHelper sharedInstance] startObserving];
    [[MenuHelper sharedInstance] setItems];
    
    [Notifier addObserver:self selector:@selector(handlePasteboardNotification:) name:UIPasteboardChangedNotification object:nil];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    
    [[ApplicationHelper helper] addNotBackUpiCloud];;
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    DDLogDebug(@"Home Path : %@", HomePath);
    
    NSURLCache *URLCache = [[NSURLCache alloc] initWithMemoryCapacity:4 * 1024 * 1024
                                                         diskCapacity:32 * 1024 * 1024
                                                             diskPath:nil];
    [NSURLCache setSharedURLCache:URLCache];
    
    
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    [[ApplicationHelper helper] configureDrawerViewController];
    self.window.rootViewController = [ApplicationHelper helper].drawerViewController;
    [self.window makeKeyAndVisible];
//    [[ApplicationHelper helper].drawerViewController open];
    [ExceptionUtils configExceptionHandler];
    
    /// 注册本地通知
    [[OSLoaclNotificationHelper sharedInstance] registerLocalNotificationWithBlock:^(UILocalNotification *localNotification) {
        /// 注册完成后回调
        NSLog(@"%@", localNotification);
        
        // ios8后，需要添加这个注册，才能得到授权
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
            UIUserNotificationType type =  UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound;
            UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:type
                                                                                     categories:nil];
            [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
            // 通知重复提示的单位，可以是天、周、月
            localNotification.repeatInterval = 0;
        } else {
            // 通知重复提示的单位，可以是天、周、月
            localNotification.repeatInterval = 0;
        }
        
    }];
    
    UILocalNotification *localNotification = [launchOptions valueForKey:UIApplicationLaunchOptionsLocalNotificationKey];
    if (localNotification) {
        // 当程序启动时，就有本地通知需要推送，就手动调用一次didReceiveLocalNotification
        [self application:application didReceiveLocalNotification:localNotification];
    }
    
    [[OSAuthenticatorHelper sharedInstance] initAuthenticator];
    
    
    /////
    [ErrorPageHelper registerWithServer:[WebServer sharedInstance]];
    [SessionRestoreHelper registerWithServer:[WebServer sharedInstance]];
    
    [[WebServer sharedInstance] start];
    
    //解决UIWebView首次加载页面时间过长问题,设置UserAgent减少跳转和判断
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent" : UserAgent}];
    
    [TabManager sharedInstance];    //load archive data ahead
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applicationStartPrepare];
    });
    
    OSFileDownloaderManager *module = [OSFileDownloaderManager sharedInstance];
    module.shouldAutoDownloadWhenInitialize = [[OSFileDownloaderConfiguration defaultConfiguration].shouldAutoDownloadWhenInitialize boolValue];
    
    return YES;
}

/// 此方法是本地通知会触发的方法，当点击通知横幅进入app时会调用
- (void)application:(UIApplication *)application didReceiveLocalNotification:(nonnull UILocalNotification *)notification {
    
    // 取消所有通知
    [application cancelAllLocalNotifications];
    [[[UIAlertView alloc] initWithTitle:@"下载通知" message:[OSLoaclNotificationHelper sharedInstance].notifyMessage delegate:nil cancelButtonTitle:@"好" otherButtonTitles:nil, nil] show];
    
    // 点击通知后，就让图标上的数字减1
    application.applicationIconBadgeNumber -= 1;
}

/// 当有电话进来或者锁屏，此时应用程会挂起，调用此方法，此方法一般做挂起前的工作，比如关闭网络，保存数据
- (void)applicationWillResignActive:(UIApplication *)application {
    // 图标上的数字减1
    application.applicationIconBadgeNumber -= 1;
    [[OSAuthenticatorHelper sharedInstance] applicationWillResignActiveWithShowCoverImageView];
//    [[OSTransmitDataViewController sharedInstance] stopWevServer];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSInteger sleepTime = 5;
    if ([OSFileDownloaderManager sharedInstance].downloadingItems.count) {
        sleepTime = NSIntegerMax; // sleepTime = 5;
    }
    [self startBackgroundTask:application sleepTime:sleepTime];
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    [[OSAuthenticatorHelper sharedInstance] applicationDidBecomeActiveWithRemoveCoverImageView];
//    if ([[UIViewController xy_topViewController] isEqual:[OSTransmitDataViewController sharedInstance]]) {
//        [[OSTransmitDataViewController sharedInstance] startWebServer];
//    }
    UIPasteboard *pasteboard = [ApplicationHelper helper].pasteboard;
    
    if (self.pasteboardChangeCount != pasteboard.changeCount) {
        self.pasteboardChangeCount = pasteboard.changeCount;
        NSURL *url = pasteboard.URL;
        if (url && ![[PreferenceHelper URLForKey:KeyPasteboardURL] isEqual:url]) {
            [PreferenceHelper setURL:url forKey:KeyPasteboardURL];
            [self presentPasteboardChangedAlertWithURL:url];
        }
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    
}

// 当一个 iOS 应用被送到后台,它的主线程会被暂停。你用 NSThread 的 detachNewThreadSelector:toTar get:withObject:类方法创建的线程也被挂起了。
// 如果你想在后台完成一个长期任务,就必须调用 UIApplication 的 beginBackgroundTaskWithExpirationHandler:实例方法,来向 iOS 借点时间。
// 默认情况下，如果在这个期限内,长期任务没有被完成,iOS 将终止程序。
- (void)startBackgroundTask:(UIApplication *)application sleepTime:(NSInteger)times {
    
    _bgTask = [application beginBackgroundTaskWithExpirationHandler:^{
        // 当应用程序留给后台的时间快要到结束时（应用程序留给后台执行的时间是有限的）， 这个Block块将被执行
        // 我们需要在次Block块中执行一些清理工作。
        // 如果清理工作失败了，那么将导致程序挂掉
        // 10分钟后执行这里，应该进行一些清理工作，如断开和服务器的连接等
        [application endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }];
    if (_bgTask == UIBackgroundTaskInvalid) {
        NSLog(@"failed to start background task!");
    }
    // Start the long-running task and return immediately.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Do the work associated with the task, preferably in chunks.
        NSTimeInterval timeRemain = 0;
        do {
            [NSThread sleepForTimeInterval:times];
            if (_bgTask != UIBackgroundTaskInvalid) {
                timeRemain = [application backgroundTimeRemaining];
                NSLog(@"Time remaining: %f",timeRemain);
            }
        } while(_bgTask!= UIBackgroundTaskInvalid && timeRemain > 165);
        // 如果改为timeRemain > 165,表示后台运行165秒
        // 后台任务完成，执行清理工作
        // 如果没到10分钟，也可以主动关闭后台任务，但这需要在主线程中执行，否则会出错
        dispatch_async(dispatch_get_main_queue(), ^{
            if (_bgTask != UIBackgroundTaskInvalid) {
                // 和上面10分钟后执行的代码一样
                // if you don't call endBackgroundTask, the OS will exit your app.
                [application endBackgroundTask:_bgTask];
                _bgTask = UIBackgroundTaskInvalid;
            }
        });
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // 如果没到10分钟又打开了app,结束后台任务
    if (_bgTask != UIBackgroundTaskInvalid) {
        [application endBackgroundTask:_bgTask];
        _bgTask = UIBackgroundTaskInvalid;
    }
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)application:(UIApplication *)application handleEventsForBackgroundURLSession:(NSString *)identifier completionHandler:(void (^)(void))completionHandler {
    
    [[OSFileDownloaderManager sharedInstance].downloader setBackgroundSessionCompletionHandler:completionHandler];
}

- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    
    return YES;
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    [[AppGroupManager defaultManager] openUrlCallBack];
    return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<NSString*, id> *)options {
    
    [[AppGroupManager defaultManager] openUrlCallBack];
    return YES;
}


// Enable UIWebView video landscape
- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
//    static NSString *kAVFullScreenViewControllerStr = @"AVFullScreenViewController";
    UITabBarController *tabBarController = (UITabBarController *)window.rootViewController;
    if ([tabBarController isKindOfClass:[UITabBarController class]]) {
        if (tabBarController.selectedIndex == 0) {
            return UIInterfaceOrientationMaskPortrait;
        }
        
//        UINavigationController *nac = tabBarController.selectedViewController;
//        if ([nac isKindOfClass:[UINavigationController class]]) {
//            UIViewController *presentedViewController = [nac presentedViewController];
//            if (presentedViewController && [presentedViewController isKindOfClass:NSClassFromString(kAVFullScreenViewControllerStr)] && [presentedViewController isBeingDismissed] == NO) {
//                return UIInterfaceOrientationMaskAll;
//            }
//        }
        
    }
    return UIInterfaceOrientationMaskAll;
}

#pragma mark - Preseving and Restoring State

- (BOOL)application:(UIApplication *)application shouldSaveApplicationState:(NSCoder *)coder{
    return YES;
}

- (BOOL)application:(UIApplication *)application shouldRestoreApplicationState:(NSCoder *)coder{
    return YES;
}



@end
