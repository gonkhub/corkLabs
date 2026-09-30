# Runs every test in tests/ without a headset, on a throwaway copy of the
# project (so your open editor's .godot folder and your real takes are never
# touched).
#
# Usage (from the corkLabs folder):
#   powershell -File tools\run_tests.ps1                 # all tests
#   powershell -File tools\run_tests.ps1 -Only naming    # tests whose file name contains "naming"
#   powershell -File tools\run_tests.ps1 -Keep           # keep the copy (%TEMP%\corkcheck) for poking at
# Optional: -Godot "C:\path\to\Godot_console.exe"  -TimeoutSec 120
param(
    [string]$Godot = "$env:USERPROFILE\Desktop\Godot_v4.3-stable_win64_console.exe",
    [string]$Only = "",
    [switch]$Keep,
    [int]$TimeoutSec = 120
)

$project = Split-Path -Parent $PSScriptRoot
$tmp = "$env:TEMP\corkcheck"

Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory $tmp | Out-Null
Get-ChildItem $project -Force | Where-Object { $_.Name -notin @(".godot", ".git") } | Copy-Item -Destination $tmp -Recurse

# Let Godot scan the copy once (builds the class list). Show only real problems.
& $Godot --headless --xr-mode off --editor --path $tmp --quit-after 300 2>&1 | ForEach-Object { "$_" } |
    Where-Object { $_ -match "SCRIPT ERROR|Parse Error" } | Select-Object -First 20

$failed = 0
foreach ($test in Get-ChildItem "$tmp\tests\test_*.gd" | Where-Object { $_.Name -like "*$Only*" }) {
    Write-Host "=== $($test.Name) ==="
    $out = "$tmp\_out_$($test.BaseName).txt"
    $p = Start-Process -FilePath $Godot -NoNewWindow -PassThru `
        -ArgumentList @("--headless", "--xr-mode", "off", "--path", "`"$tmp`"", "--script", "res://tests/$($test.Name)") `
        -RedirectStandardOutput $out -RedirectStandardError "$out.err"
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill()
        Write-Host "TIMEOUT after $TimeoutSec s"
        $failed++
        continue
    }
    $lines = @(Get-Content $out -ErrorAction SilentlyContinue) + @(Get-Content "$out.err" -ErrorAction SilentlyContinue)
    $lines | Where-Object { $_ -notmatch "^Godot Engine|^\s*$" } | ForEach-Object { Write-Host $_ }
    if (-not ($lines -match "^ALL PASSED")) { $failed++ }
}

if (-not $Keep) { Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue }
if ($failed -eq 0) { Write-Host "`nALL TEST FILES PASSED" } else { Write-Host "`n$failed TEST FILE(S) FAILED" }
exit $failed
