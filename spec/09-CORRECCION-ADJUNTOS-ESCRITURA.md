# Corrección de adjuntos y escritura — 2026-10-29

Estado actual: IMPLEMENTADO Y VERIFICADO tras «HAZLO». Regresiones verdes,
suite144PASS, analyze limpio, build final PASS68.9s, reviewer APPROVE y tester
nativo PASS. Dos respuestas reales, escritura y etiquetas del último build
verificadas. Modelo/chat originales restaurados; aplicación final abierta.

Petición: al cargar un archivo aparecen mensajes contradictorios y después de
la primera respuesta no se puede escribir bien. Corrección del comportamiento
ya especificado en DOC-01, DOC-03 y DRAFT-01; sin ampliar funcionalidad.

Diagnóstico confirmado con reviewer: los cambios de selección/composición del
controlador se tratan como ediciones del borrador. Cada invalidación borra la
vista previa y muestra el cálculo documental legacy o elimina el medidor,
provocando avisos alternos y desplazamientos del editor. El chip llama recorte
a la vista previa, aunque el texto completo se conserva, y confunde extracción
con selección enviada.

Plan mínimo: corregir ChatInput, conservar un espacio informativo coherente
mientras se calcula el plan real, no recalcularlo por cada fragmento del stream,
y distinguir texto conservado de contexto enviado. Mantener descarte de
resultados antiguos, borradores por chat, modos y selección de fuentes.

Criterios verificables:

- Mover cursor/selección sin editar no guarda ni recalcula contexto y no impide
  limpiar el borrador aceptado.
- Tras primera respuesta documental, escribir mantiene foco, selección y zona
  documental estable mientras se calcula; no reaparece el presupuesto legacy.
- Mientras hay respuesta en curso se puede preparar el siguiente mensaje;
  el cálculo de su contexto se reanuda al terminar.
- Cambiar conversación/modelo/fuentes sigue invalidando resultados anteriores.
- El chip distingue extracción parcial de vista previa acotada; su visor muestra
  texto extraído/conservado, sin afirmar que sea la selección enviada.

Verificación: regresiones primero rojas y después verdes, suite completa,
flutter analyze, build Windows, reviewer independiente APPROVE y prueba real UI.
Reutilizar dependencias actuales, sin instalaciones, commit ni push. Preservar
cambios preexistentes. Evidencias y límites se registrarán en MEMORY.md.

## Bloqueo inicial de permisos (histórico)

- Implementación candidata preparada inicialmente en `09-candidate-chat_input.txt`; diff en
  `09-CORRECCION-ADJUNTOS-ESCRITURA.patch`, hashes y estado de comprobaciones en
  `09-CORRECCION-ADJUNTOS-ESCRITURA.json`. El original se mantiene sin cambios,
  confirmado por SHA256 durante el bloqueo. En esa fase no se aplicó el arreglo.
- Las cinco regresiones nuevas están en `test/chat_input_context_test.dart` y
  `test/chat_input_interaction_test.dart`: selección sin edición, aceptación y
  foco, estabilidad con historial parcial, streaming y archivo TXT real largo.
- `dart format` del candidato y ambos archivos de pruebas: parseo/formato PASS.
  Esto no acredita lint, tipos ni comportamiento.
- Intento de prueba roja bloqueado antes de ejecutar: Flutter no puede iniciar
  `where aapt` (CreateFile failed 5, acceso denegado). `dart analyze` no puede
  iniciar `dartaotruntime.exe` (acceso denegado). No se han ejecutado pruebas
  rojas/verdes, suite, build ni UI real del candidato.
- Escritura denegada en `lib/widgets/chat_input.dart`, `MEMORY.md` y `.dart_tool`.
  La bitácora provisional queda aquí hasta poder integrarla en MEMORY.md.
  No se alteraron permisos/ACL ni se solicitaron instalaciones.
