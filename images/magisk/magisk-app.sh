#!/system/bin/sh
# Make sure the full Magisk app is installed. On a fresh /data, magiskd
# installs its stub (versionName 1.0, which downloads the real app from the
# internet when opened); replace it with the full APK shipped in the image.
src=/system/etc/init/magisk
want="versionCode=$(sed -n 's/^MAGISK_VER_CODE=//p' $src/util_functions.sh)"
for i in 1 2 3 4 5 6; do
  sleep 5
  have="$(dumpsys package com.topjohnwu.magisk | grep -m1 -o 'versionCode=[0-9]*')"
  [ "$have" = "$want" ] && exit 0
  [ -n "$have" ] && break
done
pm install -r $src/magisk.apk
