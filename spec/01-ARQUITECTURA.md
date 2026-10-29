# Arquitectura

Fecha: 2026-10-26.

## Estado observado antes de la implementación (histórico)

Flutter de escritorio, `provider`, servicios Dart, Ollama local. Flujo: widgets → servicios → API de Ollama; los servicios no dibujan UI.

- `lib/config/vllm_config.dart`: `OllamaConfig`, contexto fijo de 16.384 tokens y respuesta máxima de 2.048.
- `lib/services/document_service.dart`: extracción y recorte; 16.000 caracteres/documento, 24.000/mensaje, 8.000/seguimiento, 25 MB/archivo, 1.000 filas y 50 columnas.
- `lib/services/chat_service_ollama.dart`: últimos diez mensajes como contexto; texto documental solo del último mensaje con documentos dentro de esa ventana.
- `lib/services/ollama_service.dart`: transporte, streaming y `showModel()` existente para consultar metadatos.
- `lib/models/document_attachment.dart` y `message.dart`: texto documental serializado con los mensajes.
- `lib/services/conversation_service.dart`: índice y mensajes por conversación en SharedPreferences.
- `lib/services/context_service.dart`: poda de mensajes antiguos, además de preferencias e idioma.
- `lib/widgets/document_text_dialog.dart`: muestra texto extraído almacenado, no la selección final de cada petición.
- No existe servicio de exportación. La carpeta `spec/` no existía antes de esta sesión.

## Diseño aprobado e implementado

1. Perfiles persistentes por modelo en configuración, con 16k como referencia actual y opción hasta 32k cuando el modelo y la prueba de hardware lo permitan. Respetar modelos de 2k/8k; metadata desconocida no autoriza 32k. Reutilizar `showModel()`; no cambiar `num_ctx` automáticamente según adjuntos.
2. Planificador de contexto compartido por envío y vista previa: reservar sistema, pregunta, historial y respuesta; asignar el resto a documentos. Estimación de tokens etiquetada como tal, margen conservador y contraste con `prompt_eval_count` real. Reutilizar el mismo resultado para medidor, visor y petición.
3. Almacén local de documentos separado del JSON de mensajes: extracción conservada con límites configurados, identificador y fragmentos con archivo/hoja/página o rango disponible. Referencias persistentes por conversación; lectura compatible del texto antiguo sin recuperar contenido que ya fue descartado.
4. Carpeta local elegida mediante `file_selector` y persistida en configuración, sin nueva dependencia para rutas. Cancelar su selección conserva el flujo actual. Escrituras seguras, control de errores, límites de almacenamiento y eliminación ligada a referencias al borrar una conversación; no borrar originales del usuario. Validar rutas resueltas para impedir lecturas o borrados fuera de la carpeta configurada por referencias manipuladas.
5. Búsqueda léxica local de fragmentos por pregunta, sin descargar modelos de embeddings. Repartir fuentes y conservar referencias verificables. Las preguntas de totales/recuentos requieren cobertura completa verificable o aviso explícito de insuficiencia; recuperar algunos fragmentos no demuestra un total global.
6. Extracción pesada y búsqueda fuera del hilo de UI; límites de tamaño expandido de ZIP, entradas, filas/columnas y almacenamiento centralizados. Todo recorte queda indicado.
7. Servicio específico de exportación, sin duplicar chat ni transporte: TXT y Markdown, PDF mediante Syncfusion ya instalado, DOCX OOXML real mediante `archive` + `xml`; guardado con `file_selector`. Conversión común de Markdown para encabezados, párrafos, listas, tablas y código. PDF paginado y fuente Unicode local disponible; validar cobertura de caracteres y declarar fallos sin sustitución silenciosa.
8. Exportar una respuesta terminada o todos los mensajes conservados de una conversación. No incluir automáticamente los originales, rutas privadas ni el texto íntegro de adjuntos. Conservar referencias visibles a archivos. No prometer recuperar mensajes podados.

