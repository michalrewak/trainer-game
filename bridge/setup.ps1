<#
  Przygotowuje mostek trenażera na Windows (PowerShell 5.1 albo 7):
    powershell -ExecutionPolicy Bypass -File bridge\setup.ps1            # .venv + zależności + pytest
    powershell -ExecutionPolicy Bypass -File bridge\setup.ps1 -NoDev     # bez pytest
    powershell -ExecutionPolicy Bypass -File bridge\setup.ps1 -Recreate  # usuń .venv i utwórz od nowa
    powershell -ExecutionPolicy Bypass -File bridge\setup.ps1 -Portable  # tylko przenośny Python z .tools
  Python 3.12+ wybierany po kolei:
    1) przenośny z .tools\python-3.12 (w głównym checkoucie repo – wspólny także dla worktree),
    2) python / python3 z PATH (bez atrapy ze Sklepu Microsoft),
    3) launcher "py -3.12" / "py -3".
  Gdy żadnego nie ma (albo podano -Portable), pobiera oficjalny pakiet NuGet "python" 3.12.10
  (Python Software Foundation), sprawdza jego SHA-512 z metadanych NuGet i rozpakowuje folder
  tools\ do .tools\python-3.12. Nic nie instaluje w systemie i nie zmienia PATH ani rejestru.
#>
param(
    [switch]$NoDev,
    [switch]$Recreate,
    [switch]$Portable,
    [string]$PythonDir = ""
)
# "Continue": w PowerShell 5.1 przy "Stop" każda linia na stderr programu (np. pip) przerywałaby
# skrypt. Wynik poleceń sprawdzamy po kodzie wyjścia, a krytyczne cmdlety mają -ErrorAction Stop.
$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$bridge = $PSScriptRoot
$root = Split-Path -Parent $bridge
$nugetVersion = "3.12.10"

function Get-MainCheckout {
    # W worktree gita folder .tools (w .gitignore) leży w głównym checkoucie.
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $common = & git -C $root rev-parse --path-format=absolute --git-common-dir 2>$null
        if ($LASTEXITCODE -eq 0 -and $common) {
            return Split-Path -Parent ([string]$common).Trim()
        }
    }
    return $root
}

