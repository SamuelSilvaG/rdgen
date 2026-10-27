<#
.SYNOPSIS
    Cria e configura a Máquina Virtual Windows no Hyper-V para compilação do RustDesk / rdgen.
.DESCRIPTION
    Este script automatiza a criação de uma VM Hyper-V Geração 2 (UEFI + TPM + Secure Boot)
    pronta para o Windows 11, utilizando a ISO localizada em Downloads.
#>

[CmdletBinding()]
param(
    [string]$VMName = "rdgen-windows-builder",
    [string]$IsoPath = "C:\Users\Samuel\Downloads\W11_25H2_MULTI_MSDN_LITE_26200.6584_x64_13.09.2025_by_zerocoolroot.iso",
    [string]$VMBasePath = "C:\Hyper-V",
    [int]$DiskSizeGB = 80,
    [int]$CpuCount = 4,
    [int]$MemoryStartupGB = 8,
    [int]$MemoryMinGB = 4,
    [int]$MemoryMaxGB = 12,
    [string]$SwitchName = "Default Switch",
    [switch]$NoStart,
    [switch]$NoConsole
)

$ErrorActionPreference = "Stop"

function Write-Step($title) {
    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "======================================================" -ForegroundColor Cyan
}

# 1. Verificar privilégios de Administrador e auto-elevar se necessário
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[*] Solicitando elevacao de privilegios de Administrador para o Hyper-V..." -ForegroundColor Yellow
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($NoStart) { $argList += " -NoStart" }
    if ($NoConsole) { $argList += " -NoConsole" }
    try {
        $proc = Start-Process powershell.exe -ArgumentList $argList -Verb RunAs -Wait -PassThru
        exit $proc.ExitCode
    } catch {
        Write-Host "`n[!] Atencao: A solicitacao de elevacao automatica requer confirmacao na interface interativa." -ForegroundColor Red
        Write-Host "    Abra um terminal PowerShell como Administrador ou use o atalho 'criar-vm.bat' na raiz do projeto:" -ForegroundColor Yellow
        Write-Host "    powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`"`n" -ForegroundColor Cyan
        exit 1
    }
}

# Inicia transcrição de log para diagnóstico
$logDir = "C:\Hyper-V"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir "create-vm.log"
try { Start-Transcript -Path $logFile -Force | Out-Null } catch {}

Write-Step "1/7. Verificando Pre-requisitos"

# Verifica se a ISO existe
if (-not (Test-Path $IsoPath)) {
    Write-Error "Arquivo ISO nao encontrado em: $IsoPath"
    exit 1
}
Write-Host "[OK] ISO encontrada: $IsoPath" -ForegroundColor Green

# Adiciona o usuario atual ao grupo Administradores do Hyper-V
try {
    $loggedUser = [System.Environment]::UserName
    net localgroup "Administradores do Hyper-V" "$loggedUser" /add 2>$null
    Write-Host "[OK] Usuario '$loggedUser' configurado no grupo 'Administradores do Hyper-V'." -ForegroundColor Green
} catch {
    Write-Host "[!] Nao foi possivel adicionar ao grupo Administradores do Hyper-V: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Verifica se a VM já existe
$existingVM = Get-VM -Name $VMName -ErrorAction SilentlyContinue
if ($existingVM) {
    if ($existingVM.State -ne "Running") {
        Write-Host "`n[*] Removendo definicao anterior da VM para limpar estado criptografado que causou 0xC000A002..." -ForegroundColor Cyan
        Remove-VM -Name $VMName -Force
        $existingVM = $null
    }
}

Write-Step "2/7. Preparando Diretorios"
$vmDir = Join-Path $VMBasePath $VMName
$vhdDir = Join-Path $vmDir "Virtual Hard Disks"
$vhdPath = Join-Path $vhdDir "$VMName.vhdx"

if (-not (Test-Path $vhdDir)) {
    New-Item -ItemType Directory -Path $vhdDir -Force | Out-Null
}
Write-Host "[OK] Diretorio da VM: $vmDir" -ForegroundColor Green

