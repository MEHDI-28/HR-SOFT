$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location -LiteralPath $repoRoot
$cli = 'C:\Users\Admin\node_modules\.bin\supabase.cmd'
$container = 'supabase_db_xdjhshktjtevusigqzya'

if (-not (Test-Path -LiteralPath $cli)) { throw "Supabase CLI not found: $cli" }

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$statusRaw = (& $cli status --output-format json 2>$null | Out-String)
$ErrorActionPreference = $previousErrorAction
$status = $statusRaw | ConvertFrom-Json
$api = [string]$status.API_URL
$anonKey = [string]$status.ANON_KEY
$serviceKey = [string]$status.SERVICE_ROLE_KEY
if (-not $api -or -not $anonKey -or -not $serviceKey) {
    throw 'Local Supabase API URL or local Auth keys are unavailable.'
}

$runId = [guid]::NewGuid().ToString('N')
$tenantA = 'a1000000-0000-4000-8000-' + $runId.Substring(0, 12)
$tenantB = 'b1000000-0000-4000-8000-' + $runId.Substring(12, 12)
$systemActive = 'c1000000-0000-4000-8000-' + $runId.Substring(0, 12)
$systemInactive = 'd1000000-0000-4000-8000-' + $runId.Substring(12, 12)
$permissionActive = 'e1000000-0000-4000-8000-' + $runId.Substring(0, 12)
$permissionInactive = 'f1000000-0000-4000-8000-' + $runId.Substring(12, 12)
$users = @()
$probeCreated = $false

function New-LocalAuthUser([string]$label) {
    $email = "hrsoft-$label-$runId@example.com"
    $password = [guid]::NewGuid().ToString('N') + 'Aa1!'
    $body = @{
        email = $email
        password = $password
        email_confirm = $true
        user_metadata = @{ purpose = 'temporary HR-SOFT local JWT/RLS test' }
    } | ConvertTo-Json -Depth 5

    $headers = @{
        apikey = $serviceKey
        Authorization = "Bearer $serviceKey"
    }
    $created = Invoke-RestMethod -Uri "$api/auth/v1/admin/users" -Method Post -Headers $headers -ContentType 'application/json' -Body $body
    if (-not $created.id) { throw "Auth user creation failed for $label." }

    $loginBody = @{ email = $email; password = $password } | ConvertTo-Json
    $session = Invoke-RestMethod -Uri "$api/auth/v1/token?grant_type=password" -Method Post -Headers @{ apikey = $anonKey } -ContentType 'application/json' -Body $loginBody
    if (-not $session.access_token -or $session.user.id -ne $created.id) {
        throw "A valid local JWT could not be obtained for $label."
    }

    return [pscustomobject]@{
        Label = $label
        Id = [string]$created.id
        Email = $email
        Token = [string]$session.access_token
    }
}

function Invoke-LocalRpc([string]$name, [string]$token) {
    $headers = @{ apikey = $anonKey; Authorization = "Bearer $token" }
    return Invoke-RestMethod -Uri "$api/rest/v1/rpc/$name" -Method Post -Headers $headers -ContentType 'application/json' -Body '{}'
}

