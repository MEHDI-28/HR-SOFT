# HR-SOFT — برنامه آزمون Migration v0.2
## نسخه 2.3 | اجرا نشده

## 1. داده‌های fixture
- Tenant A / Company A1 / Company A2
- Tenant B / Company B1
- در A1: سه لایه واحد سازمانی، دو سمت و یک سمت مافوق
- در A2: واحد و سمت مستقل
- دو پرونده پرسنلی در A1 و یک پرونده در A2
- دو Auth user در Tenant A و یک Auth user در Tenant B
- ظرفیت سمت‌ها و درخواست‌های ساختگی
- فایل‌های ساختگی برای capacity request

## 2. Migration tests
| ID | ورودی/عملیات | انتظار |
|---|---|---|
| MIG-001 | org_unit parent در همان company | FK قبول |
| MIG-002 | org_unit parent در شرکت دیگر همان tenant | FK رد |
| MIG-003 | position.org_unit در شرکت دیگر | FK رد |
| MIG-004 | superior_position در شرکت دیگر | FK رد |
| MIG-005 | assignment position و personnel در شرکت یکسان | قبول |
| MIG-006 | assignment با personnel در شرکت دیگر | FK رد |
| MIG-007 | relationship سمت‌های دو شرکت | FK رد |
| MIG-008 | file owner ظرفیت معتبر | FK قبول |
| MIG-009 | file owner ناشناخته/NULL | CHECK رد |
| MIG-010 | دو نسخه با storage path یکسان | unique رد |
| MIG-011 | دو درخواست باز برای یک position | unique رد |
| MIG-012 | درخواست ردشده و درخواست جدید برای همان position | قبول |
| MIG-013 | revision پس از approval | approval باید reset شود |
| MIG-014 | اجرای revision تأییدنشده | فرمان سرور رد |
| MIG-015 | UPDATE/DELETE روی decision | trigger رد |
| MIG-016 | UPDATE/DELETE روی file_version | trigger رد |

## 3. Data audit queries
قبل از افزودن constraints:
```sql
-- Company mismatch in position assignments
select pa.id
from hr_org.position_assignments pa
join hr_org.positions p
  on p.tenant_id=pa.tenant_id and p.id=pa.position_id
join hr_core.personnel_records pr
  on pr.tenant_id=pa.tenant_id and pr.id=pa.personnel_record_id
where pa.company_id <> p.company_id
   or pa.company_id <> pr.company_id;

-- Position/org-unit mismatch
select p.id
from hr_org.positions p
join hr_org.org_units u
  on u.tenant_id=p.tenant_id and u.id=p.org_unit_id
where p.company_id <> u.company_id;

-- Duplicate Storage object paths
select storage_bucket, storage_object_path, count(*)
from hr_files.file_versions
group by 1,2 having count(*) > 1;

-- Duplicate open capacity requests (after backfill)
select tenant_id, position_id, count(*)
from hr_workflow.capacity_change_requests
where approval_status in ('pending_approval','approved','awaiting_reapproval')
  and execution_status in ('blocked','scheduled','due','overdue')
group by 1,2 having count(*) > 1;
```

## 4. مهم
Migration v0.2 یک پیشنهاد است. `NOT VALID` فقط validation اولیه را عقب می‌اندازد؛ constraints برای داده جدید اعمال می‌شوند و باید پس از پاک‌سازی داده‌های موجود validate شوند. هیچ آزمونی در این بسته اجرا نشده است.
