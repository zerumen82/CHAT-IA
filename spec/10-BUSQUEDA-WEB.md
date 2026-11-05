# spec/10 — Búsqueda web normal

## Objetivo
Permitir que un modelo con herramientas consulte internet mediante una
búsqueda web normal y segura, sin acceso a la dark net ni ejecución de código.

## Alcance
- Herramienta `web_search` para modelos Ollama con `supportsTools`.
- Fuente: DuckDuckGo Instant Answer API (sin API key).
- Sin claves nuevas, sin dependencias nuevas.
- El modelo puede pedir una o varias búsquedas; la app ejecuta la consulta y
  devuelve resumen/temas relacionados, luego el modelo responde citando fuentes.
- No se permite acceso a la dark net ni a URLs arbitrarias.

## Fuera de alcance
- Acceso a la dark net.
- Fetch arbitrario de páginas.
- Búsqueda en proveedores cloud (sus modelos pueden tener búsqueda propia).
"""