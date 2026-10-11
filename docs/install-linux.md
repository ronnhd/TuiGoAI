# TuiGoAI trên Linux

TuiGoAI cho Linux là addon Fcitx5 beta, hiện phát hành binary cho **x86_64**.
Trình cài đặt thêm TuiGoAI vào profile hiện có và không xoá Bamboo hoặc input
method khác.

## Cài đặt

```bash
curl -fsSL https://raw.githubusercontent.com/ronnhd/TuiGoAI/main/scripts/setup/linux.sh | bash
```

Sau khi cài:

1. Đăng xuất rồi đăng nhập lại để desktop nạp Fcitx5.
2. Chạy `source ~/.profile` để dùng lệnh `gn` ngay trong terminal hiện tại.
3. Chạy `gn on` để chọn TuiGoAI.

Có thể tải archive thủ công tại
[`tuigoai-linux.tar.gz`](https://github.com/ronnhd/TuiGoAI/releases/latest/download/tuigoai-linux.tar.gz),
giải nén và chạy `tuigoai-linux/install.sh`.

## Sử dụng

| Lệnh | Chức năng |
|------|-----------|
| `gn` hoặc `gn toggle` | Bật/tắt riêng TuiGoAI |
| `gn on` | Chọn và bật TuiGoAI |
| `gn off` | Tắt TuiGoAI nếu đang được chọn |
| `gn vni` | Chuyển sang VNI, tải lại Fcitx5 và bật TuiGoAI |
| `gn telex` | Chuyển sang Telex, tải lại Fcitx5 và bật TuiGoAI |
| `gn status` | Xem trạng thái riêng của TuiGoAI và input method hiện tại |
| `gn update` | Cài bản Linux mới nhất |
| `gn uninstall` | Gỡ TuiGoAI, giữ nguyên input method khác |
| `gn version` | Xem phiên bản |
| `gn help` | Hiển thị trợ giúp |

Phím chuyển input method mặc định của Fcitx5 thường là `Ctrl + Space`; cấu hình
thực tế phụ thuộc desktop.

## Gỡ cài đặt

```bash
gn uninstall
```

Trình gỡ cài đặt chỉ xoá file và profile item của TuiGoAI. Bản sao profile trước
lần chỉnh đầu tiên được giữ tại `~/.config/fcitx5/profile.tuigoai.bak`.

## Xử lý sự cố

### Không tìm thấy `gn`

```bash
source ~/.profile
```

Hoặc mở terminal mới sau khi đăng nhập lại.

### TuiGoAI chưa xuất hiện

```bash
fcitx5 -r
fcitx5-configtool
```

Kiểm tra các file:

```bash
ls ~/.local/lib/fcitx5/tuigoai.so
ls ~/.local/share/fcitx5/inputmethod/tuigoai.conf
```

### Addon không tải được

```bash
ldd ~/.local/lib/fcitx5/tuigoai.so
fcitx5 --verbose=*:4
```

### Kiến trúc ARM64 hoặc distro khác

Binary phát hành hiện chỉ hỗ trợ x86_64. Xem hướng dẫn build trong
[`platforms/linux/README.md`](../platforms/linux/README.md).

## Cài Fcitx5 thủ công

```bash
# Ubuntu/Debian
sudo apt install fcitx5 fcitx5-config-qt

# Fedora
sudo dnf install fcitx5 fcitx5-configtool

# Arch Linux
sudo pacman -S fcitx5 fcitx5-configtool
```
