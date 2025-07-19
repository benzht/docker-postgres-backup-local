#!/usr/bin/env bash

set +x

set -euo pipefail

FILE=${1?Missing output file}
KEY_ID=${2?Missing encryption key}

bzip2 | gpg --encrypt --recipient ${KEY_ID} > "${FILE}"
