param(
    [string]$ApiBaseUrl = "https://safebangle.com/api",
    [ValidateSet("apk", "appbundle")]
    [string]$Target = "apk"
)

$ErrorActionPreference = "Stop"
$AppRoot = Join-Path $PSScriptRoot ".."
$RepoRoot = Join-Path $PSScriptRoot "../.."
Set-Location $AppRoot

flutter pub get

$defines = @(
    "--dart-define=SAFECHECK_API_BASE_URL=$ApiBaseUrl",
    "--dart-define=SAFECHECK_ENV=prod"
)

if ($Target -eq "apk") {
    flutter build apk --release @defines
    $BuiltApk = Join-Path $AppRoot "build/app/outputs/flutter-apk/app-release.apk"
    if (-not (Test-Path $BuiltApk)) {
        throw "Expected APK not found: $BuiltApk"
    }
    $DeployDir = Join-Path $RepoRoot "deploy/public"
    New-Item -ItemType Directory -Force -Path $DeployDir | Out-Null
    $PublishApk = Join-Path $DeployDir "safecheck.apk"
    Copy-Item -Path $BuiltApk -Destination $PublishApk -Force
    Write-Host ""
    Write-Host "Release APK built and copied to:"
    Write-Host "  $PublishApk"
    Write-Host ""
    Write-Host "API base URL baked in: $ApiBaseUrl"
    Write-Host ""
    Write-Host "Upload to VPS:"
    Write-Host "  scp `"$PublishApk`" root@YOUR_VPS:/var/www/safebangle/public/safecheck.apk"
    Write-Host ""
    Write-Host "Download URL after upload:"
    Write-Host "  https://safebangle.com/safecheck.apk"
} else {
    flutter build appbundle --release @defines
    Write-Host "Release app bundle complete."
}
