# Samsung recovery fastbootd audit

This repository audits Samsung recovery images for the userspace-fastboot
(`fastbootd`) gate. It is based on the historical work by
[phhusson](https://github.com/phhusson/samsung-galaxy-a51-gsi-boot), but the
old byte patterns are **not** treated as universal patches.

## Safety model

- The default GitHub Actions mode is `audit`: it does not modify or upload a
  recovery image. It uploads only `patch-report.txt`.
- The downloaded input must be an Android boot image whose embedded AVB footer
  verifies before any unpacking starts.
- Every historical signature, including the current upstream additions, is
  counted and reported. A missing alternate signature is a diagnostic result,
  not an ignored error.
- `apply` requires an exact, unique, reviewed profile and an explicit
  acknowledgement. It verifies that the rebuilt ramdisk still contains exactly
  the intended change, and never applies the same profile twice. The candidate
  remains inside the disposable CI runner; no firmware-derived image is
  uploaded as an artifact.
- `apply` with `AVB_MODE=stock` leaves the stock-vbmeta limitation in place:
  the candidate is not flash-ready with stock `vbmeta`.
- `apply` with `AVB_MODE=disable-verification` requires a second explicit
  acknowledgement. It creates a minimal root `vbmeta` with AVB flag `2`
  (`VERIFICATION_DISABLED`) and no descriptors. This is a replacement for the
  root `vbmeta` partition, not a generated key trusted by Samsung. It is a
  security downgrade and is never uploaded by this workflow.

Do not upload an original recovery image or firmware package to a public
release, issue, or file host. Use a short-lived private HTTPS link when running
the workflow and remove it afterwards.

`EXPORT_FIRMWARE_ARTIFACT=true` is a separate opt-in acknowledgement. It
uploads no input firmware; it uploads only the generated patched `recovery.img`,
the generated verification-disabled `vbmeta.img`, checksums, and an AP `.tar`
for Odin. The artifact expires after one day. Do not enable this on a public
repository unless distributing those generated images is intentional.

## Running the workflow

1. Open **Actions → Recovery fastbootd audit → Run workflow**.
2. Supply a temporary HTTPS download URL for the exact `recovery.img` to be
   audited.
3. Keep `PATCH_MODE` as `audit` and inspect `patch-report.txt`.

`PATCH_MODE=apply` is intentionally opt-in and does not establish device boot
compatibility. `AVB_MODE=disable-verification` can make a candidate usable on
an unlocked device only if its bootloader permits an unsigned replacement root
`vbmeta`; the workflow cannot prove that device-specific behavior. It is for
controlled analysis only, not a recommendation to flash a device.

## Scope and limitations

`fastbootd` requires more than a changed branch: its binary, fastboot HAL,
SELinux policy, dynamic-partition access, and the device's AVB policy must all
work together. A matching signature, a successful repack, or a successful CI
run is therefore not proof that a recovery is safe to boot or suitable for
flashing a GSI.

## Credits

- [Pierre-Hugues Husson](https://github.com/phhusson)
- [James Nguyen](https://github.com/thongass000)
