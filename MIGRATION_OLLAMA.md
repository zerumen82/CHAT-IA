# Migración a Ollama - Guía

## Resumen de Cambios

Se ha completado la migración del backend de **vLLM** a **Ollama**. Esta migración simplifica drásticamente la instalación y uso de LightChat.

## Comparación: vLLM vs Ollama

| Aspecto | vLLM (Anterior) | Ollama (Nuevo) |
|---------|-----------------|----------------|
| **Tamaño instalación** | ~10GB (Python + CUDA + vLLM) | ~200MB (binario único) |
| **Tiempo setup** | 10-30 minutos | 30 segundos |
| **Plataformas** | Solo Windows | Windows, macOS, Linux |
| **Gestión modelos** | Manual desde HuggingFace | `ollama pull modelo` |
| **Actualizaciones** | Manuales | Automáticas |
| **Soporte multimodal** | ✅ Completo | ✅ Sí (modelos específicos) |

## Archivos Modificados/Creados

### Nuevos Archivos
- [`lib/services/ollama_service.dart`](lib/services/ollama_service.dart) - Servicio principal de Ollama
- [`lib/services/chat_service_ollama.dart`](lib/services/chat_service_ollama.dart) - Chat adaptado para Ollama
- [`lib/screens/ollama_manager_screen.dart`](lib/screens/ollama_manager_screen.dart) - Pantalla de gestión
- [`lib/widgets/ollama_status_widget.dart`](lib/widgets/ollama_status_widget.dart) - Widgets de estado
- [`installer/install_ollama.ps1`](installer/install_ollama.ps1) - Instalador de Ollama

### Archivos Modificados
- [`lib/main.dart`](lib/main.dart) - Actualizado providers para Ollama
- [`lib/screens/chat_screen.dart`](lib/screens/chat_screen.dart) - Adaptado para OllamaService

### Archivos Obsoletos (mantenidos para referencia)
- `lib/services/vllm_service.dart`
- `lib/services/chat_service.dart`
- `lib/screens/vllm_manager_screen.dart`
- `lib/widgets/vllm_status_widget.dart`
- `installer/install_vllm.ps1`

## Instrucciones de Instalación

### Opción 1: Instalación Automática (Windows)

1. Ejecutar el instalador de PowerShell:
```powershell
.\installer\install_ollama.ps1
```

2. El script descargará e instalará Ollama automáticamente.

3. Una vez completado, abrir LightChat.

### Opción 2: Instalación Manual

1. Descargar Ollama desde: https://ollama.com/download

2. Instalar ejecutando el instalador descargado.

3. Asegurarse de que Ollama esté ejecutándose:
```bash
ollama serve
```

4. Abrir LightChat.

## Uso de LightChat con Ollama

### Descargar tu primer modelo

1. Abrir LightChat
2. Ir a **Configuración** > **Ollama Manager**
3. Seleccionar pestaña **CATÁLOGO**
4. Elegir un modelo (recomendado: `llama3.2` para empezar)
5. Click en **Instalar**
6. Esperar la descarga (varía según tamaño del modelo)

### Modelos Recomendados

| Modelo | Tamaño | Uso Ideal |
|--------|--------|-----------|
| `llama3.2` | ~2GB | Balance rendimiento/recursos |
| `mistral` | ~4GB | Buen rendimiento general |
| `phi3` | ~2GB | Muy rápido, recursos limitados |
| `llava` | ~4.5GB | Multimodal (soporta imágenes) |
| `codellama` | ~4GB | Programación/código |

### Comandos Útiles de Ollama

Desde terminal:
```bash
# Listar modelos instalados
ollama list

# Descargar un modelo
ollama pull llama3.2

# Eliminar un modelo
ollama rm llama3.2

# Ver información de un modelo
ollama show llama3.2

# Iniciar servidor Ollama
ollama serve
```

## Configuración

### Cambiar puerto de Ollama

Por defecto Ollama usa el puerto `11434`. Si necesitas cambiarlo:

**Windows:**
```powershell
$env:OLLAMA_HOST = "0.0.0.0:8080"
ollama serve
```

Luego en LightChat ir a Configuración y actualizar el puerto.

## Resolución de Problemas

### "Ollama no detectado"

1. Verificar que Ollama está instalado:
```bash
ollama --version
```

2. Verificar que Ollama está ejecutándose:
```bash
# Windows
Get-Process ollama

# O probar la API
curl http://localhost:11434/api/tags
```

3. Si no está ejecutándose, iniciarlo:
```bash
ollama serve
```

### Errores de conexión

1. Verificar firewall no bloquea puerto 11434
2. Comprobar que no hay otro servicio usando ese puerto
3. Intentar reiniciar Ollama

### Modelos muy lentos

1. Verificar que hay suficiente RAM/VRAM disponible
2. Usar modelos más pequeños (ej: `llama3.2:1b` en lugar de `llama3.2`)
3. Cerrar otras aplicaciones que consuman recursos

## Ventajas de la Migración

1. **Instalación simplificada**: De ~30 minutos a ~30 segundos
2. **Menor uso de disco**: De ~10GB a ~200MB (sin contar modelos)
3. **Cross-platform**: Funciona en Windows, macOS y Linux
4. **Actualizaciones automáticas**: Ollama se actualiza vía package managers
5. **Mejor gestión de modelos**: Sistema de tags y versiones integrado
6. **Comunidad activa**: Amplio ecosistema de modelos pre-convertidos

## Notas Técnicas

### API de Ollama

La API de Ollama es REST y compatible con OpenAI:

- **Listar modelos**: `GET /api/tags`
- **Generar texto**: `POST /api/generate`
- **Chat**: `POST /api/chat`
- **Pull modelo**: `POST /api/pull`
- **Eliminar modelo**: `DELETE /api/delete`

### Formato de Modelos

Ollama usa el formato **GGUF** (GGML Universal Format), optimizado para inferencia local.

### Diferencias con vLLM

- Ollama no soporta el formato original de HuggingFace (requiere GGUF)
- Ollama gestiona automáticamente la cuantización
- Ollama no requiere configuración de CUDA manual

## Volver a vLLM (Si es necesario)

Si necesitas volver a usar vLLM:

1. Modificar [`lib/main.dart`](lib/main.dart):
   - Cambiar `ChatServiceOllama()` por `ChatService()`
   - Cambiar `OllamaService.instance` por `VllmService.instance`

2. Los archivos de vLLM siguen disponibles en el proyecto.

## Soporte

Para problemas con Ollama:
- Documentación: https://github.com/ollama/ollama/tree/main/docs
- Modelos disponibles: https://ollama.com/library
- GitHub: https://github.com/ollama/ollama

---

**Migración completada el:** 2026-03-02  
**Versión de Ollama soportada:** 0.3.x o superior
