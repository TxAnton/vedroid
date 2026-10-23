# Design notes

The full write-up is the "Vedroid: Android container design" doc. This file keeps the decisions that the code depends on.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Base | Redroid, not Waydroid | Supports several instances at once and Android 8.1 to 16. Waydroid runs one instance per host and ships Android 13 officially. |
| Host | x86_64 (AMD) Linux PC or VM | The user's hardware |
| ARM apps | `libndk_translation`, already included in Redroid images | Recommended on AMD; libhoudini does not work on Redroid according to redroid-script |
| ARM executables | Redroid's `/system/etc/binfmt_misc/*` point at `/system/bin/vedroid-binfmt-arm{,64}` (flag `P` kept), shell wrappers that pass the full path as argv[0] when it is a bare name (`images/binfmt/`) | The ndk_translation runner expects P-style arguments and `realpath()`s argv[0], so programs found via PATH fail with stock entries. Dropping `P` instead breaks every program called with arguments. Entries are global on the host; `recreate` clears stale ones |
| Graphics | `redroid_gpu_mode=guest` (software rendering) | No hardware acceleration needed |
| Default version | 14.0.0 | Recent, and the newest version the Magisk setup is known to work on. Translation is best proven on 11, so 14 needs to be checked first. |
| Root over adb | `ro.secure=0` boot property | Built into Redroid |
| Root for apps | Bootless Magisk 30.6 (ayasa520 fork, release tag v30.7), started from `bootanim.rc`; `/system/bin/su` links to `/sbin/su` | Redroid has no boot image to patch. Magisk's Superuser list gives per-app grants. `/sbin` is not on PATH in Android 11+. |
| Not KernelSU | | Requires a modified host kernel, because every container shares that kernel |
| Snapshots | btrfs read-only subvolume snapshots (needs sudo); otherwise `tar --xattrs --numeric-owner` in a helper container, piped to host zstd | Keeps UIDs and SELinux labels |
| Data root | `~/.local/share/vedroid`; root-owned files handled in a `--privileged` alpine helper container | No sudo after `host-setup`; docker group membership is already root-equivalent |
| Per-app backups | Host side over root adb | Works on any version and needs no app inside Android |

## Known caveats

- The Redroid 13 and 14 x86_64 images have 64-bit `libndk_translation` only (`/system/lib/libnb.so` dangles; 32-bit zygote logs "Failed to load native bridge"). armeabi-v7a apps are not supported there. Android 11/12 images are expected to ship both; verify before relying on it.
- Tested on 2026-10-23: snapshot + restore on a throwaway 14 instance (files back, boots, Magisk OK; `rm` without sudo); `backup-app`/`restore-app` of Termux within main and into a fresh Android 13 instance (data re-owned to the new UID, arm64 bash runs on 13). On 13, Magisk itself places `/system/bin/su -> ./magisk`.
- Zygisk (Magisk's in-process hooks) can break libndk for 32-bit ARM apps. Leave it off unless a module needs it.
- microG needs signature spoofing. AOSP 14 has none, so `vedroid microg` uses the runtime route: Zygisk + Vector (LSPosed) v2.2 + FakeGApps 6.6 scoped to `system`, microG and the Companion, configured with Vector's own CLI (`/data/adb/lspd/cli`). Tested on Android 14: Self-Check passes "System spoofs signature" and both "correct signature" checks; arm64 apps (Termux) still run with Zygisk on. Zygisk can break 32-bit libndk, which the 14 image lacks anyway. An image with spoofing built in (Redroid from source with the microG patch) would avoid Zygisk.
- microG is installed as a Magisk module with `system/priv-app/{GmsCore,Phonesky}`, native libraries pre-extracted, and a privapp-permissions XML. A user-installed copy of either package makes `vedroid microg` stop.
- `adb exec-in` silently does nothing against Redroid here; push a file and unpack it as root instead.
- `bootanim.stock.rc` uses `task_profiles`, so Magisk images require Android 11 or newer.
- Redroid on a non-SELinux host runs with SELinux disabled, so `magiskpolicy --live` is skipped when `/sys/fs/selinux/enforce` is missing.
- Redroid images are userdebug builds and ship AOSP `/system/xbin/su` (setuid, `root:shell` 4750, syntax `su [uid] [cmd]`). Only the shell user can run it. It is left in place; test Magisk with `/sbin/su` explicitly.
- magiskd takes its trusted manager certificate from `stub.apk` next to the binaries (`--setup-sbin` copies it). Without it every manager APK "mismatches" and magiskd uninstalls the Magisk app, so the image ships the APK's `assets/stub.apk`. With it, the app survives and the Superuser prompt works (unanswered, it times out to a saved "deny").
- `/data/adb/magisk` (MAGISKBIN) must hold busybox, magisk, magiskboot, magiskinit, magiskpolicy and the APK's `assets/*.sh` (the app checks `MAGISK_VER_CODE` in `util_functions.sh`). Otherwise magiskd aborts post-fs-data ("Magisk environment incomplete"), modules never load, and the app asks for "additional setup". `vedroid-setup-data` copies them in from `/system/etc/init/magisk` before `--post-fs-data`, on first boot and whenever the version changes.
- Module mounting works without a preinit partition (tested: a module's `system/etc` file shows up for apps too). `mount: preinit dir not found` only affects modules' `sepolicy.rule`, which is moot with SELinux disabled. magiskd also logs `set_mount_private '/sbin/.magisk/worker': Invalid argument` and `Invalid argument (os error 22)` at start; neither stopped modules from mounting.
- Magisk logs `mount: preinit dir not found`. Root grants work; module mounting is untested.

## Next

1. Boot test on the real host. Done on 2026-10-23: Android 14 boots, arm64-v8a native bridge present, Magisk daemon up, grants work via `/sbin/su`. Still to do: an arm64-only app, and an app getting root through `/system/bin/su` after an image rebuild.
2. Check libndk on 15 and 16, and 32-bit ARM on 11/12.
3. microG built into the image (signature spoofing patch), to drop the Zygisk dependency.
