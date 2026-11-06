# spec/10 — Búsqueda web y Tor

## Objetivo
Permitir que un modelo con herramientas consulte internet mediante una
búsqueda web normal y, si el usuario lo pide, en la red Tor (deep web),
sin ejecución de código ni acceso a URLs arbitrarias.

## Alcance
- Herramienta `web_search` para modelos Ollama con `supportsTools`.
- Parámetro `source`: `web` (por defecto, DuckDuckGo Instant Answer API) o
  `tor` (motores .onion vía proxy SOCKS5 local de Tor).
- Fuente web: DuckDuckGo Instant Answer API (sin API key).
- Fuente tor: proxy SOCKS5 en 127.0.0.1:9050 o 9150 (Tor o Tor Browser en ejecución);
  consulta el índice .onion de Ahmia y devuelve enlaces .onion.
- Sin claves nuevas. Dependencia `socks5_proxy` para el proxy SOCKS5.
- El modelo puede pedir una o varias búsquedas; la app ejecuta la consulta y
  devuelve resumen/temas relacionados, luego el modelo responde citando fuentes.
- No se permite fetch arbitrario de páginas ni ejecución de código.

## Fuera de alcance
- Fetch arbitrario de URLs.
- Búsqueda en proveedores cloud (sus modelos pueden tener búsqueda propia).
- Instalación automática de Tor (responsabilidad del usuario).

## Notas
- `source="tor"` requiere Tor en ejecución; si no está disponible, la
  herramienta devuelve error claro.
- Los enlaces .onion requieren Tor Browser para abrirse. En el chat, pulsar un
  enlace .onion muestra un aviso con copia al portapapeles y apertura en Tor
  Browser si está detectado; los enlaces http/https abren el navegador del sistema.