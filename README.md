<h1 align="center">
  TuiGoAI (Tui Gõ AI)
</h1>

<p align="center">
  <strong>Bộ gõ tiếng Việt hiện đại tích hợp AI Copilot cho macOS</strong><br>
  Tốc độ gõ 0ms latency · Auto-restore tiếng Anh · Trợ lý AI ngay tại con trỏ văn bản
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-BSD--3--Clause-blue.svg" alt="License: BSD-3-Clause">
  <img src="https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Engine-Rust%20%2B%20Swift-orange" />
  <img src="https://img.shields.io/badge/AI-Local%20LLM%20%2F%20OpenAI-purple" />
</p>

---

## 💡 Giới thiệu

**TuiGoAI** ("Tui Gõ AI") là bộ gõ tiếng Việt mã nguồn mở thế hệ mới dành cho macOS, kết hợp giữa:
1. **Engine gõ tiếng Việt hiệu năng cao**: Kế thừa nền tảng từ bộ gõ [GoNhanh](https://github.com/khaphanspace/gonhanh.org) (Rust core), độ trễ <10ms, không lag, không nuốt phím trong Terminal/IDE.
2. **AI Copilot ngay tại con trỏ**: Kích hoạt trợ lý AI xử lý văn bản (sửa chính tả theo ngữ cảnh, tóm tắt, viết lại, dịch thuật, ghost text gợi ý) mà không làm gián đoạn luồng gõ phím.
3. **Linh hoạt & Tôn trọng riêng tư**: Hỗ trợ chạy hoàn toàn offline qua **Local LLM** (Ollama, MLX trên Apple Silicon) hoặc kết nối qua **OpenAI / Custom API Endpoints**.

---

## ✨ Tính năng nổi bật

### ⚡ 1. Bộ gõ chuẩn xác & Siêu tốc
- **Độ trễ tiệm cận 0ms**: Xử lý Telex/VNI bằng lõi Rust thuần túy, phản hồi tức thì dưới 10ms.
- **Auto-restore tiếng Anh**: Tự động nhận diện từ tiếng Anh khi nhấn Space (`text`, `expect`, `user`, `with`, `push`...) mà không cần tắt bộ gõ.
- **Phục hồi bằng ESC**: Bấm nhầm dấu? Chỉ cần nhấn `ESC` để khôi phục nguyên dạng chuỗi phím tiếng Anh vừa gõ.
- **Tối ưu cho Developer**: Tương thích tốt với Terminal, VS Code, Cursor, Zed, Chrome và các ứng dụng Electron.

### 🤖 2. AI Copilot tại chỗ (In-place Assistant)
- **Kích hoạt tức thì**: Nhấn phím tắt nhanh (`Option + Space`) để mở thanh điều khiển AI ngay tại vị trí con trỏ.
- **Sửa chính tả ngữ cảnh**: Tự động rà soát và sửa lỗi chính tả tiếng Việt dựa trên toàn bộ câu.
- **Viết tiếp & Biến đổi giọng văn**: Hỗ trợ tóm tắt, viết dài hơn, đổi tone giọng (trang trọng/thân mật) hoặc dịch nhanh sang tiếng Anh.
- **Async & An toàn**: Luồng AI chạy hoàn toàn bất đồng bộ ở background, không bao giờ block luồng gõ phím. Tự động tắt khi ở trường mật khẩu.

### 🔌 3. Tùy chọn mô hình đa dạng (Pluggable AI Backends)
- **Local Free AI**: Kết nối với Ollama hoặc MLX (Qwen 2.5, Llama 3) chạy trực tiếp trên NPU của chip Apple Silicon, bảo mật dữ liệu tuyệt đối và không tốn phí API.
- **Cloud / Custom API**: Hỗ trợ các endpoint chuẩn OpenAI (ChatGPT Plus/Pro, DeepSeek, Claude, v.v.).

---

## 🛠️ Cài đặt & Build từ mã nguồn

### Yêu cầu hệ thống
- macOS 13.0 (Ventura) trở lên
- Xcode 15+ & Swift 6.0+
- Rust (Cargo) 1.80+

### Build ứng dụng
```bash
# 1. Clone repository
git clone https://github.com/ronnhd/TuiGoAI.git
cd TuiGoAI

# 2. Kiểm tra bộ test của Rust Core
cargo test --manifest-path core/Cargo.toml

# 3. Build ứng dụng macOS
make build
```

Sau khi build xong, app sẽ nằm tại `platforms/macos/build/Release/TuiGoAI.app`.

---

## 📐 Kiến trúc kỹ thuật

Dự án tuân thủ nghiêm ngặt nguyên tắc **Strict Core Separation**:

```text
┌────────────────────────────────────────────────────────┐
│                      macOS App                         │
│  (SwiftUI: MenuBar, Settings, Shortcuts, Overlay UI)   │
└──────────────┬──────────────────────────┬──────────────┘
               │ (Direct Events)          │ (Async Triggers)
               ▼                          ▼
┌─────────────────────────────┐  ┌───────────────────────┐
│     gonhanh-core (Rust)     │  │   TuiGoAI Copilot     │
│  Telex/VNI State Machine    │  │   Local LLM / OpenAI  │
│  Latency < 10ms (Native)    │  │   Background Tasks    │
└─────────────────────────────┘  └───────────────────────┘
```

1. **`core/`**: Rust core xử lý biến âm, từ điển kiểm tra âm tiết tiếng Việt và thuật toán auto-restore tiếng Anh.
2. **`platforms/macos/`**: Tầng Native macOS chịu trách nhiệm lắng nghe sự kiện phím qua `CGEventTap` và hiển thị UI.
3. **`platforms/macos/AIService.swift`**: Module giao tiếp bất đồng bộ với các provider LLM.

---

## 📄 Bản quyền & Ghi nhận (Credits)

- **Tác giả & Duy trì**: Ron Ng ([@ronnhd](https://github.com/ronnhd))
- **Kế thừa nền tảng**: Bộ gõ phát triển dựa trên mã nguồn mở của [GoNhanh](https://github.com/khaphanspace/gonhanh.org) của tác giả Kha Phan.
- **Giấy phép**: Phát hành theo giấy phép [BSD-3-Clause](LICENSE).
