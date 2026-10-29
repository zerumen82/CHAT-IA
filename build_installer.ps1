# LightChat Build Script for Windows Installer
# Ejecutar desde la raíz del proyecto

param(
    [string]$Configuration = "Release",
    [switch]$SkipBuild = $false,
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
$BuildDir = Join-Path $ProjectRoot "build\windows\x64\runner\$Configuration"
$DistDir = Join-Path $ProjectRoot "dist"
$InstallerScript = Join-Path $ProjectRoot "installer\lightchat_setup.iss"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  LightChat Windows Installer Builder  " -ForegroundColor Cyan
Write-Host "  Con vLLM integrado                   " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Verificar Flutter
Write-Host "Verificando Flutter..." -ForegroundColor Yellow
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "Flutter: $flutterVersion" -ForegroundColor Green
} catch {
    Write-Host "ERROR: Flutter no está instalado o no está en PATH" -ForegroundColor Red
    exit 1
}

# Verificar Inno Setup
Write-Host "Verificando Inno Setup..." -ForegroundColor Yellow
$innoSetupPath = "C:\Program Files (x86)\Inno Setup 6\ISCC.exe"
if (-not (Test-Path $innoSetupPath)) {
    $innoSetupPath = "C:\Program Files\Inno Setup 6\ISCC.exe"
}
if (-not (Test-Path $innoSetupPath)) {
    Write-Host "ERROR: Inno Setup 6 no está instalado" -ForegroundColor Red
    Write-Host "Descárgalo de: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    exit 1
}
Write-Host "Inno Setup encontrado: $innoSetupPath" -ForegroundColor Green

# Compilar aplicación Flutter
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "Compilando aplicación Flutter..." -ForegroundColor Yellow
    
    Push-Location $ProjectRoot
    try {
        flutter clean 2>&1 | Out-Null
        flutter pub get 2>&1 | Out-Null
        
        if ($Verbose) {
            flutter build windows --release
        } else {
            flutter build windows --release 2>&1 | Out-Null
        }
        
        Write-Host "Aplicación compilada exitosamente" -ForegroundColor Green
    } catch {
        Write-Host "ERROR al compilar Flutter: $_" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Pop-Location
} else {
    Write-Host "Omitiendo compilación de Flutter" -ForegroundColor Yellow
}

# Verificar que el ejecutable existe
$exePath = Join-Path $BuildDir "lightchat.exe"
if (-not (Test-Path $exePath)) {
    Write-Host "ERROR: No se encontró el ejecutable: $exePath" -ForegroundColor Red
    exit 1
}
Write-Host "Ejecutable encontrado: $exePath" -ForegroundColor Green

# Crear directorio de distribución
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir | Out-Null
    Write-Host "Directorio de distribución creado: $DistDir" -ForegroundColor Green
}

# Crear directorio de scripts del instalador
$scriptsDir = Join-Path $ProjectRoot "installer"
if (-not (Test-Path $scriptsDir)) {
    New-Item -ItemType Directory -Path $scriptsDir | Out-Null
}

# Verificar que el script de instalación de vLLM existe
$vllmScriptPath = Join-Path $scriptsDir "install_vllm.ps1"
if (-not (Test-Path $vllmScriptPath)) {
    Write-Host "ADVERTENCIA: No se encontró el script install_vllm.ps1" -ForegroundColor Yellow
}

# Crear archivo README para el instalador
$readmeContent = @"
LightChat 1.1.0
===============

LightChat es un chat ligero con IA local usando vLLM.

CARACTERÍSTICAS:
- Interfaz minimalista y pixelada
- Integración completa con vLLM
- Descarga automática de modelos desde HuggingFace
- Soporte para modelos multimodales (visión)
- Modelos sin censura disponibles

REQUISITOS DEL SISTEMA:
- Windows 10/11 (64-bit)
- 8 GB RAM mínimo (16 GB recomendado)
- GPU NVIDIA con 8GB VRAM (opcional, para mejor rendimiento)
- Conexión a internet para descargar modelos

INSTALACIÓN:
1. Ejecuta LightChat-Setup-1.1.0.exe
2. Sigue el asistente de instalación
3. El instalador puede instalar Python y vLLM automáticamente
4. Inicia LightChat desde el menú Inicio

USO:
1. Abre LightChat
2. Ve a "Gestionar vLLM" desde el menú
3. Descarga un modelo desde la pestaña "MODELOS"
4. Inicia el servidor con el modelo descargado
5. ¡Comienza a chatear!

MODELOS RECOMENDADOS:
- Dolphin-2.9-Llama3-8B (sin censura, 8GB VRAM)
- Mistral-7B-OpenHermes (sin censura, 6GB VRAM)
- Phi-3-mini-4k-instruct (ligero, 4GB VRAM)
- Pixtral-12B (multimodal, 12GB VRAM)

SOPORTE:
https://github.com/lightchat

Licencia: MIT
"@

$readmePath = Join-Path $ProjectRoot "README_INSTALLER.txt"
$readmeContent | Out-File -FilePath $readmePath -Encoding UTF8

# Crear archivo LICENSE si no existe
$licensePath = Join-Path $ProjectRoot "LICENSE"
if (-not (Test-Path $licensePath)) {
    $licenseContent = @"
MIT License

Copyright (c) 2026 LightChat

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"@
    $licenseContent | Out-File -FilePath $licensePath -Encoding UTF8
    Write-Host "Archivo LICENSE creado" -ForegroundColor Green
}

# Compilar instalador con Inno Setup
Write-Host ""
Write-Host "Compilando instalador con Inno Setup..." -ForegroundColor Yellow

try {
    $innoResult = & $innoSetupPath $InstallerScript 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Instalador compilado exitosamente" -ForegroundColor Green
        
        $installerPath = Join-Path $DistDir "LightChat-Setup-1.1.0.exe"
        if (Test-Path $installerPath) {
            $fileSize = (Get-Item $installerPath).Length / 1MB
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  INSTALADOR CREADO EXITOSAMENTE" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Archivo: $installerPath" -ForegroundColor Cyan
            Write-Host "Tamaño: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "El instalador incluye:" -ForegroundColor White
            Write-Host "  - LightChat aplicación" -ForegroundColor White
            Write-Host "  - Script de instalación de vLLM" -ForegroundColor White
            Write-Host "  - Opción para instalar Python automáticamente" -ForegroundColor White
            Write-Host ""
        }
    } else {
        Write-Host "ERROR al compilar instalador:" -ForegroundColor Red
        Write-Host $innoResult
        exit 1
    }
} catch {
    Write-Host "ERROR al ejecutar Inno Setup: $_" -ForegroundColor Red
    exit 1
}

# Limpiar archivos temporales
Remove-Item $readmePath -ErrorAction SilentlyContinue

Write-Host "Proceso completado." -ForegroundColor Green