// Điểm vào dylib: cài hook + menu sau khi app khởi động xong.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>

static void ytm_did_finish_launch(void) {
    YTModLog(@"app đã launch — cài hook (bỏ nhóm: %@)", YTModSkipGroups());
    if (YTModGroupOn(@"core")) YTHooksInstall();
    if (YTModGroupOn(@"ads")) YTAdBlockInstall();
    if (YTModGroupOn(@"pip")) YTAutoPiPInstall();
    if (YTModGroupOn(@"menu") && YTModBool(YTKeyMenu, YES)) {
        YTMenuInstall();
    }
}

__attribute__((constructor)) static void ytm_init(void) {
    YTModLogOpen();
    YTModLog(@"dylib nạp (mod %s, build %s)", YT_VERSION_TAG, YT_BUILD_LABEL);
    // Keychain/app group phải sửa trước khi app đọc token lúc khởi động.
    YTSideloadFixInstall();
#ifdef YT_NO_HOOKS
    // Biến thể chia đôi lỗi mất login: dylib nạp nhưng không cài hook nào.
    YTModLog(@"VARIANT nohook: bỏ qua mọi hook");
    return;
#endif
    // Lọc feed cài trước khi trang chủ tải lượt đầu (launch + 1s là quá muộn).
    if (YTModGroupOn(@"feed")) YTFeedFilterInstall();
    // Về foreground (scene mới) thì thử cài lại hook ad — module lazy có thể
    // chưa có lúc launch. YTAdBlockInstall chỉ chạy 1 lần nên gọi ở đây an toàn.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        if (YTModGroupOn(@"ads")) YTAdBlockInstall();
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
