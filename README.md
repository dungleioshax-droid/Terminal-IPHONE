# NewTerm 3 AI — terminal + Claude Code trên iPhone

NewTerm 3 (nguồn gốc: [HASHBANG Productions](https://github.com/hbang/NewTerm)) được
biên dịch lại kèm sẵn **môi trường AI** ngay trong file `.deb`: Node.js 18.20.4 (arm64
iOS), npm, cùng các lệnh `aienv` / `claude-auth` để cài **Claude Code chạy trực tiếp
trên máy** — không cần tải runtime từ đâu cả.

Toàn bộ mã nguồn nằm trong [`newterm/`](newterm/).

## Cài đặt

Tải `.deb` trong [`dist/`](dist/) và mở bằng Sileo:

| File | Dành cho |
| --- | --- |
| `newterm3-ai-roothide_*_iphoneos-arm64e.deb` | bootstrap **RootHide / roothide** |
| `newterm3-ai-rootless_*_iphoneos-arm64.deb` | **Dopamine** / jailbreak rootless |

Sau khi cài: mở NewTerm → Settings → **AI CLI** → *Install Claude Code*,
rồi chạy `claude-auth` và `claude` trong terminal.

Chi tiết về môi trường AI: [`newterm/README-AI.md`](newterm/README-AI.md).

## Build

GitHub Actions (macOS) tự build trong
[`.github/workflows/newterm-ios.yml`](.github/workflows/newterm-ios.yml) mỗi khi có
thay đổi trong `newterm/`. Bản build cũng nằm trong tab **Actions** của repo.

---

> Ghi chú: repo trước đây còn một app Terminal riêng (native + PWA) — đã được bỏ để chỉ
> còn duy nhất NewTerm. Cần tham khảo thì xem lại git history.
