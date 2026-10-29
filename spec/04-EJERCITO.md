# Ejército y flujo de trabajo

Fecha: 2026-10-26. Roles definidos por `C:/Users/INdaHouse/.agents/AGENTS.md` y prompts globales `sd-*.ts`.

- Usuario: aprueba alcance, diseño, prioridades y cualquier instalación.
- Coordinator: lee reglas, memoria y código, propone historias, reúne decisiones y solicita aprobación del plan.
- Scout/researcher: comprueban herramientas existentes y documentación oficial; no instalan sin aprobación. En esta propuesta se reutilizan bibliotecas ya presentes.
- Editor: implementa solo historias aprobadas, por pasos, conservando cambios preexistentes.
- Reviewer: revisión independiente de calidad, seguridad, configuración y mantenibilidad. APPROVE o CHANGES_REQUESTED; no sustituye pruebas.
- Tester: verifica cada criterio con ejecución y evidencia; PASS o FAIL y NO-VERIFICADO donde corresponda.

Flujo: especificación → aprobación del plan por el usuario → implementación → reviewer → correcciones → tester → evidencia y actualización de memoria. No declarar listo sin APPROVE y PASS.

## Revisión de la propuesta (histórico)

El reviewer revisó el código en modo lectura y pidió concretar: presupuesto global, límites por modelo, almacenamiento separado, cobertura parcial de búsqueda, límites de ZIP, archivos OOXML/PDF reales y alcance de la poda. Esos puntos se incorporaron a esta especificación. En la segunda revisión emitió **APPROVE del plan técnico**, pendiente de aprobación del usuario, sin bloqueantes. Recomendó aclarar la creación de spec durante esta sesión, el confinamiento de rutas y la cancelación de selección de carpeta; incorporado. No existe veredicto sobre una implementación nueva ni tester PASS.

## Seguimiento de la implementación

El usuario aprobó el plan y la ampliación de creación de XLSX/PDF en el chat. La primera revisión del código pidió correcciones de almacenamiento, contexto y concurrencia; tras corregirlas emitió APPROVE, registrado en `MEMORY.md` §7. Al retomar el cierre se solicita revisión independiente del estado actual y verificación final del tester. Los veredictos y la evidencia final se registran en la bitácora; el texto histórico anterior no describe el estado actual.

## Veredictos finales — 2026-10-26

- Reviewer independiente: CHANGES_REQUESTED por medidor desactualizado tras cambiar modelo/conversación/historial. Corregido con invalidación por revisión y descarte de respuestas antiguas; re-review **APPROVE**, sin hallazgos pendientes.
- Tester independiente: **PASS** para GEN-01, DOC-01, DOC-02, EXP-01 y guardado/cancelación/error. Analyze limpio, 106 pruebas verdes, build Windows verde y verificación real de Ollama, Office, PDF nativo y guardado desde UI.
- Coordinator: evidencia consolidada en `MEMORY.md` §8, SDD actualizado y limitaciones conservadas. Sin instalaciones, commit ni push. LightChat queda abierto con el build final.
# Ampliación UI — 2026-10-29

- Usuario: aprobó propuestas con «hazlo», eligió modos/fuentes y panel de cálculo,
  habilitó acceso efectivo al entorno y pidió continuar.
- Coordinator/editor: especificación antes de código, candidato temporal durante
  denegación de acceso y aplicación posterior comprobando hashes previos.
- Reviewer independiente: APPROVE del plan; revisiones de borradores, fuentes,
  fórmulas, cierre y normalización Windows; APPROVE estático final tras corregir.
- Root: analyze limpio, 138 pruebas PASS + live real separado PASS. Inferencia
  y build se ejecutan en fases separadas.
- Tester independiente nuevo: PASS nativo en cálculo/exportación, modos/fuentes,
  borradores/reinicio y navegación estrecha. Evidencia y límites en
  .dart_tool/ui-improvements-20261029/tester-result.json y MEMORY.md/spec/07.
- Cierre: reviewer APPROVE + tester PASS + analyze/suite/build verdes y live real.

## Corrección de adjuntos y escritura — 2026-10-29

- Usuario: «HAZLO» tras habilitar acceso al proyecto y ejecución de Flutter.
- Editor: aplica candidato sólo tras verificar hashes; conserva cambios ajenos.
- Reviewer independiente: APPROVE final del código y regresiones, incluida rama
  sin callback de vista previa. No sustituye validación de ejecución.
- Root: cinco regresiones rojas con original, 14 focalizadas verdes tras arreglo;
  suite completa144PASS+1opt-inomitido, analyze limpio y build final PASS68.9s.
- Tester independiente: PASS nativo con dos respuestas reales, escritura/cursor,
  etiquetas y reinicio/borrador. Modelo/chat restaurados true/true; app abierta.
  Evidencia en .dart_tool/attachment-editor-20261029/tester-result.json.
- Cierre: APPROVE + PASS, SDD/memoria actualizados; sin inferencia durante build.

