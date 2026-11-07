---
description: "Google Cloud MyDrive: đã Publish In production xong"
evidence:
  - path: "apps/MyDrive/oauth_client.txt"
    quote: "205146002516-8op6ah9qpglbpnst6t3645rsdfqp0hl7.apps.googleusercontent.com"
  - path: "PRIVACY.md"
    quote: "# Chính sách quyền riêng tư — MyDrive\n\n_Cập nhật lần cuối: 07/11/2026_\n\nMyDrive là ứng dụng iOS giúp bạn quản lý tệp trên Google Drive cá nhân của mình."
---
Google Cloud MyDrive: project `mydrive-514004`, OAuth client iOS `205146002516-8op6ah9qpglbpnst6t3645rsdfqp0hl7.apps.googleusercontent.com`, Drive API bật, consent screen **In production** (đã publish 07/11/2026 — refresh token không còn chết sau 7 ngày). Nút Publish từng bị khóa: nguyên nhân là THIẾU Privacy policy URL trên Branding (bắt buộc 3 trường: home page, privacy policy, authorized domain) — đã fix bằng PRIVACY.md trong repo + link github.com/doanhvanvu82/ios-apps/blob/main/PRIVACY.md. Banner "requires verification" là nhắc nhở chung, KHÔNG chặn token với scope drive.file (non-sensitive). Lưu ý đăng nhập có thể gặp màn "unverified app" → Advanced → Go to MyDrive.
