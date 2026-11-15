<#
  Pobiera oficjalny, przenośny Godot 4.7.2 (Windows x64) do .tools\godot-4.7.2\
  i sprawdza sumę SHA-512 z wydania na GitHubie. Nic nie instaluje w systemie.
    powershell -ExecutionPolicy Bypass -File tools\get-godot.ps1
#>
$ErrorActionPreference = "Stop"
$version = "4.7.2-stable"
$root = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $root ".tools\godot-4.7.2"
$zipName = "Godot_v$version`_win64.exe.zip"
$base = "https://github.com/godotengine/godot/releases/download/$version"

if (Test-Path (Join-Path $dest "Godot_v$version`_win64_console.exe")) {
    Write-Host "Godot już jest w $dest"
    exit 0
}
New-Item -ItemType Directory -Force -Path $dest | Out-Null
$zip = Join-Path $dest $zipName
$sums = Join-Path $dest "SHA512-SUMS.txt"
Write-Host "Pobieram $zipName (~86 MB)..."
Invoke-WebRequest -Uri "$base/$zipName" -OutFile $zip -UseBasicParsing
Invoke-WebRequest -Uri "$base/SHA512-SUMS.txt" -OutFile $sums -UseBasicParsing
$expected = (Select-String -Path $sums -Pattern ([regex]::Escape($zipName) + '$')).Line.Split(" ")[0].ToLower()
$actual = (Get-FileHash -Algorithm SHA512 -Path $zip).Hash.ToLower()
if ($expected -ne $actual) {
    Remove-Item $zip
    throw "Suma SHA-512 się nie zgadza – plik usunięty."
}
Expand-Archive -Path $zip -DestinationPath $dest -Force
Remove-Item $zip
Write-Host "Gotowe: $dest"
