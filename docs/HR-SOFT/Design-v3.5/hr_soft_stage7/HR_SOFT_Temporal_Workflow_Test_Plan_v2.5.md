# HR-SOFT — آزمون‌های زمانی، گردش کار و اعلان
## نسخه 2.5 | اجرا نشده

| ID | سناریو | انتظار |
|---|---|---|
| TMP-001 | assignment با تاریخ شروع آینده | scheduled؛ در چارت جاری نیست |
| TMP-002 | رسیدن effective date و اجرای scheduler | active و event ثبت شود |
| TMP-003 | لغو assignment آینده | cancelled؛ تاریخچه حفظ؛ اعلان کارمند ارسال نشود |
| TMP-004 | تغییر تاریخ شروع آینده | رویداد changed؛ اعلان کارمند ارسال نشود |
| TMP-005 | correction گذشته بدون permission | رد |
| TMP-006 | correction گذشته با permission و reason | رویداد correction؛ رکورد اصلی حفظ |
| TMP-007 | query as_of_effective_at و known_at متفاوت | دو بازسازی صحیح |
| WF-001 | bulk approve با یک ردیف غیرمجاز | فقط رفتار صریح atomic/per-item |
| WF-002 | تصمیم approver غیرمجاز | رد |
| CAP-001 | approve بدون execute | ظرفیت تغییر نکند |
| CAP-002 | revision پس از approval | approval reset |
| CAP-003 | execution روی revision قدیمی | رد |
| CAP-004 | دو execute هم‌زمان | فقط یک اجرا موفق |
| CAP-005 | overdue | ظرفیت قبلی حفظ؛ اعلان روزانه idempotent |
| NOT-001 | assignment اجرا شد | in-app برای employee و مدیران لازم |
| NOT-002 | SMS opt-out | in-app ارسال؛ SMS ارسال نشود |
| NOT-003 | recipient تکراری در manager chain | فقط یک اعلان |
| NOT-004 | manager chain خالی | تمام system admins واجد مجوز |
| NOT-005 | outbox worker retry | پیام تکراری ایجاد نشود |
| NOT-006 | provider fail | retry با backoff؛ اطلاعات حساس در log نباشد |
| NOT-007 | company timezone نامشخص | زمان‌بندی حساس حدس زده نشود |

هیچ‌یک از این آزمون‌ها در این بسته اجرا نشده‌اند.
