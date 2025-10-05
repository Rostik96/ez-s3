#!/bin/bash
set -e

interactive_mode() {
  echo "=== CA Keystore Generation ==="
  echo "Leave blank to use default values in parentheses"
  echo ""

  read -p "Enter CA keystore password (default: changeit): " PASSWORD
  PASSWORD="${PASSWORD:-changeit}"

  read -p "Enter CA keystore filename (default: \"ca\"): " CA_FILENAME
  CA_FILENAME="${CA_FILENAME:-ca.p12}"

  CA_KEYSTORE="$(pwd)/$CA_FILENAME"

  echo ""
  echo "Summary:"
  echo "- CA keystore: $CA_KEYSTORE"
  echo "- Password: $PASSWORD"
  echo ""

  read -p "Proceed? (y/n): " CONFIRM
  CONFIRM="${CONFIRM:-y}"
  if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Operation cancelled."
    exit 0
  fi
}

command_line_mode() {
  PASSWORD="${1:-changeit}"
  CA_FILENAME="${2:-ca.p12}"
  CA_KEYSTORE="$(pwd)/$CA_FILENAME"
}

# Check if running with password parameter or interactive mode
if [ $# -eq 0 ]; then
  interactive_mode
else
  command_line_mode "$@"
fi

echo "=== Generating CA keystore ==="
keytool -keystore "$CA_KEYSTORE" -storepass "$PASSWORD" \
  -genkeypair -alias ca -keyalg RSA \
  -dname "CN=CA" \
  -ext "BC=ca:true,pathlen:3" \
  -ext "KeyUsage=keyCertSign,cRLSign"

printf "\nAbsolute path to CA keystore:\n"
echo "$CA_KEYSTORE"  # Print absolute path to CA keystore
echo "Password: $PASSWORD"