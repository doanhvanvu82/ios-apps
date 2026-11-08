// Điểm vào dylib: cài hook + menu sau khi app khởi động xong.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>

static void ytm_did_finish_launch(void) {
    YTModLog(@"app đã launch — cài hook");
    // Probe cài trước để ghi được element/cell của feed ngay từ lượt tải đầu.
    YTProbeInstall();
    YTHooksInstall();
    YTDiagInstall();
    YTAdBlockInstall();
    YTPromoBlockInstall();
    YTSectionFilterInstall();
    YTAutoPiPInstall();
    if (YTModBool(YTKeyMenu, YES)) {
        YTMenuInstall();
    }
}

__attribute__((constructor)) static void ytm_init(void) {
    YTModLogOpen();
    YTModLog(@"dylib nạp (mod %s, build %s)", YT_VERSION_TAG, YT_BUILD_LABEL);
    // UISweep cài SỚM NHẤT: hook YTActiveViewDisplayContainerNode phải có trước
    // khi feed render cell ad đầu (log 3.16: hook cài lúc launchMissed element #1).
    YTUISweepInstall();
    // Về foreground (scene mới) thì thử cài lại hook ad — module lazy có thể
    // chưa có lúc launch. YTAdBlockInstall chỉ chạy 1 lần nên gọi ở đây an toàn.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        YTAdBlockInstall();
        YTPromoBlockInstall();
        YTSectionFilterInstall();
        YTProbeInstall();
    }];
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
