# HR-SOFT — بسته تحویل به تیم توسعه
## نسخه 3.3

## 1. وضعیت فعلی
طراحی محصول و مدل داده به سطح قابل تحویل برای بازبینی فنی رسیده است؛ اما برای شروع اجرای واقعی، repository و schema واقعی لازم است. این بسته به‌معنی تکمیل کدنویسی یا استقرار نیست.

## 2. اسناد مرجع
- سند مادر جاری: `HR_SOFT_Master_v3.3.md`
- دفتر تصمیم‌ها: `HR_SOFT_Decision_Register_v3.3.md`
- نقشه ماژول‌ها: `HR_SOFT_Module_Roadmap_v2.6.md`
- فرهنگ داده: `HR_SOFT_Data_Dictionary_v2.8.md`
- ماتریس سیاست‌ها: `HR_SOFT_Policy_Matrix_v2.2.md`
- طراحی موتور دسترسی: `HR_SOFT_Access_Resolver_Spec_v2.4.md`
- معماری زمانی و اعلان: `HR_SOFT_Temporal_Personnel_Model_v2.5.md`
- مدل سازمانی: `HR_SOFT_Organization_Model_v3.0.md`
- مدل شخص/پرسنلی: `HR_SOFT_Personnel_Data_Model_v3.2.md`
- معماری فنی: `HR_SOFT_Technical_Architecture_v2.7.md`
- برنامه MVP: `HR_SOFT_MVP_Delivery_Plan_v2.7.md`

## 3. ترتیب اجرای واقعی پیشنهادی

### فاز A — شناخت محیط
1. شناسایی repository و branch فعال.
2. استخراج schema واقعی و extensions.
3. شناسایی محیط dev/staging/prod.
4. تهیه backup و ثبت baseline.
5. مقایسه schema واقعی با DDL محلی.

### فاز B — پایگاه داده
1. baseline cleanup.
2. company-safe FKs.
3. organization extensions.
4. personnel private details.
5. user security/IP/bulletin.
6. capacity status migration.
7. file owner registry.
8. append-only events and outbox.

### فاز C — امنیت
1. seed permission catalogue.
2. implement resolver.
3. public wrappers.
4. RLS policies.
5. Storage policies.
6. pgTAP two-tenant suite.
7. penetration/security review.

### فاز D — محصول
1. Auth and account administration.
2. organization structure and chart.
3. personnel and assignments.
4. workflow/capacity.
5. notifications.
6. reports and exports.
7. dashboard and UI hardening.

## 4. شروط شروع coding
- دسترسی read-only به repository و schema برای بررسی.
- هیچ credential حساس در فایل‌های ارسالی قرار نگیرد.
- branch توسعه و محیط dev جدا.
- امکان reset دیتابیس آزمایشی.
- نسخه‌گذاری migrationها.
- معیارهای پذیرش در CI.

## 5. معیارهای عدم انتشار
- هر تست cross-tenant fail.
- resolver هنوز deny-only یا ناقص باشد.
- Storage عمومی باشد یا بدون owner permission دسترسی دهد.
- history قابل بازنویسی باشد.
- داده حساس در API عمومی یا log افشا شود.
- capacity request بدون approval/revision match اجرا شود.
- backup/restore تست نشده باشد.

## 6. مرز مسئولیت
این بسته طراحی و handoff است. هیچ تغییر remote، خرید سرویس، ساخت حساب provider، ارسال SMS، deployment یا migration واقعی انجام نشده است.
