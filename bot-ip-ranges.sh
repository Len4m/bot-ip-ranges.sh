#!/usr/bin/env bash
set -euo pipefail

# bot-ip-ranges.sh
#
# Fetch official IP prefix ranges (CIDR) for several bots/providers using curl + jq.
# Outputs one prefix per line (text), or other formats via --format.
#
# Requirements:
#   - bash 4+ (associative arrays)
#   - curl
#   - jq (for JSON sources and JSON output)
#
# Notes:
#   - Anthropic does NOT publish crawler IP ranges; only API egress IPs are published (HTML page).
#     We include those as a special "bot" (anthropic:api-egress) and extract CIDRs via regex.

#######################################
# Configuration: bot registry
#######################################

# Each bot has:
#   - URL
#   - provider   (derived from your registration)
#   - category: training | search | user | api

declare -A BOT_URL=()
declare -A BOT_PROVIDER=()
declare -A BOT_CATEGORY=()

register_bot() {
  local id="$1" provider="$2" category="$3" url="$4"
  BOT_URL["$id"]="$url"
  BOT_PROVIDER["$id"]="$provider"
  BOT_CATEGORY["$id"]="$category"
}

# ---- Register bots here ----
# OpenAI
register_bot "openai:gptbot"           "openai"     "training" "https://openai.com/gptbot.json"
register_bot "openai:oai-searchbot"    "openai"     "search"   "https://openai.com/searchbot.json"
register_bot "openai:chatgpt-user"     "openai"     "user"     "https://openai.com/chatgpt-user.json"

# Perplexity
register_bot "perplexity:perplexitybot"   "perplexity" "search" "https://www.perplexity.ai/perplexitybot.json"
register_bot "perplexity:perplexity-user" "perplexity" "user"   "https://www.perplexity.ai/perplexity-user.json"

# Google
register_bot "google:googlebot"                        "google" "search" "https://developers.google.com/static/search/apis/ipranges/googlebot.json"
register_bot "google:special-crawlers"                 "google" "search" "https://developers.google.com/static/search/apis/ipranges/special-crawlers.json"
register_bot "google:user-triggered-fetchers"          "google" "user"   "https://developers.google.com/static/search/apis/ipranges/user-triggered-fetchers.json"
register_bot "google:user-triggered-fetchers-google"   "google" "user"   "https://developers.google.com/static/search/apis/ipranges/user-triggered-fetchers-google.json"

# Microsoft (Bing)
register_bot "microsoft:bingbot" "microsoft" "search" "https://www.bing.com/toolbox/bingbot.json"

# Anthropic (API egress IPs; NOT crawler IPs)
register_bot "anthropic:api-egress" "anthropic" "api" "https://platform.claude.com/docs/en/api/ip-addresses"
# ----------------------------

#######################################
# Helpers: dynamic providers/bots
#######################################

list_providers() {
  # Providers are derived dynamically from registered bots.
  local providers=()
  for id in "${!BOT_PROVIDER[@]}"; do
    providers+=("${BOT_PROVIDER[$id]}")
  done
  printf "%s\n" "${providers[@]}" | sort -u
}

list_bots() {
  # Bots are derived dynamically from registered bots.
  for id in "${!BOT_URL[@]}"; do
    printf "%-35s  provider=%-12s  category=%-8s  url=%s\n" \
      "$id" "${BOT_PROVIDER[$id]}" "${BOT_CATEGORY[$id]}" "${BOT_URL[$id]}"
  done | sort
}

providers_csv() {
  # Pretty print providers as "a,b,c"
  list_providers | paste -sd, - 2>/dev/null || list_providers | tr '\n' ',' | sed 's/,$//'
}

#######################################
# CLI defaults
#######################################
IP_MODE="all"            # 4 | 6 | all
OUTPUT_FILE=""           # if empty => stdout
PROVIDERS="all"          # comma list or all
BOTS="all"               # comma list or all
EXCLUDE_SEARCH=0
EXCLUDE_USER=0
FORMAT="text"            # text | json | nginx | apache

