# Runs every test in tests/ without a headset.
# Usage (from the corkLabs folder):  powershell -File tools\run_tests.ps1
# Optional: -Godot "C:\path\to\Godot_console.exe"
param(
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64_console.exe"
)

$project = Split-Path -Parent $PSScriptRoot
# Make sure Godot has scanned the project (builds the class list).
& $Godot --headless --xr-mode off --editor --path $project --quit 2>&1 | Out-Null

$failed = 0
foreach ($test in Get-ChildItem "$project\tests\test_*.gd") {
    Write-Host "=== $($test.Name) ==="
    & $Godot --headless --xr-mode off --path $project --script "res://tests/$($test.Name)" 2>&1 |
        Where-Object { $_ -notmatch "^Godot Engine" -and $_ -ne "" } | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) { $failed++ }
}
if ($failed -eq 0) { Write-Host "`nALL TEST FILES PASSED" } else { Write-Host "`n$failed TEST FILE(S) FAILED" }
exit $failed
