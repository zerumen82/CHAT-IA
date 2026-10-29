# Principios y definición de listo

Fecha: 2026-10-26. Especificación inicial del estado observado y de la propuesta documental. Las historias propuestas requieren aprobación del usuario antes de implementar.

- Autoridad: reglas globales de `C:/Users/INdaHouse/.agents/AGENTS.md`, instrucciones del usuario y `../AGENTS.md`.
- El usuario aprueba alcance, diseño, dependencias y prioridades. Seleccionar opciones de alcance no equivale a aprobar toda la implementación.
- NO HARDCODE: presupuestos, límites de extracción, rutas y perfiles se centralizan en la configuración.
- NO STUB / NO FAKE: exportar genera archivos válidos; un resultado solo se afirma con evidencia ejecutada.
- LOCAL-FIRST: documentos, extracción, búsqueda e inferencia permanecen locales. Catálogo y descarga de modelos son las conexiones externas existentes.
- No instalar paquetes, modelos ni skills sin aprobación explícita. La propuesta reutiliza las dependencias actuales.
- Conservar decisiones de `MEMORY.md`: Ollama único, reparto entre todos los documentos/hojas, configuración de contexto estable entre peticiones, conversaciones compatibles.
- Registrar decisiones, revisiones, pruebas, fallos y límites en `MEMORY.md`, respetando las modificaciones preexistentes del usuario.

## Definición de listo para implementación

Historia aprobada y especificada; código ejecutado; `flutter analyze` sin incidencias; `flutter test` verde; `flutter build windows --no-pub` verde; reviewer APPROVE; tester PASS; prueba real con Ollama/UI y archivos exportados abiertos; evidencia y deudas registradas. Un documento de planificación no acredita funcionalidad implementada.
