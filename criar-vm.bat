@echo off
title Criar VM Windows Hyper-V - rdgen
cd /d "%~dp0"
echo ========================================================
echo   Iniciando Criador da VM Windows Hyper-V para rdgen
echo ========================================================
echo Solicitando elevacao de Administrador...
powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0create-hyperv-vm.ps1\"'"
