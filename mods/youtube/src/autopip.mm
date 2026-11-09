// Tự bật PiP khi người dùng về màn hình chính (mod 2.0).
//
// YouTube có sẵn YTPlayerPIPController.maybeTogglePictureInPicture, nhưng chỉ gọi
// khi người dùng bấm nút PiP. Ghi lại controller đang phát rồi gọi đúng hàm đó
// lúc app sắp rời foreground, để PiP bật đúng như bấm nút thủ công.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static __weak id g_pipController = nil;

static void ytm_remember_pip_controller(id obj) {
    if (obj) g_pipController = obj;
}

// Ghi lại controller khi nó được tạo / nhận video đang phát.
static IMP _o_pipInit;
static id h_pipInit(id s, SEL c, id delegate) {
    id r = ((id (*)(id, SEL, id))_o_pipInit)(s, c, delegate);
    ytm_remember_pip_controller(r);
    return r;
}

static IMP _o_pipSetActiveVideo;
static void h_pipSetActiveVideo(id s, SEL c, id video) {
    ytm_remember_pip_controller(s);
    ((void (*)(id, SEL, id))_o_pipSetActiveVideo)(s, c, video);
}

// Bật PiP nếu công tắc bật, video đang phát và PiP chưa hiện.
static void ytm_try_start_pip(void) {
    if (!YTPiPEnabled()) return;
    id ctl = g_pipController;
    if (!ctl) return;
    @try {
        SEL activeSel = sel_registerName("isPictureInPictureActive");
        BOOL active = [ctl respondsToSelector:activeSel] &&
                      ((BOOL (*)(id, SEL))objc_msgSend)(ctl, activeSel);
        if (active) return;
        // Không chặn theo canEnablePictureInPicture: hàm toggle tự kiểm tra lại
        // lúc chạy, còn giá trị đọc sớm có thể chưa kịp cập nhật.
        SEL toggleSel = sel_registerName("maybeTogglePictureInPicture");
        if (![ctl respondsToSelector:toggleSel]) {
            YTModLog(@"autopip: thiếu maybeTogglePictureInPicture");
            return;
        }
        ((void (*)(id, SEL))objc_msgSend)(ctl, toggleSel);
    } @catch (__unused NSException *e) {
        YTModLog(@"autopip: lỗi khi bật PiP");
    }
}

void YTAutoPiPInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("YTPlayerPIPController");
        if (!cls) {
            YTModLog(@"autopip MISS YTPlayerPIPController");
            return;
        }
        Method m = class_getInstanceMethod(cls, sel_registerName("initWithDelegate:"));
        if (m) {
            _o_pipInit = method_getImplementation(m);
            class_replaceMethod(cls, sel_registerName("initWithDelegate:"), (IMP)h_pipInit,
                                method_getTypeEncoding(m));
        }
        m = class_getInstanceMethod(cls, sel_registerName("setActiveSingleVideo:"));
        if (m) {
            _o_pipSetActiveVideo = method_getImplementation(m);
            class_replaceMethod(cls, sel_registerName("setActiveSingleVideo:"),
                                (IMP)h_pipSetActiveVideo, method_getTypeEncoding(m));
        }
        // willResignActive bắn khi bấm Home hoặc chuyển app, lúc này PiP còn bật được.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        ytm_try_start_pip();
                    }];
    });
}
