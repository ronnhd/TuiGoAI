# Đặc tả 9 tính năng AI Copilot trên TuiGoAI

Tài liệu chi tiết kỹ thuật và luồng vận hành cho 9 tính năng AI trong bộ gõ TuiGoAI.

---

## Nguyên tắc kiến trúc: Strict Core Separation
- **Luồng gõ phím tức thì (<10ms)**: Tuyệt đối không gọi mạng hoặc suy luận LLM trực tiếp trên luồng sự kiện phím chính. Toàn bộ logic kiểm tra khi gõ chỉ sử dụng bảng luật, từ điển offline và mô hình n-gram nhẹ cục bộ.
- **Luồng trợ lý AI bất đồng bộ (Async Intent)**: Các tính năng thông minh phức tạp (viết lại, dịch, tra cứu thuật ngữ, rà soát xưng hô) được kích hoạt chủ động qua phím tắt riêng hoặc chạy ngầm (background task), hiển thị qua bảng điều khiển nổi (floating palette/ghost text).

---

## Nhóm 1: Xử lý cục bộ theo thời gian thực khi gõ (Local Heuristics / Fast Path)

### 1. Hiểu Việt - Anh xen kẽ (Bilingual Auto-Restore)
- **Mục tiêu**: Tự động nhận diện từ tiếng Anh trong câu tiếng Việt để không áp sai dấu Telex/VNI (ví dụ: `proposal`, `confirm`, `budget`).
- **Input**: Từ đang gõ trong bộ đệm và 2 từ liền trước.
- **Xử lý**:
  - Đối soát với từ điển 100k từ tiếng Anh và bảng luật âm vị học (các đuôi âm tiết không tồn tại trong tiếng Việt như `al`, `rm`, `ct`, `sh`).
  - Khi người dùng nhấn phím `Space`, nếu từ khớp tiếng Anh, tự động hoàn tác các ký tự dấu về chữ cái gốc.
- **Hoàn tác**: Nhấn phím `Backspace` hoặc `ESC` để quay lại dạng có dấu nếu muốn giữ chữ tiếng Việt.

### 2. Khôi phục dấu theo ngữ cảnh (Contextual Diacritic Restoration)
- **Mục tiêu**: Khôi phục dấu chuẩn xác cho câu gõ không dấu (`toi dang o nha` -> `tôi đang ở nhà`) và phân biệt từ đồng âm (`ban` -> `bạn`, `bàn`, `bán`, `bản`).
- **Input**: Cụm 3-5 từ không dấu vừa hoàn thành.
- **Xử lý**:
  - Chạy mô hình xác suất n-gram tiếng Việt siêu nhẹ offline trên CPU/NPU khi kết thúc cụm từ hoặc ngắt câu.
  - Phân tích ngữ nghĩa từ đi trước và sau để chọn từ có xác suất cao nhất.
- **Hiển thị**: Hiện bản khôi phục dưới dạng chữ mờ (Ghost Text). Nhấn `Tab` hoặc `Enter` để chấp nhận thay thế.

### 3. Sửa lỗi gõ theo ý định (Intent-based Typo Correction)
- **Mục tiêu**: Tự động sửa lỗi đảo phím khi gõ nhanh (`khôgn` -> `không`, `ngya` -> `ngày`) và lỗi lặp phím thừa ký tự.
- **Input**: Từ vừa gõ có cấu trúc âm tiết bất thường.
- **Xử lý**:
  - Tầng 1 (Luật hoán vị): Nhận diện các cặp đảo phím kinh điển ở phụ âm cuối (`gn` -> `ng`, `ya` -> `ay`) và sửa trực tiếp.
  - Tầng 2 (Xác suất ngữ cảnh): Với lỗi tạo ra từ khác có nghĩa (như gõ `về` thành `vé`), so sánh với từ loại liền kề để đưa ra gợi ý.
- **Hiển thị**: Lỗi rõ ràng tự sửa nhẹ; lỗi mơ hồ hiển thị gạch chân gợi ý.

