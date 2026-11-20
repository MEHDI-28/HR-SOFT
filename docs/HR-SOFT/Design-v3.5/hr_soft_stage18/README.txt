HR-SOFT Stage 18 / Security integrity corrections v0.1

Files:
- HR_SOFT_Security_Integrity_Corrections_v0.1.sql
- HR_SOFT_Security_Integrity_Test_Plan_v0.1.md
- HR_SOFT_Action_Log_v0.1.md

Scope:
- Enforce same-system group/permission references.
- Require approval metadata for tenant-wide temporary access.
- Add append-only triggers to login/access event logs.

Status:
- Proposal and test plan only.
- Not executed against Supabase or PostgreSQL.
- Requires disposable database, preflight cleanup, validation and pgTAP/integration tests.
