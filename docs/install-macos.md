# TuiGoAI trên macOS

## Cài đặt

### Cách 1: Tải bản phát hành (Khuyến nghị)

1. **Tải về:** [TuiGoAI.dmg](https://github.com/ronnhd/TuiGoAI/releases) (Bản Alpha Preview)
2. **Cài đặt:** Mở file `.dmg` → Kéo vào **Applications**
3. **Vượt qua Gatekeeper macOS:**
   ```bash
   xattr -cr /Applications/TuiGoAI.app
   ```
   *(Hoặc vào `System Settings > Privacy & Security` → Bấm **Open Anyway**)*
4. **Cấp quyền Trợ năng:** Mở app → System Settings → Privacy & Security → Accessibility → Bật **TuiGoAI**
5. **Cài đặt Local AI (Ollama):**
   ```bash
   ollama run qwen2.5:3b
   ```

---

## Sử dụng & Phím tắt

| Phím tắt | Chức năng |
|----------|-----------|
| `Ctrl + Shift` *(hoặc `Ctrl + Space`)* | Bật/tắt chế độ gõ tiếng Việt |
| `Tab` | Chấp nhận toàn bộ câu gợi ý AI |
| `Option + Mũi tên phải (⌥→)` | Chấp nhận từng từ một của gợi ý AI |
| `Escape (⎋)` | Huỷ gợi ý AI / Phục hồi ký tự gốc nếu gõ nhầm dấu |
| `Space (␣)` | Tự động hoàn tác sang từ tiếng Anh nếu gõ nhầm |

### Kiểu gõ Telex (mặc định)

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

### Tính năng AI Copilot
- **Inline Ghost Text:** Khi bạn gõ dở câu và dừng lại khoảng 200ms, AI sẽ gợi ý phần viết tiếp mờ ngay sau con trỏ.
- **Tự động bắt phong cách hội thoại:** Khi chat trên Zalo, Telegram, Slack..., AI tự động học theo ngôi xưng hô của bạn (anh/em, mình/bạn).
- **Tránh trùng lặp từ:** Thuật toán FIM tự động nhận biết chữ phía sau con trỏ để không gợi ý đè lên chữ cũ.
- **Tự động cập nhật:** Menu Bar → **Kiểm tra bản cập nhật** (App cũng tự động tải ngầm bản mới mỗi 1 tiếng).
- **Gõ tắt:** Menu Bar → Cài đặt → Gõ tắt → Thêm từ viết tắt
- **Ngoại lệ:** Menu Bar → Cài đặt → Ngoại lệ → Thêm app không muốn gõ tiếng Việt

---

## Nâng cấp & Gỡ cài đặt

**Thủ công:**
1. Menu Bar → **Thoát**
2. Xóa app từ Applications
3. (Tùy chọn) Xóa cấu hình:
   ```bash
   rm -rf ~/.config/tuigoai ~/Library/Preferences/com.ronnhd.TuiGoAI.*
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
