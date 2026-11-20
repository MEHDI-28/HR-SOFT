# HR-SOFT — نقشه Schema به ماژول و مالکیت دامنه
## نسخه 2.8

| Schema | ماژول/دامنه | جداول |
|---|---|---|
| `hr_core` | هویت، Tenant، شرکت و پرونده | tenants, companies, people, personnel_records |
| `hr_security` | حساب، سیستم، گروه، مجوز، scope | app_users, systems, user_groups, group_memberships, permissions, group_permission_rules, data_scopes, group_scope_assignments, temporary_access |
| `hr_org` | ساختار سازمانی و انتساب | org_layers, org_units, positions, position_relationships, position_assignments |
| `hr_workflow` | گردش کار و ظرفیت | requests, steps, decisions, capacity_change_requests, capacity_request_revisions, capacity_request_notes, capacity_request_files |
| `hr_files` | فایل و خروجی | file_objects, file_versions, export_jobs, export_job_items |
| `hr_notify` | تنظیمات و اعلان | user_preferences, notifications |
| `hr_sensitive` | اطلاعات هویتی و بانکی | identity_data, bank_accounts |
| `hr_audit` | ممیزی و تاریخچه مجوز | audit_events, permission_change_history |

## مالکیت دامنه
- هر schema یک مالک دامنه منطقی دارد.
- UI نباید مستقیماً مالک status جداول دامنه دیگر شود.
- تغییر cross-domain باید از command/API رسمی عبور کند.
- audit/outbox باید در همان تراکنش تغییر اصلی ثبت شود.
- گزارش‌ها فقط read modelهای مجاز را مصرف کنند.

## جداول تکمیلی طراحی‌شده پس از DDL 0.1
- `hr_audit.sensitive_access_events` (proposal v2.2)
- `hr_events.outbox_events` (proposal v2.5)
- `hr_org.position_assignment_events` (proposal v2.5)

این جداول هنوز در baseline اصلی نیستند و Migration واقعی آن‌ها اجرا نشده است.