usage() {
  cat <<EOF
Usage:
  bot-ip-ranges.sh [OPTIONS]

Options:
  -4                     Output only IPv4 prefixes
  -6                     Output only IPv6 prefixes
  -a, --all              Output both IPv4 and IPv6 prefixes (default)

  -o, --output FILE      Write output to FILE. If omitted, prints to stdout.

  --providers LIST       Comma-separated provider list or "all" (default).
                         Providers are derived from registered bots.
                         Available now: $(providers_csv)
                         Tip: use --list-providers

  --bots LIST            Comma-separated bot IDs or "all" (default).
                         Tip: use --list-bots

  --exclude-search       Exclude bots categorized as "search"
  --exclude-user         Exclude bots categorized as "user"

  --format FORMAT        Output format: text (default), json, nginx, apache

  --list-providers       Print available providers and exit
  --list-bots            Print available bot IDs and exit
  -h, --help             Show this help and exit

Examples:
  # All providers, both IPv4+IPv6 (default):
  ./bot-ip-ranges.sh

  # Only IPv4, one provider:
  ./bot-ip-ranges.sh -4 --providers openai

  # Exclude search + user (keeps training/api categories):
  ./bot-ip-ranges.sh --exclude-search --exclude-user

  # Generate Apache/.htaccess snippet:
  ./bot-ip-ranges.sh --providers openai --exclude-user --format apache > .htaccess
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_cmds() {
  command -v curl >/dev/null 2>&1 || die "curl is required"
  command -v jq   >/dev/null 2>&1 || die "jq is required"
}

split_csv() {
  local s="${1:-}"
  [[ -n "$s" ]] || return 0
  tr ',' '\n' <<<"$s" | sed '/^[[:space:]]*$/d' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

#######################################
# Fetchers
#######################################

fetch_json_prefixes() {
  local url="$1"
  local mode="$2" # 4 | 6 | all

  # Recursive scan for keys ipv4Prefix/ipv6Prefix to be resilient to schema differences.
  local jq_filter
  case "$mode" in
    4)   jq_filter='.. | objects | .ipv4Prefix? // empty' ;;
    6)   jq_filter='.. | objects | .ipv6Prefix? // empty' ;;
    all) jq_filter='.. | objects | (.ipv4Prefix? // empty), (.ipv6Prefix? // empty)' ;;
    *)   die "Invalid IP mode: $mode" ;;
  esac

  curl -fsSL "$url" | jq -r "$jq_filter"
}

fetch_anthropic_api_egress() {
  local url="$1"
  local mode="$2" # 4 | 6 | all

  # Anthropic page is HTML; extract CIDRs via regex (best-effort).
  local page
  page="$(curl -fsSL "$url")"

  if [[ "$mode" == "4" || "$mode" == "all" ]]; then
    grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}' <<<"$page" || true
  fi

  if [[ "$mode" == "6" || "$mode" == "all" ]]; then
    grep -Eoi '([0-9a-f]{0,4}:){2,7}[0-9a-f]{0,4}/[0-9]{1,3}' <<<"$page" || true
  fi
}

fetch_bot() {
  local bot_id="$1"
  local mode="$2"

  local url="${BOT_URL[$bot_id]:-}"
  [[ -n "$url" ]] || die "Unknown bot id: $bot_id"

  if [[ "$bot_id" == "anthropic:api-egress" ]]; then
    fetch_anthropic_api_egress "$url" "$mode"
  else
    fetch_json_prefixes "$url" "$mode"
  fi
}

#######################################
# Output formatters
#######################################

emit_text() {
  local union_file="$1"
  sed '/^[[:space:]]*$/d' "$union_file" | sort -u
}

emit_json() {
  local union_file="$1"
  local bot_tsv_file="$2"
  local generated_at
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -Rn \
    --arg generated_at "$generated_at" \
    --arg ip_mode "$IP_MODE" \
    --arg format "$FORMAT" \
    --arg providers "$PROVIDERS" \
    --arg bots "$BOTS" \
    --argjson exclude_search "$EXCLUDE_SEARCH" \
    --argjson exclude_user "$EXCLUDE_USER" \
    --slurpfile union <(sed '/^[[:space:]]*$/d' "$union_file" | sort -u | jq -R . | jq -s .) \
    --slurpfile rows <(awk -F"\t" 'NF==2 {print $0}' "$bot_tsv_file" | jq -R 'split("\t") | {bot:.[0], prefix:.[1]}' | jq -s .) \
    '
      def groupBots($rows):
        ($rows
          | group_by(.bot)
          | map({ (.[0].bot): (map(.prefix) | unique) })
          | add);

      {
        generated_at: $generated_at,
        format: $format,
        ip_mode: $ip_mode,
        selection: {
          providers: $providers,
          bots: $bots,
          exclude_search: ($exclude_search == 1),
          exclude_user: ($exclude_user == 1)
        },
        prefixes: $union[0],
        bots: groupBots($rows[0])
      }
    '
}

emit_nginx() {
  local union_file="$1"

  cat <<'N1'
# Nginx snippet: block by IP CIDRs
#
# Put the `geo` block in the `http {}` context (e.g., nginx.conf),
# and the `if`/return in the relevant `server {}` or `location {}`.

# --- http {} context ---
geo $block_ai_bots {
    default 0;
N1

  sed '/^[[:space:]]*$/d' "$union_file" | sort -u | sed 's/^/    /; s/$/ 1;/'

  cat <<'N2'
}

# --- server {} or location {} context ---
if ($block_ai_bots) {
    return 403;
}
N2
}

emit_apache() {
  local union_file="$1"

  cat <<'A1'
# Apache 2.4+ snippet: block by IP CIDRs
#
# Place this inside the appropriate context (VirtualHost, Directory, Location, etc.).
# You can also use it in .htaccess if AllowOverride permits it (AuthConfig or All).

<RequireAll>
    Require all granted
A1

  sed '/^[[:space:]]*$/d' "$union_file" | sort -u | sed 's/^/    Require not ip /'

  cat <<'A2'
</RequireAll>
A2
}

