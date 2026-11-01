#!/usr/bin/env bash
# Diagnose and, only on an exact known match, patch Samsung recovery's
# fastbootd gate. This script deliberately does not re-sign AVB: a locally
# generated key cannot be trusted by the stock vbmeta chain.

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
magiskboot="$repo_root/magiskboot"
prepared_image="$repo_root/r.img"
report="$repo_root/patch-report.txt"
mode="${PATCH_MODE:-audit}"
allow_unverified="${ALLOW_UNVERIFIED_CANDIDATE:-false}"
work_dir=""
verify_dir=""

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  local status=$?
  if (( status != 0 )); then
    { printf 'PATCH_RESULT=ERROR\n'; printf 'ERROR_LINE=%s\n' "$LINENO"; } >> "$report" 2>/dev/null || :
  fi
  [[ -z "$work_dir" ]] || rm -rf -- "$work_dir"
  [[ -z "$verify_dir" ]] || rm -rf -- "$verify_dir"
  exit "$status"
}
trap cleanup EXIT

[[ "$mode" == "audit" || "$mode" == "apply" ]] || die "PATCH_MODE must be audit or apply"
[[ -x "$magiskboot" ]] || die "magiskboot is not executable: $magiskboot"
[[ -s "$prepared_image" ]] || die "Prepared image not found: $prepared_image"
[[ -f "$report" ]] || die "Preparation report not found: $report"

# Count exact byte patterns without relying on grep's binary-file behavior.
hex_count() {
  python3 - "$1" "$2" <<'PY'
from pathlib import Path
import sys
path, hex_pattern = sys.argv[1:]
try:
    pattern = bytes.fromhex(hex_pattern)
except ValueError as exc:
    raise SystemExit(f"invalid hex pattern: {exc}")
if not pattern:
    raise SystemExit("empty hex pattern")
print(Path(path).read_bytes().count(pattern))
PY
}

append_profile_status() {
  local name="$1" old="$2" new="$3" target="$4"
  local old_count new_count state
  old_count="$(hex_count "$target" "$old")"
  new_count="$(hex_count "$target" "$new")"
  if (( old_count == 0 && new_count == 0 )); then state="not-present"
  elif (( old_count == 0 && new_count == 1 )); then state="already-patched"
  elif (( old_count == 1 && new_count == 0 )); then state="candidate"
  else state="ambiguous"; fi
  printf 'PROFILE_%s=old:%s,new:%s,state:%s\n' "$name" "$old_count" "$new_count" "$state" >> "$report"
}

# Historic alternatives from the original project and current phhusson
# upstream. They are diagnostic probes only: a matching byte string by itself
# is not sufficient proof that modifying it is safe.
legacy_profiles=(
  'legacy_01|e10313aaf40300aa6ecc009420010034|e10313aaf40300aa6ecc0094'
  'legacy_02|eec3009420010034|eec3009420010035'
  'legacy_03|3ad3009420010034|3ad3009420010035'
  'legacy_04|50c0009420010034|50c0009420010035'
  'legacy_05|080109aae80000b4|080109aae80000b5'
  'legacy_06|20f0a6ef38b1681c|20f0a6ef38b9681c'
  'legacy_07|23f03aed38b1681c|23f03aed38b9681c'
  'legacy_08|20f09eef38b1681c|20f09eef38b9681c'
  'legacy_09|26f0ceec30b1681c|26f0ceec30b9681c'
  'legacy_10|24f0fcee30b1681c|24f0fcee30b9681c'
  'legacy_11|27f02eeb30b1681c|27f02eeb30b9681c'
  'legacy_12|b4f082ee28b1701c|b4f082ee28b970c1'
  'legacy_13|9ef0f4ec28b1701c|9ef0f4ec28b9701c'
  'upstream_2024_01|9ef00ced28b1701c|9ef00ced28b9701c'
  'upstream_2024_02|2001597ae0000054|2001597ae1000054'
  'upstream_2024_03|2001597ac0000054|2001597ac1000054'
  'upstream_2024_04|9ef0fcec28b1701c|9ef0fced28b1701c'
  'upstream_2024_05|9ef00ced28b1701c|9ef00ced28b9701c'
  'upstream_2024_06|24f0f2ea30b1681c|24f0f2ea30b9681c'
  'upstream_2025_01|e0031f2a8e000014|200080528e000014'
  'upstream_2025_02|41010054a0020012f44f48a9|4101005420008052f44f48a9'
)

work_dir="$(mktemp -d "$repo_root/.recovery-patch.XXXXXX")"
pushd "$work_dir" >/dev/null
"$magiskboot" unpack "$prepared_image"
ramdisk="ramdisk.cpio"
[[ -f vendor_ramdisk/recovery.cpio ]] && ramdisk="vendor_ramdisk/recovery.cpio"
[[ -f "$ramdisk" ]] || die "No recovery ramdisk found after unpacking"
"$magiskboot" cpio "$ramdisk" extract
recovery_binary="system/bin/recovery"
[[ -f "$recovery_binary" ]] || die "system/bin/recovery is missing from the recovery ramdisk"

