#!/bin/bash

DIR_THIS="$(dirname "${BASH_SOURCE[0]}")"

# shellcheck disable=SC1090
source ~/.reprepro.env
if [ ! -d ~/fastapi.venv ]; then
	python3 -m venv ~/fastapi.venv
	# shellcheck disable=SC1090
	source ~/fastapi.venv/bin/activate
	pip install "fastapi[standard]" starlette sse_starlette colorama
fi
# shellcheck disable=SC1090
source ~/fastapi.venv/bin/activate

# Add option "allow-preset-passphrase" to .gnupg/gpg-agent.conf before calling gpg-preset-passphrase!
/usr/lib/gnupg2/gpg-preset-passphrase -v --preset "$GPG_KEY" <<EOF
$GPG_PW
EOF
unset GPG_PW
unset GPG_KEY

# Ensure that we can sign files
touch /tmp/gpg-test-file
gpg --clear-sign /tmp/gpg-test-file || exit 1
rm /tmp/gpg-test-file /tmp/gpg-test-file.asc

fastapi run "$DIR_THIS/server.py"