### 4. Học từ điển riêng (Personal Dynamic Vocabulary)
- **Mục tiêu**: Ghi nhớ danh từ riêng, tên người (`Arin`), tên công ty (`BlockPR`, `ZY|Block`), thuật ngữ kỹ thuật riêng của người dùng.
- **Input**: Lịch sử các từ lạ mà người dùng cố tình giữ lại khi gõ.
- **Xử lý**:
  - Khi người dùng gõ từ chưa có trong từ điển và nhấn `ESC` hoặc sửa để giữ lại từ 2-3 lần, hệ thống tự động lưu vào tệp từ điển cá nhân (`user_dict.json`).
  - Hỗ trợ nhập danh sách từ thủ công trong màn hình Cài đặt.
- **Hiển thị**: Từ đã học được xem là từ hợp lệ tuyệt đối, không bao giờ bị bộ gõ tự động can thiệp sai dấu.

### 5. Hiểu viết tắt cá nhân theo ngữ cảnh (Contextual Shortcuts)
- **Mục tiêu**: Xử lý từ viết tắt (`hnay`, `đc`, `ko`, `tks`) phù hợp với từng ứng dụng.
- **Input**: Bundle ID của ứng dụng hiện tại và từ viết tắt vừa gõ.
- **Xử lý**:
  - Ứng dụng giao tiếp (Slack, Telegram, Discord, Zalo): Giữ nguyên từ viết tắt để nhắn nhanh.
  - Ứng dụng soạn thảo/công việc (Mail, Pages, Docs, Word): Nhận diện môi trường trang trọng để gợi ý mở rộng thành từ đầy đủ.
- **Hiển thị**: Hiện gợi ý nhỏ tại con trỏ. Nhấn `Tab` để bung thành từ đầy đủ, gõ tiếp để bỏ qua.

---

## Nhóm 2: Kích hoạt theo ý định người dùng (Local LLM / OpenAI API)

### 6. Viết lại đoạn đang chọn (In-place Rewrite)
- **Mục tiêu**: Biến đổi độ dài và giọng văn (ngắn gọn, rõ ràng, trang trọng, thân mật) cho văn bản đã chọn.
- **Input**: Đoạn văn bản được bôi đen (lấy qua macOS Accessibility API `AXUIElement`).
- **Trigger**: Phím tắt `Option + Space` (hoặc `Option + R`).
- **Xử lý**:
  - Gửi đoạn văn bản kèm prompt định hình phong cách đến model LLM đã cấu hình.
  - Hỗ trợ 4 phong cách: Trang trọng (Formal), Thân mật (Casual), Rút gọn (Concise), Mở rộng (Elaborate).
- **Hiển thị**: Hiển thị bảng nổi nhỏ (Floating Palette) ngay tại vị trí con trỏ chuột/text. Người dùng bấm `Enter` để thay thế đoạn cũ, hoặc `Command + Z` để hoàn tác.

### 7. Dịch ngay tại con trỏ (In-place Translation)
- **Mục tiêu**: Soạn nháp tiếng Việt rồi dịch trực tiếp sang tiếng Anh tại chỗ, bảo toàn thuật ngữ và tên riêng từ từ điển cá nhân.
- **Input**: Đoạn văn bản tiếng Việt đang chọn hoặc câu ngay trước con trỏ.
- **Trigger**: Phím tắt `Option + T`.
- **Xử lý**:
  - LLM dịch ngữ cảnh với ràng buộc giữ nguyên các danh từ riêng đã được đánh dấu trong từ điển cá nhân.
- **Hiển thị**: Xem trước bản dịch trong popup nổi, nhấn `Enter` để chèn đè lên văn bản gốc.

### 8. Giữ xưng hô nhất quán (Tone & Pronoun Consistency)
- **Mục tiêu**: Phát hiện tình trạng xưng hô lẫn lộn trong cùng một văn bản (ví dụ đầu đoạn dùng `anh - em`, cuối đoạn đổi sang `bạn - mình`).
- **Input**: Toàn bộ nội dung văn bản đang soạn trong khung nhập liệu hiện tại.
- **Xử lý**:
  - Quét ma trận đại từ nhân xưng tiếng Việt.
  - Nếu phát hiện nhiều cặp xưng hô đối nghịch cùng tồn tại, đưa ra cảnh báo nhắc nhở nhẹ.
