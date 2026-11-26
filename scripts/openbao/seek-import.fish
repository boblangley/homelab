#!/usr/bin/env fish
# Import a provider-key JSON file using the current OpenBao credentials.
# The fields keep Seek 0.3's variable names. Role seek maps each field to a Seek 0.4 setting in its server.yml
# (GEMINI_API_KEY is the `google` provider), so the secret needs no change between 0.3 and 0.4.
if test (count $argv) -ne 1
    echo 'Usage: fish scripts/openbao/seek-import.fish <provider-keys.json>' >&2
    exit 2
end

# Slurp to reject multiple JSON documents. Keep values out of command arguments.
set -l keys (jq -ces '
    ["PARALLEL_API_KEY", "EXA_API_KEY", "BRAVE_SEARCH_API_KEY",
     "BRAVE_ANSWERS_API_KEY", "PERPLEXITY_API_KEY", "GEMINI_API_KEY",
     "FIRECRAWL_API_KEY"] as $required
    | select(length == 1) | .[0] | select(type == "object")
    | select(keys == ($required | sort))
    | select(all(.[]; type == "string" and test("[^[:space:]]") and . != "<REDACTED>"))
' -- "$argv[1]" 2>/dev/null)
or begin
    echo 'Expected one JSON object with all seven Seek provider keys as nonempty strings.' >&2
    exit 2
end

set -l token (openssl rand -hex 32)
or exit 1
set -l secret (printf '%s\n' "$keys" "$token" | jq -cRs 'split("\n") | (.[0] | fromjson) + {SEEK_SERVER_TOKEN: .[1]}')
or exit 1

# CAS 0 makes this a first import and protects an existing token on reruns.
printf '%s\n' "$secret" | bao kv put -namespace=wyrwood -mount=kv -cas=0 homelab/seek - >/dev/null
or exit 1
echo 'Stored the provider keys and generated client token in wyrwood / kv / homelab/seek.'
