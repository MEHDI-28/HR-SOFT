$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $repoRoot
$cli = 'C:\Users\Admin\node_modules\.bin\supabase.cmd'
$db = 'supabase_db_xdjhshktjtevusigqzya'
$previousEA = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$statusText = (& $cli status --output-format json 2>$null | Out-String)
$ErrorActionPreference = $previousEA
if ($LASTEXITCODE -ne 0) { throw 'Start local Supabase first.' }
$status = $statusText | ConvertFrom-Json
$api = [string]$status.API_URL
$anon = [string]$status.ANON_KEY
$service = [string]$status.SERVICE_ROLE_KEY
if ($api -notmatch '^http://(127\.0\.0\.1|localhost):') { throw "Refusing non-local API URL: $api" }
$pg = docker exec $db psql -At -U postgres -d postgres -c 'show server_version'
if ($pg -notmatch '^17\.') { throw "Expected PostgreSQL 17, found $pg" }
$existing = docker exec $db psql -At -U postgres -d postgres -c "select count(*) from hr_security.systems where system_key='HR-SOFT'"
if ([int]$existing -ne 0) { throw 'Expected a clean local database without HR-SOFT system seed.' }

$run = [guid]::NewGuid().ToString('N')
$ids = @{}
foreach ($key in 'tenant','company','system','permission','appuser','allowgroup','denygroup','scope','allowmember','denymember') {
    $ids[$key] = [guid]::NewGuid().ToString()
}
$auth = $null
$fixtures = $false
$probe = $false
try {
    $email = "resolver-$run@example.com"
    $password = [guid]::NewGuid().ToString('N') + 'Aa1!'
    $auth = Invoke-RestMethod -Uri ($api + '/auth/v1/admin/users') -Method Post -Headers @{ apikey=$service; Authorization=('Bearer ' + $service) } -ContentType 'application/json' -Body (@{email=$email;password=$password;email_confirm=$true}|ConvertTo-Json)
    $session = Invoke-RestMethod -Uri ($api + '/auth/v1/token?grant_type=password') -Method Post -Headers @{ apikey=$anon } -ContentType 'application/json' -Body (@{email=$email;password=$password}|ConvertTo-Json)
    if (-not $session.access_token) { throw 'Auth did not issue a JWT.' }

    $sql = @'
begin;
insert into hr_core.tenants(id,tenant_key,display_name,status) values ('__TENANT__','resolver-__RUN__','Resolver E2E','active');
insert into hr_core.companies(id,tenant_id,company_code,legal_name,display_name,status) values ('__COMPANY__','__TENANT__','E2E','Resolver E2E','Resolver E2E','active');
insert into hr_security.systems(id,system_key,title,is_active) values ('__SYSTEM__','HR-SOFT','HR-SOFT test',true);
insert into hr_security.permissions(id,system_id,permission_key,title,is_active) values ('__PERMISSION__','__SYSTEM__','hrsoft.local.resolver.e2e','Resolver E2E',true);
insert into hr_security.app_users(id,tenant_id,auth_user_id,status,auth_mode) values ('__APPUSER__','__TENANT__','__AUTH__','active','local');
insert into hr_security.user_groups(id,tenant_id,system_id,group_key,title,is_active) values
('__ALLOWGROUP__','__TENANT__','__SYSTEM__','resolver_allow','Allow fixture',true),
('__DENYGROUP__','__TENANT__','__SYSTEM__','resolver_deny','Deny fixture',true);
insert into hr_security.group_memberships(id,tenant_id,group_id,app_user_id,is_active,valid_from) values
('__ALLOWMEMBER__','__TENANT__','__ALLOWGROUP__','__APPUSER__',true,now()),
('__DENYMEMBER__','__TENANT__','__DENYGROUP__','__APPUSER__',true,now());
insert into hr_security.group_permission_rules(tenant_id,system_id,group_id,permission_id,can_add,can_edit,can_delete,effect) values
('__TENANT__','__SYSTEM__','__ALLOWGROUP__','__PERMISSION__',true,true,true,'allow'),
('__TENANT__','__SYSTEM__','__DENYGROUP__','__PERMISSION__',false,false,false,'deny');
insert into hr_security.data_scopes(id,tenant_id,scope_type) values ('__SCOPE__','__TENANT__','tenant');
insert into hr_security.group_scope_assignments(tenant_id,group_id,scope_id,effect,valid_from) values
('__TENANT__','__ALLOWGROUP__','__SCOPE__','allow',now()),
('__TENANT__','__DENYGROUP__','__SCOPE__','allow',now());
create function public.hr_soft_local_resolver_probe(p_tenant_id uuid,p_operation text)
returns table(allowed boolean,reason_code text,policy_version text,matched_allow_count integer,matched_deny_count integer)
language sql volatile security definer set search_path=''
as $function$
select r.allowed,r.reason_code,r.policy_version,r.matched_allow_count,r.matched_deny_count
from hr_internal.evaluate_permission_context('hrsoft.local.resolver.e2e',p_operation,p_tenant_id,null,null,null,now()) r;
$function$;
revoke all on function public.hr_soft_local_resolver_probe(uuid,text) from public,anon;
grant execute on function public.hr_soft_local_resolver_probe(uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
'@
    foreach ($key in $ids.Keys) { $sql = $sql.Replace('__' + $key.ToUpper() + '__', $ids[$key]) }
    $sql = $sql.Replace('__RUN__',$run).Replace('__AUTH__',[string]$auth.id)
    $sql | docker exec -i $db psql -v ON_ERROR_STOP=1 -U postgres -d postgres
    if ($LASTEXITCODE -ne 0) { throw 'Fixture setup failed.' }
    $fixtures = $true
    $probe = $true
    Start-Sleep -Seconds 2

    $headers = @{ apikey=$anon; Authorization=('Bearer ' + $session.access_token) }
    $cases = @(
        @{op='view'; tenant=$ids.tenant; allowed=$false; reason='EXPLICIT_DENY'},
        @{op='add'; tenant=$ids.tenant; allowed=$false; reason='EXPLICIT_DENY'},
        @{op='edit'; tenant=$ids.tenant; allowed=$false; reason='EXPLICIT_DENY'},
        @{op='delete'; tenant=$ids.tenant; allowed=$false; reason='EXPLICIT_DENY'},
        @{op='view'; tenant=([guid]::NewGuid().ToString()); allowed=$false; reason='TENANT_MISMATCH'}
    )
    $results = @()
    foreach ($case in $cases) {
        $body = @{p_tenant_id=$case.tenant;p_operation=$case.op}|ConvertTo-Json
        $out = Invoke-RestMethod -Uri ($api + '/rest/v1/rpc/hr_soft_local_resolver_probe') -Method Post -Headers $headers -ContentType 'application/json' -Body $body
        if ($out -is [array]) { $out=$out[0] }
        $ok = ([bool]$out.allowed -eq $case.allowed) -and ($out.reason_code -eq $case.reason)
        $results += [pscustomobject]@{Operation=$case.op;Reason=$out.reason_code;Allow=$out.matched_allow_count;Deny=$out.matched_deny_count;Result=$(if($ok){'PASS'}else{'FAIL'})}
        if (-not $ok) { throw "Resolver assertion failed for $($case.op): $($out.reason_code)" }
    }
    $disable = "update hr_security.group_memberships set is_active=false,valid_to=now() where id='$($ids.denyMember)';"
    $disable | docker exec -i $db psql -v ON_ERROR_STOP=1 -U postgres -d postgres | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Could not disable deny fixture.' }
    $body = @{p_tenant_id=$ids.tenant;p_operation='add'}|ConvertTo-Json
    $out = Invoke-RestMethod -Uri ($api + '/rest/v1/rpc/hr_soft_local_resolver_probe') -Method Post -Headers $headers -ContentType 'application/json' -Body $body
    if ($out -is [array]) {$out=$out[0]}
    $ok = [bool]$out.allowed -and $out.reason_code -eq 'ALLOWED_BY_GROUP'
    $results += [pscustomobject]@{Operation='add after deny disabled';Reason=$out.reason_code;Allow=$out.matched_allow_count;Deny=$out.matched_deny_count;Result=$(if($ok){'PASS'}else{'FAIL'})}
    if (-not $ok) { throw 'Positive allow assertion failed.' }
    Write-Output "Resolver E2E on PostgreSQL $pg"
    $results | Format-Table -AutoSize
}
finally {
    if ($probe) {
        $cleanup = @'
drop function if exists public.hr_soft_local_resolver_probe(uuid,text);
delete from hr_security.group_scope_assignments where tenant_id='__TENANT__';
delete from hr_security.group_permission_rules where tenant_id='__TENANT__';
delete from hr_security.group_memberships where tenant_id='__TENANT__';
delete from hr_security.data_scopes where id='__SCOPE__';
delete from hr_security.user_groups where tenant_id='__TENANT__';
delete from hr_security.app_users where id='__APPUSER__';
delete from hr_security.permissions where id='__PERMISSION__';
delete from hr_security.systems where id='__SYSTEM__';
delete from hr_core.companies where id='__COMPANY__';
delete from hr_core.tenants where id='__TENANT__';
notify pgrst,'reload schema';
'@
        foreach ($key in $ids.Keys) { $cleanup = $cleanup.Replace('__' + $key.ToUpper() + '__', $ids[$key]) }
        $cleanup | docker exec -i $db psql -v ON_ERROR_STOP=1 -U postgres -d postgres | Out-Null
        if ($LASTEXITCODE -ne 0) { Write-Warning 'Fixture cleanup reported an error.' }
    }
    if ($auth.id) {
        try { Invoke-RestMethod -Uri ($api + '/auth/v1/admin/users/' + $auth.id) -Method Delete -Headers @{apikey=$service;Authorization=('Bearer ' + $service)} | Out-Null }
        catch { Write-Warning 'Could not remove temporary Auth user.' }
    }
}
