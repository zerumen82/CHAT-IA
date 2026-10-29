# Bitácora de revisión — 2026-10-26

> Registro histórico de la propuesta inicial. Integrado en `MEMORY.md` §7 y §8 una vez disponible la escritura. La implementación aprobada y su verificación final están terminadas; este texto conserva las circunstancias originales y no representa el estado actual.

Registro provisional porque escribir `MEMORY.md` fue denegado tanto con `apply_patch` como con `Add-Content -ErrorAction Stop`: `Access to the path 'D:/PROJECTS/LITGHCHAT/lightchat/MEMORY.md' is denied.` No se modificaron permisos ni se solicitó elevación. Pendiente incorporar esta entrada a MEMORY cuando su escritura esté disponible.

## Petición y elecciones

Ampliar contexto documental, exportación y revisión de mejoras. El usuario eligió explícitamente respuestas/conversaciones a TXT, Markdown, PDF y DOCX; contexto configurable hasta 32k, documentos persistentes y búsqueda local de fragmentos. Pendiente aprobación del plan completo. No se implementó funcionalidad ni se instaló ningún paquete, modelo o skill.

## Revisión y evidencia

- Leídos reglas globales/locales, MEMORY.md, skill plan, código y pruebas existentes. Creado SDD en spec/00 a 04, plan concreto en spec/05. Escribir el plan en plans/ falló y se conservó en spec/.
- Hallazgos: contexto fijo 16.384 tokens pese a modelos con límites menores; recortes 16.000/documento, 24.000/envío y 8.000/seguimiento; últimos diez mensajes/último turno documental; avisos incompletos; medidor y visor distintos de petición final; columnas omitidas sin marca; exportaciones ausentes; poda del historial limita exportación.
- `GET http://localhost:11434/api/tags` respondió con modelos instalados; `GET /api/ps` → `models: []`.
- `POST /api/show` → Qwen2.5 32.768, Llama3 8.192 y Wizard-Vicuna 2.048 tokens.
- `nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader` → `NVIDIA GeForce RTX 3060 Ti, 8192 MiB, 7109 MiB`. Las consultas CIM de RAM/GPU fueron denegadas.
- No se ejecutó inferencia a 32k: viabilidad y velocidad SIN VERIFICAR. No convertir metadata en promesa de rendimiento.
- Fuentes oficiales consultadas: https://docs.ollama.com/context-length y API de PdfDocument de Syncfusion 35.1.41. Creación PDF soportada por dependencia actual; DOCX OOXML propuesto con ZIP/XML actuales, pendiente de implementación y apertura real.
- Reviewer independiente: CHANGES_REQUESTED inicial por riesgos no concretados; incorporados a spec; segunda revisión **APPROVE del plan técnico**, sin bloqueantes, pendiente aprobación del usuario. Recomendaciones menores incorporadas: estado inicial de spec, confinamiento de rutas y cancelación de carpeta.
- Estado git preexistente con modificaciones y borrados en código, pruebas, documentos y artefactos: preservado. Git de Cygwin falló con Win32 error 5; funcionó `C:/Program Files/Git/cmd/git.exe`.
- No se ejecutaron lint/build/suite porque solo se redactaron especificación y plan. No hay tester PASS ni afirmación de nueva funcionalidad lista. Verificaciones de implementación constan en spec/05.
