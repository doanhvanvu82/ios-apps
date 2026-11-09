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

// SSOService.identityWithAuth: (@24@0:8@16) — flow login gọi hàm này để tạo
// SSOIdentity từ auth object. Log auth trước khi tạo identity.
static IMP _o_identityWithAuth;
static id h_identityWithAuth(id s, SEL c, id auth) {
    id identity = ((id (*)(id, SEL, id))_o_identityWithAuth)(s, c, auth);
    @try {
        NSString *email = nil, *uid = nil;
        if ([auth respondsToSelector:@selector(userEmail)]) {
            email = ((NSString *(*)(id, SEL))objc_msgSend)(auth, @selector(userEmail));
        }
        if ([auth respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(auth, @selector(userID));
        }
        NSString *outUid = nil;
        if ([identity respondsToSelector:@selector(userID)]) {
            outUid = ((NSString *(*)(id, SEL))objc_msgSend)(identity, @selector(userID));
        }
        static int n = 0;
        if (n < 20) {
            n++;
            YTModLog(@"login: identityWithAuth email=%@ uid=%@ → identity %@ (uid=%@, class %@)",
                     email ?: @"(nil)", uid ?: @"(nil)",
                     identity ? @"CÓ" : @"NIL", outUid ?: @"(nil)",
                     identity ? NSStringFromClass(object_getClass(identity)) : @"-");
        }
    } @catch (__unused NSException *e) {}
    return identity;
}

// SSOService.forget* — nếu YouTube TỰ XOÁ identity (invalidGrant → thu hồi token),
// đây là nguồn gốc mất login. Log mọi lần forget.
static IMP _o_forgetIdentity;
static void h_forgetIdentity(id s, SEL c, id id1, id callback) {
    @try {
        NSString *uid = nil;
        if ([id1 respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(id1, @selector(userID));
        }
        YTModLog(@"login: forgetIdentity ← %@ (app tự xoá identity!)", uid ?: @"(nil)");
    } @catch (__unused NSException *e) {}
    if (callback) {
        // gọi callback(nil) để flow không treo — forget chấp nhận callback nullable
    }
    ((void (*)(id, SEL, id, id))_o_forgetIdentity)(s, c, id1, callback);
}

static IMP _o_forgetIdentityInvalidGrant;
static void h_forgetIdentityInvalidGrant(id s, SEL c, id id1, id callback) {
    @try {
        NSString *uid = nil;
        if ([id1 respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(id1, @selector(userID));
        }
        YTModLog(@"login: forgetIdentityWithInvalidGrant ← %@ (TOKEN BỊ SERVER THU HỒI)",
                 uid ?: @"(nil)");
    } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id, id))_o_forgetIdentityInvalidGrant)(s, c, id1, callback);
}

// setCurrentIdentity: v24@0:8@16 — YouTube gán identity sau login; log userID
// để biết identity có thật được gắn vào store không (GHI nil = currentIdentity
// nil lúc store → identity chưa được gán).
static IMP _o_setCurrentIdentity;
static void h_setCurrentIdentity(id s, SEL c, id identity) {
    @try {
        NSString *uid = nil;
        if ([identity respondsToSelector:@selector(userID)]) {
            uid = ((NSString *(*)(id, SEL))objc_msgSend)(identity, @selector(userID));
        }
        BOOL valid = NO;
        if ([identity respondsToSelector:@selector(hasValidAuth)]) {
            valid = ((BOOL (*)(id, SEL))objc_msgSend)(identity, @selector(hasValidAuth));
        }
        static int n = 0;
        if (n < 30) {
            n++;
            YTModLog(@"identity: setCurrentIdentity ← %@ (hasValidAuth=%d)", uid ?: @"(nil)", valid);
        }
    } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL, id))_o_setCurrentIdentity)(s, c, identity);
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
        Class ssoCls = objc_getClass("SSOService");
        // forget* — log mọi lần app tự xoá identity (điểm bắt đầu mất login).
        static IMP _o_forgetUserInitiated, _o_forgetRevoke, _o_forgetUserRevoke;
        struct { const char *sel; IMP *orig; IMP hook; const char *label; } forgets[] = {
            {"forgetIdentity:callback:", &_o_forgetIdentity, (IMP)h_forgetIdentity, "forgetIdentity"},
            {"forgetIdentityWithInvalidGrant:callback:", &_o_forgetIdentityInvalidGrant, (IMP)h_forgetIdentityInvalidGrant, "forInvalidGrant"},
            {"forgetIdentity:userInitiated:callback:", &_o_forgetUserInitiated, (IMP)h_forgetIdentity, "forgetUserInitiated"},
            {"forgetIdentity:revokeToken:callback:", &_o_forgetRevoke, (IMP)h_forgetIdentity, "forgetRevokeToken"},
            {"forgetIdentity:userInitiated:revokeToken:invalidGrant:callback:", &_o_forgetUserRevoke, (IMP)h_forgetIdentityInvalidGrant, "forgetUserRevoke"},
        };
        for (size_t fi = 0; fi < sizeof(forgets)/sizeof(forgets[0]); fi++) {
            Method fm = ssoCls ? class_getInstanceMethod(ssoCls, sel_registerName(forgets[fi].sel)) : NULL;
            if (fm) {
                *forgets[fi].orig = method_getImplementation(fm);
                class_replaceMethod(ssoCls, sel_registerName(forgets[fi].sel),
                                    forgets[fi].hook, method_getTypeEncoding(fm));
                YTModLog(@"identity-diag: hook %s OK", forgets[fi].label);
            } else {
                YTModLog(@"identity-diag: MISS %s", forgets[fi].sel);
            }
        }
        Method m4 = ssoCls ? class_getInstanceMethod(ssoCls, sel_registerName("identityWithAuth:")) : NULL;
        if (m4) {
            _o_identityWithAuth = method_getImplementation(m4);
            class_replaceMethod(ssoCls, sel_registerName("identityWithAuth:"),
                                (IMP)h_identityWithAuth, method_getTypeEncoding(m4));
            YTModLog(@"identity-diag: hook SSOService.identityWithAuth OK");
        }
        Method m3 = class_getInstanceMethod(cls, sel_registerName("setCurrentIdentity:"));
        if (m3) {
            _o_setCurrentIdentity = method_getImplementation(m3);
            class_replaceMethod(cls, sel_registerName("setCurrentIdentity:"),
                                (IMP)h_setCurrentIdentity, method_getTypeEncoding(m3));
        }
        YTModLog(@"identity-diag: cài xong (log đọc/ghi identity mỗi lần)");
    });
}
