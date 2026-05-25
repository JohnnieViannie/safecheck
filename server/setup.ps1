# One-time / after-clone setup for the SafeBangle Django server (Windows PowerShell).
# Run from the server folder:  .\setup.ps1

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if (-not (Test-Path '.\venv\Scripts\python.exe')) {
    Write-Host 'Creating virtual environment...'
    python -m venv venv
}

Write-Host 'Installing dependencies...'
.\venv\Scripts\python.exe -m pip install --upgrade pip
.\venv\Scripts\python.exe -m pip install -r requirements.txt

Write-Host 'Applying migrations...'
.\venv\Scripts\python.exe manage.py migrate

Write-Host ''
Write-Host 'Done. Start the API with:'
Write-Host '  .\venv\Scripts\python.exe manage.py runserver 0.0.0.0:8080'
