# HR-SOFT — برنامه آزمون RLS، Tenant isolation و Storage
## نسخه 2.2 | طرح آزمون؛ اجرا نشده

## 1. پیش‌نیاز محیط

- پایگاه داده staging مجزا؛ هرگز روی production آزمایش نشود.
- دو Tenant مستقل: `tenant_a`, `tenant_b`.
- دو شرکت در Tenant A (برای بررسی مرز company) و یک شرکت در Tenant B.
- حداقل چهار حساب: مدیر سیستم A، کاربر عادی A، کاربر دارای deny در گروه دوم A، مدیر سیستم B.
- ساختار سازمانی سه‌سطحی در شرکت A و یک واحد مشابه در شرکت B.
- رکوردهای پرسنلی، انتساب سمت، درخواست ظرفیت، فایل و داده حساس ساختگی.
- تمام UUIDها ثابت و test-only باشند؛ داده واقعی کارکنان وارد نشود.

## 2. سناریوهای آزمون

| شناسه | سناریو | انتظار |
|---|---|---|
| RLS-001 | کاربر A، SELECT رکورد Tenant B | صفر ردیف/permission denied |
| RLS-002 | کاربر A، UPDATE رکورد Tenant B با UUID معلوم | هیچ تغییری |
| RLS-003 | کاربر B، خواندن فایل متعلق به A | رد |
| RLS-004 | app_user غیرفعال/blocked | هیچ دسترسی کسب‌وکاری |
| RLS-005 | عضویت گروه غیرفعال | مجوزهای گروه نادیده گرفته شود |
| ACL-001 | allow در گروه اول و deny در گروه دوم | deny |
| ACL-002 | allow منقضی‌شده | deny |
| ACL-003 | دسترسی موقت قبل از starts_at | deny |
| ACL-004 | دسترسی موقت پس از ends_at | deny |
| SCOPE-001 | scope شرکت A به شرکت B | deny |
| SCOPE-002 | scope واحد + descendants | فقط واحد و زیرواحدهای مجاز |
| SCOPE-003 | scope personnel به پرونده دیگر | deny |
| SENS-001 | `personnel.view` بدون `sensitive.identity.view` | اطلاعات هویتی مخفی |
| SENS-002 | مشاهده اطلاعات بانکی بدون مجوز | deny |
| SENS-003 | مشاهده داده حساس با مجوز | allowed + یک audit event |
| SENS-004 | دانلود سند بدون `sensitive.documents.download` | deny + audit denied |
| SENS-005 | رویداد audit update/delete | exception |
| FILE-001 | path تصادفی اما بدون file permission | deny |
| FILE-002 | signed URL پس از expiry | deny |
| FILE-003 | نسخه قدیمی فایل | فقط در صورت مجوز history |
| FILE-004 | owner_id جعلی یا owner_table خارج allowlist | upload/attach رد |
| WF-001 | تصمیم گردش کار توسط کاربر غیر approver | deny |
| CAP-001 | دو درخواست باز برای یک position | درخواست دوم رد |
| CAP-002 | درخواست تأییدشده پس از revision و قبل از reapproval اجرا شود | deny |
| CAP-003 | درخواست overdue اجرا نشده | ظرفیت قدیمی حفظ شود |
| AUD-001 | تغییر permission بدون permission_change_history | تراکنش fail |
| EXP-001 | مدیر غیرسازنده تلاش برای دانلود ZIP | deny |
| EXP-002 | سازنده پس از دانلود موفق مجدداً همان token را مصرف کند | deny |

## 3. ساختار pgTAP پیشنهادی

تست‌ها باید با `SET LOCAL ROLE authenticated` و تنظیم claimهای JWT آزمایشی اجرا شوند. هر تست:
1. هویت Auth تست را تنظیم کند.
2. عملیات واقعی را انجام دهد.
3. نتیجه row count، SQLSTATE یا وضعیت audit را assert کند.
4. داده‌ها در transaction rollback شوند.

نمونه‌های مفهومی pgTAP (پس از پیاده‌سازی policyها قابل تبدیل به SQL اجرایی):

```sql
select plan(4);

-- RLS-001: cross-tenant SELECT returns no rows.
select is(
  (select count(*)::int from hr_core.people where id = :'tenant_b_person_id'),
  0,
  'Tenant A cannot read Tenant B person'
);

-- RLS-002: cross-tenant update must not mutate the target row.
-- Execute UPDATE, then assert unchanged state from privileged test harness.

-- SENS-003: allowed view creates one audit record.
-- Assert count(*) increments by exactly one for actor+subject+event.

-- AUD-001: append-only log rejects mutation.
select throws_ok(
  $$update hr_audit.sensitive_access_events set purpose='tamper' where id=1$$,
  'P0001',
  'sensitive access events are append-only',
  'audit tampering is rejected'
);

select * from finish();
```

**توجه:** نمونه بالا قالب مفهومی است؛ متغیرهای `:'...'`، JWT claims و policyهای واقعی باید در test harness تکمیل شوند. فعلاً نباید به‌عنوان تست آماده اجرا تلقی شود.

## 4. معیار قبولی

- هیچ آزمون cross-tenant مجاز نباشد.
- هیچ permission deny با allow گروه دیگر خنثی نشود.
- هیچ داده حساس از API عمومی قابل دریافت نباشد.
- هر مشاهده/دانلود حساس، یک رویداد audit با actor و subject صحیح ایجاد کند.
- تاریخچه‌ها append-only باشند.
- Storage فقط پس از authorization رکورد مالک اجازه دانلود دهد.
- آزمون‌ها در CI اجرا شوند و شکست هر تست مانع merge/deploy شود.
