#!/bin/bash
set -e

interactive_mode() {
  echo "=== Interactive Certificate Generation ==="
  echo "Leave blank to use default values in parentheses"
  echo ""

  read -p "Enter alias/CN (default: localhost): " CLIENT_ALIAS
  CLIENT_ALIAS="${CLIENT_ALIAS:-localhost}"

  read -p "Enter SANs (comma-separated, e.g., minio,localhost,127.0.0.1; default: $CLIENT_ALIAS): " SANS
  SANS="${SANS:-$CLIENT_ALIAS}"

  read -p "Enter CA keystore path (default: ./ca.p12): " CA_KEYSTORE
  CA_KEYSTORE="${CA_KEYSTORE:-./ca.p12}"

  read -p "Enter CA keystore password (default: changeit): " CA_PASSWORD
  CA_PASSWORD="${CA_PASSWORD:-changeit}"

  read -p "Enter truststore/keystore format (PKCS or JKS; default: PKCS): " KEYSTORE_TYPE
  KEYSTORE_TYPE="${KEYSTORE_TYPE:-PKCS}"
  KEYSTORE_TYPE=$(echo "$KEYSTORE_TYPE" | tr '[:lower:]' '[:upper:]')

  # Set file extension based on type
  if [ "$KEYSTORE_TYPE" = "PKCS" ]; then
    KEYSTORE_EXT="p12"
  else
    KEYSTORE_EXT="jks"
  fi

  read -p "Enter keystore name (default: \"keystore\"): " KEYSTORE_NAME
  KEYSTORE_NAME="${KEYSTORE_NAME:-keystore}"
  KEYSTORE_FILE="$KEYSTORE_NAME.$KEYSTORE_EXT"

  read -p "Enter truststore name (default: \"truststore\"): " TRUSTSTORE_NAME
  TRUSTSTORE_NAME="${TRUSTSTORE_NAME:-truststore}"
  TRUSTSTORE_FILE="$TRUSTSTORE_NAME.$KEYSTORE_EXT"

  read -p "Enter password (default: changeit): " PASSWORD
  PASSWORD="${PASSWORD:-changeit}"

  echo ""
  echo "Summary:"
  echo "- Alias/CN: $CLIENT_ALIAS"
  echo "- SANs: $SANS"
  echo "- CA keystore: $CA_KEYSTORE"
  echo "- CA keystore password: $CA_PASSWORD"
  echo "- Keystore type: $KEYSTORE_TYPE"
  echo "- Keystore file: $KEYSTORE_FILE"
  echo "- Truststore file: $TRUSTSTORE_FILE"
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
  CLIENT_ALIAS="$1"
  SANS="$2"
  CA_KEYSTORE="$3"
  KEYSTORE_TYPE="${4:-PKCS}"
  KEYSTORE_TYPE=$(echo "$KEYSTORE_TYPE" | tr '[:lower:]' '[:upper:]')
  PASSWORD="${5:-changeit}"
  CA_PASSWORD="${6:-changeit}"

  # If SANs not provided, use CN as default
  if [ -z "$SANS" ]; then
    SANS="$CLIENT_ALIAS"
  fi

  # Set file extension based on type
  if [ "$KEYSTORE_TYPE" = "PKCS" ]; then
    KEYSTORE_EXT="p12"
  else
    KEYSTORE_EXT="jks"
  fi

  # Set default filenames
  KEYSTORE_FILE="keystore.$KEYSTORE_EXT"
  TRUSTSTORE_FILE="truststore.$KEYSTORE_EXT"
}

