# Propuesta: más contexto documental y exportación

Fecha: 2026-10-26. Estado: APROBADO por el usuario («sí»), IMPLEMENTADO Y VERIFICADO. Reviewer APPROVE + tester PASS. Resultados y límites en `02-REQUISITOS.md` y `MEMORY.md` §8.

Ampliación explícita aprobada: al pedir archivos en lenguaje natural, el chat debe generar archivos reales PDF y Excel. El usuario confirmó XLSX (formato actual), sin exigir XLS antiguo. Se añadirá una herramienta local de creación de documentos con argumentos estructurados validados, sin ejecutar código del modelo, y tarjetas de archivos guardables desde el chat. Reutilizará el generador PDF y un escritor XLSX OOXML con archive/xml existentes. Los archivos se conservarán localmente por conversación y sobrevivirán al reinicio; no se anunciará éxito antes de crear el archivo.

## 1. Contexto

El usuario solicita más contexto para documentos, exportación en formatos básicos y revisión de mejoras. Ha elegido TXT, Markdown, PDF y DOCX para respuestas y conversaciones; además, contexto hasta 32k con documentos persistentes y búsqueda local de fragmentos.

Diagnóstico: 16.384 tokens fijos para todos los modelos, 16.000 caracteres/documento, 24.000 por envío y 8.000 en seguimientos; documentos vinculados al contexto de los últimos diez mensajes. Visor y medidor no reflejan siempre la petición final. No existe exportación.

Evidencia local de esta sesión: `/api/show` informa Qwen2.5 32.768, Llama3 8.192 y Wizard-Vicuna 2.048 tokens. `nvidia-smi`: RTX 3060 Ti, 8.192 MiB totales, 7.109 MiB libres en la consulta. `/api/ps`: sin modelos cargados. Esto prueba metadata/disponibilidad, no viabilidad ni rendimiento de 32k.

## 2. Cumplimiento de AGENTS.md

- «El usuario es el orchestrator supremo»: este documento propone diseño y orden para aprobación; elegir el alcance no aprueba todavía cada paso.
- SDD antes de implementar: creados `spec/00-PRINCIPIOS.md` a `04-EJERCITO.md`, diferenciando estado actual y propuesta.
- «NO HARDCODE · NO STUB · NO FAKE · LOCAL-FIRST»: configuración central, persistencia/búsqueda local, formatos auténticos y evidencia ejecutada.
- «Prohibido instalar paquetes/skills/modelos sin aprobación explícita»: reutilizar paquetes actuales; no instalar ni actualizar ninguno.
- «Listo» exige lint, build, reviewer APPROVE y verificación real; bitácora en `MEMORY.md`.

## 3. Pasos de implementación propuestos

1. **Presupuestos y perfiles**. Tocar `lib/config/vllm_config.dart`, `lib/services/ollama_service.dart` (reutilizar `showModel`), `lib/services/chat_service_ollama.dart`, `lib/screens/ollama_manager_screen.dart` y pruebas de chat. Añadir `lib/config/document_config.dart`, `lib/models/context_plan.dart` y `lib/services/document_context_service.dart`. Preferencias por modelo, límite nativo, selección explícita hasta 32k, perfil estable y reserva conjunta de prompt/historial/respuesta. Verificar 32k antes de declararlo validado; fallback elegido por el usuario si no es viable.
2. **Conservar documentos**. Tocar `lib/services/document_service.dart`, `lib/models/document_attachment.dart`, `lib/models/message.dart`, `lib/services/conversation_service.dart`; añadir `lib/services/document_store_service.dart` y `lib/models/document_chunk.dart`. Carpeta local seleccionada y persistida usando `file_selector`; texto/fragmentos separados de preferencias; referencias compatibles con mensajes actuales. Límites de expansión/almacenamiento y aislamiento del trabajo pesado. Nunca borrar originales.
3. **Recuperar contenido pertinente**. Ampliar el servicio de contexto y orquestación del chat. Búsqueda léxica local sin modelos nuevos, referencia por archivo/hoja/página/rango disponible, documentos accesibles tras múltiples turnos y reinicios. Conservar reparto entre fuentes. Aviso de cobertura parcial; no afirmar totales globales sin comprobar cobertura completa.
4. **Hacer transparente la selección**. Tocar `lib/widgets/chat_input.dart`, `lib/widgets/document_text_dialog.dart` y `lib/widgets/message_bubble.dart`. Medidor/visor de la selección usada en la petición, separado del texto extraído; avisos por recorte previo, fuentes omitidas y filas/columnas. Contar todos los separadores y no exceder presupuestos pequeños.
5. **Exportar los cuatro formatos**. Añadir `lib/services/export_service.dart`, `lib/models/export_format.dart`; tocar `lib/widgets/message_bubble.dart`, `lib/screens/chat_screen.dart` y `lib/widgets/conversation_sidebar.dart`. Acciones para respuesta terminada y conversación conservada; diálogo nativo y cancelación limpia. TXT UTF-8, Markdown, PDF paginado mediante Syncfusion y DOCX OOXML mediante ZIP/XML. Formato básico de encabezados/listas/tablas/código; fuente Unicode local validada. Compartir conversión, sin duplicar lógica por cada botón.
6. **Verificar y documentar**. Ampliar `test/document_service_test.dart`, `test/chat_service_ollama_test.dart`, `test/conversation_service_test.dart`, `test/widget_test.dart`; nuevas pruebas focalizadas de almacenamiento/contexto/exportación. Actualizar `README.md`, `AGENTS.md`, `spec/` y `MEMORY.md` con resultados, límites y decisiones aprobadas.

