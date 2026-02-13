#!/bin/bash
set -e

CACERT_PATH="${SRCROOT}/PostKit/Resources/cacert.pem"
SHA256_PATH="${SRCROOT}/PostKit/Resources/CACERT_SHA256"

if [ ! -f "$CACERT_PATH" ]; then
    echo "error: cacert.pem not found at $CACERT_PATH"
    exit 1
fi

if [ ! -f "$SHA256_PATH" ]; then
    echo "error: CACERT_SHA256 file not found at $SHA256_PATH"
    exit 1
fi

COMPUTED_HASH=$(shasum -a 256 "$CACERT_PATH" | cut -d ' ' -f 1)
STORED_HASH=$(cat "$SHA256_PATH" | tr -d '[:space:]')

if [ "$COMPUTED_HASH" != "$STORED_HASH" ]; then
    echo "error: cacert.pem integrity check failed!"
    echo "  Computed: $COMPUTED_HASH"
    echo "  Expected: $STORED_HASH"
    echo "  This could indicate a compromised download or intentional update."
    echo "  If updating curl-apple xcframework, update CACERT_SHA256 with the new hash."
    exit 1
fi

echo "cacert.pem integrity verified: $COMPUTED_HASH"
