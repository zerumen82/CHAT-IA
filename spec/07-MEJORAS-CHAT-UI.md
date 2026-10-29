# Mejoras de interacción y UI — 2026-10-29

## Contexto y autorización

El usuario pidió una revisión general y, tras recibir las ocho propuestas
priorizadas, indicó «hazlo». Esta entrada concreta esa aprobación para ejecutar
las mejoras, conservando todos los cambios locales anteriores. Confirmó activar
consulta documental al adjuntar, con control visible para volver a general, y
cálculo mediante panel explícito de archivo, hojas y columnas.

## Cumplimiento

AGENTS global/local: SDD antes del código, cómputo local, configuración
centralizada, ninguna instalación, sin éxitos simulados, reviewer independiente
y tester con evidencia real. Se reutilizan Flutter, HTTP, SharedPreferences,
archive/xml y excel2003 presentes. No se modifica el backend único Ollama.
La herramienta de tareas no está disponible; el seguimiento se hace aquí.

## Requisitos y criterios

- CHAT-01: un fallo de red conserva el texto parcial y muestra el fallo por
  separado; detener conserva la respuesta e indica su estado. Distinguir final
  normal, límite, interrupción y parada. Continuar conserva los turnos previos.
- CHAT-02: estados observables de preparación, espera del modelo, razonamiento,
  respuesta y archivos, con tiempo transcurrido. No presentar un porcentaje ni
  carga de modelo deducidos sin evidencia. Conexión e inactividad acotadas con
  configuración compatible con las recargas lentas documentadas.
- MODEL-01: capacidades de imágenes/herramientas obtenidas de metadata real,
  con estado desconocido explícito; bloquear imágenes incompatibles antes de
  enviar sin perder borrador. Selector bloqueado con explicación al generar.
- DOC-03: control visible chat general/consulta documental y fuentes elegibles.
  General no aplica restricciones documentales. Historial parcial y cobertura
  documental visibles; conservar historial guardado, sin poda automática nueva.
- DATA-01: suma y agrupación local determinista de tablas completas, con elección
  explícita de archivo/hojas/columnas, filas procesadas y celdas excluidas.
  Nunca afirmar total global desde fragmentos; no ejecutar código ni fórmulas
  propuestas por el modelo. Reutilizar lectores y límites de seguridad. Si hace
  falta el original completo, seleccionarlo con diálogo nativo y explicarlo.
- DRAFT-01: texto y referencias de adjuntos por conversación, restaurados al
  cambiar/reiniciar, preparación sin Ollama, sin contenido grande en preferencias.
  No borrar el borrador antes de aceptar el envío; errores de persistencia visibles.
- UI-01: ancho de lectura limitado por el espacio del chat, acciones secundarias
  agrupadas, historial accesible mediante panel en ventanas estrechas, búsqueda
  de conversaciones y acción volver al final. Conservar tema azul/teal.
- UI-02: acciones útiles en conversación vacía según capacidades, sin prometer
  generación no soportada ni instalar modelos automáticamente.

## Pasos de implementación

- [x] Transporte y orquestación: ollama_service.dart, chat_service_ollama.dart,
  context_profile_service.dart, configuración compartida y pruebas de regresión.
- [x] Entrada/navegación: chat_screen.dart, chat_input.dart, model_selector.dart,
  message_bubble.dart, conversation_sidebar.dart y servicio de borradores.
- [x] Cálculo local: ampliar DocumentService con lectura estructurada segura,
  servicio de agregación, panel de selección y pruebas con archivos reales.
- [x] Integración, reviewer, correcciones, analyze, suite y build Windows.
- [x] Recorrido UI y Ollama reales, cálculo de archivo real, evidencia y bitácora.

## Riesgos, límites e impacto

Los estados de carga/espera no aseguran conocer la fase interna de Ollama.
Los tokens son estimados salvo métricas recibidas. Mantener num_ctx estable.
No hay OCR ni evaluación de fórmulas Excel; fechas BIFF8 siguen como seriales.
El cálculo usa celdas conservadas o archivo completo seleccionado, nunca texto
recortado ambiguo. No se recuperan turnos que ya se hubieran podado.
Cambios de configuración o modelo durante generación quedan bloqueados.
La implementación mantiene servicios separados de widgets y conserva los
flujos de exportación/guardado. No se introduce dependencia de red nueva.

## Verificación

Regresiones con HTTP local real: error tras varios fragmentos, fin por límite,
fin prematuro, parada y capacidades. Pruebas de borradores al alternar chats y
reiniciar, de contexto general/documental y fuentes, y de navegación estrecha.
Tablas XLSX/CSV con números, negativos, vacíos, texto, grupos y múltiples hojas;
rechazar cobertura incompleta y no ejecutar fórmulas. Analyze sin incidencias,
suite verde y build Windows; reviewer APPROVE y tester PASS antes del cierre.

### Criterios reforzados por reviewer

- DATA-01: selección explícita del formato decimal para texto/CSV; números
  nativos de XLSX no se reinterpretan por locale. Fórmulas y errores se excluyen
  con recuento visible; no se ejecutan ni se trata el caché como un recálculo.
  En XLS BIFF8 se declara el límite del lector respecto a fórmulas/cachés.
  Límites de lectura alcanzados bloquean el cálculo completo, nunca omiten
  filas/columnas en silencio. Sumas decimales sin deriva binaria.
- DOC-03: selección de fuentes aplicada al plan y al envío, también al contexto
  reconstruido del historial. Una fuente desmarcada no se reintroduce por un
  mensaje previo. Verificar petición HTTP real frente a la vista previa.
