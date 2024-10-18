#!/bin/bash

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"

# shellcheck disable=SC1090
source ~/.reprepro.env
# shellcheck disable=SC1090
source ~/venv/bin/activate

# Add option "allow-preset-passphrase" to .gnupg/gpg-agent.conf before calling gpg-preset-passphrase!
/usr/lib/gnupg2/gpg-preset-passphrase -v --preset "$GPG_KEY" <<EOF
$GPG_PW
EOF

fastapi run "$DIR_THIS/server.py"
