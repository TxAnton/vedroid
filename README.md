# Vedroid

Android instances in containers on a Linux PC or VM, built on [Redroid](https://github.com/remote-android/redroid-doc):

- several instances side by side, each on its own Android version (8.1 to 16, default 14)
- root over adb, plus per-app root inside Android through Magisk
- ARM and ARM64 apps on x86_64 hosts through `libndk_translation` (included in Redroid images)
- no Google services; microG is planned (see [docs/design.md](docs/design.md))
- full instance snapshots and per-app backup and restore

Status: early. Android 14 + Magisk boots on an x86_64 host; see [docs/design.md](docs/design.md) for what has been tested.

## Host setup

You need a Linux kernel with the binder driver, plus Docker or Podman, `adb`, `scrcpy` and `zstd`.

```sh
sudo ./vedroid host-setup     # loads binder_linux and keeps it loaded on boot
./vedroid host-check
```

`host-setup` is the only step that needs sudo. Data lives in `~/.local/share/vedroid` (or `$VEDROID_HOME`), owned by you. Files that Android writes as root or app UIDs are handled through a throwaway helper container (`vedroid/helper:1`, alpine + GNU tar), so your user only needs to be in the `docker` group.

If `binder_linux` is missing, install your distro's extra kernel modules (on Ubuntu, `linux-modules-extra-$(uname -r)`). On btrfs, snapshots are instant subvolume snapshots, but those commands need sudo. On other filesystems, snapshots fall back to compressed tarballs that keep UIDs and SELinux labels.

## Quick start

```sh
./vedroid create main                 # Android 14 + Magisk, adb on 127.0.0.1:5555
./vedroid create legacy --android 11  # a second instance on an older version
./vedroid list
./vedroid view main                   # opens the screen with scrcpy
./vedroid install main app.apk
```

The first `create` for a given version builds the `vedroid/android:<ver>-magisk` image. Use `--no-magisk` for a stock image without in-Android root.

## Root

`adb` is always root (`./vedroid shell main`). Apps that ask for `su` go through Magisk. You can answer Magisk's prompt, or grant root from the host:

```sh
./vedroid su-allow main com.machiav3lli.backup
./vedroid su-deny  main com.example.app
./vedroid su-list  main
```

Magisk runs from `/sbin` (Magisk 30.6, from the ayasa520 fork's v30.7 release). `/sbin` is not on Android's PATH, so the image links `/system/bin/su` to `/sbin/su`. The stock AOSP `/system/xbin/su` is left in place, but `/system/bin` comes first on PATH, and apps cannot enter `/system/xbin` anyway. To test a grant from the host as the shell user (uid 2000):

```sh
./vedroid su-allow main com.android.shell
./vedroid shell main '/sbin/su 2000 -c "/sbin/su -c id"'   # -> uid=0(root)
```

## Backups

```sh
./vedroid snapshot main before-update   # whole instance, including OS version
./vedroid snapshots main
./vedroid restore main 20261023-153144-before-update

./vedroid backup-app main org.example.notes            # APKs + data
./vedroid restore-app legacy ~/.local/share/vedroid/app-backups/org.example.notes/<backup>
```

Per-app backups contain the app's APKs (including splits) and its internal, device-protected and external app-specific data. On restore, files are re-owned to the app's new UID and their SELinux labels are reset. This means you can move an app into a different instance or Android version.

## Layout

```
~/.local/share/vedroid/            ($VEDROID_HOME; /srv/vedroid when run as plain root)
  instances/<name>/instance.env   version, image, adb port, display
  instances/<name>/data/          the instance's /data (btrfs subvolume if available)
  instances/<name>/snapshots/     full snapshots
  app-backups/<package>/<time>-<instance>/
```

## Security notes

- Instances run `--privileged` (Redroid requires this) and share the host kernel. For stronger isolation, run Vedroid inside a VM.
- adb is bound to `127.0.0.1` only. An exposed adb port gives root on the instance.

## Credits

The bootless Magisk setup follows [ayasa520/redroid-script](https://github.com/ayasa520/redroid-script).
