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
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token

if bao kv get -namespace=wyrwood -mount=kv -field=webhook_secret $path >/dev/null 2>&1
    echo "$owner: already in OpenBao, kept"
    set -e VAULT_TOKEN
    exit 0
end
set s (openssl rand -hex 32)
bao kv put -namespace=wyrwood -mount=kv $path webhook_secret=$s >/dev/null
if test (bao kv get -namespace=wyrwood -mount=kv -field=webhook_secret $path) = "$s"
    echo "$owner: stored (length "(string length -- $s)")"
else
    echo "$owner: read-back DIFFERS"
end
set -e s VAULT_TOKEN
