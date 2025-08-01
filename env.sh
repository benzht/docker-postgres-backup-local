#!/usr/bin/env bash
# Pre-validate the environment
if [ "${POSTGRES_DB}" = "**None**" -a "${POSTGRES_DB_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_DB or POSTGRES_DB_FILE environment variable."
  exit 1
fi

if [ "${POSTGRES_HOST}" = "**None**" ]; then
  if [ -n "${POSTGRES_PORT_5432_TCP_ADDR}" ]; then
    POSTGRES_HOST=${POSTGRES_PORT_5432_TCP_ADDR}
    POSTGRES_PORT=${POSTGRES_PORT_5432_TCP_PORT}
  else
    echo "You need to set the POSTGRES_HOST environment variable."
    exit 1
  fi
fi

if [ "${POSTGRES_USER}" = "**None**" -a "${POSTGRES_USER_FILE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_USER or POSTGRES_USER_FILE environment variable."
  exit 1
fi

if [ "${POSTGRES_PASSWORD}" = "**None**" -a "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  echo "You need to set the POSTGRES_PASSWORD or POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE environment variable or link to a container named POSTGRES."
  exit 1
fi

#Process vars
if [ "${POSTGRES_DB_FILE}" = "**None**" ]; then
  POSTGRES_DBS=$(echo "${POSTGRES_DB}" | tr , " ")
elif [ -r "${POSTGRES_DB_FILE}" ]; then
  POSTGRES_DBS=$(cat "${POSTGRES_DB_FILE}")
else
  echo "Missing POSTGRES_DB_FILE file."
  exit 1
fi
if [ "${POSTGRES_USER_FILE}" = "**None**" ]; then
  export PGUSER="${POSTGRES_USER}"
elif [ -r "${POSTGRES_USER_FILE}" ]; then
  export PGUSER=$(cat "${POSTGRES_USER_FILE}")
else
  echo "Missing POSTGRES_USER_FILE file."
  exit 1
fi
if [ "${POSTGRES_PASSWORD_FILE}" = "**None**" -a "${POSTGRES_PASSFILE_STORE}" = "**None**" ]; then
  export PGPASSWORD="${POSTGRES_PASSWORD}"
elif [ -r "${POSTGRES_PASSWORD_FILE}" ]; then
  export PGPASSWORD=$(cat "${POSTGRES_PASSWORD_FILE}")
elif [ -r "${POSTGRES_PASSFILE_STORE}" ]; then
  export PGPASSFILE="${POSTGRES_PASSFILE_STORE}"
else
  echo "Missing POSTGRES_PASSWORD_FILE or POSTGRES_PASSFILE_STORE file."
  exit 1
fi
export PGHOST="${POSTGRES_HOST}"
export PGPORT="${POSTGRES_PORT}"
KEEP_MINS=${BACKUP_KEEP_MINS}
KEEP_DAYS=${BACKUP_KEEP_DAYS}
KEEP_WEEKS=`expr $(((${BACKUP_KEEP_WEEKS} * 7) + 1))`
KEEP_MONTHS=`expr $(((${BACKUP_KEEP_MONTHS} * 31) + 1))`

# Validate backup dir
if [ '!' -d "${BACKUP_DIR}" -o '!' -w "${BACKUP_DIR}" -o '!' -x "${BACKUP_DIR}" ]; then
  echo "BACKUP_DIR points to a file or folder with insufficient permissions."
  exit 1
fi


if [ "${ENCRYPTION_TYPE}" = "X.509" ]; then
  export ENCRYPTION_PIPE="./encryptions_pipe.sh"
  for DB in ${POSTGRES_DBS}; do
      KEY_BASE="${CERT_DIR}/${ENCRYPTION_CERT}${DB}"
      SUBJECT="$(echo "${CERT_SUBJECT}" | env DB="$DB" envsubst '${DB}')"
      if [ ! -f  "${KEY_BASE}.crt" ]; then
          echo "Generating Key Pair for ${DB} - REMEMBER TO MOVE THE KEY TO A SAFE PLACE"
          openssl req -x509 -nodes -days 1000000 \
              -newkey rsa:4096 \
              -subj "${SUBJECT}" \
              -keyout "${KEY_BASE}.key" \
              -out "${KEY_BASE}.crt"
      fi
  done
else
  GPG_RAMDIR="/dev/shm/gpg-temp-$$"        # Unique temp GPG home
  # Create temp GPG directory in RAM
  mkdir -p "$GPG_RAMDIR"
  chmod 700 "$GPG_RAMDIR"

  export ENCRYPTION_PIPE="./gpg_encrypt"
  declare -A GPG_KEYS
  for DB in ${POSTGRES_DBS}; do
      KEY_BASE="${CERT_DIR}/${ENCRYPTION_CERT}${DB}"
      SUBJECT="$(echo "${CERT_SUBJECT}" | env DB="$DB" envsubst '${DB}')"
      PUBLIC_KEY_FILE="${KEY_BASE}.pub.asc"
      if [ -f  "${PUBLIC_KEY_FILE}" ]; then
          echo "Importing GPG Key for ${DB}"
          gpg --homedir "$GPG_RAMDIR" --import "${PUBLIC_KEY_FILE}" 2>&1 | awk '/^gpg: key/ {print $3}'
          # Extract the fingerprint of the last imported key and Trust this key
          FPR=$(gpg --homedir "$GPG_RAMDIR" --with-colons --import-options show-only --import "${PUBLIC_KEY_FILE}" | awk -F: '/^fpr:/ {print $10; exit}')
          echo "${FPR}:6:" | gpg --homedir "$GPG_RAMDIR" --import-ownertrust
          GPG_KEYS["${DB}"]="${FPR}"
      fi
  done
fi