binary_description="$(file -b "$recovery_binary")"
[[ "$binary_description" == *'ELF 64-bit LSB'* && "$binary_description" == *'aarch64'* ]] || die "Unexpected recovery binary: $binary_description"
{
  printf 'RECOVERY_BINARY_SHA256=%s\n' "$(sha256sum "$recovery_binary" | awk '{print $1}')"
  printf 'RECOVERY_BINARY_FILE=%s\n' "$binary_description"
  printf 'RAMDISK_PATH=%s\n' "$ramdisk"
  printf 'FASTBOOTD_BINARY_PRESENT=%s\n' "$([[ -x system/bin/fastbootd ]] && printf yes || printf no)"
} >> "$report"

for profile in "${legacy_profiles[@]}"; do
  IFS='|' read -r name old new <<< "$profile"
  append_profile_status "$name" "$old" "$new" "$recovery_binary"
done

# Exact AArch64 context observed in the supplied SM-A166P Android 15 image:
# cset w0,eq (ro.boot.fastbootd == "true") becomes mov w0,#1. The surrounding
# cmp and stack-check branch prevent this from being a generic four-byte match.
a16_profile_name='a16x_android15_fastboot_property_gate'
a16_old='e0179f1a1f0109eba1000054'
a16_new='200080521f0109eba1000054'
append_profile_status "$a16_profile_name" "$a16_old" "$a16_new" "$recovery_binary"
a16_old_count="$(hex_count "$recovery_binary" "$a16_old")"
a16_new_count="$(hex_count "$recovery_binary" "$a16_new")"

if [[ "$mode" == "audit" ]]; then
  printf 'PATCH_MODE=audit\nPATCH_RESULT=NOT_MODIFIED\n' >> "$report"
  printf 'Audit complete; no recovery binary was modified.\n'
  popd >/dev/null
  exit 0
fi

[[ "$allow_unverified" == "true" ]] || die "Refusing apply mode without ALLOW_UNVERIFIED_CANDIDATE=true"
if (( a16_old_count == 0 && a16_new_count == 1 )); then
  printf 'PATCH_MODE=apply\nPATCH_RESULT=ALREADY_PATCHED\n' >> "$report"
  printf 'The exact A16 profile is already patched; no second patch was applied.\n'
  popd >/dev/null
  exit 0
fi
(( a16_old_count == 1 && a16_new_count == 0 )) || die "No unique supported A16 profile; refusing to modify this recovery"

"$magiskboot" hexpatch "$recovery_binary" "$a16_old" "$a16_new"
(( $(hex_count "$recovery_binary" "$a16_old") == 0 )) || die "Post-patch verification: old context remains"
(( $(hex_count "$recovery_binary" "$a16_new") == 1 )) || die "Post-patch verification: new context is not unique"
"$magiskboot" cpio "$ramdisk" "add 0755 system/bin/recovery system/bin/recovery"
candidate="$repo_root/recovery-patched-unsigned.img"
"$magiskboot" repack "$prepared_image" "$candidate"
[[ -s "$candidate" ]] || die "magiskboot did not create a candidate image"

# Re-open the output and prove its ramdisk and exact patched context survived.
verify_dir="$(mktemp -d "$repo_root/.recovery-verify.XXXXXX")"
pushd "$verify_dir" >/dev/null
"$magiskboot" unpack "$candidate"
verify_ramdisk="ramdisk.cpio"
[[ -f vendor_ramdisk/recovery.cpio ]] && verify_ramdisk="vendor_ramdisk/recovery.cpio"
[[ -f "$verify_ramdisk" ]] || die "Candidate lacks a recovery ramdisk"
"$magiskboot" cpio "$verify_ramdisk" extract
verify_binary="system/bin/recovery"
[[ -f "$verify_binary" ]] || die "Candidate lacks system/bin/recovery"
[[ "$(file -b "$verify_binary")" == *'ELF 64-bit LSB'* ]] || die "Candidate recovery binary is not a 64-bit ELF"
(( $(hex_count "$verify_binary" "$a16_old") == 0 )) || die "Candidate still contains the old gate"
(( $(hex_count "$verify_binary" "$a16_new") == 1 )) || die "Candidate does not contain exactly one new gate"
candidate_binary_sha="$(sha256sum "$verify_binary" | awk '{print $1}')"
popd >/dev/null
{
  printf 'PATCH_MODE=apply\n'
  printf 'PATCH_RESULT=CANDIDATE_BUILT_NOT_AVB_SIGNED\n'
  printf 'CANDIDATE_IMAGE_SHA256=%s\n' "$(sha256sum "$candidate" | awk '{print $1}')"
  printf 'CANDIDATE_RECOVERY_BINARY_SHA256=%s\n' "$candidate_binary_sha"
  printf 'AVB_STATUS=NOT_SIGNED_BY_STOCK_KEY_DO_NOT_FLASH_WITH_STOCK_VBMETA\n'
} >> "$report"
printf 'Candidate rebuilt and structurally verified; it is deliberately not AVB-signed.\n'
popd >/dev/null
