$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrationPath = Join-Path $repoRoot 'supabase\migrations\20261119090000_hr_soft_resolver_deny_precedence_hardening.sql'

if (-not (Test-Path -LiteralPath $migrationPath)) {
    throw "Migration not found: $migrationPath"
}

$sql = [System.IO.File]::ReadAllText($migrationPath)

$denyBlock = [regex]::Match(
    $sql,
    '(?s)into v_group_deny(.*?)select count\(\*\)::integer\s+into v_temp_allow'
).Groups[1].Value

if ([string]::IsNullOrWhiteSpace($denyBlock)) {
    throw 'Could not isolate v_group_deny block.'
}
if ($denyBlock -match 'case p_operation') {
    throw 'Deny path still depends on can_add/can_edit/can_delete.'
}
if ($denyBlock -notmatch "\(r\.effect = 'deny' or gsa\.effect = 'deny'\)") {
    throw 'Deny effect predicate is missing.'
}
if (([regex]::Matches($sql, 'and case p_operation')).Count -ne 2) {
    throw 'Allow operation gates must remain in both allow-related counts.'
}
if (([regex]::Matches($sql, 'create or replace function')).Count -ne 4) {
    throw 'Expected resolver, two identity helpers, and session-status function.'
}
if (([regex]::Matches($sql, 'au\.archived_at is null')).Count -ne 4) {
    throw 'Expected archived_at guard in resolver and all three active-user helpers.'
}
if (([regex]::Matches($sql, "'2\.4\.2'")).Count -ne 15) {
    throw 'Resolver policy-version literals are not consistently set to 2.4.2.'
}

$requiredConstraints = @(
    'ck_temporary_access_approval_pair_v18',
    'ck_temporary_access_global_scope_approval_v18'
)
foreach ($constraint in $requiredConstraints) {
    if ($sql -notmatch [regex]::Escape($constraint)) {
        throw "Missing constraint: $constraint"
    }
    if ($sql -notmatch "validate constraint $constraint") {
        throw "Constraint is not validated: $constraint"
    }
}

if ($sql -match '(?im)^\s*(create\s+policy|grant\s|revoke\s|drop\s+table|delete\s+from|update\s+hr_)') {
    throw 'Unexpected RLS policy, privilege, destructive, or business-data mutation statement.'
}

$bytes = [System.IO.File]::ReadAllBytes($migrationPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
    throw 'UTF-8 BOM detected at the start of the migration.'
}

Write-Output 'PASS: deny is independent of operation allow flags.'
Write-Output 'PASS: allow operation gates remain intact.'
Write-Output 'PASS: all active-user paths reject archived accounts.'
Write-Output 'PASS: resolver policy version is 2.4.2.'
Write-Output 'PASS: temporary-access approval constraints are present and validated.'
Write-Output 'PASS: no RLS policy/grant/revoke or business-data mutation was introduced.'
Write-Output 'STATIC MIGRATION VALIDATION: PASS (not a PostgreSQL runtime test).'
