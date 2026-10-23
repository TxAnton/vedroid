# Design notes

The full write-up is the "Vedroid: Android container design" doc. This file keeps the decisions that the code depends on.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Base | Redroid, not Waydroid | Supports several instances at once and Android 8.1 to 16. Waydroid runs one instance per host and ships Android 13 officially. |
| Host | x86_64 (AMD) Linux PC or VM | The user's hardware |
| ARM apps | `libndk_translation`, already included in Redroid images | Recommended on AMD; libhoudini does not work on Redroid according to redroid-script |
| ARM executables | Redroid's `/system/etc/binfmt_misc/*` replaced by copies without the `P` flag (`images/binfmt/`) | With `P`, the translator `realpath()`s a bare argv[0], so programs found via PATH fail. Entries are global on the host; `host-setup --clean-binfmt` clears stale ones |
| Graphics | `redroid_gpu_mode=guest` (software rendering) | No hardware acceleration needed |
| Default version | 14.0.0 | Recent, and the newest version the Magisk setup is known to work on. Translation is best proven on 11, so 14 needs to be checked first. |
| Root over adb | `ro.secure=0` boot property | Built into Redroid |
| Root for apps | Bootless Magisk 30.6 (ayasa520 fork, release tag v30.7), started from `bootanim.rc`; `/system/bin/su` links to `/sbin/su` | Redroid has no boot image to patch. Magisk's Superuser list gives per-app grants. `/sbin` is not on PATH in Android 11+. |
| Not KernelSU | | Requires a modified host kernel, because every container shares that kernel |
| Snapshots | btrfs read-only subvolume snapshots (needs sudo); otherwise `tar --xattrs --numeric-owner` in a helper container, piped to host zstd | Keeps UIDs and SELinux labels |
| Data root | `~/.local/share/vedroid`; root-owned files handled in a `--privileged` alpine helper container | No sudo after `host-setup`; docker group membership is already root-equivalent |
| Per-app backups | Host side over root adb | Works on any version and needs no app inside Android |

## Known caveats

- The Redroid 14 x86_64 image has 64-bit `libndk_translation` only (`/system/lib/libnb.so` dangles; 32-bit zygote logs "Failed to load native bridge"). armeabi-v7a apps are not supported there. Android 11/12 images are expected to ship both; verify before relying on it.
- Zygisk (Magisk's in-process hooks) can break libndk for 32-bit ARM apps. Leave it off unless a module needs it.
- microG needs signature spoofing. The runtime route (LSPosed) needs Zygisk, which conflicts with the caveat above. The preferred route is therefore an image with signature spoofing built in.
- `bootanim.stock.rc` uses `task_profiles`, so Magisk images require Android 11 or newer.
- Redroid on a non-SELinux host runs with SELinux disabled, so `magiskpolicy --live` is skipped when `/sys/fs/selinux/enforce` is missing.
- Redroid images are userdebug builds and ship AOSP `/system/xbin/su` (setuid, `root:shell` 4750, syntax `su [uid] [cmd]`). Only the shell user can run it. It is left in place; test Magisk with `/sbin/su` explicitly.
- Magisk logs `mount: preinit dir not found`. Root grants work; module mounting is untested.

## Next

1. Boot test on the real host. Done on 2026-10-23: Android 14 boots, arm64-v8a native bridge present, Magisk daemon up, grants work via `/sbin/su`. Still to do: an arm64-only app, and an app getting root through `/system/bin/su` after an image rebuild.
2. Check libndk on 15 and 16, and 32-bit ARM on 11/12.
3. microG image.
