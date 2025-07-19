#!/usr/bin/env bash
set -Eeo pipefail
set -x


FILE=${1?Missing file to encrypt}
CERTIFICATE_FILE=${2?Missing certificate}

bzip2 | \
openssl smime -encrypt -aes256 -binary -outform DEM -stream -out "${FILE}" "${CERTIFICATE_FILE}"
