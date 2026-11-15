#!/usr/bin/env fish
# Stores a Docker host's Arcane agent token, from the environment created for the host in Arcane, in OpenBao
# (namespace wyrwood, kv homelab/hosts/<host>/arcane, field agent_token), where role docker_agent reads it. Asks for
# the token without echoing it. Replaces a token already there. Prints only its length.
#   fish scripts/openbao/arcane-agent-token.fish <host, such as ser6-p.internal>

set host $argv[1]
if not string match --quiet --regex '^[a-z0-9-]+\.internal$' -- "$host"
    echo "usage: fish scripts/openbao/arcane-agent-token.fish <host>.internal"
    exit 2
end
set path homelab/hosts/$host/arcane

read --silent --prompt-str 'OpenBao root token: ' token
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token

read --silent --prompt-str "Arcane agent token for $host: " t
if test (string length -- "$t") -lt 16; or string match --quiet --regex '\s' -- "$t"
    echo "that doesn't look like an agent token; nothing stored."
    set -e VAULT_TOKEN t
    exit 1
end
bao kv put -namespace=wyrwood -mount=kv $path agent_token=$t >/dev/null
if test (bao kv get -namespace=wyrwood -mount=kv -field=agent_token $path) = "$t"
    echo "$host: stored (length "(string length -- $t)")"
else
    echo "$host: read-back DIFFERS"
end
set -e t VAULT_TOKEN
