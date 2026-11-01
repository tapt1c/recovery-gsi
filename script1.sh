#!/usr/bin/env bash
# Prepare a Samsung recovery image for magiskboot. Samsung appends a
# SEANDROIDENFORCE marker and AVB footer after the boot image, so refuse to
# guess the boundary if the expected layout is not present.

set -euo pipefail

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
input_image="${RECOVERY_IMAGE:-$repo_root/recovery.img}"
prepared_image="$repo_root/r.img"
report="$repo_root/patch-report.txt"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

[[ -f "$input_image" ]] || die "Recovery image not found: $input_image"
[[ -s "$input_image" ]] || die "Recovery image is empty: $input_image"
magic="$(LC_ALL=C dd if="$input_image" bs=8 count=1 status=none)"
[[ "$magic" == "ANDROID!" ]] || die "Input is not an Android boot image"

# grep's non-zero result for no match is handled explicitly below.
mapfile -t marker_hits < <(LC_ALL=C grep -aob 'SEANDROIDENFORCE' "$input_image" || :)
(( ${#marker_hits[@]} > 0 )) || die "SEANDROIDENFORCE marker not found; refusing to guess image boundaries"
last_marker="${marker_hits[${#marker_hits[@]} - 1]}"
marker_offset="${last_marker%%:*}"
[[ "$marker_offset" =~ ^[0-9]+$ ]] || die "Could not parse marker offset: $last_marker"

input_size="$(wc -c < "$input_image")"
(( marker_offset > 0 && marker_offset < input_size )) || die "Marker offset is outside the input image"
(( marker_offset % 4096 == 0 )) || die "Marker offset $marker_offset is not 4 KiB aligned"

dd if="$input_image" of="$prepared_image" bs=4096 count=$((marker_offset / 4096)) status=none
[[ -s "$prepared_image" ]] || die "Prepared boot image is empty"

{
  printf '# Recovery fastbootd patch report\n'
  printf 'INPUT_IMAGE=%s\n' "$(basename -- "$input_image")"
  printf 'INPUT_SIZE=%s\n' "$input_size"
  printf 'INPUT_SHA256=%s\n' "$(sha256sum "$input_image" | awk '{print $1}')"
  printf 'SEANDROID_MARKER_COUNT=%s\n' "${#marker_hits[@]}"
  printf 'SEANDROID_MARKER_OFFSET=%s\n' "$marker_offset"
  printf 'PREPARED_SIZE=%s\n' "$(wc -c < "$prepared_image")"
  printf 'PREPARED_SHA256=%s\n' "$(sha256sum "$prepared_image" | awk '{print $1}')"
  printf 'PREPARE_RESULT=OK\n'
} > "$report"

printf 'Prepared %s bytes for magiskboot (marker at %s).\n' "$(wc -c < "$prepared_image")" "$marker_offset"
