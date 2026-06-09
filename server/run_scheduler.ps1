# Runs the check-in scheduler every 5 minutes alongside the Django API.
# Usage (from server folder):  .\run_scheduler.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$python = Join-Path $PSScriptRoot 'venv\Scripts\python.exe'
if (-not (Test-Path $python)) {
    Write-Error 'Virtual environment not found. Run .\setup.ps1 first.'
}

Write-Host 'Starting check-in scheduler loop (every 5 minutes). Press Ctrl+C to stop.'
while ($true) {
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$stamp] Running run_checkin_scheduler..."
    & $python manage.py run_checkin_scheduler
    Start-Sleep -Seconds 300
}
