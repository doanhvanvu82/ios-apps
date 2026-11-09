// Sửa mất login khi cài qua Ksign (3.29: cả IPA không dylib cũng mất login).
//
// YouTube ghi token vào keychain group EQHXZ8M8AV.com.google.common.SSO và file
// vào app group group.com.google.*. Ksign ký bằng team khác (profile chỉ có
// <TEAM>.* và không có app group) → SecItem* trả errSecMissingEntitlement,
// containerURLForSecurityApplicationGroupIdentifier: trả nil → token không
// lưu được, mở lại app là mất login.
//
// Sửa: bỏ kSecAttrAccessGroup khỏi mọi lệnh SecItem* (rơi về group mặc định của
// chứng chỉ), app group thiếu → thư mục trong container của app. SecItem* là
// hàm C nên ghi đè con trỏ trong __got (vùng data) của binary app, không đụng
// trang code (bản ký Ksign có CS_KILL).
#import "common.h"
#import "hooks.h"
#import <Security/Security.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <sys/mman.h>

static OSStatus (*o_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*o_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*o_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*o_SecItemDelete)(CFDictionaryRef);

static int g_kcLogged = 0;

static CFDictionaryRef ytm_strip_group(CFDictionaryRef d) {
    if (!d) return NULL;
    if (!CFDictionaryContainsKey(d, kSecAttrAccessGroup)) return (CFDictionaryRef)CFRetain(d);
    CFMutableDictionaryRef m = CFDictionaryCreateMutableCopy(NULL, 0, d);
    CFDictionaryRemoveValue(m, kSecAttrAccessGroup);
    return m;
}

static void ytm_kc_log(const char *fn, CFDictionaryRef q, OSStatus st) {
    // Chỉ log lỗi + vài lượt đầu: SecItem* chạy rất nhiều lần mỗi phiên.
    if (st == errSecSuccess && g_kcLogged >= 10) return;
    if (st != errSecSuccess && st != errSecItemNotFound && g_kcLogged >= 60) return;
    g_kcLogged++;
    NSDictionary *d = (__bridge NSDictionary *)q;
    YTModLog(@"keychain: %s service=%@ group=%@ → %d", fn,
             d[(__bridge id)kSecAttrService] ?: @"-",
             d[(__bridge id)kSecAttrAccessGroup] ?: @"-", (int)st);
}

static void ytm_cfrelease(CFTypeRef v) {
    if (v) CFRelease(v);
}

static OSStatus h_SecItemAdd(CFDictionaryRef a, CFTypeRef *r) {
    CFDictionaryRef s = ytm_strip_group(a);
    OSStatus st = o_SecItemAdd(s, r);
    ytm_kc_log("Add", a, st);
    ytm_cfrelease(s);
    return st;
}

static OSStatus h_SecItemCopyMatching(CFDictionaryRef q, CFTypeRef *r) {
    CFDictionaryRef s = ytm_strip_group(q);
    OSStatus st = o_SecItemCopyMatching(s, r);
    ytm_kc_log("CopyMatching", q, st);
    ytm_cfrelease(s);
    return st;
}

static OSStatus h_SecItemUpdate(CFDictionaryRef q, CFDictionaryRef a) {
    CFDictionaryRef sq = ytm_strip_group(q), sa = ytm_strip_group(a);
    OSStatus st = o_SecItemUpdate(sq, sa);
    ytm_kc_log("Update", q, st);
    ytm_cfrelease(sq);
    ytm_cfrelease(sa);
    return st;
}

static OSStatus h_SecItemDelete(CFDictionaryRef q) {
    CFDictionaryRef s = ytm_strip_group(q);
    OSStatus st = o_SecItemDelete(s);
    ytm_kc_log("Delete", q, st);
    ytm_cfrelease(s);
    return st;
}

typedef struct { void *target; void *hook; } YTMRebind;

