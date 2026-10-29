# AGENTS.md

> Guía para agentes de IA y nuevos colaboradores que trabajen en **LightChat**.
> Última revisión: 2026-10-29. El estado persistente (deuda, decisiones, historial) vive en [`MEMORY.md`](MEMORY.md).

---

## 1. Overview (¿Qué es este proyecto?)

LightChat es una **aplicación de escritorio hecha en Flutter** con un chat ligero y privado para **LLMs locales ejecutados con [Ollama](https://ollama.com)**. Todo corre en la máquina del usuario (API de Ollama en `http://localhost:11434`): sin nube, sin cuentas, sin credenciales.

- **Stack:** Flutter 3.47.8 stable (Dart 3.13.7) · Dart SDK `>=3.0.0 <4.0.0` · estado con `provider` · HTTP con `http` (streaming) · archivos con `desktop_drop` + `file_selector` · Markdown con `flutter_markdown_plus`
- **Plataformas:** Windows (principal; ventana maximizada vía `window_manager`), macOS y Linux. `android/`, `ios/`, `web/` existen por plantilla, no son foco.
- **Idioma:** UI y documentación en español; identificadores de código en inglés.
- **Historia:** inició como herramienta de programación → chat con vLLM (feb-2026) → **migrado a Ollama el 2026-03-02** (commit `63d2175`). La migración está *terminada*; **no reintroducir vLLM ni LM Studio**.

## 2. Commands (Comandos de desarrollo)

Ejecutar siempre desde la raíz del repo (`lightchat/`):

```bash
flutter pub get        # dependencias (obligatorio en entorno limpio)
flutter analyze        # lints — línea base actual: 0 incidencias (~40 s)
flutter test           # 144 pruebas + 1 opt-in live (ver §7)
flutter run            # desarrollo con hot-restart
flutter build windows  # release Windows (también: macos | linux)
```

Para probar la app hace falta Ollama corriendo:

```bash
ollama serve                # servidor local en :11434
ollama pull llama3.2        # modelo recomendado para empezar
ollama list / ollama show   # inspección de modelos instalados
# Windows (instalador automático):
powershell -ExecutionPolicy Bypass -File installer/install_ollama.ps1
```

Empaquetado del instalador Windows: `build_installer.ps1` + `installer/lightchat_setup.iss` (Inno Setup).

## 3. Architecture (Arquitectura)

Capas: **`screens/ → services/ → API de Ollama`**, con modelos de datos en `models/` y UI reutilizable en `widgets/`. No hay backend propio ni servicios en la nube.

```
lib/
├── main.dart                    # entrada: MyApp (línea 34), MultiProvider, temas, ventana Windows
├── config/
│   └── vllm_config.dart         # clase OllamaConfig (¡config ACTIVA!) + typedef VllmConfig = OllamaConfig
├── models/                      # local_model, message, document_attachment, conversation
├── screens/
│   ├── chat_screen.dart         # pantalla principal de chat (home)
│   └── ollama_manager_screen.dart   # gestor de modelos/estado Ollama
├── services/                    # lógica de negocio y transporte HTTP
│   ├── ollama_service.dart          # cliente API Ollama (singleton .instance) ← servicio principal
│   ├── chat_service_ollama.dart     # orquestación del chat con streaming, parada, regenerar/editar y conversaciones
│   ├── conversation_service.dart    # índice y mensajes de cada conversación en SharedPreferences
│   ├── context_service.dart         # migración del historial antiguo + detección de 8 idiomas
│   ├── model_catalog_service.dart   # catálogo online de modelos (con caché)
│   ├── hardware_detector_service.dart # RAM/VRAM para recomendaciones (solo tests)
│   ├── document_service.dart        # texto de PDF/XLSX/XLS/DOCX/PPTX/HTML/XML/CSV/TSV/TXT
│   └── theme_service.dart           # tema claro/oscuro
└── widgets/                     # chat_input, message_bubble, assistant_markdown,
                                 # conversation_sidebar, document_text_dialog, model_*,
                                 # ollama_status_widget, capsule_icon, model_capability_icons…
```

**Flujo de datos (regla):** `Widget → Service (vía Provider) → HTTP a Ollama (streaming NDJSON) → estado → UI`.
Los widgets **no** hacen HTTP directo; los services **no** dibujan UI.

**Estado y providers registrados en `MyApp`** (main.dart): `ThemeService`, `ChatServiceOllama`, `OllamaService.instance`, `ModelCatalogService`. Patrón: singletons `XxxService.instance` + `ChangeNotifierProvider`.

## 4. Configuration & State (Dónde se guarda qué)

| Dónde | Qué contiene | Notas |
|---|---|---|
| `lib/config/vllm_config.dart` → `OllamaConfig` | `serverUrl` (`http://localhost:11434`, mutable), `defaultPort`, `timeoutSeconds` 120, `maxContextTokens` 16384 (fijo), `maxResponseTokens` 2048, `defaultTemperature` 0.7, `documentTemperature` 0.2, `preferredModels`, `multimodalModels` (`llava`…), `isUncensoredModel`, `isThinkingModel` | Aunque el archivo se llama `vllm_config`, es la config vigente de Ollama; el `typedef VllmConfig = OllamaConfig` mantiene compatibilidad de nombres. **No** volver a hacer `num_ctx` condicional: Ollama recarga el modelo. Los límites de `DocumentService` (16.000 por documento, 24.000 por mensaje) están calculados para 16.384 tokens: si se suben, subir también `maxContextTokens` |
| `SharedPreferences` (prefs del usuario) | claves reales en uso: `ollama_host`, `installed_models`, `model_catalog_cache`, `model_catalog_last_update`, `user_language`, `lightchat_conversations_v1` (índice), `lightchat_active_conversation_v1`, `lightchat_conversation_messages_v1_<id>`, `chat_messages` (historial antiguo, solo migración) | leídas/escritas desde `ollama_service`, `model_catalog_service`, `context_service`, `conversation_service`, `theme_service` |

## 5. Common tasks (¿Dónde tocar para cada tarea?)

| Tarea | Archivos principales |
|---|---|
| Cambiar modelo por defecto / modelos recomendados o multimodales | `lib/config/vllm_config.dart` (`preferredModels`, `multimodalModels`) |
| Cambiar URL o puerto de Ollama | `OllamaConfig.serverUrl` + clave `ollama_host` (aplicada en `ollama_service.dart`) |
| Añadir o modificar un endpoint de Ollama | `lib/services/ollama_service.dart` |
| UI del chat (burbujas, input, adjuntar imágenes) | `lib/screens/chat_screen.dart`, `lib/widgets/chat_input.dart`, `message_bubble.dart`, `image_*` |
| Documentos adjuntos (arrastrar y soltar, extracción PDF/XLSX/XLS/DOCX/PPTX/HTML/XML/CSV/TSV) | `lib/services/document_service.dart`, `lib/models/document_attachment.dart`, `lib/widgets/chat_input.dart`, `lib/screens/chat_screen.dart` (`DropTarget`) |
| Cómo se reparte el texto de los adjuntos entre archivos y hojas | `DocumentService._shareBudget` / `_documentSlices` / `_renderSheetTexts` (reparto igualitario con marcas `[Hoja recortada: N de M filas]`) |
| Ver el texto enviado de un documento / medidor de contexto | `lib/widgets/document_text_dialog.dart`, `ChatInput._buildContextMeter`, `DocumentService.contextCharsFor` + `isContextTruncated` |
| Respuestas en Markdown y bloques de código copiables | `lib/widgets/assistant_markdown.dart` (+ `flutter_markdown_plus` en `pubspec.yaml`) |
| Conversaciones guardadas (barra lateral, renombrar, borrar) | `lib/services/conversation_service.dart`, `lib/models/conversation.dart`, `lib/widgets/conversation_sidebar.dart`, `ChatServiceOllama` (`newConversation`, `selectConversation`, `deleteConversation`) |
| Regenerar / editar un mensaje | `ChatServiceOllama.regenerateLastResponse`, `editAndResend`, `lib/widgets/message_bubble.dart` (`onRegenerate`, `onEdit`) |
| Detección e indicador de modelos sin censura | `lib/config/vllm_config.dart` (`isUncensoredModel`), `lib/widgets/model_selector.dart` |
| Catálogo y descarga de modelos | `model_catalog_service.dart`, `screens/ollama_manager_screen.dart`, `widgets/model_download_card.dart` |
| Detección de idioma / historial / contexto | `lib/services/context_service.dart` (`detectLanguage`, 8 idiomas) |
| Tema claro/oscuro | `lib/services/theme_service.dart` |
| Indicador de conexión/estado | `lib/widgets/ollama_status_widget.dart` |
| Instalador y empaquetado Windows | `installer/`, `build_installer.ps1` |

## 6. Code conventions (Convenciones de código)

- **Lints:** `flutter_lints` por defecto en `analysis_options.yaml`. **Nunca** añadir `// ignore:` / `ignore_for_file` para ocultar un problema: corregir la causa.
- **Nombres:** clases `PascalCase`, archivos `snake_case.dart`, privados con prefijo `_`.
- **Estilo Dart:** `final` donde sea posible, comillas simples, **corchetes obligatorios en bloques `if`** (`curly_braces_in_flow_control_structures` activo), `@override` siempre (el lint lo exige y ya hay un caso pendiente en `OllamaService.dispose`).
- **Colores/opacidad:** usar `.withValues(alpha: …)`; **`.withOpacity()` está deprecado** y es el 90 % del ruido actual del analyzer (30+ avisos).
- **Fin de línea:** los archivos históricos usan CRLF (`\r\n`); conservar el fin de línea existente al editar.
- **Editar > crear:** los servicios existentes cubren las capacidades; no duplicar `ollama_service` ni `chat_service`.
- **Sobre legacy:** `Main.py`, `main.spec`, `create_icon.py` (PyInstaller, anterior a Flutter), `.aider.*` y el sintáctico `typedef VllmConfig` son restos de etapas previas. **No borrar sin plan aprobado**; ver `MEMORY.md`.

## 7. Testing & Verification (Pruebas y verificación mínima)

**Estado actual (2026-10-29):** 144 pruebas pasan y una prueba real de Ollama es opt-in: chat/streaming, cancelación/timeouts/fin/parciales, capacidades, fuentes y rutas legacy, borradores/reinicio/concurrencia, cálculo tabular, exportación, contexto, idioma, temas y UI. `test/widget_test.dart` prueba la pantalla real. La evidencia live actual se guarda fuera de Git en `.dart_tool/live-evidence-20261029`.

Checklist de verificación antes de dar un cambio por terminado:

1. `flutter pub get` (si es entorno limpio)
2. `flutter analyze` → **cero errores** (warnings/info: no aumentarlos; ideal: reducir)
3. `flutter test --no-pub` → deben pasar todos (hoy 144 + 1 live omitido por defecto); **cualquier test nuevo debe pasar**
4. Prueba manual con Ollama corriendo: `flutter run` → enviar un mensaje y ver streaming + comprobar el indicador de estado

Prioridad de cobertura futura (hoy 0 tests reales): lógica pura en `context_service`, parsing/caché de `model_catalog_service`, `hardware_detector_service`.

## 8. External services & dependencies (Servicios externos)

| Servicio | Uso | Endpoint | Notas |
|---|---|---|---|
| **Ollama** | inferencia local | `http://localhost:11434` | `GET /api/tags`, `POST /api/chat`, `POST /api/generate`, `POST /api/pull`, `DELETE /api/delete` |
| Catálogo online de modelos | lista de modelos a descargar | HTTP en `model_catalog_service.dart` | caché en prefs con expiración (`modelCacheExpiry`) |

Sin variables de entorno ni credenciales. La app funciona 100 % offline salvo el catálogo online y `ollama pull`.

## 9. Git conventions (Convenciones de git)

- Rama única: `master` (remoto `github.com/zerumen82/CHAT-IA`).
- Mensajes de commit en **español**, directos y en minúscula inicial, estilo histórico: `Migracion a Ollama: soporte multimodal, icono retrocapsula…`.
- **No** commitear artefactos (ver §10) ni hacer push/reset/destructivos sin indicación explícita.

## 10. Repository hygiene (Higiene y deuda conocida)

Ya existe deuda histórica (detalle en `MEMORY.md`); **no aumentarla**:

- `build/` y `dist/` están trackeados en git (~991 archivos) → nunca añadir artefactos nuevos; si se compila, revisar `git status` antes de commit.
- **Directorio fantasma `" lib/"` (espacio inicial)**: existe en la raíz y está vacío/no trackeado. Escribir siempre en `lib/`; nunca en `" lib"`.
- `.aider.*`, `.idea/`, `.dart_tool/` son locales → ignorar.
- `MIGRATION_OLLAMA.md` y la `description` de `pubspec.yaml` (aún dice "vLLM") están **desactualizados en detalles**; fuente de verdad del alcance actual = este archivo + código en `lib/`.

---

## Documentos relacionados

| Documento | Uso |
|---|---|
| [`MEMORY.md`](MEMORY.md) | estado del proyecto, pendientes priorizados, decisiones no deshacer, lecciones |
| [`README.md`](README.md) | guía de usuario/instalación |
| [`MIGRATION_OLLAMA.md`](MIGRATION_OLLAMA.md) | guía técnica de Ollama (2026-03-02; parte de "archivos obsoletos" ya no aplica) |
| `plans/` | planes históricos (feb-2026, era vLLM): contexto, no especificación vigente |

## 11. Contexto, almacén y archivos (2026-10-26)

- Configuración activa nueva: context_config.dart, document_config.dart y export_config.dart. OllamaConfig.maxContextTokens sigue como compatibilidad/default16k; el envío efectivo usa ContextProfileService (límite nativo, perfil persistente hasta32k, desconocido4k). No cambiar num_ctx por presencia de documentos.
- DocumentStoreService conserva texto completo acotado e índice de referencias en carpeta elegida por el usuario. DocumentContextService construye la selección con búsqueda léxica local; ContextSnapshotService guarda selección exacta fuera de preferencias. No volver a serializar extractedText/contextText grandes en SharedPreferences.
- ExportService y GeneratedFileService crean formatos auténticos (TXT/MD/PDF/DOCX y XLSX para herramientas). Widgets/file_actions y context_settings_dialog gestionan los selectores. Tool calls sólo datos estructurados; nunca ejecutar código del modelo ni aceptar rutas arbitrarias.
- XLSX/DOCX: declarar namespace por defecto con atributo xmlns explícito. namespaceUris con prefijo vacío generaba xmlns:= inválido tolerado por parser Dart pero rechazado por Office. Validar con lector independiente/apertura real.
- Limpiar/eliminar conversaciones también retira referencias/archivos locales exclusivos. Mantener guard de operación durante todos los awaits para impedir vaciar otra conversación. No borrar originales.
- Prueba real opt-in: flutter test --no-pub --dart-define=LIGHTCHAT_LIVE=true test/live_documents_test.dart; no ejecutar junto con build, por las recargas/IO de Ollama. Evidencia en .dart_tool/live-evidence-20261026.
- `ChatInput.contextRevision` recibe modelo, conversación y versión del historial desde el Selector. `didUpdateWidget` invalida/refresca la vista previa; `_previewVersion` impide publicar resultados antiguos. Mantener la regresión `test/chat_input_context_test.dart` al tocar el medidor.

## 12. Interacción y borradores (2026-10-29)

- ChatConfig configura conexión/inactividad del stream. Cada petición tiene su
  cliente cancelable; EOF sin done es interrupción. Conservar texto parcial y
  error por separado, finishReason y fases observadas. No inventar carga/porcentaje.
- ContextProfileService verifica capacidades de imágenes/herramientas con metadata.
  No deducir visión del nombre. Adjuntar activa documental en su evento de UI;
  preview/send respetan General o exclusiones elegidas después.
- sourceKey normaliza rutas Windows. Aplicar la misma identidad a fuentes, borrador,
  exclusiones y procedencia histórica; no reintroducir fuentes desmarcadas por
  diferencias de mayúsculas/separadores. No podar historial persistido automáticamente.
- DraftService guarda contenido completo en archivos por chat; prefs solo marcador
  con ubicación. Fallback local del SO cuando falta biblioteca, dirty/identidad,
  tombstones al borrar, clear al vaciar. Cierre hace flush antes y después de liberar
  GPU; mantener ventana si no pudo guardar. No mover/borrar originales adjuntos.
- Cálculo tabular usa DocumentService.readSpreadsheet y SpreadsheetAnalysisService
  en isolate, con decimales BigInt y exclusiones explícitas. Rechazar límites o
  lectura incompleta. BIFF8 no sirve para calcular con excel2003 porque oculta
  fórmulas como cachés; XLSX renombrado sí se reconoce. No ejecutar fórmulas/modelo.
- Suite actual: 144 PASS + 1 live opt-in; live real separado PASS. Evidencia de
  2026-10-29 en .dart_tool/live-evidence-20261029 y logs ui-improvements-*.

## 13. Escritura y avisos documentales (2026-10-29)

- En ChatInput, ignorar cambios de selección/composición que no cambian texto:
  no deben incrementar versión del borrador ni recalcular contexto.
- Durante preview pendiente conservar espacio del medidor/aviso de historial;
  no mostrar presupuestos legacy. Pausar preview durante streaming y refrescar
  con historial final. Mantener identidad/versionado y borradores al aceptar.
- En entrada y burbujas, el visor normal muestra texto extraído/conservado;
  selección enviada es la acción específica de contexto. Distinguir extracción
  parcial de vista previa acotada. Regresiones y evidencia en spec/09.
