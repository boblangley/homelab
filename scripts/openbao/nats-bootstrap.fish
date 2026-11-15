#!/usr/bin/env fish
# Sets up NATS's operator (JWT) mode from nothing: issues operator homelab, accounts SYS and APP (JetStream on, unlimited), and the
# users below, each with its permissions in its user JWT. nsc runs in a throwaway nats-box container whose working
# directory is in memory (--tmpfs); its output passes through a 0700 directory in /dev/shm (memory) on its way into
# OpenBao, and is shredded there. Stores, in namespace wyrwood, kv:
#   homelab/nats/nsc         tgz: the nsc stores and keys (operator, account and user seeds), base64, to issue or
#                            change users later
#   homelab/nats/server      resolver: the server's operator JWT, system account and preloaded account JWTs
#   homelab/nats/<user>      creds: the user's .creds file
#   xolotl/nats              creds: Xolotl's copy of its login
# Stops without changing anything if homelab/nats/nsc exists; add users later with nats-user.fish.
# Prints only names, lengths and results.
#   fish scripts/openbao/nats-bootstrap.fish

set users admin workspace xolotl clickhouse trowel

read --silent --prompt-str 'OpenBao root token: ' token
set -x VAULT_ADDR https://openbao.internal:8200
set -x VAULT_TOKEN $token
set -e token
function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end
function fail
    echo $argv
    set -e -g VAULT_TOKEN
    exit 1
end

if kv get homelab/nats/nsc >/dev/null 2>&1
    fail "homelab/nats/nsc exists already; nothing changed."
end

# Runs in the container. Permissions are those of the current users; admin and workspace are unrestricted.
set inner '
set -eu
export HOME=/nsc NKEYS_PATH=/nsc/keys NSC_HOME=/nsc/nsc
mkdir -p /nsc/out
nsc env -s /nsc/stores >/dev/null 2>&1
nsc add operator --name homelab --sys --generate-signing-key >/dev/null 2>&1
nsc add account APP >/dev/null 2>&1
nsc edit account APP --js-enable 1 >/dev/null 2>&1
nsc add user -a APP admin >/dev/null 2>&1
nsc add user -a APP workspace >/dev/null 2>&1
nsc add user -a APP xolotl \
  --allow-pub "xolotl.exchanges.>,\$JS.API.STREAM.INFO.XOLOTL" --allow-sub "_INBOX.>" >/dev/null 2>&1
nsc add user -a APP clickhouse \
  --allow-pub "\$JS.API.CONSUMER.MSG.NEXT.XOLOTL.clickhouse,\$JS.API.CONSUMER.INFO.XOLOTL.clickhouse,\$JS.API.STREAM.INFO.XOLOTL,\$JS.ACK.XOLOTL.clickhouse.>" \
  --allow-sub "_INBOX.>" >/dev/null 2>&1
nsc add user -a APP trowel --allow-pub "github.>" --allow-sub "_INBOX.>" >/dev/null 2>&1
for u in admin workspace xolotl clickhouse trowel; do
  nsc generate creds -a APP -n $u -o /nsc/out/$u.creds >/dev/null 2>&1
done
nsc generate config --mem-resolver --sys-account SYS > /nsc/out/resolver.conf 2>/dev/null
tar czf /nsc/out/nsc.tgz -C /nsc stores keys nsc
tar cz -C /nsc/out . | base64 | tr -d "\n"
'

set work (mktemp -d /dev/shm/nats-jwt.XXXXXX)
chmod 0700 $work
set bundle (docker run --rm --tmpfs /nsc:mode=0700 natsio/nats-box:0.20.2 sh -c $inner)
if test -z "$bundle"
    rmdir $work
    fail "nsc produced nothing; nothing stored."
end
printf '%s' $bundle | base64 -d | tar xz -C $work
set -e bundle
for f in resolver.conf nsc.tgz $users.creds
    if not test -s $work/$f
        shred -u $work/* 2>/dev/null; rmdir $work
        fail "nsc didn't produce $f; nothing stored."
    end
end
if not grep -q '^operator:' $work/resolver.conf; or not grep -q '^resolver: MEMORY' $work/resolver.conf
    shred -u $work/*; rmdir $work
    fail "resolver.conf doesn't look right; nothing stored."
end

set bad 0
base64 -w0 $work/nsc.tgz > $work/nsc.b64
kv put homelab/nats/nsc tgz=@$work/nsc.b64 >/dev/null; or set bad 1
kv put homelab/nats/server resolver=@$work/resolver.conf >/dev/null; or set bad 1
for u in $users
    kv put homelab/nats/$u creds=@$work/$u.creds >/dev/null; or set bad 1
end
kv put xolotl/nats creds=@$work/xolotl.creds >/dev/null; or set bad 1

# Read back: compare checksums, print lengths.
function same
    test (printf '%s' (kv get -field=$argv[2] $argv[1]) | sha256sum | string sub --length 64) = (printf '%s' (cat $argv[3]) | sha256sum | string sub --length 64)
end
same homelab/nats/server resolver $work/resolver.conf; or set bad 1
same homelab/nats/nsc tgz $work/nsc.b64; or set bad 1
for u in $users
    same homelab/nats/$u creds $work/$u.creds; or set bad 1
end
same xolotl/nats creds $work/xolotl.creds; or set bad 1

shred -u $work/*
rmdir $work

if test $bad -eq 0
    echo "stored: homelab/nats/nsc, homelab/nats/server, creds for $users, xolotl/nats creds"
else
    echo "something failed or read back DIFFERENT; check the lines above"
end
set -e VAULT_TOKEN
