# MEMORY.md — Memoria persistente de LightChat

> **Propósito:** memoria de largo plazo del proyecto para agentes de IA y colaboradores.
> Actualizar este archivo cada vez que cambien hechos relevantes (fases completadas, decisiones, deuda conocida, entorno). Guía de trabajo en [`AGENTS.md`](AGENTS.md).

**Última actualización:** 2026-10-29

---

## 1. Estado actual del proyecto

| Aspecto | Estado |
|---|---|
| Tipo | App de escritorio Flutter (chat con LLMs locales vía Ollama) |
| Ciclo | **Usable y en mantenimiento**; migración vLLM → Ollama completada 2026-03-02 |
| Rama | `master` (única), remoto `github.com/zerumen82/CHAT-IA`; cambios locales preexistentes y de la implementación actual, conservados sin commit ni push |
| Builds recientes | Último commit significativo: `63d2175` "Migración a Ollama: multimodal, icono retrocápsula, 8 idiomas, modelo preferido guardado" |
| Tamaño código | ~11,500 líneas Dart en `lib/` (26 archivos `.dart`) |
| `flutter analyze` | **Sin incidencias** |
| `flutter test` | **138 pruebas pasan + 1 live opt-in omitido en suite normal**; ejecución live separada PASS (2026-10-29) |
| Build Windows | `flutter build windows --no-pub` completado tras correcciones (2026-10-29, 71.7s) |
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
| **Dependencias acotadas** | `provider` para estado, `http` para streaming de Ollama, `shared_preferences` para preferencias, `file_selector`/`desktop_drop` para archivos, `syncfusion_flutter_pdf` + `archive` + `xml` para documentos, `flutter_markdown_plus` + `markdown` para las respuestas (`pubspec.yaml`) | Decidido en plan 2026-02-14; `dio`, `uuid`, `path_provider`, `image`, `flutter_animate` y `cupertino_icons` retirados el 2026-10-24 al no tener uso. |
| **Documentos: `desktop_drop` + Syncfusion PDF 35.x + parser Office propio** | `desktop_drop` recibe archivos del sistema; `syncfusion_flutter_pdf` 35.1.41 extrae texto; XLSX, DOCX y PPTX se leen con `archive` + `xml` (ZIP/Office Open XML); XLS (BIFF8) con `excel2003`; HTML con `html`; CSV/TSV con un separador de comillas propio | 2026-10-24: actualizado 30.2.7 → 35.1.41 con `xml` 7.1.0. La restricción a 30.x venía de `image` (exigía `xml ^6`); retirado `image`, ya no aplica. Las pruebas de PDF pasan con 35. 2026-10-25: añadido `excel2003` 1.0.0 (puro Dart, sin dependencias) para `.xls`; es solo lectura y las fechas de `.xls` salen como número de serie porque no resuelve formatos de celda. |
| **Dependencias al día (2026-10-24)** | Flutter 3.47.8 · `syncfusion_flutter_pdf` 35.1.41 · `xml` 7.1.0 · `window_manager` 0.5.2 (`screen_retriever` 0.2.2) · `archive` 4.5.2 · `http` 1.6.0 · `image_picker` 1.2.4 · `shared_preferences` 2.5.6 · `system_info2` 4.2.0 · `flutter_markdown_plus` 1.0.12 | Subidas con `flutter pub upgrade --major-versions`; no hubo cambios de código. `desktop_drop` se queda en 0.8.4: la 0.9.2 exige `cross_file ^0.4.0` y `file_selector` fija `cross_file` 0.3.x. |
| **Markdown con `flutter_markdown_plus`** | Sustituye a `flutter_markdown`, que está discontinuado; `markdown` se declara explícito para el builder de bloques de código | 2026-10-24: el renderizado se aplica solo a respuestas del asistente, nunca al texto que escribe el usuario. |
| **Una clave de `SharedPreferences` por conversación** | `lightchat_conversations_v1` (índice), `lightchat_active_conversation_v1`, `lightchat_conversation_messages_v1_<id>`; el historial antiguo (`chat_messages`) se migra a la primera conversación | 2026-10-24: guardar todo el historial junto obligaba a reescribir MB al cambiar de chat. El nombre visible se toma del primer mensaje del usuario salvo que se renombre. |
| **Singleton de servicios** | Patrón `XxxService.instance` registrado en `main.dart` con `provider` | Ya aplicado en `ollama_service.dart`; mantener consistencia. |
| **Planes en `plans/` (español)** | `YYYY-MM-DD_Nombre_Contexto.md` | Formato establecido 2026-02-14; es el "estilo de otros proyectos" del equipo: documento de resumen + documento de plan. |
| **Presupuesto de documentos repartido, no por orden** | 16.000 caracteres por documento, 24.000 por mensaje y 8.000 en el historial; el texto se reparte a partes iguales entre **todos** los archivos y entre **todas** las hojas del libro, con marcas `[Hoja recortada: N de M filas]` | 2026-10-25: antes se llenaba en orden y el segundo archivo (y las hojas 2, 3… de un Excel) desaparecían del contexto. Con `num_ctx` 16.384 cabe el triple de texto. |
| **Puerto Ollama 11434** | Configurable en la app si cambia `OLLAMA_HOST` | Estándar de Ollama. |
| **Cierre: liberar VRAM sin matar Ollama** | `setPreventClose` + `unloadLoadedModels()` (`keep_alive: 0`); `stopServer()` solo termina el proceso que inició LightChat | Matar `ollama.exe` afectaba a otras apps del usuario (corregido 2026-10-24). Nunca volver a `taskkill /F /IM ollama.exe`. |

