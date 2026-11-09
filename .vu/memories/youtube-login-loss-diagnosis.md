---
description: "Mất login YouTube khi cài qua Ksign: keychain/app group của Google, sửa bằng sideloadfix"
evidence:
  - path: "mods/youtube/src/sideloadfix.mm"
    quote: "    CFDictionaryRemoveValue(m, kSecAttrAccessGroup);"
  - path: "mods/youtube/src/sideloadfix.mm"
    quote: "    u = [[lib URLByAppendingPathComponent:@\"AppGroups\" isDirectory:YES]"
---
Mất login YouTube sau khi đóng app KHÔNG do mod: thí nghiệm 3.29 bản C (IPA gốc, không dylib, chỉ ký lại) vẫn mất. Gốc: provisioning profile của chứng chỉ Ksign chỉ có keychain-access-groups <TEAM>.* và KHÔNG có app group, còn YouTube ghi token vào keychain EQHXZ8M8AV.com.google.common.SSO và group.com.google.* → iOS từ chối (-34018), token không lưu. Entitlements trong chữ ký (ldid -e) vẫn ghi group Google nên nhìn binary tưởng ổn — phải đọc profile trên máy (ideviceprovision copy). Sửa (3.30, xác nhận trên máy): sideloadfix.mm chạy trong constructor, bỏ kSecAttrAccessGroup khỏi SecItemAdd/CopyMatching/Update/Delete bằng ghi đè slot __got của các image trong bundle (log "sideloadfix: keychain OK (N slot)"), containerURLForSecurityApplicationGroupIdentifier: trả nil → Library/AppGroups/<id>. Sau khi cài bản có sửa phải đăng nhập lại một lần. Bài học: lỗi lạ thì thử bản gốc/không hook trước, đừng thêm log từng bước (3.23–3.28 phí công).
