# HR-SOFT — موتور گردش کار و اجرای ظرفیت
## نسخه 2.5

## 1. درخواست عمومی

جداول موجود `requests`, `steps`, `decisions` مبنای عمومی‌اند، اما state transition باید از طریق فرمان‌های کنترل‌شده انجام شود. کلاینت حق update مستقیم status را ندارد.

### transitionهای عمومی
- draft → submitted
- submitted → in_review
- in_review → approved / rejected / returned
- approved → completed
- draft/submitted/in_review → cancelled طبق permission و policy
- transitionهای نامعتبر باید در DB/Domain Service رد شوند.

هر تصمیم:
- immutable
- actor مشخص
- timestamp
- reason برای رد اجباری
- step مرتبط
- request مرتبط

## 2. Inbox
- فهرست درخواست‌های قابل اقدام برای approver فردی یا گروهی.
- bulk approve/reject فقط وقتی هر ردیف جداگانه authorization و validation شود.
- bulk action باید atomic یا به‌صورت نتیجه مستقل per item با گزارش خطا اجرا شود؛ رفتار نیمه‌کاره نباید پنهان بماند.
- refresh/filter فقط query هستند و مجوز اضافه نمی‌کنند.

## 3. Capacity workflow
- تنظیم هر شرکت تعیین می‌کند approval لازم است یا خیر و approver mode چیست.
- در حالت org_manager، approver سمت مستقیم مدیر position است؛ اگر vacant، اولین مدیر بالاتر دارای incumbent.
- اگر manager chain پیدا نشد، تمام system admins واجد مجوز دریافت می‌کنند.
- در حالت system_admin، مدیران سیستم واجد مجوز.
- چند مدیر می‌توانند مستقل تصمیم ثبت کنند؛ آخرین اقدام ثبت‌شده در DB مبنای وضعیت جاری است، ولی تمام تصمیم‌ها در history می‌مانند.
- رد شدن reason اجباری.
- approve به معنی execute نیست.
- اجرای تغییر فقط توسط مدیر سیستم و با permission مستقل.
- immediate و scheduled هر دو از فرمان execute عبور می‌کنند؛ immediate پس از approval می‌تواند بلافاصله command را فراخوانی کند.
- یک درخواست باز برای هر position.
- ویرایش پس از approval توسط requester یا system admin، revision جدید می‌سازد و approval را reset می‌کند.
- اگر due date برسد ولی revision هنوز reapproved نشده باشد، اجرا ممنوع و وضعیت blocked/awaiting_reapproval باقی می‌ماند.
- approved request due date گذشته و اجرا نشده → overdue؛ ظرفیت فعلی تغییر نمی‌کند.
- cancel approved but unexecuted فقط مدیر سیستم و reason اجباری.

## 4. Concurrency
- ردیف request و position در execute قفل شوند.
- revision و approval با قفل همان request serialize شوند.
- آخرین تصمیم با `recorded_at` دیتابیس و sequence monotonic تعیین شود؛ timestamp سمت client پذیرفته نشود.
- ظرفیت جدید و audit event و outbox event در یک transaction ثبت شوند.

## 5. یادداشت و فایل داخلی مدیران
- notes فقط مدیر سیستم می‌بیند/ایجاد می‌کند؛ immutable.
- attachments فقط مدیر سیستم می‌بیند/دانلود می‌کند.
- replacement فقط نسخه جدید می‌سازد و reason اجباری.
- دسترسی به فایل هم به مجوز request و هم file permission وابسته است.
