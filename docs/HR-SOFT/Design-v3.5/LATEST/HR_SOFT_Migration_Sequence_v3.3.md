# HR-SOFT — ترتیب نهایی مهاجرت‌ها و Gateهای کیفیت
## نسخه 3.3

| ترتیب | Migration/بخش | وابستگی | Gate |
|---|---|---|---|
| 0 | استخراج schema و baseline | دسترسی dev DB | schema snapshot |
| 1 | اصلاح company-safe FK | baseline | mismatch queries = 0 |
| 2 | position profile/org position/duties/offices/succession | migration 1 | FK and temporal tests |
| 3 | private person details/contact/country/city | baseline | PII access tests |
| 4 | user auth mode/IP/default group/login logs/bulletin | auth architecture | login/IP tests |
| 5 | capacity approval/execution split | workflow baseline | concurrency tests |
| 6 | file owner registry + private Storage | file schema | owner and storage tests |
| 7 | permission catalogue and resolver | all scope tables | ACL test suite |
| 8 | RLS and grants | resolver | cross-tenant pgTAP |
| 9 | temporal events/outbox/workers | domain commands | idempotency and schedule tests |
| 10 | reports/read models/exports | permissions | export scope tests |
| 11 | UI and release | all above | end-to-end acceptance |

**اصل:** Migration بعدی تا قبولی Gate قبلی وارد production نمی‌شود.


---

## الحاقیه مرحله هجدهم — اصلاحات یکپارچگی امنیت

این الحاقیه ترتیب پایه را جایگزین نمی‌کند؛ اصلاحات امنیتی مرحله 18 باید پس از وجود baseline، تابع append-only مرحله 5، Migration امنیت کاربر مرحله 13 و بازبینی correction snippets مرحله 16، و پیش از نهایی‌سازی permission resolver و RLS اعمال شوند.

| ترتیب تکمیلی | بسته | پیش‌نیاز | Gate اجباری |
|---|---|---|---|
| 4.1 | اصلاح FK مرکب bulletin در Migration v0.4 | تعریف `UNIQUE(tenant_id,id)` پیش از acknowledgement FK | اجرای v0.4 از DB خالی و ساخت موفق FK |
| 4.2 | Stage 18: هم‌سیستمی group-permission و approval برای temporary access | baseline + user security v0.4 + correction v0.6 | preflight بدون ناسازگاری، VALIDATE همه قیود و تست SEC-401 تا SEC-407 |
| 4.3 | Stage 18: append-only برای login/access events | تابع `hr_audit.reject_mutation_append_only()` از Stage 5 | تست UPDATE/DELETE با roleهای واقعی و قبولی SEC-408 تا SEC-411 |

**شرط ورود به مرحله permission resolver/RLS:** تمام Gateهای بالا باید در پایگاه داده disposable/staging پاس شوند. Stage 18 به‌تنهایی مجوزدهی را پیاده‌سازی نمی‌کند و هیچ policy مجازکننده‌ای را فعال نمی‌سازد.

**وضعیت این الحاقیه:** طراحی و برنامه آزمون؛ اجرا نشده.
