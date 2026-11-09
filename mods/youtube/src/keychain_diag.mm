// Chẩn đoán mất login (mod 3.24): log YTIdentityStore đọc/ghi identity từ disk.
//
// 3.23: cookies SSO của sharedHTTPCookieStorage = 0 — không chứng minh gì vì
// token đăng nhập của YouTube iOS KHÔNG nằm ở đó. Cửa sổ thật:
//   YTIdentityStore.readIdentityFromDisk / storeCurrentIdentityToDisk —
//   identity (userID + auth) serialize ra file trong Library. Log mỗi lần
//   đọc/ghi + userID (không log token) để biết:
//   - login xong → storeCurrentIdentityToDisk chạy không?
//   - mở lại app → readIdentityFromDisk trả gì (nil = file mất/không đọc được)?
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static IMP _o_readIdentity;
static id h_readIdentity(id s, SEL c) {
    id v = ((id (*)(id, SEL))_o_readIdentity)(s, c);
    @try {
        NSString *uid = nil;
        if ([v respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(v, @selector(userID));
        }
        BOOL valid = NO;
        if ([v respondsToSelector:@selector(hasValidAuth)]) {
            valid = ((BOOL (*)(id, SEL))objc_msgSend)(v, @selector(hasValidAuth));
        }
        YTModLog(@"identity: ĐỌC disk → %@ (hasValidAuth=%d)", uid ?: @"(nil)", valid);
    } @catch (__unused NSException *e) {}
    return v;
}

static IMP _o_storeIdentity;
static void h_storeIdentity(id s, SEL c) {
    @try {
        id cur = nil;
        SEL curSel = sel_registerName("currentIdentity");
        if ([s respondsToSelector:curSel]) {
            cur = ((id (*)(id, SEL))objc_msgSend)(s, curSel);
        }
        NSString *uid = nil;
        if ([cur respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(cur, @selector(userID));
        }
        YTModLog(@"identity: GHI disk ← %@", uid ?: @"(nil)");
    } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL))_o_storeIdentity)(s, c);
}

void YTKeychainDiagInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = objc_getClass("YTIdentityStore");
        if (!cls) {
            YTModLog(@"identity-diag MISS YTIdentityStore");
            return;
        }
        Method m1 = class_getInstanceMethod(cls, sel_registerName("readIdentityFromDisk"));
        if (m1) {
            _o_readIdentity = method_getImplementation(m1);
            class_replaceMethod(cls, sel_registerName("readIdentityFromDisk"),
                                (IMP)h_readIdentity, method_getTypeEncoding(m1));
        }
        Method m2 = class_getInstanceMethod(cls, sel_registerName("storeCurrentIdentityToDisk"));
        if (m2) {
            _o_storeIdentity = method_getImplementation(m2);
            class_replaceMethod(cls, sel_registerName("storeCurrentIdentityToDisk"),
                                (IMP)h_storeIdentity, method_getTypeEncoding(m2));
        }
        YTModLog(@"identity-diag: cài xong (log đọc/ghi identity mỗi lần)");
    });
}
