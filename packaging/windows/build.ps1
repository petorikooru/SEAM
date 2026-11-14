[CmdletBinding()]
param(
    [switch]$SkipInstaller,
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Venv = Join-Path $ProjectRoot ".packaging-venv"
$Python = Join-Path $Venv "Scripts\python.exe"
$Dist = Join-Path $ProjectRoot "dist"
$Release = Join-Path $ProjectRoot "release"
$GuiBundle = Join-Path $Dist "KAI Bridge Inspection"

if ($Clean) {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Venv, $Dist, (Join-Path $ProjectRoot "build"), $Release
}

if (-not (Test-Path $Python)) {
    $Launcher = Get-Command py -ErrorAction SilentlyContinue
    if ($Launcher) {
        & py -3.12 -m venv $Venv
    } else {
        $PythonCommand = Get-Command python -ErrorAction Stop
        & $PythonCommand.Source -m venv $Venv
    }
}

& $Python -m pip install --upgrade pip wheel
& $Python -m pip install -e "$ProjectRoot[packaging]"

Push-Location $ProjectRoot
try {
    & $Python -m PyInstaller --clean --noconfirm "packaging\pyinstaller\gui.spec"
} finally {
    Pop-Location
}

if (-not (Test-Path $GuiBundle)) { throw "GUI bundle was not created: $GuiBundle" }

New-Item -ItemType Directory -Force $Release | Out-Null
$PortableZip = Join-Path $Release "KAI_Bridge_Inspection_v5.2.0_Windows_x64_Portable.zip"
Remove-Item -Force -ErrorAction SilentlyContinue $PortableZip
Compress-Archive -Path "$GuiBundle\*" -DestinationPath $PortableZip -CompressionLevel Optimal

if (-not $SkipInstaller) {
    $IsccCandidates = @(
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 7\ISCC.exe",
        "$env:ProgramFiles(x86)\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 7\ISCC.exe"
    )
    $Iscc = $IsccCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($Iscc) {
        & $Iscc "/DSourceDir=$GuiBundle" (Join-Path $ProjectRoot "packaging\windows\KAI_Bridge_Inspection.iss")
    } else {
        Write-Warning "Inno Setup was not found. Portable ZIP created. Install Inno Setup and rerun to create Setup.exe."
    }
}

Write-Host "Build outputs: $Release"
