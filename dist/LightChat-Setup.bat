@echo off
echo ========================================
echo LightChat - Instalador y Ejecutor
echo ========================================
echo.

REM Verificar si Ollama está instalado
where ollama >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Ollama no está instalado.
    echo [INFO] Descargando instalador de Ollama...
    
    powershell -Command "Start-Process 'https://ollama.com/download/windows'"
    
    echo.
    echo [IMPORTANT] Por favor, instala Ollama y luego ejecuta este script de nuevo.
    echo [IMPORTANT] After installing Ollama, run this script again.
    pause
    exit /b 1
)

echo [OK] Ollama está instalado.

REM Verificar si Ollama está ejecutándose
powershell -Command "Invoke-WebRequest -Uri 'http://localhost:11434/api/tags' -TimeoutSec 2 -ErrorAction SilentlyContinue" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Iniciando Ollama...
    start /B ollama serve
    timeout /t 5 /nobreak >nul
)

echo [OK] Ollama está ejecutándose.

REM Verificar modelos instalados
echo.
echo [INFO] Verificando modelos instalados...
powershell -Command "try { $r = Invoke-WebRequest -Uri 'http://localhost:11434/api/tags' -TimeoutSec 5 -ErrorAction Stop | ConvertFrom-Json; if ($r.models.Count -eq 0) { Write-Host '[WARN] No hay modelos instalados.'; Write-Host '[INFO] Puedes instalar modelos desde LightChat o ejecutando: ollama pull llama3.2' } else { Write-Host \"[OK] Modelos instalados: $($r.models.Count)\" } } catch { Write-Host '[WARN] No se pudo verificar modelos.' }"

echo.
echo ========================================
echo Listo para usar LightChat
echo ========================================
echo.
echo Para iniciar LightChat, ejecuta: lightchat.exe
echo.
echo NOTA: Ollama debe estar ejecutándose en segundo plano.
echo.

pause