## 4. Riesgos y límites

- Contexto mayor implica más memoria; no prometer 32k íntegramente en GPU antes de medir. No cambiar `num_ctx` por mensaje, por la recarga ya documentada.
- Tokens por caracteres son estimación: etiquetarla y contrastarla con métricas reales de Ollama; no afirmar tokenización exacta sin tokenizer.
- Texto descartado en adjuntos históricos no se puede recuperar de sus JSON. Solicitar readjuntar si hace falta, conservando lo disponible.
- Búsqueda de fragmentos no garantiza resultados exhaustivos para sumas/recuentos. No inventar totales sobre cobertura parcial.
- Exportar conversación significa los mensajes conservados; no cambiar la política de poda ni recuperar mensajes ya eliminados en este alcance.
- No incluir automáticamente imágenes ni originales adjuntos en las exportaciones; sí referencias visibles. OCR y exportación a Excel/CSV quedan fuera de las opciones elegidas.
- PDF/DOCX ofrecen formato básico, sin promesa de fidelidad exacta al chat. Una fuente local insuficiente debe producir un diagnóstico; empaquetar fuentes/añadir bibliotecas requiere aprobación si resultara necesario.

## 5. Impacto

Beneficio esperado: consultar partes posteriores de documentos, mantener sus fuentes entre turnos y guardar respuestas utilizables fuera de la app. Se mantienen Ollama, provider, selectores actuales y conversaciones existentes. Pasos independientes y verificables para mantener los flujos de chat, streaming, reintento, editar/regenerar y modelos. Evitar deuda de JSON enormes o renderizadores duplicados; cualquier límite pendiente queda en `spec/03-PENDIENTES.md`.

## 6. Verificación

- Pruebas de presupuesto final, recorte previo, múltiples documentos/hojas/columnas, metadata 2k/8k/32k, reinicio y migración.
- Recuperación real de datos al principio, centro y final de documentos conservados, tras más de diez mensajes; identificar cobertura parcial y preguntas de totales.
- Exportar contenido largo con tildes, tablas, listas y código a los cuatro formatos; abrir TXT/MD, extraer/verificar texto PDF y abrir DOCX real en un lector disponible. Probar cancelación, errores de escritura y rutas con espacios.
- `flutter analyze --no-pub`, `flutter test --no-pub`, `flutter build windows --no-pub`, sin instalar dependencias. No compilar durante la medición de Ollama.
- Prueba de UI Windows y Ollama real; registrar contexto, consumo, tiempos y métricas disponibles. Reviewer APPROVE + tester PASS antes de declarar terminado.

Fuentes oficiales consultadas: [contexto Ollama](https://docs.ollama.com/context-length), [PdfDocument de Syncfusion instalado](https://pub.dev/documentation/syncfusion_flutter_pdf/35.1.41/pdf/PdfDocument-class.html). `file_selector`, `archive` y `xml` están ya declarados; comprobar sus APIs instaladas al implementar.
