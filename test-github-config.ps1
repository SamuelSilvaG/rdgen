<#
.SYNOPSIS
    Script de diagnóstico para validar as configurações do GitHub e do rdgen.
#>

param(
    [string]$Token = ""
)

Write-Host "======================================================" -ForegroundColor Cyan
Write-Host "   Diagnóstico de Configuração GitHub - rdgen" -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan

# Carrega do .env se não foi passado como parâmetro
if (-not $Token -and (Test-Path ".env")) {
    Get-Content ".env" | ForEach-Object {
        if ($_ -match "^\s*GHBEARER\s*=\s*(.+)$") {
            $Token = $matches[1].Trim('"', "'", " ")
        }
    }
}

if (-not $Token -or $Token -eq "insira_seu_token_aqui") {
    Write-Host "[!] Nenhum token do GitHub informado." -ForegroundColor Yellow
    Write-Host "    Passe via parametro: .\test-github-config.ps1 -Token 'seu_token'" -ForegroundColor Yellow
    Write-Host "    Ou preencha GHBEARER no arquivo .env" -ForegroundColor Yellow
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $Token"
    "Accept"        = "application/vnd.github+json"
    "User-Agent"    = "rdgen-config-checker"
}

Write-Host "`n1. Verificando autenticacao do Token..." -NoNewline
try {
    $userRes = Invoke-RestMethod -Uri "https://api.github.com/user" -Headers $headers -Method Get
    Write-Host " [OK]" -ForegroundColor Green
    Write-Host "   Logado como: $($userRes.login)" -ForegroundColor Gray
} catch {
    Write-Host " [ERRO]" -ForegroundColor Red
    Write-Host "   Falha ao autenticar token: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host "`n2. Verificando acesso ao repositorio SamuelSilvaG/rdgen..." -NoNewline
try {
    $repoRes = Invoke-RestMethod -Uri "https://api.github.com/repos/SamuelSilvaG/rdgen" -Headers $headers -Method Get
    Write-Host " [OK]" -ForegroundColor Green
    Write-Host "   Fork detectado: $($repoRes.fork)" -ForegroundColor Gray
} catch {
    Write-Host " [ERRO]" -ForegroundColor Red
    Write-Host "   Repositorio nao encontrado ou sem permissao no token." -ForegroundColor Red
    exit 1
}

Write-Host "`n3. Verificando Workflows do GitHub Actions..." -NoNewline
try {
    $wfRes = Invoke-RestMethod -Uri "https://api.github.com/repos/SamuelSilvaG/rdgen/actions/workflows" -Headers $headers -Method Get
    Write-Host " [OK]" -ForegroundColor Green
    Write-Host "   Workflows encontrados: $($wfRes.total_count)" -ForegroundColor Gray
    
    $disabledCount = 0
    foreach ($wf in $wfRes.workflows) {
        if ($wf.state -ne "active") {
            $disabledCount++
        }
    }
    if ($disabledCount -gt 0) {
        Write-Host "   [ATENCAO] Ha $disabledCount workflow(s) desativado(s)!" -ForegroundColor Yellow
        Write-Host "   Acesse https://github.com/SamuelSilvaG/rdgen/actions para ativar os workflows." -ForegroundColor Yellow
    } else {
        Write-Host "   Todos os workflows estao ATIVOS e prontos!" -ForegroundColor Green
    }
} catch {
    Write-Host " [ERRO]" -ForegroundColor Red
    Write-Host "   Nao foi possivel listar os workflows. Verifique se o token tem permissao de 'Actions' e 'Workflows'." -ForegroundColor Red
}

Write-Host "`n======================================================" -ForegroundColor Cyan
Write-Host "Concluido! Se todos os itens estiverem verdes, o backend do rdgen podera acionar os runners perfeitamente." -ForegroundColor Cyan
Write-Host "======================================================" -ForegroundColor Cyan
