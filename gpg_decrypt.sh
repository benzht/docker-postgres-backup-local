#!/usr/bin/env bash

set -euo pipefail

### CONFIGURATION ###
ENCRYPTED_FILE="${1?Missing input file}"                      # First argument: encrypted .gpg file
OUTPUT_FILE="${2:-decrypted_output}"     # Optional second argument: output file name
GPG_RAMDIR="/dev/shm/gpg-temp-$$"        # Unique temp GPG home
#####################

# Create temp GPG directory in RAM
mkdir -p "$GPG_RAMDIR"
chmod 700 "$GPG_RAMDIR"

echo "[*] Importing private key into RAM-resident keyring from stdin..."
KEY_FILE="$(cat)"
gpg --homedir "$GPG_RAMDIR" --import <(echo "$KEY_FILE")

echo "[*] Decrypting file..."
gpg --homedir "$GPG_RAMDIR" --output "$OUTPUT_FILE" --decrypt "$ENCRYPTED_FILE"

echo "[*] Wiping RAM keyring and temporary key..."
rm -rf "$GPG_RAMDIR"
#shred -u "$KEY_FILE"

echo "[✔] Decryption complete. Output saved to: $OUTPUT_FILE"