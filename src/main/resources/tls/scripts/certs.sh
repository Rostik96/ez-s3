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

  # New option for private.key and public.crt
  read -p "Provide also 'private.key' & 'public.crt'? (y/n, default: y): " EXPORT_KEY_CERT
  EXPORT_KEY_CERT="${EXPORT_KEY_CERT:-y}"

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
  echo "- Export private.key & public.crt: $EXPORT_KEY_CERT"
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
  EXPORT_KEY_CERT="${7:-y}"

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

# Export private key and certificate from keystore
export_private_key_and_cert() {
  local keystore_file="$1"
  local alias_name="$2"
  local password="$3"
  local keystore_type="$4"

  echo "=== Exporting private.key and public.crt ==="

  # Export the client certificate in PEM format
  keytool -keystore "$keystore_file" -storepass "$password" \
    -exportcert -alias "$alias_name" -rfc -file "${alias_name}.crt.pem"

  # For PKCS12 keystores, we can extract the private key more easily
  if [ "$keystore_type" = "PKCS" ]; then
    # Export the entire entry to a temporary PKCS12 file
    keytool -importkeystore -srckeystore "$keystore_file" -srcstorepass "$password" \
      -srcalias "$alias_name" -destkeystore "temp_${alias_name}.p12" \
      -deststoretype PKCS12 -deststorepass "temp_pass" -noprompt

    # Extract private key from the temporary PKCS12 file
    openssl pkcs12 -in "temp_${alias_name}.p12" -passin pass:temp_pass \
      -nodes -nocerts -out "${alias_name}.key.pem" 2>/dev/null

    # Clean up temporary PKCS12 file
    rm -f "temp_${alias_name}.p12"
  else
    # For JKS, we need to use keytool and openssl differently
    # This is a fallback method that may require additional tools
    echo "Warning: JKS private key extraction is limited. Consider using PKCS12 format for better key export capabilities."
    echo "You can extract the private key manually using:"
    echo "  keytool -importkeystore -srckeystore $keystore_file -srcstorepass $password -srcalias $alias_name -destkeystore temp.p12 -deststoretype PKCS12 -deststorepass temp_pass"
    echo "  openssl pkcs12 -in temp.p12 -passin pass:temp_pass -nodes -nocerts -out ${alias_name}.key.pem"
  fi

  # Rename to the expected filenames
  mv "${alias_name}.crt.pem" "public.crt"
  mv "${alias_name}.key.pem" "private.key"

  echo "Exported: private.key & public.crt"
}

# Check if running in interactive mode
if [ $# -eq 0 ]; then
  interactive_mode
else
  if [ -z "$3" ]; then
    echo "Usage: $0 <client-alias> <sans> <path-to-ca-keystore> [JKS|PKCS] [password] [ca-password] [export-key-cert(y/n)]"
    echo "  <sans>: comma-separated SANs (e.g., minio,localhost,127.0.0.1)"
    echo "Example: $0 myclient minio,localhost,127.0.0.1 /path/to/ca-keystore.p12"
    echo "Default: PKCS format, password: changeit, CA password: changeit, export-key-cert: y"
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

# Export private.key and public.crt if requested
if [ "$EXPORT_KEY_CERT" = "y" ] || [ "$EXPORT_KEY_CERT" = "Y" ]; then
  export_private_key_and_cert "$KEYSTORE_FILE" "$CLIENT_ALIAS" "$PASSWORD" "$KEYSTORE_TYPE"
fi

echo "=== Cleaning up temporary files ==="
rm -v ca-cert.pem "$CLIENT_ALIAS.csr" "$CLIENT_ALIAS.pem"

echo "=== Done ==="
echo "Generated files:"
echo "- Truststore: $(pwd)/$TRUSTSTORE_FILE"
echo "- Client keystore: $(pwd)/$KEYSTORE_FILE (alias: $CLIENT_ALIAS)"
if [ "$EXPORT_KEY_CERT" = "y" ] || [ "$EXPORT_KEY_CERT" = "Y" ]; then
  echo "- Private key: $(pwd)/private.key"
  echo "- Public certificate: $(pwd)/public.crt"
fi
echo "- CN: $CLIENT_ALIAS"
echo "- SANs: $SANS"
echo "Keystore type: $KEYSTORE_TYPE"
echo "Password: $PASSWORD"
echo "CA keystore password: $CA_PASSWORD"