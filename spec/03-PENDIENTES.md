# Pendientes y riesgos

Fecha: 2026-10-26. El diagnóstico inicial se conserva abajo como historial. El estado vigente figura en la tabla de seguimiento.

## Seguimiento de la implementación aprobada

| Hallazgo inicial | Estado actual |
|---|---|
| Recorte temprano y pérdida tras diez mensajes | Corregido: extracción conservada con límites, fuentes por conversación y selección local de fragmentos. Los recortes de adjuntos antiguos requieren volver a adjuntar. |
| Presupuesto, visor y avisos divergentes | Corregido: plan común, reserva conjunta, selección enviada persistida y avisos de extracción/contexto/columnas. Los tokens siguen siendo una estimación, contrastada con métricas reales. |
| Contexto incompatible con modelos pequeños | Corregido: perfil limitado por metadata; pruebas de 2k/8k y fallback conservador de 4k. |
| Perfil 32k sin inferencia real | Verificado con Qwen2.5 7B Q4_K_M: `/api/ps` confirmó 32768, 6255678586 bytes de VRAM y 14671 tokens de prompt. El ensayo no llenó los 32768 tokens. Reparto parcial CPU/GPU; no equivale a rendimiento garantizado para otros modelos. |
| Texto extenso en preferencias | Corregido: almacén documental y snapshots separados, con vistas previas/referencias compatibles. |
| ZIP y extracción en UI | Corregido: límites centralizados de expansión/entradas/texto/filas/columnas y extracción en isolate. |
| PDF Unicode sin fuente empaquetada | Resuelto mediante fuente local y validación de cobertura; configurable con `LIGHTCHAT_PDF_FONT`. Caracteres sin cobertura producen error visible. |
| OOXML inválido tolerado por parser Dart | Corregido con `xmlns` explícito; apertura Office real y lector XML independiente documentados. Mantener validación independiente de formatos. |
| Poda del historial, PDF escaneado, fechas XLS BIFF8 | Limitaciones conservadas: solo se exportan mensajes conservados, sin OCR; XLS antiguo no resuelve formatos de fechas. |
| Búsqueda parcial y totales globales | Límite declarado: los fragmentos no garantizan lectura exhaustiva ni totales. El modelo puede equivocarse incluso cuando se incluye una referencia. |

La biblioteca permanece en la carpeta elegida mientras contenga archivos; trasladarla con migración automática queda fuera del alcance aprobado. No se han instalado dependencias, modelos ni skills.

## Diagnóstico inicial (histórico)

| Hallazgo | Evidencia | Tratamiento propuesto |
|---|---|---|
| Recorte destructivo temprano | `DocumentService.extract()` guarda como máximo 16.000 caracteres | Almacén local con límites y fragmentos; lo ya descartado exige volver a adjuntar |
| Documentos se pierden del contexto | Últimos diez mensajes y solo último turno documental | Fuentes persistentes por conversación y búsqueda local |
| Presupuesto parcial | Medidor omite preámbulo/marcas; mínimo de extracto puede exceder presupuestos pequeños | Plan común y límite final comprobado |
| Aviso global incompleto | `isContextTruncated()` ignora recorte anterior `document.truncated` | Mostrar todos los motivos de contexto parcial |
| Visor inexacto | Llama «enviados» a caracteres de `document.text` | Separar extracción de selección enviada |
| Columnas descartadas sin marca | Límite 50 en CSV/XLS/XLSX | Indicar columnas omitidas y alcance real |
| Perfil incompatible con algunos modelos | Contexto app 16.384; `/api/show` informa modelos instalados de 2.048/8.192 | Limitar por metadata y configuración persistente |
| 32k sin prueba de inferencia actual | Qwen2.5 declara 32.768; GPU 8 GB confirmada, no se ha cargado a 32k | Medir antes de habilitarlo como validado |
| JSON grandes en preferencias | Adjuntos serializan texto dentro de mensajes | Contenido separado y referencias; migración compatible |
| Poda del historial | `cleanOldHistory()` elimina algunos mensajes antiguos | Exportar lo conservado y declarar límite; cambiar retención requeriría ampliar alcance |
| ZIP pequeño puede expandir mucho | Office se descomprime durante extracción | Límites configurados de expansión y trabajo fuera de UI |
| PDFs escaneados | No hay texto extraíble ni OCR | Mantener error explícito; OCR requeriría propuesta separada |
| Fechas XLS BIFF8 | `excel2003` no expone formatos de celda | Mantener deuda existente declarada |
| PDF Unicode | No hay fuentes empaquetadas en `assets/` | Resolver fuente local, validar cobertura; cualquier asset/dependencia nueva requiere revisión/aprobación |

32k consume más memoria; no se promete que quepa enteramente en GPU ni que mejore velocidad. La búsqueda de fragmentos no equivale a leer todo el documento para cálculos globales.

La revisión encontró modificaciones y borrados preexistentes en git. Preservarlos. `git` por defecto apunta a Cygwin y falló con Win32 error 5; la lectura con `C:/Program Files/Git/cmd/git.exe` funcionó. Las consultas CIM de hardware fueron denegadas; `nvidia-smi` sí confirmó la GPU. No son fallos de la aplicación.
# Límites vigentes de la ampliación UI — 2026-10-29

- El cálculo local exige XLSX/XLSM/CSV/TSV completo dentro de los límites de
  SpreadsheetConfig/DocumentConfig. Alcanzarlos bloquea la lectura, sin total
  parcial silencioso. XLS BIFF8 requiere conversión a XLSX/CSV para calcular.
- Fórmulas (incluidas matrices), errores, fechas, booleanos y texto no numérico
  no se suman. Se muestran sus recuentos; no afirmar total de importes con
  valores excluidos. No hay motor de recálculo Excel.
- Imágenes de borradores conservan referencias a originales; si desaparecen,
  hay que volver a adjuntarlas. Documentos/texto se conservan en archivos locales.
- Borradores acotados a UiConfig.maxDraftBytes; errores de disco se muestran y
  el cierre no destruye la ventana si no pudo completar el guardado.
- Se conserva todo historial que exista desde esta ampliación; no se recuperan
  mensajes podados por versiones anteriores. Contexto enviado sigue acotado y
  la cobertura parcial no garantiza exactitud de citas ni totales del modelo.
- Sin OCR ni dependencias nuevas. Pruebas/modelos reales en esta máquina no
  garantizan iguales tiempos o consumo con otros modelos.

