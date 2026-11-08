// Chẩn đoán mất login (mod 3.23): khi app vào foreground, in danh sách cookie
// SSO của youtube.com + accounts.google.com. Login Google iOS lưu token ở
// keychain NHƯNG session cookie (SAPISID…) ở NSHTTPCookieStorage (Library/
// Cookies — file persist). Nếu cookies mất sau khi đóng app = container bị
// iOS xoá / không flush; nếu cookies còn mà mất login = keychain.
#import "common.h"
#import "hooks.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

void YTKeychainDiagInstall(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class sec = objc_getClass("SecStaticPlaceholder") ?: Nil;
        (void)sec;  // SecItem* là hàm C — hook qua CFFunction pointer không được;
                    // thay thế: dùng fishhook? Không có. Ghi chú: SecItem không
                    // hook được bằng method swizzle vì là C function.
        // C làm thật: swizzle qua rebind các symbol trong DYLD bằng fishhook là
        // phức tạp. DÙNG CÁCH KHÁC: log trạng thái NSHTTPCookieStorage khi app
        // vào foreground — xem cookie SSO còn không.
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        NSHTTPCookieStorage *store = [NSHTTPCookieStorage sharedHTTPCookieStorage];
                        NSArray *cookies = [store cookiesForURL:[NSURL URLWithString:@"https://youtube.com"]];
                        NSMutableString *names = [NSMutableString string];
                        for (NSHTTPCookie *ck in cookies) {
                            [names appendFormat:@" %@", ck.name];
                        }
                        YTModLog(@"keychain-diag: cookies youtube.com (%lu):%@",
                                 (unsigned long)cookies.count, names);
                        NSArray *g = [store cookiesForURL:[NSURL URLWithString:@"https://accounts.google.com"]];
                        names = [NSMutableString string];
                        for (NSHTTPCookie *ck in g) {
                            [names appendFormat:@" %@", ck.name];
                        }
                        YTModLog(@"keychain-diag: cookies accounts.google.com (%lu):%@",
                                 (unsigned long)g.count, names);
                    }];
        YTModLog(@"keychain-diag: cài xong (cookie check mỗi foreground)");
    });
}