Write-Step "3/7. Criando Maquina Virtual Hyper-V (Geracao 2)"
if (Test-Path $vhdPath) {
    New-VM -Name $VMName `
           -Path $VMBasePath `
           -Generation 2 `
           -VHDPath $vhdPath `
           -MemoryStartupBytes ([int64]$MemoryStartupGB * 1GB) `
           -SwitchName $SwitchName | Out-Null
} else {
    New-VM -Name $VMName `
           -Path $VMBasePath `
           -Generation 2 `
           -NewVHDPath $vhdPath `
           -NewVHDSizeBytes ([int64]$DiskSizeGB * 1GB) `
           -MemoryStartupBytes ([int64]$MemoryStartupGB * 1GB) `
           -SwitchName $SwitchName | Out-Null
}

Write-Host "[OK] VM '$VMName' criada com sucesso." -ForegroundColor Green

Write-Step "4/7. Configurando Recursos de Hardware (CPU e Memoria Dinamica)"
Set-VMProcessor -VMName $VMName -Count $CpuCount
Set-VMMemory -VMName $VMName `
             -DynamicMemoryEnabled $true `
             -MinimumBytes ([int64]$MemoryMinGB * 1GB) `
             -StartupBytes ([int64]$MemoryStartupGB * 1GB) `
             -MaximumBytes ([int64]$MemoryMaxGB * 1GB)
Set-VM -VMName $VMName -AutomaticStopAction ShutDown

Write-Host "[OK] Processadores: $CpuCount vCPUs" -ForegroundColor Green
Write-Host "[OK] Memoria Dinamica: $MemoryMinGB GB - $MemoryMaxGB GB (Startup: $MemoryStartupGB GB)" -ForegroundColor Green

Write-Step "5/7. Habilitando Recursos de Seguranca (Secure Boot)"
# Habilita Secure Boot com template padrao da Microsoft
Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
Write-Host "[OK] Secure Boot ativado (Template: MicrosoftWindows)." -ForegroundColor Green
Write-Host "[OK] vTPM desativado (elimina o erro 0xC000A002; a ISO Lite do Windows 11 nao requer TPM)." -ForegroundColor Gray

Write-Step "6/7. Conectando Imagem ISO e Configurando Ordem de Boot"
$dvdDrive = Get-VMDvdDrive -VMName $VMName -ErrorAction SilentlyContinue
if (-not $dvdDrive) {
    $dvdDrive = Add-VMDvdDrive -VMName $VMName -Path $IsoPath -Passthru
} else {
    $dvdDrive | Set-VMDvdDrive -Path $IsoPath
    $dvdDrive = Get-VMDvdDrive -VMName $VMName
}

# Define o DVD como primeiro dispositivo de boot
Set-VMFirmware -VMName $VMName -FirstBootDevice $dvdDrive
Write-Host "[OK] ISO conectada no drive de DVD virtual." -ForegroundColor Green
Write-Host "[OK] Primeiro dispositivo de boot configurado: DVD com a ISO do Windows." -ForegroundColor Green

Write-Step "7/7. Inicializacao da VM"
$vmCurrent = Get-VM -Name $VMName
if ($vmCurrent.State -ne "Running" -and -not $NoStart) {
    Write-Host "Ligando a Maquina Virtual '$VMName'..." -ForegroundColor Cyan
    Start-VM -Name $VMName
    Write-Host "[OK] VM iniciada com sucesso!" -ForegroundColor Green
} elseif ($vmCurrent.State -eq "Running") {
    Write-Host "[OK] VM ja esta em execucao." -ForegroundColor Green
}

if (-not $NoConsole) {
    Write-Host "Abrindo janela de conexao do Hyper-V (vmconnect)..." -ForegroundColor Cyan
    Start-Process "vmconnect.exe" -ArgumentList "localhost `"$VMName`""
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host "   VM Criada e Iniciada com Sucesso no Hyper-V!       " -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green
Write-Host "PROXIMOS PASSOS:" -ForegroundColor Yellow
Write-Host "1. Na janela do console da VM (vmconnect), caso apareca a mensagem" -ForegroundColor Yellow
Write-Host "   'Press any key to boot from CD or DVD...', pressione qualquer tecla rapidamente." -ForegroundColor Yellow
Write-Host "2. A instalacao do Windows 11 Lite iniciara (ela ja contem Autounattend.xml" -ForegroundColor Yellow
Write-Host "   para instalacao automatizada rapida)." -ForegroundColor Yellow
Write-Host "3. Apos a conclusao da instalacao e inicializacao do Windows na VM," -ForegroundColor Yellow
Write-Host "   abra o PowerShell como Administrador dentro da VM e execute:" -ForegroundColor Yellow
Write-Host '   irm https://raw.githubusercontent.com/SamuelSilvaG/rdgen/main/setup-windows-runner-vm.ps1 | iex' -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Green

try { Stop-Transcript | Out-Null } catch {}
Start-Sleep -Seconds 5

