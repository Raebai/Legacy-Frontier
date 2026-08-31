<#
    Register (or re-register) the STICKSPIRE daily ops task.

        powershell -ExecutionPolicy Bypass -File python-tools\install_daily_task.ps1
        powershell -ExecutionPolicy Bypass -File python-tools\install_daily_task.ps1 -Remove

    WHAT IT RUNS, AND WHY A LOCAL TASK IS THE RIGHT ANSWER *THIS* TIME
    -----------------------------------------------------------------
    A local task that POSTED was built once and deleted (commit 7060ac3). It was
    the wrong shape: it needed the laptop awake, plugged in and logged on at the
    same minute every morning, forever, and any morning it was not, a post was
    silently missed and nothing said so.

    This task does not post. Upload-Post holds the queue and their servers do the
    posting. All this does is REFILL that queue back to 30 days, snapshot the
    analytics, and check that yesterday's posts actually went out. Because the
    queue is 30 days deep and `--topup` is idempotent, the task can fail, be
    skipped, or not run for a fortnight without costing a single post. The laptop
    stopped being a dependency of posting; it is now only a dependency of posting
    CONTINUING a month from now.

    THE SCHEDULER DEFAULTS ARE WRONG FOR A LAPTOP AND ARE OVERRIDDEN BELOW
    ---------------------------------------------------------------------
    Out of the box a scheduled task carries:
        DisallowStartIfOnBatteries  True   -> never runs unplugged
        StopIfGoingOnBatteries      True   -> killed mid-upload if unplugged
        StartWhenAvailable          False  -> a missed run is simply lost
    All three are flipped. `StartWhenAvailable` is the important one: it makes the
    task catch up after the machine has been off, which is precisely the case the
    old design failed on.
#>
param(
    [switch]$Remove,
    [string]$Time = "11:47"
)

$ErrorActionPreference = "Stop"
$TaskName = "StickSpire daily ops"
$Repo = Split-Path -Parent $PSScriptRoot
$Cmd = Join-Path $Repo "python-tools\daily_ops.cmd"

if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "Removed '$TaskName'."
    } else {
        Write-Host "'$TaskName' was not registered; nothing to remove."
    }
    Write-Host ""
    Write-Host "The VENDOR still holds whatever is already queued - removing this task"
    Write-Host "does not cancel anything. Posts continue until the queue drains, then"
    Write-Host "stop. Use: python python-tools\daily_post.py --list"
    return
}

if (-not (Test-Path $Cmd)) { throw "Missing $Cmd" }

# Prove python can actually run the tools before promising a task will.
$probe = & python -c "import sys; print(sys.version.split()[0])" 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "'python' is not runnable from this shell, so the task would fail silently every day. Fix PATH first. ($probe)"
}
Write-Host "python $probe found on PATH"

$action = New-ScheduledTaskAction -Execute "cmd.exe" `
    -Argument "/c `"$Cmd`"" -WorkingDirectory $Repo

$trigger = New-ScheduledTaskTrigger -Daily -At $Time

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 6) `
    -MultipleInstances IgnoreNew

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Description `
    "Refills the Upload-Post queue to 30 days, snapshots analytics, verifies yesterday. Does NOT post." | Out-Null

$t = Get-ScheduledTask -TaskName $TaskName
Write-Host ""
Write-Host "Registered '$TaskName', daily at $Time."
Write-Host ("  AllowStartIfOnBatteries : {0}" -f (-not $t.Settings.DisallowStartIfOnBatteries))
Write-Host ("  DontStopOnBatteries     : {0}" -f (-not $t.Settings.StopIfGoingOnBatteries))
Write-Host ("  StartWhenAvailable      : {0}" -f $t.Settings.StartWhenAvailable)
Write-Host ""
Write-Host "Run it once now to prove it works end to end:"
Write-Host "  Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Get-Content content\daily_post.log -Tail 40"