write_output() {
  local content="$1"
  if [[ -n "$OUTPUT_FILE" ]]; then
    printf "%s\n" "$content" >"$OUTPUT_FILE"
    echo "Wrote output to: $OUTPUT_FILE" >&2
  else
    printf "%s\n" "$content"
  fi
}

#######################################
# Argument parsing
#######################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    -4) IP_MODE="4"; shift ;;
    -6) IP_MODE="6"; shift ;;
    -a|--all) IP_MODE="all"; shift ;;

    -o|--output)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      OUTPUT_FILE="$2"
      shift 2
      ;;

    --providers)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      PROVIDERS="$2"
      shift 2
      ;;

    --bots)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      BOTS="$2"
      shift 2
      ;;

    --exclude-search) EXCLUDE_SEARCH=1; shift ;;
    --exclude-user)   EXCLUDE_USER=1; shift ;;

    --format)
      [[ $# -ge 2 ]] || die "Missing value for $1"
      FORMAT="$2"
      shift 2
      ;;

    --list-providers) list_providers; exit 0 ;;
    --list-bots)      list_bots; exit 0 ;;

    -h|--help) usage; exit 0 ;;
    *)
      die "Unknown option: $1 (use --help)"
      ;;
  esac
done

case "$FORMAT" in
  text|json|nginx|apache) : ;;
  *) die "Invalid --format: $FORMAT (use: text|json|nginx|apache)" ;;
esac

require_cmds

#######################################
# Selection logic (dynamic providers)
#######################################

# Build a set of available providers from the registry, for validation + selection.
declare -A AVAILABLE_PROVIDER=()
while read -r p; do
  [[ -n "$p" ]] && AVAILABLE_PROVIDER["$p"]=1
done < <(list_providers)

# Build selected provider set
declare -A WANT_PROVIDER=()
if [[ "$PROVIDERS" == "all" ]]; then
  for p in "${!AVAILABLE_PROVIDER[@]}"; do
    WANT_PROVIDER["$p"]=1
  done
else
  while read -r p; do
    [[ -n "$p" ]] || continue
    if [[ -z "${AVAILABLE_PROVIDER[$p]:-}" ]]; then
      die "Unknown provider '$p'. Available: $(providers_csv)"
    fi
    WANT_PROVIDER["$p"]=1
  done < <(split_csv "$PROVIDERS")
fi

# Build selected bot list
selected_bots=()
if [[ "$BOTS" == "all" ]]; then
  while read -r id; do
    selected_bots+=("$id")
  done < <(printf "%s\n" "${!BOT_URL[@]}" | sort)
else
  while read -r id; do
    [[ -n "$id" ]] || continue
    selected_bots+=("$id")
  done < <(split_csv "$BOTS")
fi

#######################################
# Fetch, filter, deduplicate
#######################################

tmp_union="$(mktemp)"
tmp_bot_tsv="$(mktemp)"
trap 'rm -f "$tmp_union" "$tmp_bot_tsv"' EXIT

for bot_id in "${selected_bots[@]}"; do
  [[ -n "${BOT_URL[$bot_id]:-}" ]] || die "Unknown bot id in --bots: $bot_id"

  provider="${BOT_PROVIDER[$bot_id]}"
  category="${BOT_CATEGORY[$bot_id]}"

  # Provider filter
  [[ -n "${WANT_PROVIDER[$provider]:-}" ]] || continue

  # Category exclusions
  if [[ "$EXCLUDE_SEARCH" -eq 1 && "$category" == "search" ]]; then
    continue
  fi
  if [[ "$EXCLUDE_USER" -eq 1 && "$category" == "user" ]]; then
    continue
  fi

  # Fetch (best-effort per bot)
  prefixes="$(fetch_bot "$bot_id" "$IP_MODE" 2>/dev/null || true)"
  if [[ -z "${prefixes:-}" ]]; then
    echo "WARN: no prefixes fetched for $bot_id (${BOT_URL[$bot_id]})" >&2
    continue
  fi

  # Append to union and record per-bot for JSON grouping.
  while IFS= read -r line; do
    [[ -n "${line// /}" ]] || continue
    printf "%s\n" "$line" >>"$tmp_union"
    printf "%s\t%s\n" "$bot_id" "$line" >>"$tmp_bot_tsv"
  done <<<"$prefixes"
done

#######################################
# Emit
#######################################
output=""
case "$FORMAT" in
  text)     output="$(emit_text "$tmp_union")" ;;
  json)     output="$(emit_json "$tmp_union" "$tmp_bot_tsv")" ;;
  nginx)    output="$(emit_nginx "$tmp_union")" ;;
  apache)   output="$(emit_apache "$tmp_union")" ;;
esac

write_output "$output"
