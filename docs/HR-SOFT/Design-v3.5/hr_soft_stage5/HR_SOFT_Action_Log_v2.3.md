# HR-SOFT — گزارش پیشرفت مرحله پنجم
## نسخه 2.3

### انجام شد
1. بازخوانی مستقیم فایل‌های SQL پایه، تکمیلی، RLS و patch مرحله چهارم.
2. تطبیق فرض‌های app_users با SQL پایه: ستون‌های `auth_user_id` و `status` وجود دارند.
3. شناسایی مشکل cross-company درون یک Tenant و تولید FKهای مرکب پیشنهادی.
4. طراحی مدل file owner کنترل‌شده برای مالک capacity request و برنامه مهاجرت legacy polymorphic.
5. طراحی دو محور مستقل برای approval و execution درخواست ظرفیت.
6. تعریف قید یک درخواست باز برای هر position.
7. تعریف append-only trigger برای جداول تاریخچه‌ای.
8. تدوین چک‌لیست یکپارچگی داده و برنامه آزمون Migration.

### انجام نشده
- Migration اجرا نشده.
- constraintها روی هیچ DB validate نشده‌اند.
- pgTAP اجرا نشده.
- permission resolver و policyهای نهایی RLS هنوز ساخته نشده‌اند.
- Storage bucket و policy ساخته نشده‌اند.
- هیچ دسترسی به پروژه Supabase واقعی تأیید نشده است.

### نکته فنی مهم
Migration پیشنهادی برای file owner فقط نوع `capacity_request` را backfill می‌کند. اگر در داده‌های موجود ownerهای دیگری باشند، باید ابتدا فهرست و برای هر نوع مالک FK مستقل تعریف شود. اجرای بی‌بررسی migration می‌تواند به‌علت داده‌های ناسازگار متوقف شود.

### مرحله بعدی
مرحله ششم: طراحی permission resolver واقعی به‌صورت SQL/RPC، مدل کلیدهای permission، توابع تراکنشی workflow/capacity و RLS policies مبتنی بر resolver؛ سپس تست integration در DB توسعه.
