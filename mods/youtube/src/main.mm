// Điểm vào dylib: cài hook + menu sau khi app khởi động xong.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>

static void ytm_did_finish_launch(void) {
    YTModLog(@"app đã launch — cài hook");
    YTHooksInstall();
    YTDiagInstall();
    if (YTModBool(YTKeyMenu, YES)) {
        YTMenuInstall();
    }
}

__attribute__((constructor)) static void ytm_init(void) {
    YTModLogOpen();
    YTModLog(@"dylib nạp (mod %s)", YT_VERSION_TAG);
    // Dylib nạp trước UIApplicationMain: chờ notification launch. Nếu app đã
    // launch từ trước (không xảy ra với LC_LOAD_DYLIB nhưng để chắc), dùng timer.
    if ([UIApplication sharedApplication]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ytm_did_finish_launch(); });
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ ytm_did_finish_launch(); });
    }];
}
