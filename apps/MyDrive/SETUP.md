# SETUP — MyDrive: cấu hình Google Cloud để đăng nhập được

App MyDrive cần 1 **OAuth Client ID** (loại iOS) để đăng nhập Google qua OAuth.
Chỉ làm 1 lần, ~5 phút, miễn phí.

## Vì sao phải tự tạo?

- Google **cấm app tự nhập gmail/mật khẩu** — đăng nhập phải qua trang Google
  (OAuth). Client ID chính là "danh tính" của app với Google.
- OAuth consent screen phải để **In production** (không cần gửi verify) — nếu để
  "Testing" thì refresh token **hết hạn sau 7 ngày** và app sẽ đòi đăng nhập lại
  liên tục. Chỉ dùng scope `drive.file` (không phải scope nhạy cảm) nên **không
  cần Google duyệt**, không màn hình cảnh báo "app chưa được xác minh".

## Các bước

### 1. Tạo project Google Cloud

1. Mở https://console.cloud.google.com/projectcreate
2. Đặt tên vd `MyDrive` → **Create**.

### 2. Bật Google Drive API

1. Vào https://console.cloud.google.com/apis/library/drive.googleapis.com
   (chọn đúng project vừa tạo ở thanh trên).
2. Bấm **Enable**.

### 3. Tạo OAuth consent screen

1. Menu ≡ → **APIs & Services** → **OAuth consent screen**.
2. User type: **External** → **Create**.
3. Điền tối thiểu: App name `MyDrive`, email hỗ trợ của bạn, email developer.
   Các bước sau bấm **Save and Continue** cho tới khi xong (không thêm scope
   nào trong consent screen).
4. Quay lại **OAuth consent screen** → mục **Publishing status** → bấm
   **PUBLISH APP** → confirm **In Production**.
   ⚠️ Bước này bắt buộc — không thì refresh token chết sau 7 ngày.

### 4. Tạo OAuth Client ID (loại iOS)

1. **APIs & Services** → **Credentials** → **+ Create Credentials** →
   **OAuth client ID**.
2. Application type: **iOS**.
3. Bundle ID: `vn.vudv.mydrive`
4. **Create** → copy **Client ID** (dạng
   `1234567890-abcdefg.apps.googleusercontent.com`).

### 5. Đưa Client ID vào app

Trong thư mục `apps/MyDrive/`:

```
cp oauth_client.example.txt oauth_client.txt
# mở oauth_client.txt, dán Client ID vào (1 dòng)
./build.sh            # build lại — build.sh tự đọc file này ghi vào Info.plist
```

Sau đó cài lại app qua Ksign (source `http://<IP>:8765/source.json` hoặc file
`apps/MyDrive/xtool/MyDrive.ipa`), mở tab **Tài khoản** → **Thêm tài khoản
Google** → màn Google hiện ra → đăng nhập/chọn account → xong.

> Đổi client ID sau này: chỉ cần sửa `oauth_client.txt` + build + cài lại.
> File `oauth_client.txt` không được commit (đã thêm vào `.gitignore`).

## Lưu ý

- **Token**: refresh token nằm trong Keychain của iPhone. Xóa app → mất
  Keychain → cài lại phải đăng nhập lại từng account **1 lần** (Safari thường
  nhớ phiên Google nên chỉ chọn account là xong). Sau đó app tự tìm thư mục
  `MyDrive` trên Drive và kéo toàn bộ dữ liệu về.
- **Thu hồi**: hủy quyền app trong https://myaccount.google.com/permissions
  sẽ làm refresh token chết → app báo "Cần đăng nhập lại".
- Dữ liệu nằm trong thư mục `MyDrive/` trên Drive của từng account; file lớn
  ≥ 256 MiB thành các part `tên-file.myd-part-0001` mang `appProperties` để
  app nhận diện. **Đừng xóa tay** các file lạ có đuôi `.myd-part-` hay file
  `index.json` trong thư mục `MyDrive/` — đó là dữ liệu của app.
