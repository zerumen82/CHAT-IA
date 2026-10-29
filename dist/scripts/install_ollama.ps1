# LightChat - Ollama Installation Script
# Este script descarga e instala Ollama automáticamente

param(
    [switch]$Silent = $false
)

$ErrorActionPreference = "Stop"
$LogFile = "$env:LOCALAPPDATA\LightChat\ollama_install.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    
    # Crear directorio si no existe
    $logDir = Split-Path $LogFile -Parent
    if (!(Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-Ollama {
    try {
        $result = ollama --version 2>&1
        if ($result -match "ollama") {
            Write-Log "Ollama encontrado: $result"
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Get-OllamaVersion {
    try {
        $result = ollama --version 2>&1
        if ($result -match "(\d+\.\d+\.\d+)") {
            return $matches[1]
        }
    } catch {
        return $null
    }
    return $null
}

function Install-Ollama {
    Write-Log "Descargando Ollama..."
    
    $ollamaUrl = "https://ollama.com/download/OllamaSetup.exe"
    $ollamaInstaller = "$env:TEMP\OllamaSetup.exe"
    
    try {
        # Descargar instalador
        Write-Log "Descargando desde $ollamaUrl..."
        Invoke-WebRequest -Uri $ollamaUrl -OutFile $ollamaInstaller -UseBasicParsing
        
        # Instalar Ollama
        Write-Log "Ejecutando instalador de Ollama..."
        if ($Silent) {
            $installArgs = "/S"
        } else {
            $installArgs = ""
        }
        
        Start-Process -FilePath $ollamaInstaller -ArgumentList $installArgs -Wait
        
        # Limpiar instalador
        Remove-Item $ollamaInstaller -Force -ErrorAction SilentlyContinue
        
        # Verificar instalación
        if (Test-Ollama) {
            $version = Get-OllamaVersion
            Write-Log "Ollama instalado correctamente (versión $version)"
            return $true
        } else {
            Write-Log "ERROR: Ollama no se instaló correctamente"
            return $false
        }
    } catch {
        Write-Log "Error instalando Ollama: $_"
        return $false
    }
}

function Start-OllamaService {
    Write-Log "Iniciando servicio Ollama..."
    
    try {
        # Iniciar Ollama en segundo plano
        $process = Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden -PassThru
        
        # Esperar a que inicie
        Write-Log "Esperando a que Ollama inicie..."
        Start-Sleep -Seconds 5
        
        # Verificar que está corriendo
        $maxAttempts = 12
        $attempt = 0
        $running = $false
        
        while ($attempt -lt $maxAttempts -and !$running) {
            try {
                $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction SilentlyContinue
                if ($response.StatusCode -eq 200) {
                    $running = $true
                    Write-Log "Ollama está ejecutándose correctamente"
                }
            } catch {
                $attempt++
                Write-Log "Intento $attempt/$maxAttempts..."
                Start-Sleep -Seconds 2
            }
        }
        
        return $running
    } catch {
        Write-Log "Error iniciando Ollama: $_"
        return $false
    }
}

function Download-DefaultModel {
    Write-Log "Descargando modelo por defecto (llama3.2)..."
    
    try {
        # Descargar modelo pequeño para empezar
        ollama pull llama3.2
        Write-Log "Modelo llama3.2 descargado correctamente"
        return $true
    } catch {
        Write-Log "Error descargando modelo: $_"
        return $false
    }
}

# ============== SCRIPT PRINCIPAL ==============

Write-Log "=========================================="
Write-Log "LightChat - Instalador de Ollama"
Write-Log "=========================================="

# Verificar si Ollama ya está instalado
Write-Log "Verificando instalación existente..."

if (Test-Ollama) {
    $version = Get-OllamaVersion
    Write-Log "Ollama ya está instalado (versión $version)"
    
    # Verificar si está corriendo
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 5 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            Write-Log "Ollama ya está ejecutándose"
            Write-Log "Instalación completada correctamente"
            exit 0
        }
    } catch {
        Write-Log "Ollama está instalado pero no ejecutándose"
        $start = Start-OllamaService
        if ($start) {
            Write-Log "Ollama iniciado correctamente"
        } else {
            Write-Log "ADVERTENCIA: No se pudo iniciar Ollama automáticamente"
            Write-Log "Por favor, inicia Ollama manualmente ejecutando: ollama serve"
        }
        exit 0
    }
}

# Instalar Ollama
Write-Log "Ollama no encontrado. Procediendo con la instalación..."
Write-Log ""
Write-Log "NOTA: Esta instalación requiere privilegios de administrador."
Write-Log "Se abrirá una ventana de instalación de Ollama."
Write-Log ""

$installed = Install-Ollama

if (!$installed) {
    Write-Log "ERROR: No se pudo instalar Ollama"
    Write-Log "Por favor, descarga Ollama manualmente desde: https://ollama.com/download"
    exit 1
}

# Iniciar servicio
$started = Start-OllamaService

if (!$started) {
    Write-Log "ADVERTENCIA: Ollama está instalado pero no se pudo iniciar automáticamente"
    Write-Log "Por favor, inicia Ollama manualmente desde el menú de inicio"
    exit 0
}

# Descargar modelo por defecto (opcional)
$hasModels = $false
try {
    $response = Invoke-WebRequest -Uri "http://localhost:11434/api/tags" -TimeoutSec 10
    $models = ($response.Content | ConvertFrom-Json).models
    if ($models.Count -gt 0) {
        $hasModels = $true
        Write-Log "Modelos ya disponibles: $($models.Count)"
    }
} catch {
    $hasModels = $false
}

if (!$hasModels) {
    Write-Log ""
    Write-Log "No hay modelos instalados."
    Write-Log "Desde LightChat podrás descargar modelos desde el catálogo."
    Write-Log "Modelos recomendados: llama3.2 (pequeño y rápido) o mistral (balanceado)"
}

# Instalar modelo con soporte de imágenes por defecto
Write-Log ""
Write-Log "Instalando modelo con soporte de imágenes..."
$hasImageModels = $false
try {
    ollama pull llava
    Write-Log "Modelo llava (soporte de imágenes) instalado correctamente"
    $hasImageModels = $true
} catch {
    Write-Log "Error instalando llava: $_"
}

if (!$hasImageModels) {
    try {
        ollama pull llama3.2
        Write-Log "Modelo llama3.2 (texto) instalado como alternativa"
    } catch {
        Write-Log "Error instalando llama3.2: $_"
    }
}

Write-Log ""
Write-Log "=========================================="
Write-Log "Instalación completada exitosamente!"
Write-Log "=========================================="
Write-Log ""
Write-Log "Ollama está listo para usar con LightChat."
Write-Log "Abre LightChat y ve a Configuración > Ollama Manager"
Write-Log ""
Write-Log "Modelos instalados:"
if ($hasImageModels) {
    Write-Log "  ✓ llava - Soporte de imágenes (recomendado)"
}
Write-Log "  ✓ llama3.2 - Modelo de texto (alternativa)"

exit 0
