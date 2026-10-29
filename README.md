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

### Documentos y contexto

Arrastra documentos al chat o usa el clip. En **⋮ → Contexto y archivos**, elige una carpeta local para conservar el texto y los archivos generados. Los documentos conservados siguen disponibles al reabrir la conversación, aunque el original se mueva o se elimine. La carpeta se mantiene fija mientras la biblioteca contenga archivos, para proteger sus referencias.

El contexto se configura por modelo hasta 32k, respetando su límite. El valor predeterminado es 16k o el máximo inferior del modelo. En una RTX 3060 Ti de 8 GB, Qwen2.5 7B respondió a 32k con reparto parcial en CPU; 16k sigue siendo la opción inicial. Cambiar el perfil puede recargar el modelo.

Los documentos extensos se consultan mediante búsqueda local de fragmentos con referencias. El medidor indica la estimación y la cobertura parcial; **Ver contexto enviado** permite comprobar la selección exacta. Una búsqueda parcial no permite garantizar sumas o recuentos de todo el documento. Los PDF escaneados siguen necesitando texto seleccionable: no se ha añadido OCR.

### Exportar y crear archivos

- **Exportar respuesta** en una burbuja o **Exportar conversación** en el menú: TXT, Markdown, PDF o Word/DOCX. La conversación incluye todos sus mensajes conservados; los turnos ya eliminados no se recuperan.
- Con un modelo que admita herramientas, como Qwen2.5, escribe **«Genera un Excel con estas ventas»** o **«Crea un PDF con este informe»**. Se crea un archivo real XLSX/PDF y aparece una tarjeta con **Guardar** para elegir destino. La primera vez se solicita la carpeta local si falta.
- Excel utiliza **XLSX**, con hojas y celdas de texto, números o booleanos. El contenido del modelo nunca se ejecuta como código ni como fórmula.
- PDF y DOCX conservan formato básico de encabezados, listas, tablas y código. PDF usa una fuente Unicode local; si necesitas otra, configura `LIGHTCHAT_PDF_FONT` con una ruta de fuente TTF compatible. Si faltan caracteres, se muestra el error.

Todo este procesamiento se realiza localmente y utiliza las dependencias existentes. Limpiar el historial también retira las fuentes documentales y archivos locales exclusivos de esa conversación; los originales del usuario se conservan.

## Estructura del proyecto

```
lightchat/
├── lib/
│   ├── main.dart                    # Punto de entrada, temas y ventana
│   ├── config/
│   │   └── vllm_config.dart       # Config de Ollama (aunque el archivo diga vllm)
│   ├── models/
│   │   ├── message.dart             # Mensajes, documentos y archivos generados
│   │   └── local_model.dart         # Definiciones de modelo
│   ├── screens/
│   │   ├── chat_screen.dart         # Pantalla principal de chat
│   │   └── ollama_manager_screen.dart # Gestor de modelos/estado Ollama
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

## Conversación, fuentes y cálculos locales

- Puedes preparar mensajes y adjuntos mientras Ollama está desconectado. Cada
  conversación conserva su borrador; cambiar de chat no lo mezcla con otro.
- Adjuntar documentos activa **Consultar documentos**. El control **General**
  permite volver a una conversación sin consulta documental; **Fuentes** deja
  elegir qué archivos se pueden consultar. Una selección parcial sigue sin
  garantizar totales completos ni citas perfectas del modelo.
- **Calcular tabla** abre un panel local para elegir archivo completo, hojas,
  cabecera, columna numérica y agrupación. Selecciona el separador CSV y formato
  decimal adecuados. Se muestran filas procesadas y valores excluidos; puedes
  copiar o exportar el resultado. No usa al modelo para sumar ni ejecuta fórmulas.
- Para calcular con un XLS antiguo, guárdalo como XLSX o CSV. Puedes seguir
  adjuntando XLS al chat para consultar su texto. Los límites de lectura bloquean
  el cálculo en vez de presentar un total de datos recortados.
- La respuesta muestra su estado final y conserva lo recibido si se interrumpe.
  **Continuar** está disponible para respuestas detenidas o limitadas. El selector
  informa de las capacidades del modelo; las imágenes requieren uno con visión.
- En ventanas estrechas, abre el historial con el botón de conversaciones. La
  búsqueda filtra los chats y **Volver al final** recupera el último mensaje.

## Licencia

MIT License - Ver [LICENSE](LICENSE) para detalles

## Recursos

- [Ollama](https://ollama.com) - Hacer LLMs locales accesibles
- [Flutter](https://flutter.dev) - Framework de UI
- [Ollama Library](https://ollama.com/library) - Catálogo de modelos oficiales

---

Hecho con ❤️ para la comunidad de IA local
