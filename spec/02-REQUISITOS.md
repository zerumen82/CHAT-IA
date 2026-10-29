# Requisitos

Fecha: 2026-10-26. Estado general: IMPLEMENTADO Y VERIFICADO. Reviewer APPROVE y tester PASS; evidencia detallada y límites en `MEMORY.md` §8.

## Alcance elegido por el usuario

- Exportar respuestas y conversaciones a TXT, Markdown, PDF y Word/DOCX.
- Contexto configurable hasta 32k, documentos persistentes y búsqueda local de fragmentos para archivos largos.
- Plan completo aprobado por el usuario. No se autoriza instalar dependencias por estas elecciones.

## GEN-01 — Crear archivos solicitados en el chat

- Peticiones como «genera un Excel de estas ventas» y «crea un PDF con el informe» generan archivos reales XLSX/PDF, elegidos explícitamente por el usuario; no instrucciones para crearlos manualmente.
- Herramienta local con argumentos estructurados y validados; nunca ejecutar scripts, fórmulas activas ni rutas arbitrarias que proponga el modelo.
- Tarjeta de archivo con nombre, formato y guardar mediante selector nativo; persistencia por conversación y restauración tras reinicio. Éxito solo con archivo válido creado; fallos visibles.
- XLSX con hojas, filas y celdas de texto/números; PDF con contenido y formato básico. Límites configurados de volumen y rutas contenidas en el almacén local.
- Comprobar generación por el modelo local real y apertura/lectura de archivos, además de pruebas del transporte/tool calls y guardado.

## DOC-01 — Contexto configurable y coherente

- Preferencia persistente por modelo; se respeta su máximo informado. Un modelo de 2.048/8.192 tokens nunca recibe un perfil 16k/32k incompatible.
- 32k se valida en la RTX 3060 Ti antes de declararlo utilizable; registrar modelo, contexto real, memoria, reparto GPU/CPU y tiempos. Si no es viable, informar y permitir elegir un perfil inferior.
- El perfil permanece estable con/sin adjuntos. Cambiarlo es una acción explícita, con advertencia de recarga.
- Presupuesto conjunto para sistema, pregunta, historial, documentos y respuesta; estimación de tokens identificada, nunca presentada como medición exacta.
- Medidor y visor usan el plan de contexto de la petición, incluyendo cabeceras y marcas. Diferencian extraído, conservado y enviado; advierten recorte previo, omisiones y truncamiento de filas/columnas.
- Cambiar modelo, conversación o historial actualiza la vista previa del borrador sin editarlo. Se descartan resultados asíncronos anteriores al cambio para que no sustituyan el contexto actual.
- Presupuestos pequeños nunca producen bloques mayores que el límite: si las cabeceras no caben, el diagnóstico se muestra fuera del bloque documental.

## DOC-02 — Documentos persistentes y búsqueda local

- Tras reiniciar, renombrar o mover el archivo original, el texto ya conservado sigue disponible en su conversación, dentro de límites declarados.
- El documento no desaparece por superar diez mensajes ni por adjuntar otro archivo. La selección usa las fuentes asociadas a la conversación.
- Preguntas sobre contenido al principio, centro y final de un archivo recuperan fragmentos pertinentes con referencias reales, cuando la extracción lo haya conservado.
- Texto extenso fuera de SharedPreferences; referencias y lectura compatible con conversaciones actuales. No prometer recuperar texto ya recortado: avisar si hace falta volver a adjuntar el original.
- Conservar reparto entre documentos/hojas; límites configurables y explícitos para tamaño original/expandido, entradas ZIP, almacenamiento y fragmentos. Evitar bloquear UI.
- Búsqueda parcial se identifica como parcial. Totales/recuentos solo se afirman con cobertura completa comprobada; de lo contrario se explica el límite.
- Borrar una conversación elimina sus referencias y solo sus archivos locales exclusivos; nunca los originales del usuario ni archivos usados por otra conversación.
- Validar rutas resueltas para que una referencia manipulada no permita leer/borrar fuera del almacén. Cancelar la selección de carpeta no rompe el envío actual.

## EXP-01 — Exportar respuestas y conversaciones

- Exportación de respuesta terminada desde su burbuja y de conversación desde su menú; selector de los cuatro formatos y destino nativo. Cancelar no crea archivos ni muestra éxito.
- Conversación = todos los mensajes conservados, en orden, con roles, fechas y modelo cuando exista. La política de poda actual no se modifica en este alcance; advertir su limitación y no afirmar recuperación de turnos eliminados.
- TXT legible en UTF-8; Markdown conserva su estructura; PDF paginado y legible; DOCX OOXML válido, editable y abierto por un lector real.
- Encabezados, listas, tablas y código con formato básico; Unicode, tildes, rutas con espacios y contenido extenso. No se promete reproducción exacta del diseño del chat.
- No incluir automáticamente originales adjuntos, rutas locales ni base64 de imágenes. Las referencias documentales visibles se conservan como texto.
- No exportar como final una respuesta mientras se está generando. Un error de escritura o una fuente no apta produce un error visible; éxito solo tras escritura comprobada.

