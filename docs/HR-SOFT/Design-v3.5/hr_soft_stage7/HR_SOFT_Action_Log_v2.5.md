# HR-SOFT — گزارش پیشرفت مرحله هفتم
## نسخه 2.5

### انجام شد
1. تعریف مدل زمانی با تفکیک effective_at و recorded_at.
2. تعریف scheduled/active/ended/cancelled برای assignment.
3. تعریف correction event و query تاریخی با as_of_effective_at و known_at.
4. تعریف اعلان‌های انتساب طبق نیازمندی‌های ثبت‌شده، شامل مدیر قبلی/جدید و fallback.
5. تعریف capacity reminders و overdue notifications.
6. تعریف transactional outbox و idempotency.
7. تعریف workflow/capacity command transitions و row locking.
8. تولید SQL پیشنهادی outbox و assignment event log.
9. تهیه آزمون‌های زمانی و workflow.

### انجام نشده
- SQL اجرا نشده.
- scheduler/worker پیاده‌سازی نشده.
- اتصال SMS provider انجام نشده.
- permission resolver هنوز کامل نیست.
- تست‌های concurrency و idempotency اجرا نشده‌اند.

### مرحله بعدی
مرحله هشتم: طراحی کاتالوگ گزارش‌ها، داشبوردها، فیلترها، خروجی‌ها، و مدل read-model امن؛ سپس معماری UI فارسی RTL و نقشه توسعه ماژول‌ها.
