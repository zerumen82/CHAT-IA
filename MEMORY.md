# MEMORY.md — Memoria persistente de LightChat

> **Propósito:** memoria de largo plazo del proyecto para agentes de IA y colaboradores.
> Actualizar este archivo cada vez que cambien hechos relevantes (fases completadas, decisiones, deuda conocida, entorno). Guía de trabajo en [`AGENTS.md`](AGENTS.md).

**Última actualización:** 2026-10-24

---

## 1. Estado actual del proyecto

| Aspecto | Estado |
|---|---|
| Tipo | App de escritorio Flutter (chat con LLMs locales vía Ollama) |
| Ciclo | **Usable y en mantenimiento**; migración vLLM → Ollama completada 2026-03-02 |
| Rama | `master` (única), remoto `github.com/zerumen82/CHAT-IA`, **árbol limpio** al momento de revisar |
| Builds recientes | Último commit significativo: `63d2175` "Migración a Ollama: multimodal, icono retrocápsula, 8 idiomas, modelo preferido guardado" |
| Tamaño código | ~9,500 líneas Dart en `lib/` (21 archivos `.dart`) |
| `flutter analyze` | **Sin incidencias** |
| `flutter test` | **37 pruebas pasan**: chat, reintento, documentos (TXT/XLSX/PDF/fechas), idioma, detección de modelos sin censura, recomendaciones, temas y ventana estrecha |
| Build Windows | `flutter build windows` completado correctamente (2026-10-18) |
| CI/CD | No hay (sin `.github/workflows`) |
| Instaladores | Inno Setup (`installer/lightchat_setup.iss`), script Ollama (`installer/install_ollama.ps1`), `build_installer.ps1`, `dist/` con build PyInstaller antigua |

### Optimizaciones de rendimiento aplicadas (2026-10-17)

| Área | Cambio | Archivo |
|------|--------|---------|
| ChatScreen | Quitado `addPostFrameCallback` del console; scroll con `jumpTo` en lugar de `animateTo`; eliminado `_showShortcutsHelp` sin uso | `lib/screens/chat_screen.dart` |
| MessageBubble | `RepaintBoundary` para evitar repintar burbujas largas; `MediaQuery` cacheado en variable local | `lib/widgets/message_bubble.dart` |
| ChatInput | Caché de bytes de imagen (`Uint8List`) para evitar `readAsBytes()` repetido en cada build | `lib/widgets/chat_input.dart` |
| OllamaManagerScreen | Consumers divididos por sección (status bar, catálogo, instalados, settings, logs) para no reconstruir todo el árbol | `lib/screens/ollama_manager_screen.dart` |
| ModelManagerScreen | Consumers divididos por tab; hardware info cacheado sin FutureBuilder por build; eliminación de `_sizeCache` sin uso | `lib/screens/model_manager_screen.dart` |
| ContextService | `saveMessagesDebounced()` con Timer de 300 ms para evitar escrituras frecuentes en disco; `flushMessages()` para forzar escritura inmediata | `lib/services/context_service.dart` |

### Mejoras visuales aplicadas (2026-10-17)

| Área | Cambio | Archivo |
|------|--------|---------|
| main.dart | Tema light/dark con `textTheme` definido, `cardTheme` y `dialogTheme` personalizados, esquemas de color por seed | `lib/main.dart` |
| MessageBubble | Bordes y sombras coherentes, `.withValues(alpha:)` en lugar de `.withAlpha()` deprecado, radio de bordes consistente | `lib/widgets/message_bubble.dart` |
| ChatInput | Borde superior más sutil (`outlineVariant` con alpha 0.5), contadores de texto e imágenes, `.withValues(alpha:)` | `lib/widgets/chat_input.dart` |
| OllamaManagerScreen | Colores dinámicos según tema (sin hardcodeados), tarjetas con sombra suave, estados de chip coherentes | `lib/screens/ollama_manager_screen.dart` |
| ModelManagerScreen | Estados vacíos con iconos y colores de tema, chips de hardware con `colorScheme` | `lib/screens/model_manager_screen.dart` |
| OllamaStatusWidget | `.withValues(alpha:)` en lugar de `.withOpacity()`, indicador de estado con colores de tema | `lib/widgets/ollama_status_widget.dart` |
| ImageMessageBubble | Borrado (unificado en `message_bubble.dart`) | `lib/widgets/image_message_bubble.dart` eliminado |

