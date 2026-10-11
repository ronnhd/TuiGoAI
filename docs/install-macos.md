# TuiGoAI trên macOS

## Cài đặt

### Cách 1: Tải bản phát hành (Khuyến nghị)

1. **Tải về:** [TuiGoAI.dmg](https://github.com/ronnhd/TuiGoAI/releases)
2. **Cài đặt:** Mở file `.dmg` → Kéo vào **Applications**
3. **Cho phép chạy:** (Lưu ý gỡ kiểm dịch macOS sau khi kéo app)
   ```bash
   xattr -cr /Applications/TuiGoAI.app
   ```
4. **Cấp quyền:** Mở app → System Settings → Privacy & Security → Accessibility → Bật **TuiGoAI**

---

## Sử dụng

| Phím tắt | Chức năng |
|----------|-----------|
| `Ctrl + Space` | Bật/tắt tiếng Việt |
| `Option + Space` | Kích hoạt AI Copilot tại con trỏ |

### Telex (mặc định)

| Gõ | Kết quả |
|----|---------|
| `as`, `af`, `ar`, `ax`, `aj` | á, à, ả, ã, ạ |
| `aa`, `aw`, `ee`, `oo` | â, ă, ê, ô |
| `ow`, `uw`, `dd` | ơ, ư, đ |

### Đổi sang VNI
Menu Bar → Cài đặt → Kiểu gõ → **VNI**

| Gõ | Kết quả |
|----|---------|
| `a1`, `a2`, `a3`, `a4`, `a5` | á, à, ả, ã, ạ |
| `a6`, `a8`, `o6`, `e6` | â, ă, ô, ê |
| `o7`, `u7`, `d9` | ơ, ư, đ |

### Tính năng khác
- **AI Copilot:** Chọn text hoặc để con trỏ cuối câu → nhấn `Option + Space` để mở palette AI (sửa chính tả, viết tiếp, tóm tắt, dịch).
- **Gõ tắt:** Menu Bar → Cài đặt → Gõ tắt → Thêm từ viết tắt
- **Ngoại lệ:** Menu Bar → Cài đặt → Ngoại lệ → Thêm app không muốn gõ tiếng Việt

---

## Nâng cấp & Gỡ cài đặt

**Thủ công:**
1. Menu Bar → **Thoát**
2. Xóa app từ Applications
3. (Tùy chọn) Xóa cấu hình:
   ```bash
   rm -rf ~/.config/tuigoai ~/Library/Preferences/org.gonhanh.*
   ```

---

## Xử lý sự cố

**App không mở được?**
```bash
xattr -cr /Applications/TuiGoAI.app
```

**Không gõ được tiếng Việt?**
1. Kiểm tra icon Menu Bar hiển thị "VN"
2. Nhấn `Ctrl + Space`
3. Kiểm tra quyền Accessibility đã bật

**Sau khi cập nhật macOS:**
System Settings → Privacy & Security → Accessibility → Tắt/bật lại TuiGoAI

---

## Yêu cầu hệ thống
- macOS 13.0 (Ventura) trở lên
- Apple Silicon (M1/M2/M3/M4) hoặc Intel x86_64
