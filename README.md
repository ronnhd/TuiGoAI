<h1 align="center">
  TuiGoAI (Tui Gõ AI)
</h1>

<p align="center">
  <strong>Bộ gõ tiếng Việt tích hợp AI Copilot cho macOS</strong><br>
  Độ trễ tiệm cận 0ms · Tự động phục hồi tiếng Anh · Trợ lý AI inline tại con trỏ văn bản
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-BSD--3--Clause-blue.svg" alt="License: BSD-3-Clause">
  <img src="https://img.shields.io/badge/Platform-macOS-000000?logo=apple&logoColor=white" alt="Platform: macOS" />
  <img src="https://img.shields.io/badge/Engine-Rust%20%2B%20Swift-orange" alt="Engine: Rust + Swift" />
  <img src="https://img.shields.io/badge/AI-Local%20Ollama-purple" alt="AI: Local Ollama" />
</p>

---

## Giới thiệu

TuiGoAI là bộ gõ tiếng Việt mã nguồn mở dành cho macOS, kết hợp giữa engine gõ tiếng Việt hiệu năng cao bằng Rust và lớp AI Copilot chạy offline:

1. Engine gõ tiếng Việt: Xử lý Telex và VNI bằng lõi Rust, độ trễ dưới 10ms, không lag và không nuốt phím trong Terminal hoặc IDE.
2. AI Copilot tại con trỏ: Gợi ý văn bản tiếp theo dạng ghost text ngay tại vị trí đang nhập liệu, chấp nhận gợi ý bằng phím Tab hoặc phím tắt tự chọn.
3. Chạy offline và bảo mật: AI chạy hoàn toàn nội bộ qua Ollama trên máy, không gửi phím bấm hay nội dung ra ngoài.

---

## Tính năng chính

### Bộ gõ tiếng Việt
- Xử lý Telex và VNI bằng lõi Rust độc lập.
- Tự động nhận diện và khôi phục từ tiếng Anh khi nhấn phím Space mà không cần chuyển chế độ gõ.
- Khôi phục chuỗi phím gốc bằng phím Escape khi gõ nhầm dấu.
- Hoạt động ổn định trên TextEdit, Chrome, Safari, Slack, VS Code, Cursor và Terminal.

### AI Copilot
- Gợi ý từ tiếp theo (Ghost Text Autocomplete) nối tiếp tự nhiên câu đang viết dở.
- Hai chế độ hiển thị: True Inline (chữ mờ nối tiếp trực tiếp sau con trỏ) và Pill (thẻ nổi kèm gợi ý phím Tab).
- Tùy chỉnh độ dài gợi ý theo ba mức: Ngắn (1-3 từ), Vừa (4-6 từ), Dài (7-10 từ).
- Bộ lọc thông minh: Tự động cân chỉnh khoảng trắng ở đầu từ, loại bỏ trùng lặp với đoạn văn bản phía sau con trỏ, tự động ngắt khi ở trường mật khẩu.
- Tự do ghi lại phím tắt (Record Shortcuts) cho hành động nhận gợi ý và bật/tắt AI.

---

## Cài đặt và build từ mã nguồn

### Yêu cầu hệ thống
- macOS 13.0 (Ventura) trở lên
- Xcode 15+ và Swift 6.0+
- Rust 1.80+
- Ollama (nếu sử dụng tính năng AI Copilot)

### Build ứng dụng
```bash
# 1. Clone repository
git clone https://github.com/ronnhd/TuiGoAI.git
cd TuiGoAI

# 2. Chạy kiểm thử lõi Rust
cargo test --manifest-path core/Cargo.toml

# 3. Build ứng dụng macOS
make build
```

File cài đặt sau khi build sẽ nằm tại `platforms/macos/build/Release/TuiGoAI.app`.

---

## Kiến trúc kỹ thuật

Dự án áp dụng nguyên tắc phân tách lõi nghiêm ngặt:

```text
┌────────────────────────────────────────────────────────┐
│                      macOS App                         │
│  (SwiftUI: MenuBar, Settings, Shortcuts, Overlay UI)   │
└──────────────┬──────────────────────────┬──────────────┘
               │ (Direct Events)          │ (Async Triggers)
               ▼                          ▼
┌─────────────────────────────┐  ┌───────────────────────┐
│     gonhanh-core (Rust)     │  │   TuiGoAI Copilot     │
│  Telex/VNI State Machine    │  │   Local Ollama / Raw  │
│  Latency < 10ms (Native)    │  │   AutocompleteCore    │
└─────────────────────────────┘  └───────────────────────┘
```

1. `core/`: Lõi Rust xử lý biến âm, từ điển kiểm tra âm tiết tiếng Việt và thuật toán khôi phục tiếng Anh.
2. `platforms/macos/`: Tầng Native macOS lắng nghe sự kiện bàn phím qua `CGEventTap` và quản lý giao diện.
3. `platforms/macos/AutocompleteCore.swift`: Thuật toán cân chỉnh biên con trỏ (`CaretBoundary`), kiểm soát trùng lặp đuôi (`SuffixOverlapGuard`) và phân tách từ (`NextWordSplitter`).
4. `platforms/macos/AIService.swift`: Giao tiếp bất đồng bộ với local Ollama qua raw generation.

---

## Bản quyền và ghi nhận

- Tác giả và phát triển: Ron Ng ([@ronnhd](https://github.com/ronnhd))
- Kế thừa nền tảng: Bộ gõ kế thừa nền tảng từ dự án [GoNhanh](https://github.com/khaphanspace/gonhanh.org) của tác giả Kha Phan.
- Thuật toán Autocomplete: Tham khảo và chuyển đổi từ dự án mã nguồn mở [KeyType](https://github.com/johnbean393/KeyType) (bản quyền Xi Nai Lai, giấy phép MIT).
- Giấy phép: Phát hành theo giấy phép [BSD-3-Clause](LICENSE).