// Ghi đè mọi slot con trỏ symbol (__got, __la_symbol_ptr…) trỏ tới target.
static int ytm_rebind_image(const struct mach_header_64 *mh, intptr_t slide,
                            const YTMRebind *rb, int n) {
    int hits = 0;
    const uint8_t *p = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++, p += ((const struct load_command *)p)->cmdsize) {
        const struct load_command *lc = (const struct load_command *)p;
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
        if (strncmp(seg->segname, "__DATA", 6) != 0 && strncmp(seg->segname, "__AUTH", 6) != 0) continue;
        const struct section_64 *sec = (const struct section_64 *)(seg + 1);
        for (uint32_t j = 0; j < seg->nsects; j++, sec++) {
            uint32_t type = sec->flags & SECTION_TYPE;
            if (type != S_NON_LAZY_SYMBOL_POINTERS && type != S_LAZY_SYMBOL_POINTERS) continue;
            void **slots = (void **)(sec->addr + slide);
            size_t count = sec->size / sizeof(void *);
            uintptr_t pageMask = (uintptr_t)getpagesize() - 1;
            uintptr_t start = (uintptr_t)slots & ~pageMask;
            size_t len = (((uintptr_t)(slots + count) + pageMask) & ~pageMask) - start;
            BOOL unprotected = NO;
            for (size_t k = 0; k < count; k++) {
                for (int t = 0; t < n; t++) {
                    if (slots[k] != rb[t].target) continue;
                    if (!unprotected) {
                        if (mprotect((void *)start, len, PROT_READ | PROT_WRITE) != 0) {
                            YTModLog(@"sideloadfix: mprotect %s.%s lỗi %d", seg->segname, sec->sectname, errno);
                            return hits;
                        }
                        unprotected = YES;
                    }
                    slots[k] = rb[t].hook;
                    hits++;
                }
            }
            if (unprotected && strcmp(seg->segname, "__DATA") != 0) {
                mprotect((void *)start, len, PROT_READ);
            }
        }
    }
    return hits;
}

static void ytm_rebind_keychain(void) {
    o_SecItemAdd = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemAdd");
    o_SecItemCopyMatching = (OSStatus (*)(CFDictionaryRef, CFTypeRef *))dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    o_SecItemUpdate = (OSStatus (*)(CFDictionaryRef, CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemUpdate");
    o_SecItemDelete = (OSStatus (*)(CFDictionaryRef))dlsym(RTLD_DEFAULT, "SecItemDelete");
    if (!o_SecItemAdd || !o_SecItemCopyMatching || !o_SecItemUpdate || !o_SecItemDelete) {
        YTModLog(@"sideloadfix: thiếu symbol SecItem*");
        return;
    }
    const YTMRebind rb[] = {
        {(void *)o_SecItemAdd, (void *)h_SecItemAdd},
        {(void *)o_SecItemCopyMatching, (void *)h_SecItemCopyMatching},
        {(void *)o_SecItemUpdate, (void *)h_SecItemUpdate},
        {(void *)o_SecItemDelete, (void *)h_SecItemDelete},
    };
    // Chỉ image nằm trong bundle app (binary chính + Frameworks), trừ dylib mod.
    NSString *bundle = [[NSBundle mainBundle] bundlePath];
    int total = 0;
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        const char *name = _dyld_get_image_name(i);
        if (!name || !strstr(name, bundle.UTF8String) || strstr(name, "libyoutubemod")) continue;
        int hits = ytm_rebind_image((const struct mach_header_64 *)_dyld_get_image_header(i),
                                    _dyld_get_image_vmaddr_slide(i), rb, 4);
        if (hits) YTModLog(@"sideloadfix: %d slot SecItem* trong %s", hits, strrchr(name, '/') + 1);
        total += hits;
    }
    YTModLog(@"sideloadfix: keychain %@ (%d slot)", total ? @"OK" : @"MISS", total);
}

static IMP o_containerURL;
static NSURL *h_containerURL(id s, SEL c, NSString *group) {
    NSURL *u = ((NSURL *(*)(id, SEL, NSString *))o_containerURL)(s, c, group);
    if (u || !group.length) return u;
    NSURL *lib = [[NSFileManager defaultManager] URLsForDirectory:NSLibraryDirectory
                                                        inDomains:NSUserDomainMask].firstObject;
    u = [[lib URLByAppendingPathComponent:@"AppGroups" isDirectory:YES]
            URLByAppendingPathComponent:group isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:u withIntermediateDirectories:YES attributes:nil error:NULL];
    static NSMutableSet *logged;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ logged = [NSMutableSet set]; });
    @synchronized (logged) {
        if (![logged containsObject:group]) {
            [logged addObject:group];
            YTModLog(@"sideloadfix: app group %@ → container app", group);
        }
    }
    return u;
}

void YTSideloadFixInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ytm_rebind_keychain();
        Method m = class_getInstanceMethod([NSFileManager class],
                                           @selector(containerURLForSecurityApplicationGroupIdentifier:));
        if (m) {
            o_containerURL = method_setImplementation(m, (IMP)h_containerURL);
            YTModLog(@"sideloadfix: hook containerURLForSecurityApplicationGroupIdentifier OK");
        }
    });
}
