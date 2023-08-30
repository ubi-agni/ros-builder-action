#!/bin/bash
# shellcheck disable=SC2034
HOOK="for i in 1 2 3; do echo -n '.' ; sleep 1 ; done"
ici_hook HOOK
