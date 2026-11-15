<#
  Testy gry bez sprzętu (Windows PowerShell):
    powershell -ExecutionPolicy Bypass -File tools\test.ps1
  Kroki: import projektu, kompilacja wszystkich skryptów i scen, testy jednostkowe,
  test dymny (pełna wyprawa autopilotem, przyspieszona, z zapisem do user://smoke.json).
  Godot: zmienna GODOT, albo .tools\godot-*\*_console.exe (tools\get-godot.ps1), albo PATH.
#>
# "Continue": Godot pisze ostrzeżenia na stderr, a w PowerShell 5.1 przy "Stop" każda taka
# linia przerywałaby skrypt. Wynik każdego kroku sprawdzamy po kodzie wyjścia.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$game = Join-Path $root "game"

function Find-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    $local = Get-ChildItem -Path (Join-Path $root ".tools") -Filter "Godot_v4*_console.exe" -Recurse -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($local) { return $local.FullName }
    foreach ($name in @("godot4", "godot")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    throw "Nie znaleziono Godota 4.7. Uruchom tools\get-godot.ps1 albo ustaw zmienną GODOT."
}

$godot = Find-Godot
Write-Host "Godot: $godot"
$failed = @()

function Step($title, [string[]]$godotArgs) {
    Write-Host ""
    Write-Host "=== $title ===" -ForegroundColor Cyan
    & $godot @godotArgs 2>&1 | ForEach-Object { "$_" } | Where-Object { $_ -notmatch "Unreferenced static string|string_name.cpp|NavMeshGeometryParser|PagedAllocator|Thread object is being destroyed|wait_to_finish|thread.cpp" } | Write-Host
    if ($LASTEXITCODE -ne 0) { $script:failed += $title; Write-Host "BŁĄD ($LASTEXITCODE)" -ForegroundColor Red }
    else { Write-Host "OK" -ForegroundColor Green }
}

Step "Import projektu" @("--headless", "--path", $game, "--import")
Step "Kompilacja skryptów i scen" @("--headless", "--path", $game, "--script", "res://tests/check_scripts.gd")
Step "Testy jednostkowe" @("--headless", "--path", $game, "--script", "res://tests/run_tests.gd")
Step "Test dymny (wyprawa autopilotem)" @("--headless", "--path", $game, "--", "--autostart", "--autopilot", "--minutes=0.5", "--time-scale=10", "--quit-on-finish", "--save=user://smoke.json")

Write-Host ""
if ($failed.Count -gt 0) {
    Write-Host ("NIEUDANE: " + ($failed -join ", ")) -ForegroundColor Red
    exit 1
}
Write-Host "Wszystkie kroki zielone." -ForegroundColor Green
exit 0
