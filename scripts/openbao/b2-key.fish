#!/usr/bin/env fish
# Stores (or replaces) the B2 application key for bucket wyrd-clickhouse in OpenBao (namespace wyrwood, kv homelab/b2/clickhouse,
# fields key_id and application_key), where role clickhouse reads it. Asks for both without echoing them, then checks
# the key against B2's S3 endpoint (a bucket listing) and reads the secret back. Prints only lengths and results.
#   fish scripts/openbao/b2-key.fish

set path homelab/b2/clickhouse

read --silent --prompt-str 'OpenBao root token: ' token
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token

read --silent --prompt-str 'B2 keyID: ' kid
read --silent --prompt-str 'B2 applicationKey: ' akey
if test -z "$kid"; or test -z "$akey"
    echo "empty value; nothing stored."
    set -e VAULT_TOKEN kid akey
    exit 1
end

# Check the key works before storing it: an S3 ListObjectsV2 on the bucket, signed with the key.
set code (curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 'aws:amz:us-west-004:s3' --user "$kid:$akey" \
    'https://s3.us-west-004.backblazeb2.com/wyrd-clickhouse?list-type=2&max-keys=1')
if test "$code" != 200
    echo "B2 refused the key (HTTP $code); nothing stored."
    set -e VAULT_TOKEN kid akey
    exit 1
end
echo "B2 accepted the key for wyrd-clickhouse."

bao kv put -namespace=wyrwood -mount=kv $path key_id=$kid application_key=$akey >/dev/null
set k2 (bao kv get -namespace=wyrwood -mount=kv -field=key_id $path)
set a2 (bao kv get -namespace=wyrwood -mount=kv -field=application_key $path)
if test "$k2" = "$kid"; and test "$a2" = "$akey"
    echo "stored (key_id length "(string length -- $kid)", application_key length "(string length -- $akey)")"
else
    echo "read-back DIFFERS"
end
set -e VAULT_TOKEN kid akey k2 a2
