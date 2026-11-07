// Đọc/ghi cấu hình qua NSUserDefaults suite riêng, tách khỏi dữ liệu game.
// Giá trị dùng trong đường hook được cache ở biến volatile trong hooks.mm.
#import "common.h"

static NSUserDefaults *g_defaults = nil;
static NSMutableString *g_log = nil;
static NSLock *g_logLock = nil;
static dispatch_queue_t g_fileQueue = NULL;
static NSString *g_filePath = nil;

static NSUserDefaults *defaults(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g_defaults = [[NSUserDefaults alloc] initWithSuiteName:@"vn.vudv.cherrytale.mod"];
    });
    return g_defaults;
}

double CTConfigGetNumber(NSString *key, double def) {
    id v = [defaults() objectForKey:key];
    return v ? [v doubleValue] : def;
}

BOOL CTConfigGetBool(NSString *key, BOOL def) {
    id v = [defaults() objectForKey:key];
    return v ? [v boolValue] : def;
}

void CTConfigSetNumber(NSString *key, double v) { [defaults() setDouble:v forKey:key]; }
void CTConfigSetBool(NSString *key, BOOL v) { [defaults() setBool:v forKey:key]; }
NSString *CTConfigGetString(NSString *key, NSString *def) {
    id v = [defaults() objectForKey:key];
    return [v isKindOfClass:[NSString class]] ? v : def;
}
void CTConfigSetString(NSString *key, NSString *v) {
    if (v) [defaults() setObject:v forKey:key]; else [defaults() removeObjectForKey:key];
}
void CTConfigFlush(void) { [defaults() synchronize]; }

// ---- log ----
// Ghi thêm ra Documents/Logs/<ngày>.log để cắm USB lấy về bằng
// toolkit/pull_app_logs.sh (NSLog trên iOS 27 sideload thường không đọc được).
static void ct_append_file(NSString *line) {
    if (!g_filePath) return;
    if (!g_fileQueue) g_fileQueue = dispatch_queue_create("vn.vudv.cherrytale.log", DISPATCH_QUEUE_SERIAL);
    NSString *path = g_filePath;
    dispatch_async(g_fileQueue, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        if (![fm fileExistsAtPath:path]) {
            [data writeToFile:path atomically:YES];
            return;
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { [data writeToFile:path atomically:YES]; return; }
        @try {
            [h seekToEndOfFile];
            [h writeData:data];
            [h closeFile];
        } @catch (__unused NSException *e) {}
    });
}

void CTLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    static NSDateFormatter *df = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        df = [NSDateFormatter new];
        df.dateFormat = @"HH:mm:ss.SSS";
        g_log = [NSMutableString new];
        g_logLock = [NSLock new];

        NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        if (docs.length) {
            NSString *dir = [docs stringByAppendingPathComponent:@"Logs"];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES attributes:nil error:nil];
            NSDateFormatter *day = [NSDateFormatter new];
            day.dateFormat = @"yyyyMMdd";
            g_filePath = [dir stringByAppendingPathComponent:
                          [NSString stringWithFormat:@"%@.log", [day stringFromDate:[NSDate date]]]];
        }
    });

    NSString *line = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], msg];
    NSLog(@"[CherryTaleMod] %@", msg);
    ct_append_file(line);

    [g_logLock lock];
    if (g_log.length > 200000) [g_log deleteCharactersInRange:NSMakeRange(0, 100000)];
    [g_log appendFormat:@"%@\n", line];
    [g_logLock unlock];
}

NSString *CTLogText(void) {
    [g_logLock lock];
    NSString *s = [g_log copy] ?: @"";
    [g_logLock unlock];
    return s;
}

void CTLogClear(void) {
    [g_logLock lock];
    [g_log setString:@""];
    [g_logLock unlock];
}
