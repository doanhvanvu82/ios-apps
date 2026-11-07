---
description: "CI macOS bash 3.2 coi \"$VAR…\" là tên biến"
evidence:
  - path: "toolkit/build_app.sh"
    quote: "echo \"→ Building với ${XTOOL}…\""
  - path: "toolkit/build_all.sh"
    quote: "set -uo pipefail\n\nROOT=\"$(cd \"$(dirname \"${BASH_SOURCE[0]}\")/..\" && pwd)\""
  - path: ".github/workflows/build.yml"
    quote: "runs-on: ${{ vars.BUILD_RUNNER || 'macos-latest' }}"
---
GitHub Actions chạy `macos-latest` bằng bash 3.2: khi biến viết liền ký tự Unicode (vd `$XTOOL…` với dấu …) thì bash gộp cả ký tự vào tên biến → `XTOOL…: unbound variable` và `set -u` làm fail cả bước build. Luôn viết `${VAR}` trước ký tự không phải ASCII. `build_all.sh` cố ý dùng `set -uo pipefail` (không `-e`) để một mục lỗi không dừng cả lượt.