## 3. Contexto de entorno (para no redescubrir)

- **Máquina:** Windows (Git Bash/MSYS), ruta real del proyecto `D:\PROJECTS\LITGHCHAT\lightchat`.
- **GPU:** NVIDIA RTX 3060 Ti, **8 GB VRAM** → mantener modelos en 7–8B Q4. Descargados el 2026-10-23: `qwen2.5:7b` (normal) y `huihui_ai/qwen2.5-abliterate:7b-instruct-q4_K_M` (sin censura), ~4,7 GB cada uno; ambos respondieron correctamente sobre texto tipo Excel.
- **Flutter 3.47.8 stable**, canal stable, **Dart 3.13.7** (actualizado el 2026-10-24 desde 3.41.7).
- **Análisis completo tarda ~40 s** (`flutter analyze`) — preveerlo al verificar cambios.
- Flutter 3.47 añadió solo, al hacer `pub get`, un bloque `analyzer.exclude` en `analysis_options.yaml` para `build/` y los directorios de plataforma; se conserva.
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
15. **Archivos, Markdown y conversaciones** (2026-10-24):
    - Documentos: `DocumentService` añade DOCX (párrafos + tablas), PPTX (diapositivas en orden), HTML (sin scripts ni estilos), XML (texto de elementos con entidades) y TSV; CSV/TSV se presentan como `Fila N: a | b` igual que un XLSX. Nuevo `DocumentKind.presentation`. Mensaje de formatos centralizado en `DocumentService.supportedFormatsLabel`.
    - Transparencia: `showDocumentTextDialog` abre el texto exacto enviado al modelo desde el chip de `ChatInput` y desde los documentos de la burbuja (también si hubo error o recorte).
    - Contexto: barra en la entrada con los caracteres que ocuparán los documentos sobre los 16.000 disponibles (`DocumentService.contextCharsFor`), en rojo cuando el último se recortará.
    - UI: respuestas del asistente en Markdown (negritas, listas, tablas, encabezados) con bloques de código que muestran el lenguaje y botón «Copiar código»; «Regenerar» en la última respuesta; «Editar y reenviar» en un mensaje del usuario (descarta los turnos posteriores y conserva sus adjuntos).
    - Conversaciones: barra lateral con crear, abrir, renombrar y eliminar; título automático del primer mensaje; guardado por conversación con debounce e índice propio. Se oculta por debajo de 720 px de ancho (decidido con `LayoutBuilder`, no `MediaQuery`).
    - Correcciones encontradas al probar: `XFile.name` devolvía «carpeta/notas.txt» en rutas con separadores mezclados (ahora el nombre sale del `path`); la tarjeta «Ollama no detectado» usaba un `Row` con dos botones y desbordaba en ventanas estrechas (ahora `Wrap`).
    - Verificados `flutter test` (58), `flutter analyze` y `flutter build windows`.
