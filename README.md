# LightChat

Aplicación de chat ligero y privado para LLMs locales ejecutados con [Ollama](https://ollama.com). Todo corre en tu máquina: sin nube, sin cuentas, sin credenciales.

## Características

- **Catálogo dinámico de modelos**: Descarga modelos directamente desde el registry de Ollama, siempre actualizado
- **Local y privado**: Todo el procesamiento ocurre en tu máquina (API de Ollama en `localhost:11434`)
- **Soporte multimodal**: Chatea con imágenes usando modelos de visión
- **Gestión de modelos**: Descarga, elimina y controla modelos instalados desde la app
- **Multiplataforma**: Windows, macOS y Linux
- **Respuestas en streaming**: Experiencia de chat en tiempo real
- **Bajo consumo de recursos**: Optimizado para eficiencia

## Requisitos

- [Ollama](https://ollama.com) instalado y ejecutándose
- Windows 10/11, macOS 10.15+, o Linux
- 4GB+ RAM (8GB+ recomendado)

## Instalación

### 1. Instalar Ollama

Descarga e instala Ollama desde [ollama.com](https://ollama.com/download) o usa el instalador automático:

```powershell
# Windows PowerShell
.\installer\install_ollama.ps1
```

### 2. Descargar LightChat

Descarga el último release o compila desde el código fuente:

```bash
git clone https://github.com/zerumen82/CHAT-IA.git
cd CHAT-IA/lightchat
flutter pub get
flutter build windows  # o macos, linux
```

### 3. Ejecutar

Inicia Ollama:

```bash
ollama serve
```

Luego lanza LightChat y descarga tu primer modelo desde el catálogo.

## Uso

1. Abre LightChat y ve a **Gestión de Ollama → Catálogo**
2. Explora los modelos disponibles (obtenidos directamente del registry de Ollama)
3. Pulsa **Instalar** en el modelo que quieras (ej: `llama3:latest`, `llama3.2:3b`, `mistral:7b`, `phi3:mini`, etc.)
4. Vuelve a la pantalla de chat y comienza a conversar

## Estructura del proyecto

```
lightchat/
├── lib/
│   ├── main.dart                    # Punto de entrada, temas y ventana
│   ├── config/
│   │   └── vllm_config.dart       # Config de Ollama (aunque el archivo diga vllm)
│   ├── models/
│   │   ├── chat_message.dart        # Modelos de mensaje
│   │   └── local_model.dart         # Definiciones de modelo
│   ├── screens/
│   │   ├── chat_screen.dart         # Pantalla principal de chat
│   │   ├── ollama_manager_screen.dart # Gestor de modelos/estado Ollama
│   │   └── model_manager_screen.dart  # Instalación/descarga de modelos
│   ├── services/
│   │   ├── ollama_service.dart          # Cliente API Ollama (singleton)
│   │   ├── chat_service_ollama.dart     # Lógica del chat con streaming
│   │   ├── model_catalog_service.dart   # Catálogo online de modelos
│   │   ├── context_service.dart         # Contexto conversacional
│   │   └── hardware_detector_service.dart # RAM/VRAM para recomendaciones
│   └── widgets/
│       ├── chat_input.dart          # Entrada de mensajes
│       ├── message_bubble.dart      # Visualización de mensajes
│       └── ollama_status_widget.dart # Estado de conexión
```

## Desarrollo

### Requisitos previos

- Flutter SDK 3.0+
- Dart SDK 3.0+

### Build

```bash
# Obtener dependencias
flutter pub get

# Ejecutar en modo depuración
flutter run

# Compilar en release
flutter build windows  # Windows
flutter build macos    # macOS
flutter build linux    # Linux
```

### Empaquetado Windows

Usa `build_installer.ps1` + `installer/lightchat_setup.iss` (Inno Setup).

## Licencia

MIT License - Ver [LICENSE](LICENSE) para detalles

## Recursos

- [Ollama](https://ollama.com) - Hacer LLMs locales accesibles
- [Flutter](https://flutter.dev) - Framework de UI
- [Ollama Library](https://ollama.com/library) - Catálogo de modelos oficiales

---

Hecho con ❤️ para la comunidad de IA local