### Ajustes de usabilidad visual (2026-10-18; corregidos después)

| Área | Cambio | Archivo |
|------|--------|---------|
| Tema | Paleta fría azul/teal; el modo oscuro es el predeterminado y se respetan preferencias explícitas | `lib/main.dart`, `lib/services/theme_service.dart` |
| Chat | Burbujas con contraste, errores con reintento visible, copiar accesible y controles de entrada más fáciles de pulsar | `lib/widgets/message_bubble.dart`, `lib/widgets/chat_input.dart` |
| Navegación | Selector de modelo con modelo/flecha visibles; estados basados en el tema | `lib/widgets/model_selector.dart`, `lib/widgets/ollama_status_widget.dart`, `lib/screens/chat_screen.dart` |
| Gestor Ollama | Mejor jerarquía de pestañas, búsqueda, tarjetas y registros; consola adaptable a ventanas estrechas | `lib/screens/ollama_manager_screen.dart`, `lib/screens/chat_screen.dart` |
| Pruebas visuales | Contraste WCAG AA en superficies de ambos temas; render en 480 px y reintento de errores | `test/widget_test.dart` |

### Mejoras de UI aplicadas (primera sesión, 2026-10-17)

| Área | Cambio | Archivo |
|------|--------|---------|
| Burbujas de mensaje | Unificado `MessageBubble` + `ImageMessageBubble` en un solo widget con soporte texto + imágenes + retry + copy | `lib/widgets/message_bubble.dart` (borrado `image_message_bubble.dart`) |
| Pantalla chat | Typing indicator ("Escribiendo…"), errores con botón Reintentar, empty state con botón "Conectar Ollama" | `lib/screens/chat_screen.dart` |
| ChatInput | Contador de caracteres, preview de imágenes más grande (80px), botón adjuntar directo | `lib/widgets/chat_input.dart` |
| Ollama Manager | Consola como pestaña "LOGS" integrada | `lib/screens/ollama_manager_screen.dart` |
| Model Manager | Filtros de chip implementados (Sin censura, Multimodal, Recomendados) | `lib/screens/model_manager_screen.dart` |
| Recomendaciones | Nombres reales de Ollama con etiquetas de tamaño (llama3.2, phi3, qwen2.5, gemma2, mistral, codellama, deepseek-coder, llava, tinyllama, mixtral) | `lib/services/hardware_detector_service.dart` |

### Pendientes conocidos (deuda técnica, orden sugerido)

