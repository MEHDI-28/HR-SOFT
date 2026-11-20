# HR-SOFT — Gate 0 Evidence Register
## Template v0.1 — وضعیت اولیه: در انتظار snapshot واقعی

| ID | مدرک | وضعیت فعلی | منبع لازم | نتیجه/یادداشت |
|---|---|---|---|---|
| G0-01 | شناسه پروژه و محیط DEV | نامشخص | Supabase project settings | ثبت بدون کلید/secret |
| G0-02 | PostgreSQL version و role | جمع‌آوری‌نشده | SQL inventory 01 |  |
| G0-03 | schema و relation inventory | جمع‌آوری‌نشده | SQL inventory 03–04 |  |
| G0-04 | column/type inventory | جمع‌آوری‌نشده | SQL inventory 05 |  |
| G0-05 | PK/FK/unique/check constraints | جمع‌آوری‌نشده | SQL inventory 06 |  |
| G0-06 | indexes و validity | جمع‌آوری‌نشده | SQL inventory 07 |  |
| G0-07 | RLS و policyها | جمع‌آوری‌نشده | SQL inventory 08 |  |
| G0-08 | ACL، role و membership | جمع‌آوری‌نشده | SQL inventory 09–10 |  |
| G0-09 | routineها و triggerها | جمع‌آوری‌نشده | SQL inventory 11–12 | بدنه routineها عمداً استخراج نمی‌شود |
| G0-10 | enumها و sequenceها | جمع‌آوری‌نشده | SQL inventory 13–14 |  |
| G0-11 | Storage buckets/policies | جمع‌آوری‌نشده | SQL inventory 15 | محتویات فایل‌ها خارج از دامنه |
| G0-12 | migration ledger | جمع‌آوری‌نشده | SQL inventory 16 + CLI/repo | فقط وجود جدول کافی نیست |
| G0-13 | repository / branch / commit | نامشخص | Git provider/local checkout | تطبیق با DEV |
| G0-14 | backup و restore drill | تأییدنشده | Supabase/project operator | صرف وجود backup کافی نیست |
| G0-15 | Auth / OAuth / SMS configuration | خارج از SQL | Dashboard + repo config | secrets نباید صادر شوند |
| G0-16 | drift classification | در انتظار | مقایسه snapshot با baseline | existing/missing/drifted/unknown |

## تصمیم Gate
- [ ] PASS — فقط برای شروع طراحی migration در DEV
- [ ] HOLD — شواهد ناقص یا اختلاف حل‌نشده
- [ ] FAIL — ریسک امنیتی/یکپارچگی حل‌نشده

**قاعده:** تا تکمیل شواهد و بررسی اختلاف‌ها، هیچ migration اجرایی و هیچ تغییر RLS/Storage مجاز نیست.
