<#
.SYNOPSIS
    Script de configuração automatizada da Máquina Virtual (Windows) para Build Local do RustDesk e rdgen.
.DESCRIPTION
    Executar este script DENTRO DA VM Windows como Administrador.
    Ele instala todas as dependências de compilação:
    - Visual Studio 2022 Build Tools (C++ Desktop, Windows SDK)
    - Rust (MSVC x64)
    - LLVM / Clang
    - Flutter SDK (3.24.5)
    - Python 3.12 & Git
    - ImageMagick & NASM
    - vcpkg e bibliotecas
    - GitHub Actions Self-Hosted Runner
#>

param(
    [string]$GitHubRepo = "SamuelSilvaG/rdgen",
    [string]$RunnerToken = ""
)

$ErrorActionPreference = "Stop"

function Write-Step($msg) {
    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
}

# 1. Verificar privilégios de Administrador
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "ERRO: Este script deve ser executado como Administrador no PowerShell." -ForegroundColor Red
    exit 1
}

Write-Step "1/8. Habilitando Suporte a Nomes Longos de Arquivo (Long Paths)"
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -Force
git config --global core.longpaths true 2>$null

Write-Step "2/8. Instalando Ferramentas Básicas via Winget (Git, Python, LLVM, ImageMagick, NASM)"
winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements --silent
winget install --id Python.Python.3.12 -e --source winget --accept-package-agreements --accept-source-agreements --silent
winget install --id LLVM.LLVM -e --source winget --accept-package-agreements --accept-source-agreements --silent
winget install --id ImageMagick.ImageMagick -e --source winget --accept-package-agreements --accept-source-agreements --silent
winget install --id NASM.NASM -e --source winget --accept-package-agreements --accept-source-agreements --silent

# Atualizar PATH na sessão atual
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

Write-Step "3/8. Instalando Visual Studio 2022 Build Tools (C++ / MSVC / Windows SDK)"
$vsInstallerArgs = "--quiet --wait --norestart --nocache " +
    "--add Microsoft.VisualStudio.Workload.VCTools " +
    "--add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 " +
    "--add Microsoft.VisualStudio.Component.Windows11SDK.22621 " +
    "--add Microsoft.VisualStudio.Component.VC.CMake.Project"

winget install --id Microsoft.VisualStudio.2022.BuildTools -e --source winget --override $vsInstallerArgs --accept-package-agreements --accept-source-agreements

Write-Step "4/8. Instalando Rustup e Toolchain Rust"
if (-not (Get-Command rustup -ErrorAction SilentlyContinue)) {
    Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile "$env:TEMP\rustup-init.exe"
    Start-Process -FilePath "$env:TEMP\rustup-init.exe" -ArgumentList "-y --default-toolchain stable-x86_64-pc-windows-msvc" -Wait
    Remove-Item "$env:TEMP\rustup-init.exe" -Force
}

$cargoPath = "$env:USERPROFILE\.cargo\bin"
if ($env:Path -notlike "*$cargoPath*") {
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";$cargoPath", "Machine")
    $env:Path += ";$cargoPath"
}

# RustDesk recomenda Rust 1.75 para compatibilidade com sciter / flutter runner
& "$cargoPath\rustup.exe" default 1.75.0-x86_64-pc-windows-msvc 2>$null
if ($LASTEXITCODE -ne 0) {
    & "$cargoPath\rustup.exe" install 1.75.0-x86_64-pc-windows-msvc
    & "$cargoPath\rustup.exe" default 1.75.0-x86_64-pc-windows-msvc
}

Write-Step "5/8. Configurando Variáveis de Ambiente do LLVM"
$llvmBin = "C:\Program Files\LLVM\bin"
[System.Environment]::SetEnvironmentVariable("LIBCLANG_PATH", $llvmBin, "Machine")
$env:LIBCLANG_PATH = $llvmBin

Write-Step "6/8. Instalando Flutter SDK (3.24.5)"
$flutterDir = "C:\flutter"
if (-not (Test-Path "$flutterDir\bin\flutter.bat")) {
    Write-Host "Baixando Flutter 3.24.5..."
    $flutterZip = "$env:TEMP\flutter_windows_3.24.5-stable.zip"
    Invoke-WebRequest -Uri "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.24.5-stable.zip" -OutFile $flutterZip
    Write-Host "Extraindo Flutter para C:\..."
    Expand-Archive -Path $flutterZip -DestinationPath "C:\" -Force
    Remove-Item $flutterZip -Force
}

if ($env:Path -notlike "*$flutterDir\bin*") {
    [System.Environment]::SetEnvironmentVariable("Path", $env:Path + ";$flutterDir\bin", "Machine")
    $env:Path += ";$flutterDir\bin"
}
& "$flutterDir\bin\flutter.bat" config --no-analytics
& "$flutterDir\bin\flutter.bat" config --enable-windows-desktop

Write-Step "7/8. Configurando vcpkg"
$vcpkgDir = "C:\vcpkg"
if (-not (Test-Path "$vcpkgDir\vcpkg.exe")) {
    Write-Host "Clonando vcpkg..."
    git clone https://github.com/microsoft/vcpkg.git $vcpkgDir
    pushd $vcpkgDir
    .\bootstrap-vcpkg.bat -disableMetrics
    popd
}
[System.Environment]::SetEnvironmentVariable("VCPKG_ROOT", $vcpkgDir, "Machine")
$env:VCPKG_ROOT = $vcpkgDir

Write-Step "8/8. Configuração do GitHub Self-Hosted Runner"
$runnerDir = "C:\actions-runner"
if (-not (Test-Path $runnerDir)) {
    New-Item -ItemType Directory -Path $runnerDir | Out-Null
}

$runnerZip = "$runnerDir\actions-runner-win-x64.zip"
if (-not (Test-Path "$runnerDir\config.cmd")) {
    Write-Host "Baixando GitHub Actions Runner mais recente..."
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/actions/runner/releases/latest"
    $asset = $latestRelease.assets | Where-Object { $_.name -match "actions-runner-win-x64-.*\.zip" } | Select-Object -First 1
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $runnerZip
    Expand-Archive -Path $runnerZip -DestinationPath $runnerDir -Force
    Remove-Item $runnerZip -Force
}

if ($RunnerToken) {
    Write-Host "Registrando runner com o repositório $GitHubRepo..."
    pushd $runnerDir
    .\config.cmd --url "https://github.com/$GitHubRepo" --token "$RunnerToken" --name "rdgen-windows-builder" --labels "self-hosted,Windows,X64" --unattended --runasservice
    popd
    Write-Host "Runner registrado e instalado como serviço do Windows com sucesso!" -ForegroundColor Green
} else {
    Write-Host "`nPara finalizar o registro do runner no GitHub:" -ForegroundColor Yellow
    Write-Host "1. Acesse: https://github.com/$GitHubRepo/settings/actions/runners/new" -ForegroundColor Yellow
    Write-Host "2. Copie o TOKEN de registro que o GitHub exibir." -ForegroundColor Yellow
    Write-Host "3. Abra o CMD ou PowerShell em $runnerDir e execute:" -ForegroundColor Yellow
    Write-Host "   .\config.cmd --url https://github.com/$GitHubRepo --token SEU_TOKEN --runasservice" -ForegroundColor Yellow
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "   Ambiente de Build da VM Configurado com Sucesso!   " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
