#import "LQFaceCaptureModule.h"
#import "LQFaceCaptureViewController.h"

@interface UniFaceCaptureModule ()
@property (nonatomic) BOOL capturePending;
@end

@implementation UniFaceCaptureModule

UNI_EXPORT_METHOD(@selector(capture:callback:))

- (void)capture:(NSDictionary *)options callback:(UniModuleKeepAliveCallback)callback {
    (void)options;
    if (callback == nil) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.capturePending) {
            callback(@{
                @"code": @-1,
                @"errorCode": @"CAPTURE_ALREADY_OPEN",
                @"message": @"人脸拍照页面已打开"
            }, NO);
            return;
        }
        UIViewController *presenter = [self topViewController];
        if (presenter == nil || presenter.view.window == nil
            || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) {
            callback(@{
                @"code": @-1,
                @"errorCode": @"PRESENTER_UNAVAILABLE",
                @"message": @"当前页面无法打开相机"
            }, NO);
            return;
        }

        self.capturePending = YES;
        __block BOOL settled = NO;
        void (^finish)(NSDictionary *) = ^(NSDictionary *result) {
            if (settled) {
                return;
            }
            settled = YES;
            self.capturePending = NO;
            callback(result, NO);
        };
        LQFaceCaptureViewController *controller = [[LQFaceCaptureViewController alloc]
            initWithCompletion:finish];
        controller.modalPresentationStyle = UIModalPresentationFullScreen;
        controller.modalPresentationCapturesStatusBarAppearance = YES;
        [presenter presentViewController:controller animated:YES completion:nil];
    });
}

- (UIViewController *)topViewController {
    UIWindow *window = nil;
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]
                || scene.activationState != UISceneActivationStateForegroundActive) {
                continue;
            }
            for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
        }
    }
    window = window ?: UIApplication.sharedApplication.keyWindow;
    UIViewController *controller = window.rootViewController;
    BOOL advanced = YES;
    while (controller != nil && advanced) {
        advanced = NO;
        if (controller.presentedViewController != nil) {
            controller = controller.presentedViewController;
            advanced = YES;
        } else if ([controller isKindOfClass:UINavigationController.class]) {
            controller = ((UINavigationController *)controller).visibleViewController;
            advanced = YES;
        } else if ([controller isKindOfClass:UITabBarController.class]) {
            controller = ((UITabBarController *)controller).selectedViewController;
            advanced = YES;
        }
    }
    return controller;
}

@end
