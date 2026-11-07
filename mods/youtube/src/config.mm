#import "common.h"

static NSUserDefaults *YTModDefaults(void) {
    static NSUserDefaults *d = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:@"vn.vudv.youtube.mod"];
    });
    return d;
}

BOOL YTModBool(NSString *key, BOOL def) {
    id v = [YTModDefaults() objectForKey:key];
    return v ? [v boolValue] : def;
}

void YTModSetBool(NSString *key, BOOL v) {
    [YTModDefaults() setBool:v forKey:key];
}

void YTModFlush(void) {
    [YTModDefaults() synchronize];
}

static dispatch_queue_t g_logQueue = NULL;
static NSString *g_logPath = nil;

void YTModLogOpen(void) {
    if (g_logPath) return;
    NSArray *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *base = docs.firstObject;
    if (!base.length) return;
    NSString *dir = [base stringByAppendingPathComponent:@"Logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"yyyy-MM-dd";
    NSString *name = [[df stringFromDate:[NSDate date]] stringByAppendingString:@".log"];
    g_logPath = [dir stringByAppendingPathComponent:name];
    g_logQueue = dispatch_queue_create("vn.vudv.youtube.mod.log", DISPATCH_QUEUE_SERIAL);
}

void YTModLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSDateFormatter *df = [NSDateFormatter new];
    df.dateFormat = @"HH:mm:ss.SSS";
    NSString *line = [NSString stringWithFormat:@"[%@] %@", [df stringFromDate:[NSDate date]], msg];
    NSLog(@"[YouTubeMod] %@", line);

    if (!g_logPath || !g_logQueue) return;
    NSString *path = g_logPath;
    dispatch_async(g_logQueue, ^{
        NSData *data = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        NSFileManager *fm = [NSFileManager defaultManager];
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
