# HR-SOFT — گزارش سازگاری و شکاف‌های فرهنگ داده
## نسخه 2.8

## 1. موجودی استخراج‌شده
- 35 جدول در SQL پایه و تکمیلی.
- 8 schema اصلی.
- جداول audit و workflow دارای تاریخچه/تصمیم هستند، اما enforce append-only در DDL پایه وجود ندارد.
- جداول حساس identity_data و bank_accounts از پروفایل عمومی جدا هستند.
- file_objects مالک polymorphic دارد و FK واقعی به owner ندارد.
- app_users یک auth_user_id unique در کل DB دارد؛ یک Auth identity به یک app_user متصل می‌شود.

## 2. شکاف‌های ساختاری
1. جداول permissions و systems سراسری‌اند؛ tenant-specific catalogue نیستند.
2. بعضی FKها tenant-safe هستند اما company-safe نیستند.
3. data_scopes check اولیه کامل نیست.
4. position_assignments نیازمند قیدهای company consistency و overlap business rules است.
5. position_relationships نیازمند company boundary policy است.
6. assignment events و outbox در DDL 0.1 وجود ندارند؛ فقط در proposal آمده‌اند.
7. audit_events عمومی به تنهایی جایگزین sensitive_access_events اختصاصی نیست.
8. file_versions باید path unique و append-only باشد.
9. capacity request status در نسخه 0.1 چند مفهوم را در یک ستون ترکیب می‌کند.
10. timezone شرکت و سیاست retention در schema اولیه موجود نیست.

## 3. ستون‌های لازم برای تکمیل آینده
- company timezone setting.
- permission catalogue version / release id.
- file owner type + FKهای owner.
- assignment event stream.
- outbox event idempotency.
- capacity approval/execution split.
- audit policy version and outcome.
- export one-time token hash and expiry.

## 4. محدودیت منبع
این فرهنگ داده از DDL محلی موجود استخراج شده است؛ schema واقعی remote یا Admino داخلی را توصیف نمی‌کند.