function Test-Python([string]$Exe, [string[]]$PreArgs = @()) {
    # Zwraca ścieżkę interpretera, jeśli to Python >= 3.12; inaczej $null.
    if (-not $Exe) { return $null }
    if ($Exe -like "*\WindowsApps\*") { return $null }  # atrapa ze Sklepu Microsoft
    if ($Exe.Contains("\") -and -not (Test-Path $Exe)) { return $null }
    $code = "import sys; print(sys.executable if sys.version_info >= (3, 12) else '')"
    $out = & $Exe @PreArgs -I -c $code 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    $path = ([string]($out | Select-Object -Last 1)).Trim()
    if ($path -and (Test-Path $path)) { return $path }
    return $null
}

function Install-PortablePython([string]$Dest) {
    Write-Host "Pobieram przenośny Python $nugetVersion (pakiet NuGet `"python`", Python Software Foundation)..."
    $reg = Invoke-RestMethod -Uri "https://api.nuget.org/v3/registration5-semver1/python/$nugetVersion.json" -UseBasicParsing -ErrorAction Stop
    $catalog = Invoke-RestMethod -Uri $reg.catalogEntry -UseBasicParsing -ErrorAction Stop
    if ($catalog.id -ne "python" -or $catalog.version -ne $nugetVersion -or $catalog.packageHashAlgorithm -ne "SHA512") {
        throw "Nieoczekiwane metadane pakietu w NuGet – przerwano."
    }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("wasteland-python-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tmp -ErrorAction Stop | Out-Null
    try {
        $pkg = Join-Path $tmp "python.$nugetVersion.nupkg"
        Invoke-WebRequest -Uri $reg.packageContent -OutFile $pkg -UseBasicParsing -ErrorAction Stop
        $sha = [Security.Cryptography.SHA512]::Create()
        $stream = [IO.File]::OpenRead($pkg)
        try { $actual = [Convert]::ToBase64String($sha.ComputeHash($stream)) } finally { $stream.Dispose(); $sha.Dispose() }
        if ($actual -cne $catalog.packageHash) { throw "Suma SHA-512 pakietu nie zgadza się z NuGet – przerwano." }
        Write-Host "SHA-512 zgodna z metadanymi NuGet."
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        New-Item -ItemType Directory -Force -Path $Dest -ErrorAction Stop | Out-Null
        $destFull = [IO.Path]::GetFullPath($Dest).TrimEnd('\') + '\'
        $zip = [IO.Compression.ZipFile]::OpenRead($pkg)
        try {
            foreach ($entry in $zip.Entries) {
                if (-not $entry.FullName.StartsWith("tools/")) { continue }
                $rel = $entry.FullName.Substring(6)
                if (-not $rel) { continue }
                $target = [IO.Path]::GetFullPath((Join-Path $Dest $rel))
                if (-not $target.StartsWith($destFull, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Podejrzana ścieżka w paczce: $($entry.FullName)"
                }
                if ($entry.FullName.EndsWith("/")) { New-Item -ItemType Directory -Force -Path $target | Out-Null; continue }
                $dir = Split-Path -Parent $target
                if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
            }
        } finally { $zip.Dispose() }
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }
    Write-Host "Przenośny Python rozpakowany do $Dest"
}

# --- 1. Interpreter --------------------------------------------------------------------
if (-not $PythonDir) { $PythonDir = Join-Path (Get-MainCheckout) ".tools\python-3.12" }
$python = Test-Python (Join-Path $PythonDir "python.exe")
if (-not $python -and -not $Portable) {
    foreach ($name in @("python", "python3")) {
        foreach ($cmd in @(Get-Command $name -All -CommandType Application -ErrorAction SilentlyContinue)) {
            $python = Test-Python $cmd.Source
            if ($python) { break }
        }
        if ($python) { break }
    }
}
if (-not $python -and -not $Portable -and (Get-Command py -ErrorAction SilentlyContinue)) {
    foreach ($flag in @("-3.12", "-3")) {
        $python = Test-Python "py" @($flag)
        if ($python) { break }
    }
}
if (-not $python) {
    Install-PortablePython $PythonDir
    $python = Test-Python (Join-Path $PythonDir "python.exe")
    if (-not $python) { throw "Nie udało się uruchomić przenośnego Pythona z $PythonDir" }
}
Write-Host "Python: $python"

# --- 2. Środowisko wirtualne i zależności ---------------------------------------------------
$venv = Join-Path $bridge ".venv"
$venvPython = Join-Path $venv "Scripts\python.exe"
if ($Recreate -and (Test-Path $venv)) {
    Write-Host "Usuwam $venv ..."
    Remove-Item -Recurse -Force $venv -ErrorAction Stop
}
if (-not (Test-Path $venvPython)) {
    Write-Host "Tworzę $venv ..."
    & $python -I -m venv $venv
    if ($LASTEXITCODE -ne 0) { throw "python -m venv nie powiodło się" }
}
$requirements = if ($NoDev) { "requirements.txt" } else { "requirements-dev.txt" }
Write-Host "Instaluję zależności z $requirements ..."
& $venvPython -m pip install --disable-pip-version-check -q -r (Join-Path $bridge $requirements)
if ($LASTEXITCODE -ne 0) { throw "pip install nie powiodło się" }
& $venvPython -c "import importlib.metadata as m; print('Zainstalowane: ' + ', '.join(p + ' ' + m.version(p) for p in ('bleak', 'websockets', 'rich')))"
if ($LASTEXITCODE -ne 0) { throw "Zależności nie dają się zaimportować" }

Write-Host ""
Write-Host "Gotowe. W katalogu bridge:" -ForegroundColor Green
Write-Host "  .\.venv\Scripts\python -m wasteland_bridge --sim   # symulator, bez sprzętu"
Write-Host "  .\.venv\Scripts\python -m wasteland_bridge         # Elite Suito przez Bluetooth"
Write-Host "  .\.venv\Scripts\python scan.py                     # urządzenia BLE w pobliżu"
if (-not $NoDev) { Write-Host "  .\.venv\Scripts\python -m pytest                   # testy" }
exit 0
