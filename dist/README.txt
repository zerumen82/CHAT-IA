# LightChat - Chat con IA Local

## Instalación

### 1. Instalar Ollama (Requerido)

Ollama es el motor de IA local que permite usar modelos de lenguaje en tu computadora.

**Opción A - Instalador automático:**
Ejecuta `LightChat-Setup.bat` y sigue las instrucciones.

**Opción B - Manual:**
1. Descarga Ollama desde: https://ollama.com/download/windows
2. Instala Ollama
3. Abre una terminal y ejecuta: `ollama pull llama3.2`

### 2. Ejecutar LightChat

Ejecuta `lightchat.exe` para abrir la aplicación.

## Modelos Recomendados

### Para texto:
- `llama3.2` - Rápido y eficiente
- `mistral` - Bueno para conversación

### Para imágenes:
- `llava` - Soporte de imágenes

### Instalar modelos:
```bash
ollama pull llama3.2
ollama pull llava
ollama pull mistral
```

## Solución de problemas

### Ollama no se inicia:
```bash
ollama serve
```

### Ver modelos instalados:
```bash
ollama list
```

### Error de conexión:
Asegúrate de que Ollama esté ejecutándose en el puerto 11434.

## Estructura de archivos

```
LightChat/
├── lightchat.exe              # Aplicación principal
├── LightChat-Setup.bat        # Script de instalación
├── flutter_windows.dll        # Biblioteca Flutter
├── data/                      # Archivos de la aplicación
└── scripts/
    └── install_ollama.ps1    # Instalador de Ollama
```

## Requisitos del sistema

- Windows 10/11 (64 bits)
- Mínimo 8GB de RAM (16GB recomendado)
- Espacio en disco: 2GB + modelos (4-8GB por modelo)

## Licencia

MIT License