## VAL-01 — Evidencia

Pruebas de presupuestos y recuperación, migración/reinicio, formatos/exportación y cancelación; regresión completa; analyze y build; reviewer APPROVE y tester PASS. Prueba real con Ollama y UI, apertura de los cuatro formatos y bitácora con comandos, resultados y limitaciones.

## Verificación final — 2026-10-26

| Historia | Resultado | Evidencia |
|---|---|---|
| GEN-01 | PASS | Ollama real generó XLSX/PDF; Excel real, lector PDF nativo y XML independiente abren los archivos. |
| DOC-01 | PASS | Perfiles nativos y persistencia; regresiones del medidor al cambiar modelo/conversación/historial; perfil real 32768 con prompt de 14671 tokens. |
| DOC-02 | PASS | Reinicio sin original, recuperación inicio/medio/final y más de diez turnos, límites y limpieza de referencias comprobados; consulta real recupera el dato fuera de los primeros 16000 caracteres. |
| EXP-01 | PASS | TXT/MD UTF-8, Word/Excel COM read-only y render PDF con Windows.Data.Pdf. Guardado de conversación desde UI Windows a ruta con espacios, archivo 4507 bytes. |
| VAL-01 | PASS | Analyze sin incidencias, 106 pruebas pasan + 1 live opt-in omitido en suite ordinaria, build Windows 73.8s, reviewer APPROVE y tester PASS. |

La inferencia real usó un perfil de 32k, sin llenar sus 32768 tokens: se midieron 14671 tokens de prompt. La rama de error de escritura se verificó mediante selector controlado sólo en pruebas y E/S real; el guardado y la cancelación también se comprobaron con diálogos nativos. No se provocó un fallo de escritura desde el selector nativo. Los límites documentales, de búsqueda parcial y de poda siguen declarados en `03-PENDIENTES.md`.
# Ampliación aprobada — UI e interacción, 2026-10-29

El usuario aprobó las mejoras de la revisión y concretó modo documental al
adjuntar con vuelta explícita a General, y cálculo mediante panel de selección.
Detalle y criterios en spec/07-MEJORAS-CHAT-UI.md.

| Requisito | Implementación | Verificación al 2026-10-29 |
|---|---|---|
| CHAT-01/02 | Parciales, fin, continuar, cancelación, fases y tiempo | HTTP local real y regresiones PASS; Ollama real PASS |
| MODEL-01 | Capacidades verificadas, imágenes incompatibles bloqueadas | Regresiones PASS; metadata de Qwen real y bloqueo sin visión PASS |
| DOC-03 | General/documentos y fuentes elegibles por chat | Regresiones PASS, incluidas rutas Windows legacy; cambio General con Ollama real PASS |
| DATA-01 | Panel y suma/agrupación local decimal, lectura completa | Archivos reales en pruebas PASS; Excel generado por Ollama sumado localmente 20.5 PASS |
| DRAFT-01 | Borrador por chat, archivo completo, fallback local, guardado al cerrar | Regresiones de reinicio/concurrencia/tombstone PASS |
| UI-01/02 | Drawer estrecho, búsqueda, ancho de lectura y acciones útiles | Widget tests y recorrido nativo PASS, incluido reinicio/borradores/cálculo/exportación |

Analyze final sin incidencias; suite 138 PASS + 1 live opt-in omitido en suite
normal, con ejecución real separada PASS. Reviewer APPROVE de código final.
Build Windows PASS71.7s y tester independiente nativo PASS; alcance cerrado.
Evidencia y límites en MEMORY.md §9 y spec/07.

## Corrección de adjuntos y escritura — 2026-10-29

Continuación autorizada por «HAZLO»; criterios en spec/09. Se corrigen DOC-01,
DOC-03 y DRAFT-01: cursor sin edición, medidor y aviso de historial estables,
estado documental sin presupuesto legacy, texto conservado diferenciado de
selección enviada y escritura del siguiente mensaje durante streaming.

Reviewer final APPROVE; regresiones rojo→verde, suite 144 PASS + 1 live opt-in
omitido, analyze limpio y build Windows PASS68.9s. Tester independiente PASS:
dos respuestas Ollama reales, escritura/cursor/tildes, etiquetas y borrador tras
reinicio. Modelo/chat originales restaurados. Cierre y evidencia en MEMORY.md
y spec/09; límites del arnés en tester-result.json.