Archivos nuevos propuestos: configuración documental, modelos de fragmento/plan de contexto y servicios de almacenamiento, selección de contexto y exportación. Sus nombres concretos figuran en el plan; los servicios existentes siguen siendo responsables de sus funciones actuales.

## Implementación vigente — 2026-10-26

- `context_config.dart`, `document_config.dart` y `export_config.dart` centralizan perfiles, presupuestos, almacenamiento y formatos. `ContextProfileService` consulta `showModel()` y persiste el perfil por modelo, limitado por su contexto nativo; metadata desconocida usa 4k.
- `ChatServiceOllama.previewContext()` construye `PreparedContext` para medidor y envío, reservando sistema, herramientas, pregunta, imágenes, historial y respuesta. `DocumentContextService` selecciona fragmentos mediante búsqueda léxica local en un isolate y devuelve referencias y avisos de cobertura parcial.
- `DocumentStoreService` conserva extracciones e índice de referencias bajo `.lightchat-documents` en la carpeta elegida por el usuario. Los mensajes guardan identificadores y vistas previas pequeñas. `ContextSnapshotService` conserva fuera de preferencias la selección documental enviada, bajo `.lightchat-contexts`.
- `ExportService` produce TXT/Markdown/PDF/DOCX y XLSX con las bibliotecas existentes. `GeneratedFileService` recibe las herramientas `create_pdf`/`create_spreadsheet`, valida datos y crea archivos bajo `generated/<conversación>`. No ejecuta código ni fórmulas del modelo.
- `context_settings_dialog.dart` y `file_actions.dart` conectan configuración, exportación y guardado con selectores nativos. Cambiar la carpeta se bloquea mientras contenga archivos. Las operaciones de conversación mantienen un guard durante los awaits; limpiar/eliminar retira referencias y archivos exclusivos, sin borrar originales.
- Las rutas se validan dentro de la raíz y se rechazan enlaces/junctions. Extracción, ZIP, filas/columnas y volumen guardado tienen límites declarados. La política previa de poda del historial se conserva.

Las secciones históricas describen el diagnóstico que motivó el cambio. El plan aprobado está en `05-PLAN-DOCUMENTOS-EXPORTACION.md`; la evidencia y los límites actuales se registran en `MEMORY.md` y `03-PENDIENTES.md`.
# Interacción y cálculo local — ampliación 2026-10-29

La orquestación mantiene fases observadas y fecha de inicio, estado final por
mensaje, métricas de Ollama y contenido parcial independiente del error. Cada
stream posee cliente HTTP cancelable; conexión e inactividad se configuran en
ChatConfig. EOF sin done no se presenta como respuesta completa.

ContextProfileService expone capabilitiesKnown, supportsVision y supportsTools
desde metadata. El modo general/documental y exclusiones se guardan por chat.
sourceKey normaliza rutas en Windows; selección, vista previa, envío e historial
comparten identidad. No se poda automáticamente el historial persistido.

DraftService guarda contenido completo por conversación en archivos, con
preferencias pequeñas que señalan la ubicación. Usa biblioteca elegida o carpeta
local de aplicación desde el SO; marcador fallback estable, escrituras seriadas,
dirty/identidad y tombstones para impedir callbacks sobre chats eliminados.
El cierre espera flush antes y después de descargar modelos; error de guardado
mantiene abierta la ventana. UiConfig contiene límites y parámetros de layout.

DocumentService.readSpreadsheet lee el archivo completo en isolate reutilizando
las validaciones ZIP y decodificación. SpreadsheetAnalysisService suma decimales
con BigInt y agrupa datos elegidos explícitamente, sin LLM ni ejecutar fórmulas.
El panel muestra cobertura, exclusiones, copia y exportación. SpreadsheetConfig
centraliza límites. XLS BIFF8 se mantiene para lectura documental, pero el cálculo
exige XLSX/CSV porque el lector no distingue fórmulas de cachés.