try {
    $users += New-LocalAuthUser 'tenant-a'
    $users += New-LocalAuthUser 'tenant-b'
    $users += New-LocalAuthUser 'archived'
    $users += New-LocalAuthUser 'unprovisioned'

    $sql = @"
begin;
insert into hr_core.tenants(id, tenant_key, display_name, status) values
('$tenantA', 'local-a-$runId', 'HR-SOFT Local Tenant A', 'active'),
('$tenantB', 'local-b-$runId', 'HR-SOFT Local Tenant B', 'active');

insert into hr_security.systems(id, system_key, title, is_active) values
('$systemActive', 'HR-SOFT-LOCAL-ACTIVE-$runId', 'Local active system', true),
('$systemInactive', 'HR-SOFT-LOCAL-INACTIVE-$runId', 'Local inactive system', false);

insert into hr_security.permissions(id, system_id, permission_key, title, is_active) values
('$permissionActive', '$systemActive', 'hrsoft.local.active.$runId', 'Local active permission', true),
('$permissionInactive', '$systemActive', 'hrsoft.local.inactive.$runId', 'Local inactive permission', false);

insert into hr_security.app_users(tenant_id, auth_user_id, status, auth_mode) values
('$tenantA', '$($users[0].Id)', 'active', 'local'),
('$tenantB', '$($users[1].Id)', 'active', 'local'),
('$tenantA', '$($users[2].Id)', 'active', 'local');

update hr_security.app_users
set status = 'archived', archived_at = now()
where auth_user_id = '$($users[2].Id)';

create function public.hr_soft_local_rls_probe()
returns table(
    auth_uid uuid,
    current_tenant uuid,
    current_app_user uuid,
    visible_tenants bigint,
    visible_app_users bigint,
    visible_own_app_user bigint,
    visible_foreign_app_users bigint,
    visible_system_rows bigint,
    visible_inactive_system_rows bigint,
    visible_permission_rows bigint,
    visible_inactive_permission_rows bigint
)
language sql
stable
security invoker
set search_path = ''
as `$function`$
    select
        auth.uid(),
        hr_security.current_tenant_id(),
        hr_security.current_app_user_id(),
        (select count(*) from hr_core.tenants),
        (select count(*) from hr_security.app_users),
        (select count(*) from hr_security.app_users where auth_user_id = auth.uid()),
        (select count(*) from hr_security.app_users where tenant_id <> hr_security.current_tenant_id()),
        (select count(*) from hr_security.systems),
        (select count(*) from hr_security.systems where not is_active),
        (select count(*) from hr_security.permissions),
        (select count(*) from hr_security.permissions where not is_active);
`$function`$;

revoke all on function public.hr_soft_local_rls_probe() from public, anon;
grant execute on function public.hr_soft_local_rls_probe() to authenticated;
notify pgrst, 'reload schema';
commit;
"@

    $sql | docker exec -i $container psql -v ON_ERROR_STOP=1 -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) { throw 'Could not create isolated local test fixtures and probe.' }
    $probeCreated = $true
    Start-Sleep -Seconds 2

    $expected = @(
        @{ Label = 'tenant-a'; Tenant = 1; AppUsers = 1; Own = 1; Foreign = 0; Provisioned = $true },
        @{ Label = 'tenant-b'; Tenant = 1; AppUsers = 1; Own = 1; Foreign = 0; Provisioned = $true },
        @{ Label = 'archived'; Tenant = 0; AppUsers = 0; Own = 0; Foreign = 0; Provisioned = $false },
        @{ Label = 'unprovisioned'; Tenant = 0; AppUsers = 0; Own = 0; Foreign = 0; Provisioned = $false }
    )

    $results = @()
    for ($i = 0; $i -lt $users.Count; $i++) {
        $probe = Invoke-LocalRpc 'hr_soft_local_rls_probe' $users[$i].Token
        if ($probe -is [array]) { $probe = $probe[0] }
        $sessionStatus = Invoke-LocalRpc 'hr_session_status' $users[$i].Token
        if ($sessionStatus -is [array]) { $sessionStatus = $sessionStatus[0] }

        $isAuth = [bool]$sessionStatus.is_authenticated
        $isProvisioned = [bool]$sessionStatus.is_provisioned
        $checks = (
            [bool]$probe.auth_uid -and
            ([int]$probe.visible_tenants -eq $expected[$i].Tenant) -and
            ([int]$probe.visible_app_users -eq $expected[$i].AppUsers) -and
            ([int]$probe.visible_own_app_user -eq $expected[$i].Own) -and
            ([int]$probe.visible_foreign_app_users -eq $expected[$i].Foreign) -and
            ([int]$probe.visible_system_rows -eq 1) -and
            ([int]$probe.visible_inactive_system_rows -eq 0) -and
            ([int]$probe.visible_permission_rows -eq 1) -and
            ([int]$probe.visible_inactive_permission_rows -eq 0) -and
            ($isAuth -eq $true) -and
            ($isProvisioned -eq $expected[$i].Provisioned)
        )
        $results += [pscustomobject]@{
            Test = $users[$i].Label
            JWTAuthenticated = $isAuth
            Provisioned = $isProvisioned
            TenantRows = [int]$probe.visible_tenants
            AppUserRows = [int]$probe.visible_app_users
            OwnRows = [int]$probe.visible_own_app_user
            ForeignTenantRows = [int]$probe.visible_foreign_app_users
            VisibleActiveSystems = [int]$probe.visible_system_rows
            VisibleInactiveSystems = [int]$probe.visible_inactive_system_rows
            VisibleActivePermissions = [int]$probe.visible_permission_rows
            VisibleInactivePermissions = [int]$probe.visible_inactive_permission_rows
            Result = if ($checks) { 'PASS' } else { 'FAIL' }
        }
        if (-not $checks) {
            throw "RLS/JWT expectation failed for $($users[$i].Label)."
        }
    }

    Write-Output 'REAL LOCAL SUPABASE JWT + RLS TESTS'
    $results | Format-Table -AutoSize
    $anonymousDenied = $false
    try {
        Invoke-RestMethod -Uri "$api/rest/v1/rpc/hr_soft_local_rls_probe" -Method Post -Headers @{ apikey = $anonKey } -ContentType 'application/json' -Body '{}' | Out-Null
    } catch {
        $statusCode = 0
        if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
        if ($statusCode -in 401, 403) { $anonymousDenied = $true } else { throw }
    }
    if (-not $anonymousDenied) { throw 'Anonymous role unexpectedly executed the local RLS probe.' }

    Write-Output 'PASS: real Auth-issued JWTs were accepted by local PostgREST.'
    Write-Output 'PASS: tenant A and tenant B each saw only their own tenant and app_user row.'
    Write-Output 'PASS: archived and unprovisioned users were authenticated but not provisioned and saw zero HR rows.'
    Write-Output 'PASS: authenticated users saw active system/permission catalogue rows only.'
    Write-Output 'PASS: anonymous role was denied execution of the authenticated-only probe.'
}
finally {
    if ($probeCreated) {
        $userIdsSql = ($users | ForEach-Object { "'" + $_.Id + "'" }) -join ','
        docker exec $container psql -U postgres -d postgres -v ON_ERROR_STOP=1 -c "drop function if exists public.hr_soft_local_rls_probe(); delete from hr_security.app_users where auth_user_id in ($userIdsSql); delete from hr_security.permissions where id in ('$permissionActive','$permissionInactive'); delete from hr_security.systems where id in ('$systemActive','$systemInactive'); delete from hr_core.tenants where id in ('$tenantA','$tenantB'); notify pgrst, 'reload schema';" | Out-Null
        Start-Sleep -Seconds 1
    }

    foreach ($user in $users) {
        if ($user.Id) {
            $headers = @{ apikey = $serviceKey; Authorization = "Bearer $serviceKey" }
            try {
                Invoke-RestMethod -Uri "$api/auth/v1/admin/users/$($user.Id)" -Method Delete -Headers $headers | Out-Null
            } catch {
                Write-Warning "Could not remove temporary local Auth user $($user.Label): $($_.Exception.Message)"
            }
        }
    }
}
