param(
    [Parameter(Mandatory=$true)]
    [string]$RunnerToken,
    [string]$GitHubRepo = "SamuelSilvaG/rdgen"
)

$ErrorActionPreference = "Stop"

Write-Host "Conectando na VM 'rdgen-windows-builder'..." -ForegroundColor Cyan
$pass = ConvertTo-SecureString "123@321" -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential("VM-Builder", $pass)

Invoke-Command -VMName "rdgen-windows-builder" -Credential $cred -ScriptBlock {
    param($token, $repo)
    Set-Location "C:\actions-runner"
    Write-Host "Registrando runner com o GitHub no repositorio $repo..." -ForegroundColor Cyan
    .\config.cmd --url "https://github.com/$repo" --token "$token" --name "rdgen-windows-builder" --labels "self-hosted,Windows,X64" --unattended --runasservice
    
    Write-Host "Iniciando servico do runner..." -ForegroundColor Cyan
    Start-Service "actions.runner.*" -ErrorAction SilentlyContinue
    Get-Service "actions.runner.*"
} -ArgumentList $RunnerToken, $GitHubRepo

Write-Host "`nRunner configurado e ativo como servico na VM com sucesso!" -ForegroundColor Green
