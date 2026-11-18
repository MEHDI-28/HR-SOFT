# HR-SOFT — گزارش پیشرفت مرحله سیزدهم
## نسخه 3.1

### انجام شد
1. طراحی auth_mode برای local/AD/both.
2. طراحی IP allow/deny با CIDR و trusted proxy requirement.
3. طراحی default group per user/system.
4. طراحی login event و access event جداگانه.
5. طراحی bulletin و acknowledgement per user/placement.
6. تهیه migration پیشنهادی v0.4 و تست‌های پذیرش.

### انجام نشده
- AD/SSO integration انتخاب یا اجرا نشده.
- IP enforcement در gateway انجام نشده.
- RLS و append-only triggers نهایی نیستند.
- هیچ migration یا تست اجرا نشده است.

### مرحله بعدی
مرحله چهاردهم: طراحی مدل پرسنلی تکمیلی در محدوده اطلاعات موجود، و سپس ساخت ماتریس نهایی تصمیم‌ها/ابهام‌ها و handoff توسعه.