- **Hiển thị**: Không tự động sửa văn bản. Hiển thị thông báo nhỏ: "Phát hiện xưng hô lẫn lộn giữa 'anh' và 'bạn'". Nhấp vào để chọn cặp chuẩn hóa duy nhất.

### 9. Tra từ lúc đang viết (Reverse Term Lookup)
- **Mục tiêu**: Tìm thuật ngữ tiếng Anh hoặc tiếng Việt khi người dùng quên từ chính xác bằng cách nhập mô tả khái niệm (ví dụ gõ "thỏa thuận hợp tác không ràng buộc" để tìm `MOU`).
- **Input**: Chuỗi mô tả ngắn bằng tiếng Việt.
- **Trigger**: Phím tắt `Option + F`.
- **Xử lý**:
  - Mở thanh nhập liệu mini tại con trỏ. AI truy vấn ngữ nghĩa và trả về 3-5 thuật ngữ sát nhất kèm định nghĩa 1 dòng.
- **Hiển thị**: Danh sách đánh số 1, 2, 3. Bấm số tương ứng để chèn ngay thuật ngữ vào vị trí con trỏ.

---

## Tính năng nền tảng: Gợi ý câu tự động (Ghost Text Autocomplete)
- Khi người dùng gõ từ 3 từ trở lên và tạm dừng gõ (debounce 300ms), hệ thống tự động suy luận phần tiếp theo của câu và hiển thị dưới dạng chữ xám mờ (Inline) hoặc thẻ nổi (Pill).
- Nhấn `Tab` (hoặc phím tắt tự chọn) để nhận toàn bộ gợi ý. Nếu tiếp tục gõ chữ khác, gợi ý cũ tự động biến mất và tính toán lại theo văn bản mới.

### Cơ chế gom ngữ cảnh thông minh (Context Enrichment Engine)
1. **Window Context 2.000 ký tự**: Đọc tối đa 2.000 ký tự trước con trỏ (thay vì 240 ký tự) và 500 ký tự sau con trỏ qua macOS Accessibility API. Đảm bảo mô hình LLM hiểu trọn vẹn chủ đề bài viết và đại từ xưng hô.
2. **Bộ đệm hội thoại tức thời (Ephemeral My-Chat Memory)**:
   - Khi người dùng nhắn tin trong các ứng dụng chat (Telegram, Zalo, Slack, Discord, Messages), việc gửi tin nhắn bằng phím `Enter` sẽ tự động lưu 3–4 câu gần nhất của người dùng vào bộ nhớ đệm RAM (tự hủy sau 5 phút).
   - Khi gõ câu tiếp theo trong cùng ứng dụng, các câu thoại trước đó được đưa vào prompt ngữ cảnh để AI suy luận tiếp mạch hội thoại của chính người dùng một cách ăn khớp, không bị lạc đề hay ngẫu nhiên.
   - Hoàn toàn bảo vệ quyền riêng tư: Không đọc trộm tin nhắn của người khác, không lưu vào ổ cứng hay gửi ra Internet.
3. **Instruct completion qua `/api/chat`**: Qwen 2.5 là mô hình instruct. Gửi system prompt tiếng Việt (chỉ trả phần tiếp theo, giữ xưng hô, không lặp prefix) thay vì raw continuation. Lịch sử chat đưa vào prompt thành đoạn văn thường, không bullet list.
4. **Bộ tham số Sampling tối ưu cho tiếng Việt**:
   - `temperature: 0.1`: Loại bỏ sự ngẫu nhiên, tập trung vào các kết hợp từ vựng tiếng Việt có xác suất xuất hiện cao nhất và chuẩn ngữ pháp.
   - `top_p: 0.8` và `top_k: 20`: Loại trừ triệt để các token dịch máy kỳ dị hoặc ảo giác.