16. **Flutter y dependencias al día** (2026-10-24): Flutter 3.41.7 → **3.47.8** (Dart 3.13.7) y `flutter pub upgrade --major-versions`: Syncfusion PDF 30.2.7 → 35.1.41, `xml` 6.6.1 → 7.1.0, `window_manager` 0.3.9 → 0.5.2, más 33 dependencias menores. Sin cambios de código. Verificados `flutter analyze`, `flutter test` (58) y `flutter build windows`; la app arranca y renderiza con Impeller. `desktop_drop` 0.9.2 no resuelve por `cross_file` 0.3.x de `file_selector`, se queda en 0.8.4.
17. **Excel completo y `.xls` de verdad** (2026-10-25): dos fallos reportados, con una sola causa de fondo.
    - Síntoma: «no coge todos los Excel» y «pregunto cosas y responde repetido». Reproducido con un libro de 3 hojas: el texto completo eran 26.532 caracteres y al modelo solo llegaban 7.953; **las hojas 2 y 3 desaparecían** y el modelo respondía «el documento solo contiene datos de febrero», repitiendo las mismas cifras de la única hoja que veía. Con varios adjuntos, el segundo y el tercero se quedaban sin texto porque el presupuesto se gastaba en orden.
    - Reparto justo: `DocumentService._shareBudget` reparte el presupuesto a partes iguales entre documentos y devuelve el sobrante de los que no lo necesitan; `_renderSheetTexts` hace lo mismo entre todas las hojas del libro y añade `[Hoja recortada: se muestran N de M filas]`. Un documento con menos de 200 caracteres posibles (`minCharsPerDocument`) queda fuera y se avisa con `[documento(s) omitido(s)]`.
    - Límites: 8.000 → **16.000** por documento, 16.000 → **24.000** por mensaje, 4.000 → **8.000** en el historial, y `num_ctx` 8.192 → **16.384**. Medido en la RTX 3060 Ti: el modelo carga con 5,47 GB en VRAM a 16.384 de contexto, entra en los 8 GB.
    - `.xls` (Excel 97-2003): nuevo `excel2003` 1.0.0 (puro Dart, sin dependencias) lee BIFF8. Si un `.xls` es en realidad un `.xlsx` renombrado (magic bytes `PK`) se lee con el lector XLSX. Limitación conocida: las fechas de `.xls` llegan como número de serie, porque el paquete no resuelve formatos de celda.
    - Medidor de contexto: `contextCharsFor` cuenta también las cabeceras `--- Documento N ---`; nueva `isContextTruncated` y aviso «Contexto lleno: el modelo solo verá parte del texto» (antes dependía de llenar los 16.000 exactos y casi nunca saltaba).
    - Prueba real: `test/fixtures/ventas_ligero.xls`, generado con `xlwt` (BIFF8 auténtico), verifica dos hojas, acentos, números y booleanos. Añadidas pruebas de `.xls` renombrado, de las tres hojas visibles con marcas de recorte y del reparto entre varios archivos. Verificados `flutter test` (62), `flutter analyze` y `flutter build windows`.
    - Verificado en vivo con Ollama (`qwen2.5:7b`, contexto 16k): con el libro de 3 hojas el modelo recibió las tres y respondió «recibo todas las filas, de la 1 a la 80… sí, la hoja Marzo está presente», en 8 s. Las dos pruebas anteriores que expiraron a 4 y 8 min no eran lentitud del modelo: coincidían con un `flutter build windows` en paralelo y con un cambio de `num_ctx` (8192 ↔ 16384) que obliga a Ollama a reiniciar `llama-server` (116 s de carga con el disco ocupado).

## 5. Lecciones y advertencias

