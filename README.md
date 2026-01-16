# bot-ip-ranges.sh

Fetch official IP prefix ranges (CIDR) for several bots/providers and output them
in multiple formats (plain text, JSON, nginx, or Apache, which can also be used
in `.htaccess`).

The script pulls published ranges from the vendors' official endpoints and
aggregates them with filters for provider, bot, category, and IP version.

## Features

- Provider and bot registry with dynamic discovery.
- Filters by provider, bot ID, category (search/user), and IP version (v4/v6).
- Multiple output formats for common server configs.
- JSON output includes grouped prefixes per bot.
- Best-effort handling when a source has no prefixes.

## Requirements

- bash 4+ (associative arrays)
- curl
- jq (for JSON sources and JSON output)

## Usage

```bash
./bot-ip-ranges.sh [OPTIONS]
```

### Options

- `-4`                 Output only IPv4 prefixes.
- `-6`                 Output only IPv6 prefixes.
- `-a`, `--all`        Output both IPv4 and IPv6 prefixes (default).
- `-o`, `--output FILE` Write output to `FILE` (default: stdout).
- `--providers LIST`   Comma-separated provider list or `all` (default).
- `--bots LIST`        Comma-separated bot IDs or `all` (default).
- `--exclude-search`   Exclude bots categorized as `search`.
- `--exclude-user`     Exclude bots categorized as `user`.
- `--format FORMAT`    `text` (default), `json`, `nginx`, `apache`.
- `--list-providers`   Print available providers and exit.
- `--list-bots`        Print available bot IDs and exit.
- `-h`, `--help`       Show help and exit.

### Examples

```bash
# All providers, both IPv4 + IPv6 (default)
./bot-ip-ranges.sh

# Only IPv4, one provider
./bot-ip-ranges.sh -4 --providers openai

# Exclude search + user (keeps training/api categories)
./bot-ip-ranges.sh --exclude-search --exclude-user

# Generate Apache/.htaccess snippet
./bot-ip-ranges.sh --providers openai --exclude-user --format apache > .htaccess
```

## Example: cron + .htaccess

Simple cron entry (runs daily; adjust as needed):

```cron
0 3 * * * /path/to/bot-ip-ranges.sh --providers openai --exclude-user --format apache > /var/www/html/.htaccess
```

## Output Formats

- `text`: one CIDR per line (sorted and unique).
- `json`: includes metadata plus:
  - `prefixes`: unique list of all prefixes
  - `bots`: per-bot grouping of prefixes
- `nginx`: `geo` map for IP blocking plus an `if` snippet.
- `apache`: `Require not ip` rules (Apache 2.4+). This format can also be used
  in `.htaccess` if `AllowOverride` permits it (AuthConfig or All).

## Providers and Bots

Providers and bot IDs are registered in the script near the top via
`register_bot`. Use `--list-providers` and `--list-bots` to see the currently
registered values.

### Contributing new bots/providers

Contributions help everyone. If you add new bots or providers, please share
them back to the repository so the community benefits too. To add entries,
edit the registry lines in `bot-ip-ranges.sh#L38-L58` (the `register_bot`
calls), verify the URLs first, and open a PR with your changes.

### Current categories

- `training`
- `search`
- `user`
- `api`

## Notes and Caveats

- Sources are fetched live from vendor endpoints. Network access is required.
- If a bot returns no prefixes, the script prints a warning and continues.
- Anthropic does not publish crawler ranges. The script only includes
  Anthropic API egress IPs (`anthropic:api-egress`) by scraping the HTML
  documentation page using a regex.

## License

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

## Authors

- Lenam
- Chat GPT 5.2-Codex
