## **Status:**
- Review: Approved
- PR: Todo

## Metadata
- **Title:** Rails integration — Grape mounted API fallback
- **Phase:** 6 — Integrations
- **GitHub Issue:** #17

---

## Description
Hỗ trợ app Rails có mounted Grape API, nơi `bin/rails routes` không phản ánh đầy đủ endpoint thực.

- **Command chính:** `:Restman rails`.
- **Problem:** nếu app dùng mounted API kiểu `mount Api::Base => "/"`, `:Restman rails` có thể chỉ thấy mount point hoặc route tổng quát, không đủ để picker toàn bộ endpoint con.
- **Detect mounted Grape API:** scan `config/routes.rb` để tìm pattern `mount ... => ...` và dấu hiệu namespace/class của Grape API.
- **Auto fallback:** khi detect Grape mount, `:Restman rails` sẽ dùng `bin/rails routes` và `bundle exec rake grape:routes` cùng nhau để build danh sách endpoint đầy đủ.
- **Warning và degrade:** nếu Grape mount được phát hiện nhưng `bundle exec rake grape:routes` không khả dụng, `:Restman rails` vẫn fail gracefully và cảnh báo user rằng route list có thể incomplete.

- **Scope v1:** `:Restman rails` detect được mounted Grape API, load được cả Rails routes và Grape routes cơ bản, rồi mở picker để user chọn route và gửi request như flow Rails hiện có.

---

## Spec Reference
- Section: §7.1 `:Restman rails` trong [`story.md`](../story.md).

---

## Acceptance Criteria
- [ ] Project có `mount Api::Base => "/"` trong `config/routes.rb` → `:Restman rails` tự động dùng `bundle exec rake grape:routes` bên cạnh `bin/rails routes`.
- [ ] Project không có mounted Grape API → `:Restman rails` không chạy `bundle exec rake grape:routes` và không hiện warning Grape.
- [ ] Nếu `bundle exec rake grape:routes` không thành công, `:Restman rails` vẫn fail gracefully và thông báo rõ ràng.
- [ ] Picker format tương thích flow hiện tại: `VERB PATH handler`.
- [ ] Chọn endpoint có dynamic params vẫn prompt và gửi request đúng URL resolved.
- [ ] Không làm regress flow `:Restman rails` hiện tại cho Rails routes thường.

---

## Implementation Checklist
- [ ] Mở rộng `lua/restman/integrations/rails.lua` hoặc tách module `lua/restman/integrations/rails_grape.lua`.
- [ ] Helper detect Grape mount từ `config/routes.rb`.
- [ ] Bổ sung auto-fallback loader để `:Restman rails` chạy `bundle exec rake grape:routes` khi cần.
- [ ] Notify warning / degrade gracefully khi Grape route loader không khả dụng.
- [ ] Implement loader/introspection cho endpoint Grape thay vì chỉ phụ thuộc `bin/rails routes`.
- [ ] Reuse picker + send flow hiện có để chọn và gửi request.

---

## Notes
- Depends on: 015 (Rails routes integration), 006 (dynamic params), 008 (env), 012 (picker), 013 (commands).
- Cần tránh over-engineer parser Ruby AST ở v1; ưu tiên một cơ chế introspection ổn định và degrade rõ ràng nếu app structure không hỗ trợ.
