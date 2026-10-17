# MEMORY.md — Memoria persistente de LightChat

> **Propósito:** memoria de largo plazo del proyecto para agentes de IA y colaboradores.
> Actualizar este archivo cada vez que cambien hechos relevantes (fases completadas, decisiones, deuda conocida, entorno). Guía de trabajo en [`AGENTS.md`](AGENTS.md).

**Última actualización:** 2026-10-17

---

## 1. Estado actual del proyecto

| Aspecto | Estado |
|---|---|
| Tipo | App de escritorio Flutter (chat con LLMs locales vía Ollama) |
| Ciclo | **Usable y en mantenimiento**; migración vLLM → Ollama completada 2026-03-02 |
| Rama | `master` (única), remoto `github.com/zerumen82/CHAT-IA`, **árbol limpio** al momento de revisar |
| Builds recientes | Último commit significativo: `63d2175` "Migración a Ollama: multimodal, icono retrocápsula, 8 idiomas, modelo preferido guardado" |
| Tamaño código | ~8,780 líneas Dart en `lib/` (25 archivos `.dart`) |
| `flutter analyze` | **0 errores** · 8 warnings · 37 info (45 issues) — ruido mayoritariamente deprecado `withOpacity` |
| `flutter test` | ❌ **Fallan**: el único test es el counter smoke test por defecto, obsoleto |
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

1. ~~Reemplazar `test/widget_test.dart`~~ ✓ pendiente de reemplazo por test real de pantalla de chat (pendiente histórico).
2. ~~Unificar migración en docs~~ — `pubspec.yaml` aún describe *"chat interface for vLLM"* (real: Ollama); `MIGRATION_OLLAMA.md` lista archivos "obsletos mantenidos" que ya no existen en disco.
3. ~~Limpiar 8 warnings + 37 info del analyzer~~ — migrar `withOpacity()` → `withValues(alpha:)`, campos sin usar, `@override` faltante, `if` sin llaves. (Reducido de 45 a 10 issues, todos preexistentes).
4. ~~Eliminar directorio fantasma `" lib/"~~ (verificación hecha).
5. ~~Dejar de trackear `build/` y `dist/`~~ (~991 archivos binarios ya en git).
6. ~~Legacy no activo~~ — `Main.py`/`main.spec`/`create_icon.py`, `.aider.*`, `typedef VllmConfig` — no borrar sin plan aprobado.
7. ~~`analysis_options.yaml`~~ plantilla por defecto, sin reglas propias.

## 2. Decisiones consolidadas (no deshacer)

| Decisión | Detalle | Cuándo/por qué |
|---|---|---|
| **Backend único: Ollama** | vLLM y LM Studio eliminados | Migración 2026-03-02: de ~10GB/30min a ~200MB/30s y cross-platform. Documentada en `MIGRATION_OLLAMA.md`. |
| **Sin soporte de programación/IDE** | Campos previos como `ide_screen`, `code_analysis_service`: borrados en "Fase 1 – Limpieza" (2026-02-14) | Reenfoque a chat general estilo mensajería. |
| **Dependencias acotadas** | `provider` para estado, `http` para streaming de Ollama + `dio` (usado en `model_manager_service.dart`), `shared_preferences` para preferencias (`pubspec.yaml`, 13 dependencias de terceros + `flutter`) | Decidido en plan 2026-02-14. |
| **Singleton de servicios** | Patrón `XxxService.instance` registrado en `main.dart` con `provider` | Ya aplicado en `ollama_service.dart`; mantener consistencia. |
| **Planes en `plans/` (español)** | `YYYY-MM-DD_Nombre_Contexto.md` | Formato establecido 2026-02-14; es el "estilo de otros proyectos" del equipo: documento de resumen + documento de plan. |
| **Puerto Ollama 11434** | Configurable en la app si cambia `OLLAMA_HOST` | Estándar de Ollama. |

## 3. Contexto de entorno (para no redescubrir)

- **Máquina:** Windows (Git Bash/MSYS), ruta real del proyecto `D:\PROJECTS\LITGHCHAT\lightchat`.
- **Flutter 3.41.7 stable**, canal stable. `flutter --version` imprime aviso de versión nueva (actualizar opcional).
- **Análisis completo tarda ~62 s** (`flutter analyze`) — preveerlo al verificar cambios.
- **Sin** Docker, servicios, BD ni credenciales: proyecto 100% cliente.
- Directorios ignorados por git/agents locales: `build/`, `.dart_tool/`, `.idea/`, `dist/` parcialmente trackeado (ver deuda).

## 4. Historial de fases

1. **Herramienta de programación con agente IDE** (commits iniciales, 2025: `itui`, `swegf`, … timestamps confusos/previos).
2. **Fase 1/2 – Transformación a chat general + vLLM** (plan 2026-02-14, `plans/2026-02-14_LightChat_Plan_Transformacion_vLLM.md`): eliminación del IDE, vLLM como backend único, catálogo de modelos, detección de hardware, UI mensajería.
3. **Migración a Ollama** (2026-03-02, commit `63d2175`): `ollama_service`, `chat_service_ollama`, `ollama_manager_screen`, instalador PS. Multimodal, 8 idiomas detectados, icono "retrocápsula".
4. **Actual (oct-2026):** mantenimiento/borrado de deuda; optimización de rendimiento y mejoras visuales de UI; sin nuevas fases planificadas en `plans/`.

## 5. Lecciones y advertencias

- ⚠️ **No confiar en `MIGRATION_OLLAMA.md` sobre qué archivos existen** — lista archivos ya borrados. Contrasta con `ls lib/**` antes de editarlos.
- ⚠️ **`pubspec.yaml` description y README de `dist/`** pueden contradecir arquitectura vigente (restos vLLM/PyInstaller). Fuente de verdad: `MIGRATION_OLLAMA.md` + código actual en `lib/`.
- ⚠️ **Directorio `" lib"` con espacio** en la raíz: los globbings mal escritos pueden escribir ahí. Usa `lib/`.
- ⚠️ El test de widget **nunca** funcionará tal cual; al corregirlo, actualizar la expectativa a la pantalla real (`ChatScreen`), no desactivarlo.
- ⚠️ `flutter analyze` tiene ~62 s de arranque; ejecutar `flutter pub get` primero en entornos limpios.

## 6. Cómo actualizar esta memoria

- Añade entradas nuevas en fecha ascendente dentro de *Historial de fases*.
- Al cerrar un pendiente: márcalo ✓ en *Pendientes* (no lo borres) durante 2 ciclos y luego elimínalo.
- Al rechazar o revertir una idea, anótala en *Lecciones* para no repetir el intento.