- DRAFT-01: clave estable por conversación; el envío se acepta antes de retirar
  el borrador, con versión para impedir que un callback tardío borre uno nuevo
  o de otro chat. Referencias de adjuntos con aviso si su archivo desaparece;
  contenido grande fuera de preferencias. Errores de persistencia visibles.
- CHAT-01/02: EOF sin done=true es interrupción; inactividad medida desde el
  último evento real, no desde tokens visuales. Cancelación libera transporte
  antes de permitir otra solicitud; el primer token no tiene plazo irreal.

## Bitácora provisional

- 2026-10-29: autorización recibida, reglas/memoria leídas, cambios anteriores
  inventariados con Git Windows. La sesión anterior no pudo escribir MEMORY.md;
  se conserva aquí evidencia hasta que pueda integrarse sin cambiar permisos.
- Docs oficiales consultadas: https://docs.ollama.com/api/chat,
  https://docs.ollama.com/api/streaming, https://docs.ollama.com/capabilities/vision.
  Se usan campos compatibles con la versión local; no se actualiza Ollama.

### Ejecución de la sesión y bloqueo efectivo

- Plan técnico revisado independientemente: CHANGES_REQUESTED por criterios de
  cobertura/cálculo, selección documental, aceptación del borrador y fin/cancelación.
  Criterios incorporados antes del código candidato; re-review del plan APPROVE.
- apply_patch rechazó crear lib/config/chat_config.dart, ui_config.dart y
  spreadsheet_config.dart en el proyecto original con Failed to write file.
  MEMORY.md ya había dado Access denied en la revisión anterior. Tras responder
  el usuario «estaba habilitado» se comprobó otra vez y siguió denegado.
  La ACL leída muestra SID sandbox diferente en lib respecto a raíz/spec.
  No se cambió ninguna ACL, atributo ni permiso ni se elevó ejecución.
- Se creó una copia para preparar un parche revisable, sin aplicarlo al original:
  C:/Users/INdaHouse/AppData/Local/Temp/lightchat-review-20261029.
  Solo se copiaron fuentes, pruebas, assets, configuración y metadata de paquetes
  ya instalados. No se instaló ni descargó nada. No hay copia ejecutable nueva.
- flutter test --no-pub --reporter expanded test/spreadsheet_analysis_test.dart
  quedó sin salida durante más de dos minutos y se interrumpió. El wrapper
  Flutter contiene un bucle de apertura de lock en el SDK; la causa de ese
  silencio no se presenta como un fallo de las pruebas.
- dart analyze de los tres archivos de cálculo falló antes de analizar:
  CreateFile failed 5 (Acceso denegado), ProcessException al arrancar
  D:/flutter/bin/cache/dart-sdk/bin/dartaotruntime.exe con analysis_server_aot.
  No se buscaron vías alternativas para ejecutar el binario bloqueado.
- dart.exe format sí se ejecutó sobre los archivos candidatos modificados:
  comprueba parseo/formato, no sustituye analyze, pruebas, build ni UI real.
- Revisión del código candidato detectó y corrigió reactivación documental tras
  elegir General, borradores resucitados tras borrar chats, drop durante restore,
  pérdida de borrador largo sin biblioteca y guard de cambio de raíz.
- Cálculo: CSV/TSV/XLSX/XLSM completos, locale textual explícito, acumulación
  decimal exacta con BigInt, exclusiones visibles y límites que rechazan lectura.
  Rangos array de fórmulas XLSX también excluyen resultados cacheados sin f en
  sus celdas. BIFF8 antiguo se rechaza para calcular: excel2003 1.0.0 transforma
  fórmulas en números/texto cacheados y no permite distinguirlas. Se explica
  guardar como XLSX/CSV; la extracción documental XLS previa sigue disponible.
- Persistencia de borrador: archivo completo fuera de preferencias. Sin
  biblioteca se usa directorio local de aplicación desde las variables del SO;
  marcador fallback estable para restaurar incluso después de elegir biblioteca.
  No se serializan textos grandes ni base64 en preferencias.

### Continuación tras habilitar acceso

El usuario habilitó acceso sin restricciones y pidió «sigue». Se comprobó
git apply --check y cada hash original antes de aplicar el parche. Los cambios
locales anteriores se conservaron. spec/08 es el candidato histórico anterior
a las correcciones de la verificación ejecutable, no un parche del estado final.

- Analyze final: No issues found!, 5.3s, exit0.
- Suite final: 138 PASS + 1 live opt-in omitido, 24s, exit0.
- Live separado con qwen2.5:7b: PASS en48s; XLSX/PDF, cálculo20.5, recuperación
  con32k y regreso a General sin documentos (respuesta4, completed).
- Build Windows final: PASS, 71.7s. Bundle data/app.so del2026-10-29.
- Reviewer independiente: APPROVE de cierre/borradores y normalización completa
  de rutas/exclusiones/metadata legacy tras regresión Windows nueva PASS.
- Tester nativo: cálculo con selectorWindows real,4filas/4números,0excluidos,
  Café0.3,Té10 y total10.3, PASS. Continúa resto del recorrido antes de cierre.

Evidencia y fallos/correcciones integrados en MEMORY.md §9; sin instalaciones,
commit ni push. Tester nativo final PASS: exportación TXT308B, fuentes y modo,
borradores por chat y reinicio, drawer/búsqueda680x820. Resumen y límites en
.dart_tool/ui-improvements-20261029/tester-result.json. Reviewer APPROVE y todas
las comprobaciones obligatorias verdes: alcance aprobado cerrado.