1. ~~Reemplazar `test/widget_test.dart`~~ ✓ test real de pantalla de chat añadido (2026-10-18).
2. ~~Unificar migración en docs~~ — `pubspec.yaml` aún describe *"chat interface for vLLM"* (real: Ollama); `MIGRATION_OLLAMA.md` lista archivos "obsletos mantenidos" que ya no existen en disco.
3. ~~Limpiar incidencias del analyzer~~ ✓ `flutter analyze` sin incidencias (2026-10-18).
4. ~~Eliminar directorio fantasma `" lib/"~~ (verificación hecha).
5. ~~Dejar de trackear `build/` y `dist/`~~ (~991 archivos binarios ya en git).
6. ~~Legacy no activo~~ — `Main.py`/`main.spec`/`create_icon.py`, `.aider.*`, `typedef VllmConfig` — no borrar sin plan aprobado.
7. ~~`analysis_options.yaml`~~ plantilla por defecto, sin reglas propias.
8. ~~Revisar `ModelManagerScreen`/`ModelManagerService`~~ ✓ eliminados junto con `image_service`, `image_picker_widget` y `ChatMessage` por no estar enlazados (2026-10-24).
9. El botón «Limpiar» de la pestaña Registros en `OllamaManagerScreen` no tiene acción; la consola flotante del chat ya tiene «Limpiar» con acción (2026-10-24).

## 2. Decisiones consolidadas (no deshacer)

| Decisión | Detalle | Cuándo/por qué |
|---|---|---|
| **Backend único: Ollama** | vLLM y LM Studio eliminados | Migración 2026-03-02: de ~10GB/30min a ~200MB/30s y cross-platform. Documentada en `MIGRATION_OLLAMA.md`. |
| **Sin soporte de programación/IDE** | Campos previos como `ide_screen`, `code_analysis_service`: borrados en "Fase 1 – Limpieza" (2026-02-14) | Reenfoque a chat general estilo mensajería. |
| **Dependencias acotadas** | `provider` para estado, `http` para streaming de Ollama, `shared_preferences` para preferencias, `file_selector`/`desktop_drop` para archivos, `syncfusion_flutter_pdf` + `archive` + `xml` para documentos (`pubspec.yaml`) | Decidido en plan 2026-02-14; `dio`, `uuid`, `path_provider`, `image`, `flutter_animate` y `cupertino_icons` retirados el 2026-10-24 al no tener uso. |
| **Documentos: `desktop_drop` + Syncfusion PDF 30.x + parser XLSX propio** | `desktop_drop` recibe archivos del sistema; `syncfusion_flutter_pdf` 30.2.7 extrae texto; XLSX se lee con `archive` + `xml` (ZIP/Office Open XML) | 2026-10-23: `excel` 4.0.6 exige `archive ^3.6.1` e `image` exige `archive ^4.0.7`; Syncfusion ≥31 exige `xml 7` e `image` usa `xml ^6`. No añadir `excel` sin resolver ese conflicto. |
| **Singleton de servicios** | Patrón `XxxService.instance` registrado en `main.dart` con `provider` | Ya aplicado en `ollama_service.dart`; mantener consistencia. |
| **Planes en `plans/` (español)** | `YYYY-MM-DD_Nombre_Contexto.md` | Formato establecido 2026-02-14; es el "estilo de otros proyectos" del equipo: documento de resumen + documento de plan. |
| **Puerto Ollama 11434** | Configurable en la app si cambia `OLLAMA_HOST` | Estándar de Ollama. |
| **Cierre: liberar VRAM sin matar Ollama** | `setPreventClose` + `unloadLoadedModels()` (`keep_alive: 0`); `stopServer()` solo termina el proceso que inició LightChat | Matar `ollama.exe` afectaba a otras apps del usuario (corregido 2026-10-24). Nunca volver a `taskkill /F /IM ollama.exe`. |

## 3. Contexto de entorno (para no redescubrir)

- **Máquina:** Windows (Git Bash/MSYS), ruta real del proyecto `D:\PROJECTS\LITGHCHAT\lightchat`.
- **GPU:** NVIDIA RTX 3060 Ti, **8 GB VRAM** → mantener modelos en 7–8B Q4. Descargados el 2026-10-23: `qwen2.5:7b` (normal) y `huihui_ai/qwen2.5-abliterate:7b-instruct-q4_K_M` (sin censura), ~4,7 GB cada uno; ambos respondieron correctamente sobre texto tipo Excel.
- **Flutter 3.41.7 stable**, canal stable. `flutter --version` imprime aviso de versión nueva (actualizar opcional).
- **Análisis completo tarda ~62 s** (`flutter analyze`) — preveerlo al verificar cambios.
- **Sin** Docker, servicios, BD ni credenciales: proyecto 100% cliente.
- Directorios ignorados por git/agents locales: `build/`, `.dart_tool/`, `.idea/`, `dist/` parcialmente trackeado (ver deuda).

## 4. Historial de fases

1. **Herramienta de programación con agente IDE** (commits iniciales, 2025: `itui`, `swegf`, … timestamps confusos/previos).
2. **Fase 1/2 – Transformación a chat general + vLLM** (plan 2026-02-14, `plans/2026-02-14_LightChat_Plan_Transformacion_vLLM.md`): eliminación del IDE, vLLM como backend único, catálogo de modelos, detección de hardware, UI mensajería.
3. **Migración a Ollama** (2026-03-02, commit `63d2175`): `ollama_service`, `chat_service_ollama`, `ollama_manager_screen`, instalador PS. Multimodal, 8 idiomas detectados, icono "retrocápsula".
4. **Actual (oct-2026):** mantenimiento/borrado de deuda; optimización de rendimiento y mejoras visuales de UI; sin nuevas fases planificadas en `plans/`.
5. **Corrección del refresco Ollama** (2026-10-18): `ChatServiceOllama.loadModels()` vuelve a consultar `/api/tags`; reintentos y retorno del gestor sincronizan el selector. Añadidas pruebas del flujo y de la pantalla principal.
6. **Mejoras de chat local** (2026-10-18): historial cronológico con imágenes, envío de mensajes solo-imagen, respuesta progresiva con NDJSON robusto y opciones de generación (`num_ctx`). Recomendaciones locales más conservadoras según RAM/VRAM, sin inventar VRAM para GPUs desconocidas. Verificados `flutter test` (6), `flutter analyze` (sin incidencias) y `flutter build windows`.
7. **Usabilidad visual** (2026-10-18): mejoras de contraste, tipografía, selector de modelo, controles accesibles y gestor Ollama optimizado para lectura y ventanas estrechas. La paleta cálida inicial fue rechazada y sustituida en la corrección descrita a continuación.
8. **Tema oscuro** (2026-10-18): sustituida la paleta cálida rechazada por acentos fríos azul/teal y modo oscuro predeterminado, manteniendo preferencias explícitas.
9. **Primer intento de catálogo (fallido)** (2026-10-18): `https://ollama.com/api/tags` no es el catálogo completo de descarga; solo muestra una selección y no incluía Llama en la comprobación. No usar ese endpoint como catálogo público de modelos.
10. **Corrección del catálogo, filtros y variantes** (2026-10-18): `OllamaService` consulta la búsqueda oficial de Ollama `/search?c=local`, sigue páginas HTMX y lista los modelos locales publicados (241 observados en esta comprobación, incluyendo Llama y Dolphin). Los filtros ahora se aplican antes de crear la lista, con estados vacíos correctos; las variantes Dolphin y modelos cuyo nombre/descripción dice uncensored aparecen en «Menos censura», sin clasificar el Llama original como tal. Verificados `flutter test` (12), `flutter analyze` y `flutter build windows`.
11. **Documentos adjuntos por arrastrar y soltar** (2026-10-23): `ChatScreen` envuelve el cuerpo en `DropTarget` (desktop_drop) con superposición «Suelta para adjuntar»; `ChatInput` acepta imágenes y documentos, muestra su estado y los envía junto al texto. `DocumentService` extrae texto de PDF (`syncfusion_flutter_pdf` 30.2.7), XLSX/XLSM (ZIP + XML), CSV/TXT/MD/JSON/YAML/LOG (UTF-8/UTF-16). Límites: 25 MB por archivo, 8.000 caracteres por documento, 16.000 por mensaje; con documentos se amplía `num_ctx` a 8192. El texto se guarda en `Message.documents` y solo el último mensaje con documentos del historial aporta su texto completo. Verificados `flutter test` (19), `flutter analyze` y `flutter build windows`.
12. **Reintento correcto** (2026-10-23): el botón «Reintentar» ya no reenvía el texto del error como pregunta del usuario. `ChatServiceOllama.retryLastMessage()` elimina la respuesta fallida, reutiliza la última pregunta (con sus imágenes y documentos) y regenera sin duplicar el turno; el botón solo aparece en el último mensaje. Verificados `flutter test` (20), `flutter analyze` y `flutter build windows`.
13. **Indicador de modelos sin censura** (2026-10-23): `OllamaConfig.isUncensoredModel()` detecta variantes `uncensored`, `abliterated`, `abliterate` y `dolphin`; el selector de modelos muestra un candado abierto en el modelo activo y la etiqueta «Sin censura» en la lista. Añadida prueba de la detección (22 tests en total).
14. **Optimización, exactitud y ligereza** (2026-10-24):
    - Contexto: los mensajes de error ya no se envían a Ollama; `num_ctx` fijo en 8192 (cambiarlo obligaba a Ollama a recargar el modelo); temperatura 0.2 y prompt de anclaje cuando hay documentos; `think: false` para Qwen3/DeepSeek-R1.
    - Idioma: `detectLanguage` compara palabras completas con listas de palabras frecuentes (antes `contains` confundía «mission» con `mi` y «difference» con `ce`); solo se cambia el idioma con mensajes de 3+ palabras.
    - Documentos: recorte en el último salto de línea con marca de caracteres omitidos; fechas de Excel (números de serie) convertidas a `dd/mm/aaaa` leyendo `xl/styles.xml`.
    - Rendimiento: la pantalla ya no se reconstruye entera en cada token (`messagesVersion` + `Selector`); miniaturas con `Future` cacheado; historial guardado una vez por respuesta y codificado en un isolate; un solo sondeo de Ollama; imágenes con `cacheWidth`; `SelectionArea` en la lista en lugar de un `SelectableText` por burbuja.
    - UI: botón Detener, autoscroll respetuoso, Enter envía (Shift+Enter salta línea), «Archivo…» en el clip, visor de imágenes, consola con autoscroll y Limpiar, sin modelo duplicado en la barra.
    - Seguridad: cerrar la app ya no ejecuta `taskkill /F /IM ollama.exe`; solo detiene el proceso que inició LightChat. Al cerrar la ventana se descargan los modelos cargados (`/api/ps` + `/api/generate` con `keep_alive: 0`) para liberar VRAM sin apagar el servidor. Además hay una acción manual «Liberar GPU» en el menú ⋮ del chat y un botón en la barra de estado del gestor de Ollama, que avisan de cuántos modelos se liberaron. Verificado en vivo: 1 modelo cargado → 1 descargado → 0 en `/api/ps`.
    - Poda: 5 archivos muertos y 6 dependencias sin uso (~1,500 líneas menos). Verificados `flutter test` (37), `flutter analyze` y `flutter build windows`.

