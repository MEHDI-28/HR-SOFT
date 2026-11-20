# HR-SOFT — قرارداد API امن و فرمان‌های تراکنشی
## نسخه 2.4

## 1. الگوی لایه‌ها

1. Client UI: نمایش و دریافت ورودی؛ فاقد منطق امنیتی مرجع.
2. Public API / RPC: ورودی محدود مانند record UUID و مقادیر تغییر.
3. Domain service: اعتبارسنجی، resolve مالک/tenant، اجرای permission check.
4. Database transaction: قفل، اعمال تغییر، audit/revision/outbox.
5. Worker: SMS، اعلان، export، پاک‌سازی فایل موقت.

## 2. قراردادهای عمومی پیشنهادی

| Endpoint/RPC | ورودی | کنترل الزامی |
|---|---|---|
| `get_personnel_record` | personnel_record_id | resolve واقعی رکورد؛ `personnel.view` + scope |
| `get_sensitive_identity` | person_id, purpose | `sensitive.identity.view` + audit |
| `get_bank_account_masked` | personnel_record_id | `sensitive.bank.view`; فقط mask |
| `get_bank_account_full` | bank_account_id, purpose | مجوز full view + audit |
| `download_file` | file_version_id | owner resolver + view + download permission + audit |
| `create_capacity_request` | position_id, proposed_capacity, mode | permission + company match + open-request check |
| `approve_capacity_request` | request_id, decision, reason | approver resolution + lock + audit |
| `revise_capacity_request` | request_id, patch, reason | requester/admin check + revision + reset approval |
| `execute_capacity_request` | request_id | admin execute permission + revision match + lock |
| `cancel_capacity_request` | request_id, reason | admin permission + lock + audit |
| `change_group_permission` | group_id, permission_id, new rule | system-admin permission + history same transaction |

هیچ endpoint نباید tenant_id یا actor_id را از کلاینت به‌عنوان هویت معتبر قبول کند.

## 3. فرمان‌های تراکنشی

### Approve capacity
- lock request `FOR UPDATE`.
- assert approval_status pending.
- assert approver is valid for this position/company or system admin.
- append decision.
- update approval_status.
- set last_approved_revision_no=current_revision_no.
- set execution_status based on mode.
- append audit event.
- commit.

### Revise capacity request
- lock request.
- assert requester or system admin.
- assert status is editable.
- append revision with before/after and reason.
- increment current_revision_no.
- set approval_status='awaiting_reapproval'.
- set execution_status='blocked'.
- clear/retain prior approval actor only as historical metadata; never treat old approval as current.
- append audit event.
- commit.

### Execute capacity
- lock request and position.
- assert system admin + `capacity.request.execute`.
- assert approval_status='approved'.
- assert current_revision_no=last_approved_revision_no.
- assert execution_status in ('due','overdue') or valid scheduled time reached.
- assert request is not cancelled/executed.
- update position capacity.
- set execution_status='executed', executed_by, executed_at.
- append audit event.
- commit.

### Replace file
- lock file object.
- assert file owner still exists and user has manage/replace permission.
- calculate next version.
- upload object to private Storage using random path.
- insert file_version; update current_version_no.
- append audit event.
- if DB commit fails after upload, enqueue orphan object cleanup; never overwrite prior version.
- commit.

## 4. Transactional outbox

For events that require external side effects:
- assignment executed → in-app + optional SMS
- capacity reminder → in-app to system admins
- export ready/expired
- file upload processing

Insert an outbox event in the same DB transaction as the business event. Worker consumes idempotently using unique event key. Never send SMS inside the DB transaction.

## 5. Idempotency

Public mutating endpoints should accept an idempotency key scoped to `(tenant_id, actor_id, operation)` and store result reference. Repeating the same key returns the original result and does not duplicate:
- approval decisions
- capacity execution
- file version
- notifications
- export jobs

## 6. Error contract
- `AUTH_REQUIRED`
- `NOT_FOUND_OR_NOT_AUTHORIZED` (avoid resource enumeration)
- `VALIDATION_ERROR`
- `CONFLICT_STATE`
- `APPROVAL_REQUIRED`
- `REAPPROVAL_REQUIRED`
- `IDEMPOTENCY_CONFLICT`
- `TEMPORARY_FAILURE`

Sensitive internals, SQL text and row existence should not leak through client errors.
