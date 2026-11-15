#!/usr/bin/env fish
# Creates the webhook secret for one GitHub organization or account: 64 hex characters, in OpenBao (namespace
# wyrwood, kv homelab/trowel/github/<owner>, field webhook_secret), where Trowel verifies /github/<owner>. Add the
# owner to trowel_github_orgs. Kept if it exists already. Prints only its length; to paste it into GitHub's webhook
# settings, read it with:
#   bao kv get -namespace=wyrwood -mount=kv -field=webhook_secret homelab/trowel/github/<owner>
#
#   fish scripts/openbao/trowel-github-secret.fish <owner>

set owner $argv[1]
if not string match --quiet --regex '^[A-Za-z0-9][A-Za-z0-9-]*$' -- "$owner"
    echo "usage: fish scripts/openbao/trowel-github-secret.fish <owner>"
    exit 2
end
set path homelab/trowel/github/$owner

read --silent --prompt-str 'OpenBao root token: ' token
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token

# 0: stored; 1: not stored; 2: OpenBao refused or couldn't be reached (error printed). A failed read must never be
# taken for "not stored", which would go on to create and overwrite.
function kv_exists -a p
    set err (bao kv get -namespace=wyrwood -mount=kv $p 2>&1 >/dev/null)
    and return 0
    string match --quiet '*No value found*' -- "$err"; and return 1
    printf '%s\n' $err >&2
    return 2
end
kv_exists $path
switch $status
    case 0
        echo "$owner: already in OpenBao, kept"
        set -e BAO_TOKEN VAULT_TOKEN
        exit 0
    case 2
        echo "$owner: can't read $path from $BAO_ADDR; nothing stored."
        set -e BAO_TOKEN VAULT_TOKEN
        exit 1
end
set s (openssl rand -hex 32)
bao kv put -namespace=wyrwood -mount=kv $path webhook_secret=$s >/dev/null
# Quoted: an empty read-back must not reach test's error message, which would print the secret.
if test "$(bao kv get -namespace=wyrwood -mount=kv -field=webhook_secret $path)" = "$s"
    echo "$owner: stored (length "(string length -- $s)")"
else
    echo "$owner: read-back DIFFERS"
end
set -e s BAO_TOKEN VAULT_TOKEN
