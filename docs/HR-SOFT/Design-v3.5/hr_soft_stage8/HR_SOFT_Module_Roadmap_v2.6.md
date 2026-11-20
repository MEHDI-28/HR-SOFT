# HR-SOFT — نقشه توسعه ماژول‌ها و اولویت‌بندی
## نسخه 2.6

## اولویت صفر — زیرساخت اجباری
- schema migrations
- Auth mapping
- Tenant isolation
- permission resolver
- RLS policies
- audit append-only
- private Storage
- test harness دو Tenant

## اولویت یک — هسته سازمان و پرسنل
- Tenant/company setup
- org layers/units
- positions/relationships
- people/personnel records
- assignments و temporal history
- executive org chart

## اولویت دو — امنیت عملیاتی
- کاربران
- گروه‌ها
- memberships
- permission keys
- scope assignment
- temporary access
- permission history
- system admin resolution

## اولویت سه — گردش کار
- generic workflow
- inbox
- decisions
- capacity request
- approval/revision/execution
- overdue reminders
- internal notes/files

## اولویت چهار — اعلان و گزارش
- in-app notifications
- SMS adapter پس از انتخاب provider و بررسی هزینه/دسترسی
- outbox worker
- dashboard
- reports and exports

## خارج از محدوده فعلی
- حضور و غیاب
- رستوران
- انبار و تدارکات
- لباس فرم
- پیرایش
- خدمات پروازی
- آموزش
- مهمانسرا
- تردد زمینی
- تسهیلات رفاهی

## Definition of Done هر ماژول
- data model و constraints
- migration و rollback
- API/domain commands
- permission keys
- RLS/authorization
- audit
- unit/integration tests
- Persian RTL UI
- empty/loading/error/forbidden states
- docs و changelog
