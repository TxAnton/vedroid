#!/system/bin/sh
# Fill /data/adb/magisk (MAGISKBIN) before post-fs-data, as the Magisk app's
# "additional setup" would. Without it magiskd aborts post-fs-data
# ("Magisk environment incomplete") and modules are never loaded.
# Runs on every boot; only copies when the files are missing or another version.
src=/system/etc/init/magisk
bin=/data/adb/magisk

want="$(grep '^MAGISK_VER_CODE=' $src/util_functions.sh)"
if [ -f $bin/busybox ] && grep -qxF "$want" $bin/util_functions.sh 2>/dev/null; then
  exit 0
fi

mkdir -p $bin
chmod 0700 /data/adb
rm -rf $bin/*
for f in busybox magisk magiskboot magiskinit magiskpolicy init-ld stub.apk $src/*.sh; do
  cp -f "$src/${f##*/}" $bin/
done
chown -R 0:0 $bin
chmod 0755 $bin $bin/*
