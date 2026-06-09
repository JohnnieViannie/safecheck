#!/usr/bin/env bash
# Run on the VPS once to prepare APK hosting at https://safebangle.com/safecheck.apk
set -euo pipefail

PUBLIC_DIR="/var/www/safebangle/public"
APK_PATH="${PUBLIC_DIR}/safecheck.apk"

mkdir -p "${PUBLIC_DIR}"
touch "${APK_PATH}"
chmod 644 "${APK_PATH}"

echo "Created ${APK_PATH}"
echo ""
echo "Next steps:"
echo "  1. Add deploy/nginx-safecheck-apk.conf to your nginx site config"
echo "  2. sudo nginx -t && sudo systemctl reload nginx"
echo "  3. Upload APK: scp deploy/public/safecheck.apk root@YOUR_VPS:${APK_PATH}"
echo "  4. Test: curl -I https://safebangle.com/safecheck.apk"