## 5. Lecciones y advertencias

- ⚠️ **No confiar en `MIGRATION_OLLAMA.md` sobre qué archivos existen** — lista archivos ya borrados. Contrasta con `ls lib/**` antes de editarlos.
- ⚠️ **`pubspec.yaml` description y README de `dist/`** pueden contradecir arquitectura vigente (restos vLLM/PyInstaller). Fuente de verdad: `MIGRATION_OLLAMA.md` + código actual en `lib/`.
- ⚠️ **Directorio `" lib"` con espacio** en la raíz: los globbings mal escritos pueden escribir ahí. Usa `lib/`.
- ⚠️ No restaurar el smoke test counter de Flutter; mantener la prueba de la pantalla real (`ChatScreen`).
- ⚠️ El selector de modelos debe refrescar `/api/tags` al reintentar; copiar solo la lista en memoria deja modelos nuevos o conexiones tardías invisibles.
- ⚠️ `https://ollama.com/api/tags` no enumera la biblioteca descargable: para el catálogo usar `/search` con paginación HTMX; validar la paginación con `HX-Request: true` porque sin ese encabezado el sitio devuelve siempre la primera página.
- ⚠️ `flutter analyze` tiene ~62 s de arranque; ejecutar `flutter pub get` primero en entornos limpios.
- ⚠️ **No usar el paquete `excel`**: exige `archive ^3.6.1` y `image` ya exige `archive ^4.0.7`. Syncfusion PDF debe quedarse en 30.x porque 31+ exige `xml 7` e `image` usa `xml ^6`.
- ⚠️ Los PDF escaneados no tienen texto seleccionable: `DocumentService` devuelve un error explícito. No hay OCR.
- ⚠️ Los Qwen3/Qwen3.5 razonan por defecto (`thinking`): desde 2026-10-24 se envía `think: false` a los modelos de esa familia (`OllamaConfig.isThinkingModel`), pero la app sigue sin leer `message.thinking`.
- ⚠️ No volver a poner `num_ctx` condicional (4096/8192): Ollama recarga el modelo al cambiar el contexto y se pierden varios segundos en cada cambio de mensaje con/sin documentos.
- ⚠️ `ContextService.detectLanguage` debe comparar palabras completas; con `contains` y palabras de 1–2 letras se detectaba español en frases inglesas.
- ⚠️ `OllamaService.instance` debe registrarse con `ChangeNotifierProvider.value`; con `create` el provider lo destruye al desmontar el árbol y la siguiente instancia de `ChatServiceOllama` falla al añadir su listener.
- ⚠️ Los elementos del menú ⋮ del chat llevan `Expanded`/`Flexible`: sin ellos el PopupMenu desborda en ventanas estrechas.

## 6. Cómo actualizar esta memoria

- Añade entradas nuevas en fecha ascendente dentro de *Historial de fases*.
- Al cerrar un pendiente: márcalo ✓ en *Pendientes* (no lo borres) durante 2 ciclos y luego elimínalo.
- Al rechazar o revertir una idea, anótala en *Lecciones* para no repetir el intento.