- Reviewer independiente detectó inicialmente desaparición del aviso de
  historial parcial y falta de prueba con archivo real: candidato y regresiones
  corregidos. Veredicto independiente final: **APPROVE estático**, sin bloqueantes
  identificados; no acredita ejecución. Se incorporó su recomendación de texto
  neutral del historial y aserción positiva del medidor final. No existe tester PASS.
- Continuación: habilitar escritura/ejecución del proyecto y SDK desde el entorno,
  comprobar hashes del original, ejecutar las regresiones rojas, aplicar parche,
  ejecutar verdes/suite/analyze/build y comprobar la UI real antes del cierre.

## Aplicación y verificación tras «HAZLO»

- Se verificaron los hashes originales antes de aplicar. No se sobrescribieron
  cambios ajenos. El candidato y parche reflejan el código final aplicado.
- Regresiones antes del arreglo: 9 PASS / 5 FAIL esperados. Tras aplicar: 14 PASS.
  El primer verde tuvo un fallo de reloj en el arnés del archivo real: la E/S se
  inicia en runAsync y el timer pertenecía al reloj real. Se rearmó la vista
  previa fuera de runAsync, sin cambiar aserciones ni simular la extracción.
- La primera suite detectó una expectativa legacy en el widget aislado sin
  planificador. Ahora exige que se indique vista previa no disponible, sin barra
  ni presupuesto inventados. El código distingue explícitamente ese estado.
- Suite final: 143 PASS y 1 ensayo live opt-in omitido, exit0, 11s. Analyze final:
  No issues found, exit0, 5.3s. Logs con prefijo attachment-editor en .dart_tool.
- Reviewer independiente: APPROVE final del código y pruebas, incluida rama sin
  planificador. En esa fase aún faltaban build y tester nativo.

## Comprobación real y ajuste de etiquetas enviadas

- Tester nativo: TXT35803caracteres por selector Windows, medidor parcial real
  con perfil16k y chip con caracteres conservados. Qwen2.5 devolvió el código
  TOPACIO-58219 y después OK; ambos mensajes finishReason=completed.
- Sin clic adicional tras aceptación, escribió segundo mensaje, movió cursor
  con HOME/RIGHT e insertó EDITADO durante generación. Tras terminar añadió texto
  con tildes. Comparación exacta del borrador PASS en draft-edit-evidence.json.
  El tercer borrador se conservó y baseline modelo/conversación se restauró.
- Las primeras capturas «accepted» y «typing-without-refocus» aún tenían selector
  de carpeta abierto por fallo del invoke UIA; NO acreditan aceptación. Se canceló
  por handle nativo y se usaron las capturas *actual y edición posterior.
- La captura real detectó el mismo tooltip incorrecto y «recortado» ambiguo en
  la burbuja de adjuntos enviados. Ajuste mínimo en message_bubble: visor de texto
  extraído/conservado; extracción parcial tiene prioridad sobre vista previa
  acotada. Comentario del visor alineado. Prueba existente cubre ambos estados.
- Reviewer final APPROVE de este ajuste. Nueva suite144PASS+1opt-inomitido,14s;
  analyze limpio13.0s y build final68.9s,exit0. Sin inferencia simultánea con build.
  Etiquetas y borrador comprobados visualmente al reabrir el build final.

## Cierre

- Tester independiente: PASS final. `final-chip-tooltip-visible.png` acredita
  vista previa acotada y tooltip extraído/conservado; visor y borrador tras
  reinicio comprobados. App final abierta PID7864.
- Modelo y conversación originales restaurados true/true. Una primera lectura
  de restauración se adelantó a la persistencia asíncrona; la confirmación final
  está en final-restoration.json y tester-result.json, sin fallo pendiente.
- Evidencia nativa y límites: `.dart_tool/attachment-editor-20261029/tester-result.json`.
  Logs de analyze/tests/build con prefijo attachment-editor y sufijo final.
- Reviewer APPROVE + tester PASS + analyze/suite/build verdes. MEMORY.md y SDD
  actualizados. Sin instalaciones, commit, push ni cambios de ACL.
