# HR-SOFT — اصلاح مدل وضعیت درخواست تغییر ظرفیت
## یادداشت بازبینی نسخه 2.2

### مسئله موجود
در SQL نسخه 0.1، وضعیت‌های `approved_awaiting_execution`, `scheduled`, `overdue` و `awaiting_reapproval` در یک ستون `status` قرار گرفته‌اند؛ درحالی‌که بخشی از آن‌ها وضعیت تأیید و بخشی وضعیت زمان‌بندی/تاخیر هستند. این موضوع می‌تواند وضعیت‌های متناقض بسازد.

### پیشنهاد تفکیک
- `approval_status`: `pending_approval`, `approved`, `rejected`, `awaiting_reapproval`
- `execution_status`: `not_scheduled`, `scheduled`, `due`, `overdue`, `executed`, `cancelled`
- `execution_mode`: `immediate`, `scheduled`
- `planned_execution_at` یا `planned_execution_date`: تاریخ/زمان اجرای برنامه‌ریزی‌شده؛ تصمیم timezone باید مشخص شود.
- `last_approved_revision_no`: نسخه‌ای که آخرین بار تأیید شده است.
- `current_revision_no`: آخرین نسخه درخواست.
- اجرای مجاز فقط وقتی `approval_status='approved'` و `current_revision_no=last_approved_revision_no` باشد.
- اگر پس از تأیید ویرایش شود، `approval_status='awaiting_reapproval'` و نسخه تأییدشده قبلی دیگر مجوز اجرا نیست.
- اگر موعد بگذرد و اجرا نشود، `execution_status='overdue'` و ظرفیت قبلی بدون تغییر می‌ماند.
- یک درخواست باز برای هر position با partial unique index؛ تعریف «باز» باید شامل pending، approved-awaiting-execution، awaiting-reapproval و overdue باشد.
- درخواست رد/لغو/اجراشده از قید یکتایی خارج می‌شود.

### مواردی که نیازمند تصمیم محصولی‌اند، نه حدس
- ساعت دقیق اجرای زمان‌بندی‌شده و timezone شرکت.
- آیا درخواست فوری پس از تأیید در همان تراکنش اجرا می‌شود یا job جداگانه.
- سیاست هم‌زمانی دو مدیر در ثبت تصمیم؛ طبق نیازمندی ثبت‌شده، آخرین اقدام ثبت‌شده مبناست، اما ترتیب باید با timestamp دیتابیس و قفل تراکنشی تعیین شود.

### وضعیت
این یادداشت اصلاح طراحی است؛ هنوز SQL migration نهایی تولید/اجرا نشده است.
