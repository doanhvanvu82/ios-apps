// Ghi request/response mạng để tìm endpoint bị 404.
//
// Tạm thời: bật bằng NSUserDefaults key `net_log` (mặc định BẬT) để chẩn đoán
// lỗi "không tải được gì". Chỉ ghi URL (bỏ query nhạy cảm), vài header không
// chứa auth, và các chuỗi ASCII trong body (client name/version nằm ở đó).
// Bỏ hẳn file này khi đã xác định nguyên nhân.
#import "common.h"
#import <objc/runtime.h>

static BOOL g_diagOn = YES;

static BOOL ytm_isApiHost(NSURL *url) {
    NSString *host = url.host.lowercaseString;
    return [host containsString:@"youtubei"] || [host hasSuffix:@".goog"] ||
           [host containsString:@".goog"] || [host containsString:@"youtube.com"];
}

static NSString *ytm_printable(NSData *body, NSUInteger max) {
    if (!body.length) return @"";
    const unsigned char *p = (const unsigned char *)body.bytes;
    NSUInteger n = MIN(body.length, max);
    NSMutableString *out = [NSMutableString stringWithString:@"|"];
    NSMutableString *run = [NSMutableString string];
    BOOL readable = YES;
    for (NSUInteger i = 0; i < n; i++) {
        unsigned char c = p[i];
        if (c >= 32 && c < 127) {
            [run appendFormat:@"%c", c];
        } else {
            if (readable && run.length >= 4) {
                [out appendFormat:@" %@", run];
            }
            [run setString:@""];
            readable = YES;
        }
    }
    if (run.length >= 4) [out appendFormat:@" %@", run];
    return out.length > 1 ? out : @"";
}

static void ytm_logRequest(NSURLRequest *req) {
    if (!g_diagOn || !req.URL) return;
    NSURL *url = req.URL;
    if (!ytm_isApiHost(url)) return;
    NSMutableString *hdrs = [NSMutableString string];
    [req.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *k, NSString *v, BOOL *stop) {
        NSString *lk = k.lowercaseString;
        if ([lk containsString:@"auth"] || [lk containsString:@"cookie"] ||
            [lk containsString:@"token"] || [lk containsString:@"sapisid"] ||
            [lk containsString:@"sid"] || [lk containsString:@"gvn"]) {
            return;
        }
        [hdrs appendFormat:@" %@=%@", k, v];
    }];
    NSString *q = url.query ?: @"";
    if (q.length > 300) q = [q substringToIndex:300];
    YTModLog(@"[net] %@ %@%@?%@%@", req.HTTPMethod ?: @"GET", url.host, url.path, q,
             ytm_printable(req.HTTPBody, 400));
    if (hdrs.length) YTModLog(@"[net]   hdr%@", hdrs);
}

static IMP _orig_taskResume;
static void ytm_taskResume(NSURLSessionTask *self, SEL _cmd) {
    @try {
        NSURLRequest *r = self.originalRequest ?: self.currentRequest;
        ytm_logRequest(r);
    } @catch (__unused NSException *e) {}
    ((void (*)(id, SEL))_orig_taskResume)(self, _cmd);
}

static IMP _orig_statusCode;
static NSInteger ytm_statusCode(NSHTTPURLResponse *self, SEL _cmd) {
    NSInteger code = ((NSInteger (*)(id, SEL))_orig_statusCode)(self, _cmd);
    if (g_diagOn && code >= 400) {
        NSURL *url = self.URL;
        if (ytm_isApiHost(url)) {
            NSString *q = url.query ?: @"";
            if (q.length > 300) q = [q substringToIndex:300];
            YTModLog(@"[net] ← %ld %@%@?%@", (long)code, url.host, url.path, q);
        }
    }
    return code;
}

static void ytm_swizzleDiag(Class cls, SEL sel, IMP hook, IMP *orig) {
    if (!cls) return;
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        YTModLog(@"[net] MISS %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    *orig = method_getImplementation(m);
    class_replaceMethod(cls, sel, hook, method_getTypeEncoding(m));
}

void YTDiagInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_diagOn = YTModBool(@"net_log", YES);
        if (!g_diagOn) return;
        ytm_swizzleDiag([NSURLSessionTask class], @selector(resume), (IMP)ytm_taskResume, &_orig_taskResume);
        ytm_swizzleDiag([NSHTTPURLResponse class], @selector(statusCode), (IMP)ytm_statusCode, &_orig_statusCode);
        YTModLog(@"[net] ghi request/response BẬT");
    });
}
