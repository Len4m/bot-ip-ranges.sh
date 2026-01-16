# bot-ip-ranges.sh

Obtiene rangos oficiales de prefijos IP (CIDR) para varios bots/proveedores y
los entrega en múltiples formatos (texto, JSON, nginx o Apache, que también se
puede usar en `.htaccess`).

El script consulta endpoints oficiales publicados por cada proveedor y agrega
los rangos con filtros por proveedor, bot, categoría y versión de IP.

## Características

- Registro de proveedores/bots con descubrimiento dinámico.
- Filtros por proveedor, ID de bot, categoría (search/user) y versión de IP (v4/v6).
- Varios formatos de salida para configuraciones comunes de servidores.
- Salida JSON con agrupación de prefijos por bot.
- Manejo best-effort cuando una fuente no devuelve prefijos.

## Requisitos

- bash 4+ (arrays asociativos)
- curl
- jq (para fuentes JSON y salida JSON)

## Uso

```bash
./bot-ip-ranges.sh [OPTIONS]
```

### Opciones

- `-4`                 Solo prefijos IPv4.
- `-6`                 Solo prefijos IPv6.
- `-a`, `--all`        IPv4 e IPv6 (por defecto).
- `-o`, `--output FILE` Escribe la salida en `FILE` (por defecto: stdout).
- `--providers LIST`   Lista de proveedores separada por comas o `all` (por defecto).
- `--bots LIST`        Lista de IDs de bot separada por comas o `all` (por defecto).
- `--exclude-search`   Excluye bots con categoría `search`.
- `--exclude-user`     Excluye bots con categoría `user`.
- `--format FORMAT`    `text` (por defecto), `json`, `nginx`, `apache`.
- `--list-providers`   Muestra proveedores disponibles y termina.
- `--list-bots`        Muestra IDs de bots disponibles y termina.
- `-h`, `--help`       Muestra la ayuda y termina.

### Ejemplos

```bash
# Todos los proveedores, IPv4 + IPv6 (por defecto)
./bot-ip-ranges.sh

# Solo IPv4, un proveedor
./bot-ip-ranges.sh -4 --providers openai

# Excluir search + user (mantiene training/api)
./bot-ip-ranges.sh --exclude-search --exclude-user

# Generar snippet Apache/.htaccess
./bot-ip-ranges.sh --providers openai --exclude-user --format apache > .htaccess
```

## Ejemplo: cron + .htaccess

Entrada de cron sencilla (diaria; ajusta si lo necesitas):

```cron
0 3 * * * /ruta/a/bot-ip-ranges.sh --providers openai --exclude-user --format apache > /var/www/html/.htaccess
```

## Formatos de salida

- `text`: un CIDR por línea (ordenado y único).
- `json`: incluye metadatos más:
  - `prefixes`: lista única de todos los prefijos
  - `bots`: agrupación por bot de prefijos
- `nginx`: bloque `geo` para bloqueo por IP + snippet `if`.
- `apache`: reglas `Require not ip` (Apache 2.4+). Este formato también se
  puede usar en `.htaccess` si `AllowOverride` lo permite (AuthConfig o All).

## Proveedores y bots

Los proveedores y IDs de bots se registran en el script cerca del inicio con
`register_bot`. Usa `--list-providers` y `--list-bots` para ver los valores
actuales.

### Colaborar con nuevos bots/proveedores

Las contribuciones benefician a todos. Si añades nuevos bots o proveedores,
por favor compártelos también en el repositorio para que la comunidad se
beneficie. Para introducirlos, solo edita las líneas de registro en
`bot-ip-ranges.sh#L38-L58` (llamadas a `register_bot`), verifica primero las
URLs y crea un PR con el cambio.

### Categorías actuales

- `training`
- `search`
- `user`
- `api`

## Notas y consideraciones

- Las fuentes se consultan en vivo desde endpoints oficiales; se requiere red.
- Si un bot no devuelve prefijos, el script emite un warning y continúa.
- Anthropic no publica rangos de crawlers. El script solo incluye IPs de
  salida de la API (`anthropic:api-egress`) extrayéndolas de la página HTML
  mediante una regex.

## Licencia

GNU General Public License v3.0

Copyright (c) 2025 Lenam

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.

## Autores

- Lenam
- Chat GPT 5.2-Codex
