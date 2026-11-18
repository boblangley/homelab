#!/usr/bin/env fish
# Sets up what the Deck service (role deck) reads from OpenBao, namespace wyrwood, kv:
#   homelab/deck/host    private_key: its SSH host key, an unencrypted OpenSSH ed25519 key
#   homelab/nats/deck    creds: its NATS user, issued by nats-user.fish with the permissions below
# The host key is made with ssh-keygen in a 0700 directory in /dev/shm (memory) and shredded there. Prints the public
# line, which clients pin as service.host_key. Stops without changing anything if homelab/deck/host exists. Asks for
# the token twice: once here, once in nats-user.fish. The bot tokens are stored by hand (deck/bots/<name>, token).
#   fish scripts/openbao/deck-bootstrap.fish

read --silent --prompt-str 'OpenBao root token: ' token
# BAO_* as well: bao prefers them, and a devcontainer may set BAO_ADDR to its Wyrwood socket.
set -x BAO_ADDR https://openbao.internal:8200
set -x BAO_TOKEN $token
set -x VAULT_ADDR $BAO_ADDR
set -x VAULT_TOKEN $token
set -e token
function kv
    bao kv $argv[1] -namespace=wyrwood -mount=kv $argv[2..]
end
function fail
    echo $argv
    set -e -g BAO_TOKEN VAULT_TOKEN
    exit 1
end

# 0: stored; 1: not stored; 2: OpenBao refused or couldn't be reached (error printed). A failed read must never be
# taken for "not stored", which would go on to create and overwrite.
function kv_exists -a p
    set err (bao kv get -namespace=wyrwood -mount=kv $p 2>&1 >/dev/null)
    and return 0
    string match --quiet '*No value found*' -- "$err"; and return 1
    printf '%s\n' $err >&2
    return 2
end
kv_exists homelab/deck/host
switch $status
    case 0
        fail "homelab/deck/host exists already; nothing changed."
    case 2
        fail "Can't read homelab/deck/host from $BAO_ADDR; nothing changed."
end

set work (mktemp -d /dev/shm/deck-host.XXXXXX)
chmod 0700 $work
if not ssh-keygen -q -t ed25519 -N '' -C deck.internal -f $work/host
    rmdir $work 2>/dev/null
    fail "ssh-keygen failed; nothing stored."
end
set bad 0
kv put homelab/deck/host private_key=@$work/host >/dev/null; or set bad 1
test (printf '%s' (kv get -field=private_key homelab/deck/host) | sha256sum | string sub --length 64) = (printf '%s' (cat $work/host) | sha256sum | string sub --length 64); or set bad 1
set public (cat $work/host.pub)
shred -u $work/*
rmdir $work
set -e -g BAO_TOKEN VAULT_TOKEN
if test $bad -ne 0
    fail "the host key failed or read back DIFFERENT; check homelab/deck/host"
end
echo "stored homelab/deck/host. Clients pin, as service.host_key:"
echo "  $public"

# Deck's own stream DECK (subjects deck.>, its activity index an ordered consumer) and bucket deck-threads (stream
# KV_deck-threads, direct gets, a watch), which it creates and corrects at start, and nothing of another stream's.
set js '$JS.API'
set pub (string join , -- 'deck.>' '$KV.deck-threads.>' '$JS.FC.>' \
    $js.STREAM.\*.DECK $js.STREAM.\*.\*.DECK $js.DIRECT.GET.DECK $js.DIRECT.GET.DECK.\> \
    $js.CONSUMER.\*.DECK $js.CONSUMER.\*.DECK.\> $js.CONSUMER.\*.\*.DECK.\> \
    $js.STREAM.\*.KV_deck-threads $js.STREAM.\*.\*.KV_deck-threads \
    $js.DIRECT.GET.KV_deck-threads $js.DIRECT.GET.KV_deck-threads.\> \
    $js.CONSUMER.\*.KV_deck-threads $js.CONSUMER.\*.KV_deck-threads.\> $js.CONSUMER.\*.\*.KV_deck-threads.\>)
set sub '_INBOX.>,$KV.deck-threads.>'
echo
echo "Now NATS user deck:"
fish (status dirname)/nats-user.fish deck --pub $pub --sub $sub
