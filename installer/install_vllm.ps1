# LightChat - vLLM Installation Script
# Este script instala Python (si no está) y vLLM automáticamente

param(
    [switch]$Silent = $false
)

$ErrorActionPreference = "Stop"
$LogFile = "$env:LOCALAPPDATA\LightChat\vllm_install.log"

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

function Test-Python {
    try {
        $pythonVersion = python --version 2>&1
        if ($pythonVersion -match "Python (\d+)\.(\d+)") {
            $major = [int]$matches[1]
            $minor = [int]$matches[2]
            Write-Log "Python encontrado: $pythonVersion"
            return ($major -ge 3 -and $minor -ge 10)
        }
    } catch {
        # Intentar con python3
        try {
            $pythonVersion = python3 --version 2>&1
            if ($pythonVersion -match "Python (\d+)\.(\d+)") {
                $major = [int]$matches[1]
                $minor = [int]$matches[2]
                Write-Log "Python3 encontrado: $pythonVersion"
                return ($major -ge 3 -and $minor -ge 10)
            }
        } catch {
            return $false
        }
    }
    return $false
}

function Install-Python {
    Write-Log "Instalando Python 3.12..."
    
    $pythonUrl = "https://www.python.org/ftp/python/3.12.0/python-3.12.0-amd64.exe"
    $pythonInstaller = "$env:TEMP\python_installer.exe"
    
    try {
        # Descargar instalador
        Write-Log "Descargando Python..."
        Invoke-WebRequest -Uri $pythonUrl -OutFile $pythonInstaller -UseBasicParsing
        
        # Instalar Python
        Write-Log "Ejecutando instalador de Python..."
        $installArgs = "/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_pip=1"
        Start-Process -FilePath $pythonInstaller -ArgumentList $installArgs -Wait
        
        # Actualizar PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        # Limpiar instalador
        Remove-Item $pythonInstaller -Force
        
        Write-Log "Python instalado correctamente"
        return $true
    } catch {
        Write-Log "Error instalando Python: $_"
        return $false
    }
}

function Install-Vllm {
    param([string]$PythonCmd)
    
    Write-Log "Instalando vLLM..."
    
    try {
        # Actualizar pip primero
        Write-Log "Actualizando pip..."
        & $PythonCmd -m pip install --upgrade pip --quiet 2>&1 | Out-Null
        
        # Instalar vLLM
        Write-Log "Instalando vLLM (esto puede tardar varios minutos)..."
        
        # Detectar si hay GPU NVIDIA
        $hasNvidia = $false
        try {
            $nvidiaSmi = nvidia-smi 2>&1
            if ($LASTEXITCODE -eq 0) {
                $hasNvidia = $true
                Write-Log "GPU NVIDIA detectada - instalando vLLM con soporte CUDA"
            }
        } catch {
            Write-Log "No se detectó GPU NVIDIA - instalando vLLM para CPU"
        }
        
        # Instalar vLLM
        $vllmInstall = & $PythonCmd -m pip install vllm --no-cache-dir 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Log "vLLM instalado correctamente"
            
            # Instalar huggingface-hub para descargar modelos
            Write-Log "Instalando huggingface-hub..."
            & $PythonCmd -m pip install huggingface-hub --quiet 2>&1 | Out-Null
            
            if ($LASTEXITCODE -eq 0) {
                Write-Log "huggingface-hub instalado correctamente"
            }
            
            return $true
        } else {
            Write-Log "Error instalando vLLM: $vllmInstall"
            return $false
        }
    } catch {
        Write-Log "Error instalando vLLM: $_"
        return $false
    }
}

function Test-Vllm {
    param([string]$PythonCmd)
    
    try {
        $result = & $PythonCmd -c "import vllm; print(vllm.__version__)" 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log "vLLM versión: $result"
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

# Main
Write-Log "========================================"
Write-Log "LightChat - Instalador de vLLM"
Write-Log "========================================"

# Verificar Python
$pythonCmd = "python"
if (-not (Test-Python)) {
    Write-Log "Python 3.10+ no encontrado"
    
    if (-not $Silent) {
        $response = [System.Windows.MessageBox]::Show(
            "Python 3.10+ no está instalado.`n`n¿Desea instalar Python 3.12 automáticamente?",
            "LightChat - Python requerido",
            "YesNo",
            "Question"
        )
        
        if ($response -eq "Yes") {
            if (-not (Install-Python)) {
                Write-Log "Error: No se pudo instalar Python"
                if (-not $Silent) {
                    [System.Windows.MessageBox]::Show(
                        "No se pudo instalar Python automáticamente.`n`nPor favor, instale Python 3.10+ desde python.org y ejecute LightChat nuevamente.",
                        "LightChat - Error",
                        "OK",
                        "Error"
                    )
                }
                exit 1
            }
        } else {
            Write-Log "Instalación cancelada por el usuario"
            exit 0
        }
    } else {
        # Modo silencioso - instalar automáticamente
        if (-not (Install-Python)) {
            Write-Log "Error: No se pudo instalar Python"
            exit 1
        }
    }
}

# Verificar comando de Python correcto
try {
    python --version 2>&1 | Out-Null
    $pythonCmd = "python"
} catch {
    try {
        python3 --version 2>&1 | Out-Null
        $pythonCmd = "python3"
    } catch {
        Write-Log "Error: Python no está disponible en PATH"
        exit 1
    }
}

# Verificar/Instalar vLLM
if (Test-Vllm -PythonCmd $pythonCmd) {
    Write-Log "vLLM ya está instalado"
} else {
    if (-not (Install-Vllm -PythonCmd $pythonCmd)) {
        Write-Log "Error: No se pudo instalar vLLM"
        if (-not $Silent) {
            [System.Windows.MessageBox]::Show(
                "No se pudo instalar vLLM automáticamente.`n`nPor favor, verifique su conexión a internet e intente nuevamente desde la aplicación.",
                "LightChat - Error",
                "OK",
                "Error"
            )
        }
        exit 1
    }
}

Write-Log "========================================"
Write-Log "Instalación completada exitosamente"
Write-Log "========================================"

if (-not $Silent) {
    [System.Windows.MessageBox]::Show(
        "vLLM se ha instalado correctamente.`n`nAhora puede usar LightChat para descargar y ejecutar modelos de IA locales.",
        "LightChat - Instalación completada",
        "OK",
        "Information"
    )
}

exit 0
