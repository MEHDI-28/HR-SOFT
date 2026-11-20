# HR-SOFT — نقشه صفحه به داده و فرمان
## نسخه 2.9

| صفحه/بخش | داده‌های اصلی | Query/Commandهای اصلی | مجوزهای نمونه |
|---|---|---|---|
| مدیریت شرکت | companies | create/update/archive company | org.company.* |
| لایه سازمانی | org_layers | create/update/archive layer | org.layer.* |
| واحد سازمانی | org_units | create/update/archive/move unit | org.unit.* |
| پایه سازمانی | position_profiles + positions | create/update/approve profile | org.position.* |
| وظایف | duties + position_duties | CRUD duty/link | org.duty.* |
| امور و دفتر | offices + position_office_assignments | CRUD/link | org.office.* |
| چارت اجرایی | units/positions/relationships/assignments | query chart by effective date | org.chart.view |
| جانشینی | succession_candidates | add/update/expire/cancel | personnel.succession.* |
| کاربران | app_users | invite/block/unblock/force reset | security.users.* |
| گروه‌ها | user_groups | create/archive/clone permissions | security.groups.* |
| عضویت | group_memberships | add/remove/bulk | security.memberships.* |
| کلیدها/مجوزها | permissions/group_permission_rules | assign/revoke | security.permissions.* |
| دامنه دسترسی | data_scopes/group_scope_assignments | add/remove scope | security.scopes.* |
| IP policy | user_ip_rules | add/remove/test | security.ip_rules.* |
| گزارش ورود | user_access_events | filter/export | security.login_history.* |
| تابلو اعلانات | bulletins/acknowledgements | publish/expire/acknowledge | notice.* |
| پرونده پرسنلی | people/personnel_records | create/update/archive | personnel.* |
| مدارک | file_objects/file_versions | upload/replace/download | sensitive.documents.* |
| گردش کار | requests/steps/decisions | submit/approve/reject | workflow.* |
| ظرفیت | capacity_change_requests | request/revise/approve/execute | capacity.* |

این نقشه طرح مفهومی است؛ جداول پیشنهادی که هنوز در schema فعلی نیستند، باید قبل از migration نهایی طراحی شوند.