# Parse SANs into keytool format
parse_sans() {
  local sans="$1"
  local san_ext=""

  # Split by comma and process each SAN
  IFS=',' read -ra SAN_ARRAY <<< "$sans"
  for san in "${SAN_ARRAY[@]}"; do
    san=$(echo "$san" | xargs)  # Trim whitespace

    # Determine if it's IP or DNS
    if [[ "$san" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      san_ext+="ip:$san,"
    else
      san_ext+="dns:$san,"
    fi
  done

  # Remove trailing comma and return
  echo "${san_ext%,}"
}

# Check if running in interactive mode
if [ $# -eq 0 ]; then
  interactive_mode
else
  if [ -z "$3" ]; then
    echo "Usage: $0 <client-alias> <sans> <path-to-ca-keystore> [JKS|PKCS] [password] [ca-password]"
    echo "  <sans>: comma-separated SANs (e.g., minio,localhost,127.0.0.1)"
    echo "Example: $0 myclient minio,localhost,127.0.0.1 /path/to/ca-keystore.p12"
    echo "Default: PKCS format, password: changeit, CA password: changeit"
    echo ""
    echo "Or run without arguments for interactive mode"
    exit 1
  fi
  command_line_mode "$@"
fi

# Validate keystore type
if [ "$KEYSTORE_TYPE" != "PKCS" ] && [ "$KEYSTORE_TYPE" != "JKS" ]; then
  echo "Error: Keystore type must be either PKCS or JKS"
  exit 1
fi

# Validate CA keystore exists
if [ ! -f "$CA_KEYSTORE" ]; then
  echo "Error: CA keystore not found: $CA_KEYSTORE"
  exit 1
fi

# Parse SANs into proper format
SAN_EXTENSION=$(parse_sans "$SANS")
echo "SAN extension: $SAN_EXTENSION"

echo "=== Exporting CA certificate from $CA_KEYSTORE ==="
keytool -keystore "$CA_KEYSTORE" -storepass "$CA_PASSWORD" \
  -exportcert -alias ca -rfc -file ca-cert.pem

echo "=== Creating truststore: $TRUSTSTORE_FILE ==="
keytool -keystore "$TRUSTSTORE_FILE" -storepass "$PASSWORD" \
  -importcert -alias ca -file ca-cert.pem -noprompt

echo "=== Creating client keystore: $KEYSTORE_FILE ==="
keytool -keystore "$KEYSTORE_FILE" -storepass "$PASSWORD" \
  -importcert -alias ca -file ca-cert.pem -noprompt

echo "=== Generating client keypair: $CLIENT_ALIAS ==="
keytool -keystore "$KEYSTORE_FILE" -storepass "$PASSWORD" \
  -genkeypair -alias "$CLIENT_ALIAS" -keyalg RSA \
  -dname "CN=$CLIENT_ALIAS"

echo "=== Creating client CSR ==="
keytool -keystore "$KEYSTORE_FILE" -storepass "$PASSWORD" \
  -certreq -alias "$CLIENT_ALIAS" -file "$CLIENT_ALIAS.csr"

echo "=== Signing client certificate with SANs ==="
keytool -keystore "$CA_KEYSTORE" -storepass "$CA_PASSWORD" \
  -gencert -alias ca \
  -infile "$CLIENT_ALIAS.csr" -outfile "$CLIENT_ALIAS.pem" \
  -ext "SAN=$SAN_EXTENSION"

echo "=== Importing signed client certificate ==="
keytool -keystore "$KEYSTORE_FILE" -storepass "$PASSWORD" \
  -importcert -alias "$CLIENT_ALIAS" -file "$CLIENT_ALIAS.pem" -noprompt

echo "=== Cleaning up temporary files ==="
rm -v ca-cert.pem "$CLIENT_ALIAS.csr" "$CLIENT_ALIAS.pem"

echo "=== Done ==="
echo "Generated files:"
echo "- Truststore: $(pwd)/$TRUSTSTORE_FILE"
echo "- Client keystore: $(pwd)/$KEYSTORE_FILE (alias: $CLIENT_ALIAS)"
echo "- CN: $CLIENT_ALIAS"
echo "- SANs: $SANS"
echo "Keystore type: $KEYSTORE_TYPE"
echo "Password: $PASSWORD"
echo "CA keystore password: $CA_PASSWORD"