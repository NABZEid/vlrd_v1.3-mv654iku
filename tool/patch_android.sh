#!/usr/bin/env bash
# Dijalankan otomatis oleh workflow setelah folder android dibuat.
set -e
M=android/app/src/main/AndroidManifest.xml
python3 - "$M" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
perm = 'android.permission.INTERNET'  # untuk jembatan lokal 127.0.0.1 ke Bloader
if perm not in s:
    s = s.replace('<application', '    <uses-permission android:name="%s"/>\n    <application' % perm, 1)
open(p, 'w', encoding='utf-8').write(s)
PY
echo "patch_android selesai"
