# HR-SOFT — گزارش پیشرفت مرحله دوازدهم
## نسخه 3.0

### انجام شد
1. تفکیک position از organizational_position و position_profile.
2. تبدیل فیلدهای پایه سازمانی ثبت‌شده در سند Admino به مدل پیشنهادی.
3. طراحی duties و position_duties.
4. طراحی offices و اتصال آن به سمت.
5. طراحی succession candidates با priority و validity.
6. تولید migration پیشنهادی v0.3.
7. تهیه آزمون‌های یکپارچگی مدل سازمانی.

### مواردی که صریحاً پیشنهادی مانده‌اند
- مدل candidate_personnel_record برای جانشین.
- کاتالوگ/نوع داده فیلدهای پایه سازمانی.
- تفسیر organization_ref، امتیاز، کد مشترک و رئیس گروه مشترک.
- قواعد هم‌پوشانی جانشینی و profile.

### انجام نشده
- Migration اجرا نشده.
- داده موجود backfill نشده.
- RLS و permission keys برای جداول جدید اضافه نشده‌اند.
- هیچ آزمونی اجرا نشده است.

### مرحله بعدی
مرحله سیزدهم: تکمیل مدل امنیت کاربر شامل AD/auth mode، IP policy، default group، گزارش ورود/دسترسی و bulletin board؛ سپس migration و تست‌های مستقل آن.
