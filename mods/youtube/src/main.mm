// Điểm vào dylib: cài hook + menu sau khi app khởi động xong.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>

// Biến thể chia đôi lỗi UI: build.sh SKIP="ads section" → bỏ cài các nhóm đó.
#ifndef YT_SKIP_GROUPS
#define YT_SKIP_GROUPS ""
#endif

static BOOL ytm_on(NSString *group) {
    NSString *skip = [NSString stringWithFormat:@",%s,", YT_SKIP_GROUPS];
    return ![skip containsString:[NSString stringWithFormat:@",%@,", group]];
}

static void ytm_did_finish_launch(void) {
    YTModLog(@"app đã launch — cài hook (bỏ nhóm: %s)", YT_SKIP_GROUPS);
    // Probe cài trước để ghi được element/cell của feed ngay từ lượt tải đầu.
    if (ytm_on(@"probe")) YTProbeInstall();
    if (ytm_on(@"core")) YTHooksInstall();
    if (ytm_on(@"diag")) {
        YTDiagInstall();
        YTKeychainDiagInstall();
    }
    if (ytm_on(@"ads")) YTAdBlockInstall();
    if (ytm_on(@"promo")) YTPromoBlockInstall();
    if (ytm_on(@"section")) YTSectionFilterInstall();
    if (ytm_on(@"pip")) YTAutoPiPInstall();
    if (ytm_on(@"menu") && YTModBool(YTKeyMenu, YES)) {
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
    // UISweep cài SỚM NHẤT: hook YTActiveViewDisplayContainerNode phải có trước
    // khi feed render cell ad đầu (log 3.16: hook cài lúc launchMissed element #1).
    if (ytm_on(@"uisweep")) YTUISweepInstall();
    // Về foreground (scene mới) thì thử cài lại hook ad — module lazy có thể
    // chưa có lúc launch. YTAdBlockInstall chỉ chạy 1 lần nên gọi ở đây an toàn.
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(__unused NSNotification *note) {
        if (ytm_on(@"ads")) YTAdBlockInstall();
        if (ytm_on(@"promo")) YTPromoBlockInstall();
        if (ytm_on(@"section")) YTSectionFilterInstall();
        if (ytm_on(@"probe")) YTProbeInstall();
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