- ⚠️ **No confiar en `MIGRATION_OLLAMA.md` sobre qué archivos existen** — lista archivos ya borrados. Contrasta con `ls lib/**` antes de editarlos.
- ⚠️ **`pubspec.yaml` description y README de `dist/`** pueden contradecir arquitectura vigente (restos vLLM/PyInstaller). Fuente de verdad: `MIGRATION_OLLAMA.md` + código actual en `lib/`.
- ⚠️ **Directorio `" lib"` con espacio** en la raíz: los globbings mal escritos pueden escribir ahí. Usa `lib/`.
- ⚠️ No restaurar el smoke test counter de Flutter; mantener la prueba de la pantalla real (`ChatScreen`).
- ⚠️ El selector de modelos debe refrescar `/api/tags` al reintentar; copiar solo la lista en memoria deja modelos nuevos o conexiones tardías invisibles.
- ⚠️ `https://ollama.com/api/tags` no enumera la biblioteca descargable: para el catálogo usar `/search` con paginación HTMX; validar la paginación con `HX-Request: true` porque sin ese encabezado el sitio devuelve siempre la primera página.
- ⚠️ `flutter analyze` tiene ~62 s de arranque; ejecutar `flutter pub get` primero en entornos limpios.
- ⚠️ No hace falta el paquete `excel`: XLSX se lee con `archive` + `xml`. La vieja incompatibilidad de Syncfusion ≥31 (`xml 7` contra `image` con `xml ^6`) desapareció al retirar `image`; hoy Syncfusion 35.1.41 y `xml` 7.1.0 conviven.
- ⚠️ No volver a repartir el texto de documentos «en orden»: el que llega primero se come el presupuesto y los demás desaparecen sin aviso. Documentos → a partes iguales; hojas de un libro → a partes iguales; y siempre con marca de recorte.
- ⚠️ Cambiar `num_ctx` respecto al runner ya cargado obliga a Ollama a **reiniciar `llama-server` y recargar el modelo del disco** (116 s medidos en esta máquina con I/O en paralelo, 10-15 s en reposo). Si una prueba o la app mandan contextos distintos, se paga esa recarga cada vez; medir siempre con el mismo `num_ctx` y sin compilaciones en paralelo.
- ⚠️ Los límites de caracteres y `num_ctx` van juntos: subir `maxCharsPerDocument`/`maxTotalChars` sin subir `OllamaConfig.maxContextTokens` hace que Ollama recorte el principio del prompt (incluido el prompt de sistema).
- ⚠️ `excel2003` devuelve el valor crudo de la celda: una fecha de `.xls` es un número de serie (`45321`), no `30/01/2024`. Convertirla exigiría leer los registros XF/FORMAT, que el paquete no expone.
- ⚠️ Un `.xls` puede ser en realidad un `.xlsx` renombrado: comprobar los dos primeros bytes (`PK`) antes de elegir el lector; es habitual en exportaciones de terceros.
- ⚠️ Los PDF escaneados no tienen texto seleccionable: `DocumentService` devuelve un error explícito. No hay OCR.
- ⚠️ Los Qwen3/Qwen3.5 razonan por defecto (`thinking`): desde 2026-10-24 se envía `think: false` a los modelos de esa familia (`OllamaConfig.isThinkingModel`), pero la app sigue sin leer `message.thinking`.
- ⚠️ No volver a poner `num_ctx` condicional (4096/8192): Ollama recarga el modelo al cambiar el contexto y se pierden varios segundos en cada cambio de mensaje con/sin documentos.
- ⚠️ `ContextService.detectLanguage` debe comparar palabras completas; con `contains` y palabras de 1–2 letras se detectaba español en frases inglesas.
- ⚠️ `OllamaService.instance` debe registrarse con `ChangeNotifierProvider.value`; con `create` el provider lo destruye al desmontar el árbol y la siguiente instancia de `ChatServiceOllama` falla al añadir su listener.
- ⚠️ Los elementos del menú ⋮ del chat llevan `Expanded`/`Flexible`: sin ellos el PopupMenu desborda en ventanas estrechas.
- ⚠️ Para decisiones de layout responsivo usar `LayoutBuilder`/constraints, no `MediaQuery.size`: en `flutter_test` tras `setSurfaceSize` la `MediaQuery` puede seguir reportando el tamaño anterior y la barra lateral se renderizaba con 280 px en una ventana de 480.
- ⚠️ `XFile.name` no es fiable con rutas que mezclan `\` y `/` (por ejemplo, rutas temporales): calcular el nombre visible desde `XFile.path`.
- ⚠️ Los tests de widgets que leen archivos reales deben envolver la E/S en `tester.runAsync`; dentro de `testWidgets` las rutas de `dart:io` creadas fuera de `runAsync` no completan.
- ⚠️ En `flutter_markdown_plus`, el builder de bloques de código se registra con la clave `pre` y hay que leer `element.children.first` (`code`) para obtener el lenguaje; `isBlockElement()` debe devolver `true`.
- ⚠️ `flutter upgrade` puede fallar en el paso de precache con «icudtl.dat is being used by another program» si queda un `flutter_tester.exe` vivo de una suite de tests. Cerrarlo (`taskkill /F /IM flutter_tester.exe`) y completar con `flutter precache --windows`; la actualización del SDK sí se aplica.

## 6. Cómo actualizar esta memoria

- Añade entradas nuevas en fecha ascendente dentro de *Historial de fases*.
- Al cerrar un pendiente: márcalo ✓ en *Pendientes* (no lo borres) durante 2 ciclos y luego elimínalo.
- Al rechazar o revertir una idea, anótala en *Lecciones* para no repetir el intento.


## 7. Contexto documental, exportación y generación local — 2026-10-26

- El usuario aprobó el plan de spec/05 y añadió creación de archivos solicitados en lenguaje natural. Confirmó XLSX (no XLS antiguo) y PDF; las exportaciones de respuesta/conversación son TXT, Markdown, PDF y DOCX. Ninguna dependencia, modelo ni skill instalada.
- Se creó spec/00 a 04 antes de implementar, con requisitos en spec/02 y diseño/plan en spec/05. La bitácora provisional spec/06 se puede integrar ahora: al principio MEMORY.md y plans/ rechazaban escritura, después el entorno habilitó acceso. Se conservaron todos los cambios y borrados preexistentes del usuario.
- Contexto: ContextProfileService consulta showModel existente, persiste perfil por modelo, limita por contexto nativo y mantiene num_ctx estable entre mensajes. Por defecto16k o límite inferior, máximo configurable32k, desconocido4k conservador. Presupuesto conjunto sistema/pregunta/historial/documentos/respuesta con estimación identificada y métricas reales prompt_eval_count.
- Documentos: extracción en isolate con límites configurados de tamaño, expansiónZIP/entradas, filas/columnas y texto; conserva hasta2M caracteres fuera de preferencias. Almacén local elegido explícitamente, índice de referencias por conversación, previews pequeños y migración compatible. Recuperación léxica de fragmentos al principio/medio/final con referencias; los documentos no desaparecen al salir de los últimos10mensajes. Cobertura parcial explícita: no garantiza totales globales. Sin OCR.
- Transparencia: medidor y envío usan mismo planificador; Ver contexto enviado muestra la selección exacta, cuyos snapshots viven en .lightchat-contexts fuera del JSON de mensajes. Visor documental distingue texto extraído/conservado. Avisos de recorte previo, presupuesto y columnas omitidas.
- Exportación: ExportService genera TXT/MD/PDF/DOCX reales y XLSX para herramienta local. PDF paginado con fuenteUnicode local validada; DOCX y XLSX OOXML con archive/xml existentes. Generación de TXT/MD/DOCX/XLSX fuera UI en isolate. Herramientas create_pdf/create_spreadsheet reciben datos estructurados, no ejecutan scripts/fórmulas ni rutas del modelo. Archivos asociados al mensaje y guardables con selector nativo.
- Persistencia/seguridad: contenido grande/snapshots fuera de SharedPreferences; cambio de raíz bloqueado si biblioteca no vacía, configuración transaccional; enlaces/junctions y rutas fuera del almacén rechazados incluyendo temporales. Almacén inaccesible no impide abrir conversaciones. Limpiar/eliminar retira fuentes y archivos exclusivos, sin originales, y bloquea envíos/cambios durante operación; persistencia esperada antes éxito.
- Hallazgo real NO OCULTAR: las primeras9pruebas de formatos y el reader Dart aceptaron XML inválido con xmlns:= producido por namespaceUris de prefijo vacío. Excel14 y Word14 reales lo rechazaron. Corregido usando xmlns explícito para namespace por defecto; tests reforzados y Python ElementTree independiente. El tester reabrió XLSX/DOCX corregidos con OfficeCOM read-only: PASS; Excel confirmó números/booleanos y HasFormula=false para texto parecido a fórmula. No confiar sólo en el parser propio para validar Office.
- Review inicial CHANGES_REQUESTED por selector en mensajes normales, cambio de raíz, inicio bloqueado por almacén, duplicación de contexto, limpieza de fuentes y temporales. Todo corregido; revisión adicional de concurrencia resuelta con _mutateConversation. Veredicto final reviewer: APPROVE del código.
- Validación parcial a este momento: flutter analyze --no-pub sin incidencias; flutter test --no-pub98PASS+1opt-inomitido; tras añadir casos nativos2k/8k y bloqueo de limpieza,17focalizadasPASS. Primera prueba Ollama real22s: XLSX1816B y PDF62837B generados porQwen2.5, recuperación de código despuésdelcarácter16000 y original eliminado. Consulta32k15.187s,prompt_eval_count14671; /api/ps context_length32768,size_vram6255678586; ollama ps9%CPU/91%GPU. Está en curso repetición live tras correcciónOffice y build/UI final: aún no declarar listo.
- Evidencia reproducible: test/live_documents_test.dart opt-in con --dart-define=LIGHTCHAT_LIVE=true; resultados y documentos en .dart_tool/live-evidence-20261026 (ignorados porGit). Preferencias del ensayo aisladas; inferencia, almacenamiento y generadores de producción reales.

## 8. Continuación y cierre de validación — 2026-10-26

- Petición del usuario: «continua». Retomado el alcance ya aprobado de spec/05, leyendo reglas globales/locales, memoria, SDD y evidencias existentes. No se han instalado paquetes, modelos ni skills; no se ha hecho commit/push ni revertido cambios preexistentes.
- La sesión anterior sí dejó evidencia final posterior a la corrección OOXML: `.dart_tool/live-evidence-20261026/evidence.json` (09:13) y UI real (09:18–09:21). Se revisó y reutilizó esa ejecución, sin repetir inferencia a la vez que la compilación. XLSX final 1812 bytes con Café/Té, 3/2 y 12.5/8; PDF final 84641 bytes con informe y tabla. Consulta tras borrar el original y reabrir conversación: código ZAFIRO-72841 recuperado; 32k confirmado en `/api/ps`, `context_length=32768`, `size_vram=6255678586`, `prompt_eval_count=14671`, 136670 ms incluyendo recarga. La ejecución previa más rápida no se presenta como tiempo garantizado. El código fue recuperado; la referencia textual del modelo puede ser inexacta y debe contrastarse con la selección enviada.
- Tester independiente reabrió XLSX/DOCX finales con Excel14 y Word14 COM read-only: PASS. Python ElementTree verificó XML/relaciones de los cuatro archivos OOXML: PASS. Texto con apariencia de fórmula siguió literal (`HasFormula=false`), números y booleanos conservaron su tipo. Logs `.dart_tool/final-formats-20261026.json` y `final-office-20261026.json`.
- Lector PDF independiente nativo `Windows.Data.Pdf`: PASS, 1 página, render 793×1123 y PNG 24679 bytes; título, tabla, Café/Té y cifras legibles. Evidencia `.dart_tool/final-pdf-native-20261026.json` y `.png`. No se instaló ningún lector.
- Reviewer independiente: CHANGES_REQUESTED por vista previa que no cambiaba al seleccionar otro modelo/conversación o actualizar historial; el envío sí recalculaba, de modo que el medidor podía mostrar un presupuesto antiguo. Aplicada skill fix local. Corrección mínima en `chat_input.dart`/`chat_screen.dart`: revisión con modelo/conversación/versión del historial, `didUpdateWidget`, invalidación inmediata y descarte de resultados anteriores por versión. El borrador se conserva.
- Regresión `test/chat_input_context_test.dart`: 3 casos (modelo, conversación, historial), cada uno con un cálculo antiguo que termina después del nuevo. Ensayo controlado sin `didUpdateWidget`: 3 FAIL reales (no se dispara el tercer cálculo); restauración exacta de bytes con finally; con corrección 3 PASS. Evidencia `.dart_tool/preview-regression-red-20261026.log` y `preview-regression-green-20261026.log`. Los primeros intentos de la prueba fallaron por el arnés asíncrono: una aserción dentro del callback era capturada por la UI y faltaba un pump para completar Future/rebuild; se sacó la aserción del callback y se esperó el ciclo correcto. No se ocultaron errores de producción.
- `test/file_widgets_test.dart` añade tres casos con selector controlado sólo en pruebas y E/S real: guardado TXT UTF-8 en ruta temporal con espacios/tildes; cancelación sin archivo ni éxito; destino que es directorio causa error visible y nunca éxito. El flujo debe iniciarse dentro de `tester.runAsync`, pues iniciar la exportación en la zona fake deja pendiente la E/S; primer intento detenido y corregido. Archivo completo: 6 PASS (`.dart_tool/file-save-regression-20261026.log`).
- Re-review independiente: APPROVE, sin bloqueantes/importantes. Valida invalidación, descarte de callbacks antiguos, borrador conservado y pruebas de escritura/error/cancelación.
- Comprobaciones definitivas tras la corrección: `flutter analyze --no-pub` → `No issues found! (ran in 13.9s)`, exit0; `flutter test --no-pub --reporter expanded` → `+106 ~1: All tests passed!`, 12s, exit0. El omitido es el ensayo Ollama opt-in cuya ejecución real ya está acreditada arriba. Logs `.dart_tool/final-analyze-20261026.log` y `final-tests-20261026.log`.
- Primera compilación de esta continuación, antes del arreglo UI: `flutter build windows --no-pub` → PASS, 109.3s. La recompilación posterior al arreglo y la exportación desde UI nativa están en curso; esta entrada todavía no declara cierre ni tester PASS final.
- Actualizado SDD para distinguir diagnóstico histórico de arquitectura implementada, decisiones aprobadas y limitaciones conservadas. La búsqueda de fragmentos no garantiza totales globales; OCR, fechas XLS BIFF8 y recuperación de mensajes podados siguen fuera del alcance. La biblioteca no se traslada automáticamente si contiene archivos.

### Cierre definitivo de esta continuación

- `flutter build windows --no-pub` tras el arreglo del medidor → exit0, `Building Windows application... 73,8s`, `√ Built build\windows\x64\runner\Release\lightchat.exe`. Log `.dart_tool/final-build-20261026.log`.
- Último recorrido Windows nativo: Opciones de conversación → Exportar → Texto (.txt) → Guardar; ruta `.dart_tool/evidencia UI con espacios/conversacion-final-20261026.txt`, 4507 bytes, UTF-8 legible y roles Usuario/Asistente presentes; selector cerrado. Evidencia `.dart_tool/final-ui-export-20261026.json`. La primera lectura a 700ms coincidió con bloqueo de escritura; la comprobación posterior a la escritura terminó correctamente. No se enviaron/editaron mensajes ni se cambió configuración personal. LightChat queda abierto con el build final, PID16696.
- Veredicto final del tester independiente: **PASS** para GEN-01, DOC-01, DOC-02, EXP-01 y guardado/cancelación/error; sin hallazgos pendientes. Reviewer independiente: **APPROVE** tras la corrección. Lint limpio + 106 pruebas PASS (1 live opt-in omitido en suite ordinaria, con evidencia live real de esta fecha) + build Windows PASS + formatos abiertos por lectores reales + guardado UI PASS.
- Límites de la evidencia, sin ocultarlos: el ensayo utilizó perfil32k con 14671 tokens de prompt, no un prompt lleno de32768; el fallo de escritura se provocó con selector controlado en pruebas y E/S real, no desde el diálogo nativo. Guardado y cancelación sí se ejercitaron nativamente. No se afirma exactitud de los totales con cobertura documental parcial ni rendimiento igual en otros modelos.
- SDD `02`, `04`, `05` cerrados con estados y resultados finales; `01` refleja arquitectura vigente; `03` conserva deuda/límites e identifica diagnóstico histórico; `06` marcado como registro histórico ya integrado. AGENTS/README actualizados. Alcance aprobado terminado; ninguna instalación, commit, push ni limpieza de artefactos preexistentes.

## 9. Mejoras de UI e interacción — 2026-10-29 (cerrado)

- El usuario pidió revisión general y aprobó las ocho propuestas con «hazlo».
  Confirmó consulta documental automática al adjuntar con control para volver a
  chat general, y cálculo de tablas mediante panel de archivo/hojas/columnas.
  Alcance/criterios en spec/07; plan reviewer APPROVE antes del código candidato.
- La primera parte de la sesión encontró permisos efectivos denegados en lib y
  MEMORY.md y ejecución del analizador bloqueada. Se preparó un candidato en
  TEMP, revisado estáticamente, sin tocar permisos ni instalar. Tras habilitar
  el usuario acceso sin restricciones y pedir «sigue», git apply --check y hashes
  originales coincidieron; se aplicaron los cambios conservando los anteriores.
- Implementados parciales/fin/cancelación/fases, capacidades reales de modelos,
  modo documental y fuentes seleccionables, historial parcial visible sin nueva
  poda automática, borradores por chat fuera de preferencias, navegación estrecha
  con búsqueda y ancho de lectura, y cálculo tabular local decimal exacto.
- Cálculo acepta XLSX/XLSM/CSV/TSV completos y rechaza límites, excluyendo fórmulas
  (también matrices/rangos cacheados), errores y valores no numéricos con recuento.
  XLS BIFF8 requiere guardar como XLSX/CSV para calcular: excel2003 1.0.0 oculta
  la procedencia fórmula de sus valores cacheados. La lectura documental XLS se
  conserva. Sin OCR ni instalación de dependencias/modelos/skills.
- Reviewer independiente APPROVE estático del original aplicado, incluyendo
  fuentes, dirty/version en guardado, tombstones y cierre con doble flush.
  El primer analyze ejecutable detectó un error nullable de _fallbackRoot por
  la versión de lenguaje Dart del paquete; corregido con variable local.
  Suite, analyze final, build y prueba real todavía pendientes: no declarar listo.
- Bitácora detallada del bloqueo y preparación en spec/07. Parche/manifest de
  aquella preparación en spec/08; describen el candidato previo, no sustituyen
  los cambios de corrección/validación posteriores del proyecto original.

### Verificación ejecutada tras habilitar el entorno

- Primera suite ejecutada detectó fallos de arnés (tooltip sin pump, E/S de
  MyApp iniciada dentro del reloj fake, sondeo singleton y buffering NDJSON del
  servidor de pruebas) y duplicación real de fuentes. Corregidos sin debilitar
  aserciones: runAsync en inicialización/desmontaje que inicia disco,
  healthcheck fuera FakeAsync y bufferOutput=false para entregar eventos reales.
  Las primeras ejecuciones con pruebas bloqueadas se detuvieron para corregir.
- Fuente única por path normalizado Windows y última versión visible. El reviewer
  encontró que las rutas legacy podían reintroducir respuestas de una fuente
  desmarcada; corregidas exclusiones cargadas/setters, metadata nueva y lectura de
  metadata antigua. Regresión Windows con diferencias de mayúsculas/separadores
  y IDs antiguos PASS. Reviewer final APPROVE, sin bloqueantes identificados.
- flutter analyze --no-pub: No issues found!, 5.3s, exit0. Suite completa final:
  +138 ~1 All tests passed!, 24s, exit0. Logs en .dart_tool con prefijo
  ui-improvements-analyze-final/tests-final-20261029. El omitido es live opt-in,
  ejecutado aparte con inferencia real; no se presenta como prueba no realizada.
- Live Ollama con qwen2.5:7b PASS, 48s: XLSX1812B y PDF84646B auténticos;
  tabla completa del XLSX calculada localmente, 2 filas/2 valores, total20.5.
  Recuperó ZAFIRO-72841 tras borrar original y reabrir; perfil32768 confirmado
  /api/ps, 14671tokens prompt y6255678586B VRAM. La cita de fila del modelo sigue
  pudiendo ser inexacta; no se certifica por esa respuesta. Consulta General
  posterior recibió0caracteres documentales y respondió4, finishReason completed.
  Metadata real conocida tools=true/vision=false y bloqueo de imágenes verificado.
  Evidencia .dart_tool/live-evidence-20261029/evidence.json y log live de esta fecha.
- flutter build windows --no-pub: exit0, 71.7s. El runner lightchat.exe puede
  conservar timestamp antiguo si C++ no cambia; el bundle Dart data/app.so es el
  recién compilado. No se ejecutó inferencia al mismo tiempo que build.
- git diff --check con cr-at-eol reconoce CRLF histórico y pasa. La primera
  comprobación sin esa opción señaló CR como whitespace; no se normalizaron
  archivos históricos para ocultar avisos. Sin instalaciones, commit ni push.
- Tester independiente está verificando la UI Windows nativa del build final;
  pendiente su veredicto y evidencia antes de cerrar el alcance.

### Cierre y evidencia nativa

- Tester independiente: **PASS**. El panel nativo leyó CSV propio mediante
  selector Windows, procesó4filas/4valores sin exclusiones y calculó10.3,
  Café0.3/Té10. Exportación TXT desde selector nativo:308B UTF-8 con cifras y tildes.
- Adjuntar context-ui.txt activó Consultar documentos; Fuentes lo mostró activo.
  Al desmarcar y elegir General, el medidor quedó en0caracteres. Borradores A/B
  conservaron textos distintos; volver a A y reiniciar la app restauró texto y
  adjunto. Ventana680x820: drawer, búsqueda y chat sin overflow.
- Evidencia: .dart_tool/ui-improvements-20261029/tester-result.json,
  calculation-result.png, calculo-ui.txt, draft-evidence.json,
  draft-after-native-restart.png, narrow-drawer-filtered.png y narrow-chat.png.
  Las capturas iniciales con escalado DPI incorrecto eran fallo del arnés y no
  se usan como evidencia visual final; el helper se hizo DPI-aware.
- LightChat final queda abierto, PID12824, usando el bundle Release comprobado.
  Modelo y conversación originales restaurados mediante UI (restoration.json
  true/true); no se editaron mensajes personales. Quedan dos chats propios de
  verificación con sus borradores, identificados en la evidencia.
- Reviewer independiente: **APPROVE**. Analyze limpio,138pruebas verdes + live
  real separado PASS, build Windows PASS y tester nativo PASS: alcance aprobado
  cerrado. SDD/README/AGENTS actualizados. Sin instalaciones, commit ni push.
- Límites de la evidencia: no se cortó el servidor Ollama desde UI ni se hizo
  inferencia visual nativa; corte/cancelación se probaron con sockets HTTP reales
  en la suite y visión se validó con metadata real/bloqueo de incompatibles.
  Perfil32k verificado con14671tokens de prompt, no lleno; las citas del modelo
  pueden equivocarse. XLS BIFF8 requiere XLSX/CSV para cálculo; no hay OCR.

## Bitácora de cambios — 2026-10-29 (UI profesional)

- **Tablas ocultas de la UI:** eliminados el chip "Calcular tabla" (estado vacío), la entrada del menú "Más opciones" y el diálogo de selección de hojas/columnas/filas (SpreadsheetAnalysisDialog). El cálculo tabular permanece intacto "por debajo" (SpreadsheetAnalysisService + pruebas spreadsheet_analysis_test.dart) sin que el usuario gestione tablas.
- **Consola de depuración removida:** eliminado botón del appBar y panel flotante CONSOLA OLLAMA que exponía logs técnicos.
- **Tema más sobrio:** semilla indigo profundo ( xFF3730A3), contraste 0.1, eliminado segundo acento teal.
- **Burbujas más limpias:** borde primario agresivo eliminado, sombra suave (lurRadius 8, alpha 0.04).
- **Estado vacío simplificado:** chips de acción removidos; bienvenida centrada.
- **Sidebar de conversaciones modernizada:** CircleAvatar con inicial, fondo activo sutil y borde indicador.
- **Verificación:** lutter analyze No issues found; lutter test 138 PASS; lutter build windows lightchat.exe construido (102 s). Sin instalaciones, commit ni push.

