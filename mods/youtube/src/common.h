// Cấu hình + log chung cho dylib mod YouTube.
// Log ghi ra Documents/Logs/<ngày>.log để cắm USB lấy về bằng
// toolkit/pull_app_logs.sh (NSLog trên iOS 27 sideload thường không đọc được).
#pragma once

#import <Foundation/Foundation.h>

// build.sh truyền vào; thiếu thì vẫn biên dịch được (build tay).
#ifndef YT_VERSION_TAG
#define YT_VERSION_TAG "dev"
#endif
#ifndef YT_BUILD_LABEL
#define YT_BUILD_LABEL "dev"
#endif

#ifdef __cplusplus
extern "C" {
#endif

BOOL YTModBool(NSString *key, BOOL def);
void YTModSetBool(NSString *key, BOOL v);
void YTModFlush(void);
void YTModLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

// Mở file log (gọi sớm trong constructor).
void YTModLogOpen(void);

#ifdef __cplusplus
}
#endif
