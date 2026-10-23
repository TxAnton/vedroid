# Vedroid

Android instances in containers on a Linux PC or VM, built on [Redroid](https://github.com/remote-android/redroid-doc):

- several instances side by side, each on its own Android version (8.1 to 16, default 14)
- root over adb, plus per-app root inside Android through Magisk
- ARM64 apps on x86_64 hosts through `libndk_translation` (included in Redroid images). The Android 14 image has no 32-bit translation, so armeabi-v7a-only apps do not run there; Android 11/12 images are expected to ship both (not yet verified)
- no Google services by default; `vedroid microg` adds microG with signature spoofing (see below)
- full instance snapshots and per-app backup and restore

Status: early. Android 14 + Magisk boots on an x86_64 host; see [docs/design.md](docs/design.md) for what has been tested.

## Host setup

Put the CLI on your PATH if you like (the rest of this README writes `./vedroid`):

```sh
mkdir -p ~/.local/bin && ln -s "$PWD/vedroid" ~/.local/bin/vedroid
```

`vedroid view` needs scrcpy 2.x or newer for Android 14; Ubuntu 24.04's package is 1.25, which shows the screen but cannot send input. Use `snap install scrcpy` or a release from GitHub.
- Redroid has no Opus encoder, so `vedroid view` passes `--audio-codec=aac` unless you pass `--no-audio` or your own `--audio-codec`.
- scrcpy releases bundle their own adb; `vedroid view` sets `ADB` to the system adb, because a different adb version restarts the server and drops the instance's `127.0.0.1:<port>` connection.

You need a Linux kernel with the binder driver, plus Docker or Podman, `adb`, `scrcpy` and `zstd`.

```sh
sudo ./vedroid host-setup     # loads binder_linux and keeps it loaded on boot
./vedroid host-check
```

`host-setup` is the only step that needs sudo. Data lives in `~/.local/share/vedroid` (or `$VEDROID_HOME`), owned by you. Files that Android writes as root or app UIDs are handled through a throwaway helper container (`vedroid/helper:1`, alpine + GNU tar), so your user only needs to be in the `docker` group.

If `binder_linux` is missing, install your distro's extra kernel modules (on Ubuntu, `linux-modules-extra-$(uname -r)`). On btrfs, snapshots are instant subvolume snapshots, but those commands need sudo. On other filesystems, snapshots fall back to compressed tarballs that keep UIDs and SELinux labels.

### binfmt_misc on the host

To run ARM *executables* (not just libraries), Redroid's init registers `arm64_exe`, `arm64_dyn`, `arm_exe` and `arm_dyn` in `binfmt_misc`. That table is global to the host kernel, so the entries show up in the host's `/proc/sys/fs/binfmt_misc` and stay after the container stops. They point at a path that exists only inside Android, so on the host itself ARM binaries fail with "not found", and they conflict with `qemu-user-static` if you install it.

The stock entries call the translator in a way that breaks ARM programs started by name through `PATH` (Termux's setup fails, for example). Vedroid images register small wrappers instead (`images/binfmt/`). An existing entry is never replaced, so `vedroid recreate` clears stale entries before it boots the instance; `host-check` warns about them, and `vedroid host-setup --clean-binfmt` clears them by hand. Clearing affects every running instance until it is recreated or restarted.

## Quick start

```sh
./vedroid create main                 # Android 14 + Magisk, adb on 127.0.0.1:5555
./vedroid create legacy --android 11  # a second instance on an older version
./vedroid list
./vedroid view main                   # opens the screen with scrcpy
./vedroid install main app.apk
./vedroid recreate main               # rebuild the image after a Vedroid update; keeps data
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

The Magisk app works as on a phone: Superuser prompts, the Superuser list and Modules. Magisk's own files in `/data/adb/magisk` are set up at boot, so the app never asks for "additional setup". Modules take effect after `./vedroid restart main`.

## microG

```sh
./vedroid microg main
```

This installs, from pinned versions checked against published SHA-256 hashes:

- **Vector** (LSPosed, JingMatrix) v2.2 as a Magisk module, with Zygisk turned on
- **microG Services** and **microG Companion** 0.3.17 as privileged system apps, through a generated Magisk module (`vedroid-microg`)
- **FakeGApps** 6.6, enabled in Vector for the framework, microG and the Companion, so the system spoofs Google's signature for them

The instance restarts a few times. Running it again only does what is missing. Check the result in microG Settings > Self-Check ("System spoofs signature"). Zygisk stays on afterwards; it can break 32-bit ARM translation, which the Android 14 image does not have anyway.

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
