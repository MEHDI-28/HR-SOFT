# HR-SOFT — گزارش اقدامات و وضعیت مرحله چهارم
## نسخه 2.2

### کارهای انجام‌شده در این مرحله
1. بازخوانی مستقیم SQL پایه نسخه 0.1، SQL تکمیلی و RLS lockdown نسخه 0.1.
2. تأیید اینکه `app_users` دارای ستون‌های `auth_user_id` و `status` است؛ بنابراین فرض تابع `current_app_user_id()` در مرحله قبل با SQL پایه تطبیق دارد.
3. استخراج ماتریس SELECT/INSERT/UPDATE/DELETE برای تمام جداول موجود.
4. ثبت ناسازگاری‌های کلیدی: parent/position company consistency، assignment company mismatch، polymorphic file owner، scope target shape، storage path uniqueness، capacity status overlap، append-only gaps.
5. طراحی رویداد ممیزی مستقل برای مشاهده/تغییر/دانلود اطلاعات حساس.
6. تعریف معماری bucket خصوصی و مسیر object versioned.
7. تهیه برنامه آزمون دو Tenant و سناریوهای RLS/ACL/Scope/Sensitive/Storage/Workflow/Capacity/Export.
8. تهیه SQL patch محدود برای audit حساس، uniqueness مسیر Storage، scope shape و append-only.

### کارهایی که انجام نشده‌اند
- هیچ SQL اجرا نشده است.
- هیچ Supabase project در این مرحله قابل شناسایی/دسترسی نبوده؛ در تلاش قبلی ابزار فهرست پروژه خطای داخلی داده بود.
- هیچ Storage bucket یا policy ساخته نشده است.
- هیچ تست pgTAP اجرا نشده و هیچ نتیجه pass ادعا نمی‌شود.
- هیچ محتوای تازه‌ای از صفحه Admino خوانده نشده؛ بنابراین این مرحله صرفاً بر مبنای اسناد و SQL موجود است.

### وضعیت ریسک
- بالا: سیاست‌های RLS نهایی و permission resolver هنوز پیاده نشده‌اند.
- بالا: Storage policy به علت مدل polymorphic مالک فایل نهایی نشده است.
- متوسط/بالا: سازگاری company_id در روابط سازمانی و انتساب سمت نیازمند trigger/constraint است.
- متوسط: وضعیت درخواست ظرفیت باید به دو محور approval/execution تفکیک شود.
- متوسط: audit append-only باید برای تمام جداول تاریخچه‌ای enforce شود.

### گام بعدی پیشنهادی
مرحله پنجم: بازطراحی دقیق مدل SQL و تولید Migration نسخه 0.2 در محیط توسعه، همراه با اصلاح FKها، triggerهای سازگاری شرکت، مدل مالک فایل، status model ظرفیت و policy resolver؛ سپس اجرای pgTAP روی دو Tenant آزمایشی.
