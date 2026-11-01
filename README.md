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
- The workflow never creates a new AVB footer with a generated key. Such a key
  is not part of the stock `vbmeta` trust chain. An opt-in `apply` output is
  labelled `UNVERIFIED` and is not flash-ready with stock `vbmeta`.

Do not upload an original recovery image or firmware package to a public
release, issue, or file host. Use a short-lived private HTTPS link when running
the workflow and remove it afterwards.

## Running the workflow

1. Open **Actions → Recovery fastbootd audit → Run workflow**.
2. Supply a temporary HTTPS download URL for the exact `recovery.img` to be
   audited.
3. Keep `PATCH_MODE` as `audit` and inspect `patch-report.txt`.

`PATCH_MODE=apply` is intentionally opt-in and does not establish device boot
compatibility or AVB compatibility. It is for controlled analysis only, not a
recommendation to flash a device.

## Scope and limitations

`fastbootd` requires more than a changed branch: its binary, fastboot HAL,
SELinux policy, dynamic-partition access, and the device's AVB policy must all
work together. A matching signature, a successful repack, or a successful CI
run is therefore not proof that a recovery is safe to boot or suitable for
flashing a GSI.

## Credits

- [Pierre-Hugues Husson](https://github.com/phhusson)
- [James Nguyen](https://github.com/thongass000)
