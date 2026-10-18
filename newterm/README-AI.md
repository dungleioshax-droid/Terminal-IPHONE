# NewTerm 3 AI

**NewTerm 3 AI là một phần của dự án Terminal này** — mã nguồn trong `newterm/`
được tích hợp thẳng vào repo, kèm sẵn **môi trường AI CLI hoàn chỉnh**: mở app
là chạy được Claude Code, không cần cài Node.js từ repo nào cả.

> Toàn bộ dự án (app Terminal + NewTerm 3 AI) nằm trong **một repo GitHub duy
> nhất**. CI ở gốc repo build cả hai:
> - `../.github/workflows/build-deb.yml` — app Terminal (runner Linux)
> - `../.github/workflows/newterm-ios.yml` — NewTerm 3 AI (runner macOS) ← chỉ
>   chạy khi có thay đổi trong `newterm/`, để không tốn phút macOS vô ích

---

## Có gì khác so với bản gốc?

Toàn bộ runtime được **nhúng thẳng trong file .deb** (máy điện thoại không cần
tải gì thêm ngoài lúc `npm install` claude-code):

| Thành phần | Ghi chú |
|---|---|
| Node.js 18.20.4 (arm64 iOS) | binary từ [imcynic/nodejs-ios](https://github.com/imcynic/nodejs-ios), SHA-256 pin ở bước build |
| npm 10.8.2 | bản npm cuối cùng chạy ổn với Node 18, tải lúc build và verify sha512 |
| wrapper `node` | tự thêm V8 flags an toàn cho iOS + preload shim `Intl.Segmenter` |
| `aienv` | quản lý môi trường: `doctor`, `fix-node`, `install-claude`, `python`… |
| `claude-auth` | đăng nhập Claude Code (API key hoặc OAuth Max/Pro ngay trên máy) |
| postinst | tự ký lại Node (JIT entitlements), tự cài `@anthropic-ai/claude-code@2.1.19` chạy nền — log ở `/var/mobile/newterm-ai.log` |
| symlink `<root>/usr/bin` + `profile.d` | `node`, `npm`, `npx`, `aienv`, `claude`… có mặt trong PATH của mọi shell |
| Settings → **AI CLI** | màn hình mới trong app: xem trạng thái, chạy check / cài / sửa ngay trong app |

Kết quả: mở NewTerm, gõ `aienv doctor` → `claude-auth` → `claude`. Hết.

## Build

### Cách 1 — GitHub Actions (khuyến nghị, không cần máy Mac)

Repo Terminal đã được `git init` + commit sẵn ở gốc dự án — chỉ cần đẩy lên
GitHub một lần:

```bash
cd ..          # gốc dự án Terminal (đã là git repo)
gh repo create terminal-iphone --private --source=. --push
# hoặc thủ công:
git remote add origin git@github.com:<tài-khoản>/<tên-repo>.git
git push -u origin main
```

Sau đó vào tab **Actions** của repo:

- **NewTerm 3 AI (iOS)** — tự chạy khi push thay đổi trong `newterm/`, hoặc bấm
  *Run workflow*. Kết quả trong artifact của từng run:
  - `newterm3-ai-rootless` → `iphoneos-arm64` (Procursus/Dopamine, prefix `/var/jb`)
  - `newterm3-ai-roothide` → `iphoneos-arm64e` (bootstrap RootHide — máy bạn)
- **Build RootHide deb (Linux)** — app Terminal như trước.

> CI NewTerm cần runner macOS vì project gốc build bằng Xcode qua Theos
> (`xcodeproj.mk`). Repo private vẫn được ~2000 phút macOS/tháng, mỗi lần build
> ~5–10 phút; filter `paths: newterm/**` giúp không đốt phút khi chỉ sửa app Terminal.

### Cách 2 — máy Mac có Xcode + Theos

```bash
cd newterm
gmake package THEOS=~/theos ROOTLESS=1 FINALPACKAGE=1   # hoặc ROOTHIDE=1
```

File deb nằm ở `newterm/packages/`.

## Cài đặt trên máy

1. Tải `.deb` từ artifact (giải nén zip của Actions).
2. Mở file bằng **Sileo** (hoặc Filza → chọn .deb) → Install.
3. Nếu đang có NewTerm 3 bản gốc từ repo khác: gói này **cùng Package ID**
   (`ws.hbang.newterm3`), version `3.0~beta1+ai1` > `3.0~beta1` nên sẽ ghi đè
   nâng cấp bình thường.
4. Mở app → **Settings → AI CLI**:
   - *Environment check (aienv doctor)* — kiểm tra tổng thể
   - *Install / Repair Claude Code* — cài/sửa claude-code
   - *Reinstall / Re-sign Node.js* — nếu runtime có vấn đề

## Sử dụng trên terminal

```sh
aienv doctor          # bảng chẩn đoán toàn bộ (node, npm, mạng, auth)
aienv install-claude  # cài/repair claude-code (đã tự chạy nền lúc cài gói)
claude-auth           # đăng nhập (1 = API key, 2 = OAuth Max/Pro, 3 = xem trạng thái)
claude                # chạy Claude Code
```

Trạng thái auth nằm ở `~/.claude/.credentials.json` (API key hoặc OAuth).

## Cập nhật theo upstream (hbang/NewTerm)

Vì NewTerm giờ là **một phần của repo Terminal** (không còn git riêng), việc kéo
upstream thực hiện bằng so sánh thủ công:

```bash
git clone --depth=1 https://github.com/hbang/NewTerm.git /tmp/hbang-newterm
diff -r /tmp/hbang-newterm newterm \
  -x .git -x build -x dist -x .theos -x packages \
  -x README-AI.md -x Tools -x layout
# rồi copy những file cần cập nhật từ /tmp/hbang-newterm vào newterm/
```

Các phần **của mình** (giữ nguyên khi sync): `Tools/`, `layout/`, `README-AI.md`,
khối `ROOTHIDE=1` + hook `after-stage` trong `Makefile`, `control`, `.gitignore`,
nhóm "AI CLI" trong `App/UI/Settings/iOS/SettingsView.swift` và `enum AIEnv` ở
cuối `Common/Controllers/SubProcess.swift`.

## Giới hạn đã biết

- **Node 18** là bản mới nhất chạy ổn định trên iOS (binary arm64): đủ cho
  `claude-code` (bản JS-only `2.1.19`).
- `claude-code` phiên bản ≥ 2.1.113 chuyển sang binary native → **không** chạy
  được trên iOS; đừng nâng cấp vượt `2.1.19` (qua `aienv install-claude <version>`
  bạn có thể thử bản khác).
- **Gemini CLI** cần Node ≥ 20 — chưa hỗ trợ trong bản này.
- **OpenCode / Codex** phát hành binary Rust/bun native, không có build cho iOS —
  không cài được.
- Phần tìm kiếm của claude cần `ldid` có mặt trên máy để ký lại helper `rg`;
  thiếu `ldid` thì claude vẫn chạy (chỉ giảm chất lượng search).

## Ghi chú kỹ thuật

- Mọi script đều POSIX `sh`, mọi đường dẫn được suy ra từ `dirname $0` → chạy
  đúng trên **rootful** (`/`), **rootless** (`/var/jb`) và **RootHide** (root
  ngẫu nhiên, đi qua symlink tương đối trong `<root>/usr/bin`).
- `Tools/fetch-ai-runtime.mjs` chạy ở `after-stage` của Theos: tải Node deb +
  npm (verify SHA-256 / sha512), stage vào `$(THEOS_STAGING_DIR)$(INSTALL_PREFIX)`
  rồi Makefile ký `node` bằng `ldid -S entitlements.xml`.
- Node binary giữ nguyên byte từ nguồn (đã verify hash) — chỉ được ký lại
  entitlements JIT (`platform-application`, `allow-jit`, `dynamic-codesigning`…).

## Giấy phép

- Mã nguồn NewTerm gốc: Apache License 2.0 — Copyright HASHBANG Productions
  (xem `LICENSE.md` và `README.md` gốc trong thư mục này).
- Node.js: MIT. npm: Artistic-2.0.
- Phần bổ sung cho môi trường AI (`Tools/`, `layout/`, các đoạn Swift thêm vào)
  thuộc dự án Terminal.
