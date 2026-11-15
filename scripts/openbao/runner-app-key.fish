#!/usr/bin/env fish
# Imports the homelab runner's GitHub App key into OpenBao Transit (wyrwood namespace), checks that Transit holds the
# same key as the downloaded file, stores the App's ID and login (kv homelab/runner), and offers to delete the file.
# For a first import: Transit refuses to import over an existing key.
#   fish scripts/openbao/runner-app-key.fish <downloaded .pem>

set pem $argv[1]
if test -z "$pem"
    echo "usage: fish scripts/openbao/runner-app-key.fish <downloaded .pem>"
    exit 2
end
set app_login 'langley-homlab-runner[bot]'
set key gh-app-homelab-runner

if not test -f $pem
    echo "Not found: $pem"
    exit 1
end

read --prompt-str 'GitHub App ID: ' app_id
if not string match --quiet --regex '^[0-9]+$' -- $app_id
    echo "The App ID should be a number."
    exit 1
end
read --silent --prompt-str 'OpenBao root token: ' token

# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token

set der (openssl pkcs8 -topk8 -nocrypt -in $pem -outform DER | base64 -w0)
bao transit import -namespace=wyrwood transit/keys/$key $der type=rsa-2048
or begin
    set -e BAO_TOKEN VAULT_TOKEN der
    echo "Import failed; the key file is untouched."
    exit 1
end
set -e der

set transit_hash (bao read -namespace=wyrwood -format=json transit/keys/$key \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"]["keys"]["1"]["public_key"], end="")' \
    | openssl pkey -pubin -outform DER | sha256sum | string split -f1 ' ')
set file_hash (openssl pkey -in $pem -pubout -outform DER | sha256sum | string split -f1 ' ')
echo "Transit: $transit_hash"
echo "File:    $file_hash"

if test "$transit_hash" != "$file_hash"
    set -e BAO_TOKEN VAULT_TOKEN
    echo "MISMATCH: kept the key file. Don't store the App details yet."
    exit 1
end
echo "Match."

bao kv put -namespace=wyrwood -mount=kv homelab/runner app_id=$app_id app_login=$app_login
set -e BAO_TOKEN VAULT_TOKEN

read --prompt-str "Delete $pem now? [y/N] " answer
if test "$answer" = y -o "$answer" = Y
    shred -u $pem
    and echo "Deleted."
else
    echo "Kept. Delete it later with: shred -u $pem"
end
