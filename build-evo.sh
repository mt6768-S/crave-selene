#!/bin/bash
# selene Evolution X cnb (Android 17) build for crave.io.
#
# Self-contained: re-inits the workspace to the Evolution X manifest, installs
# the selene local manifest, syncs, extracts vendor/xiaomi/selene from the
# stock MIUI ROM, then builds.
#
#   crave run --no-patch -- "curl -sL https://raw.githubusercontent.com/mt6768-S/crave-selene/main/build-evo.sh | ROM_URL=<miui zip url> bash"
#
# STAGE=nothing stops after soong analysis (m nothing), which is the cheap
# way to find soong errors before spending a full build.

set -o pipefail

BASE="https://raw.githubusercontent.com/mt6768-S/crave-selene/main"
EVO_BRANCH="${EVO_BRANCH:-cnb}"
LUNCH_TARGET="${LUNCH_TARGET:-lineage_selene-cp2a-userdebug}"
STAGE="${STAGE:-full}"
COMMON_VENDOR="https://github.com/mt6768-S/proprietary_vendor_xiaomi_mt6768-common"
COMMON_VENDOR_BRANCH="lineage-23.2"

say() { echo "########## $* ($(date -u +%FT%TZ)) ##########"; }
die() { echo "FATAL: $*"; exit 1; }

# Crave cancels a job that prints nothing for ~15 min (job 308631 died during
# the silent checkout wipe). Keep a heartbeat on stdout for the whole run.
( while sleep 60; do echo "[heartbeat $(date -u +%H:%M:%S)]"; done ) &
HB_PID=$!
trap 'kill $HB_PID 2>/dev/null' EXIT

say "selene evo build started"
echo "cwd: $(pwd)  cores: $(nproc)  stage: $STAGE"
free -g | head -2
df -h . | tail -1

# --- workspace root -------------------------------------------------------
if [ ! -d .repo ]; then
  for d in /tmp/src/android "$HOME" .; do
    [ -d "$d/.repo" ] && { cd "$d"; break; }
  done
fi
[ -d .repo ] || die "no .repo found, cwd=$(pwd)"
echo "workspace: $(pwd)"

# --- manifest -------------------------------------------------------------
say "repo init Evolution-X/manifest $EVO_BRANCH"
rm -rf .repo/local_manifests
git lfs install --skip-repo >/dev/null 2>&1
repo init -u https://github.com/Evolution-X/manifest -b "$EVO_BRANCH" --git-lfs --depth=1 \
  || die "repo init failed"
mkdir -p .repo/local_manifests
curl -sfL "$BASE/local_manifests/evo-selene.xml" -o .repo/local_manifests/evo-selene.xml \
  || die "local manifest download failed"

# Switching an existing workspace to another manifest leaves checkouts linked
# to the old manifest's object stores ("hooks is different in
# .repo/projects/X.git vs .repo/project-objects/Y.git"), and repo then refuses
# to check them out. Do the switch once: drop every checkout and
# .repo/projects, keep .repo/project-objects as a fetch cache.
MARK=.repo/.selene-manifest
if [ "$(cat "$MARK" 2>/dev/null)" != "evo-$EVO_BRANCH" ]; then
  say "switching workspace to evo-$EVO_BRANCH (dropping old checkouts)"
  find . -mindepth 1 -maxdepth 1 ! -name .repo -exec rm -rf {} +
  rm -rf .repo/projects
fi
find .repo -name '*.lock' -delete 2>/dev/null

# --- sync -----------------------------------------------------------------
say "sync"
sync_once() {
  repo sync -c -j"$(nproc)" --no-clone-bundle --no-tags --optimized-fetch     --force-sync --force-remove-dirty 2>&1 | tee /tmp/sync.log
}
sync_once
if grep -q -E "Unable to fully sync|Checking out local projects failed|hooks is different" /tmp/sync.log; then
  echo "sync incomplete, repairing listed projects and retrying once"
  grep -o "hooks is different in [^ ]*/.repo/projects/[^ ]*\.git" /tmp/sync.log     | sed 's#.*/.repo/projects/##; s#\.git$##' | sort -u | while read -r p; do
      rm -rf "$p" ".repo/projects/$p.git"
    done
  find .repo -name '*.lock' -delete 2>/dev/null
  sync_once
  grep -q -E "Unable to fully sync|Checking out local projects failed|hooks is different" /tmp/sync.log     && die "sync still incomplete"
fi
echo "evo-$EVO_BRANCH" > "$MARK"
echo "SYNC_OK"
for p in device/xiaomi/selene kernel/xiaomi/mt6768 hardware/mediatek hardware/xiaomi          device/mediatek/sepolicy_vndr vendor/mediatek/ims vendor/lineage          tools/extract-utils prebuilts/extract-tools          prebuilts/clang/kernel/linux-x86/clang-r416183b; do
  printf '  %-48s %s
' "$p" "$([ -d "$p" ] && echo ok || echo MISSING)"
done
[ -f vendor/lineage/config/evolution.mk ] || die "vendor/lineage is not Evolution X"
[ -f device/xiaomi/selene/lineage_selene.mk ] || die "selene tree missing after sync"

# --- vendor/xiaomi/selene ---------------------------------------------------
say "vendor extraction"
[ -n "$ROM_URL" ] || die "ROM_URL is not set (stock MIUI zip for selene)"
DUMP=/tmp/selene-dump
mkdir -p "$DUMP"
ROM="$DUMP/$(basename "${ROM_URL%%\?*}")"
if [ ! -s "$ROM" ]; then
  curl -fL --retry 3 -o "$ROM" "$ROM_URL" || die "ROM download failed"
fi
ls -lh "$ROM"

# Pinned blobs (the fire Codec2 stack) do not match the selene dump. Seed
# them from mt6768-common's vendor so extract-utils keeps them; otherwise it
# reports MISMATCH and skips their fixups.
OUTV=vendor/xiaomi/selene/proprietary
mkdir -p "$OUTV"
CV=/tmp/common-vendor
rm -rf "$CV"
git clone -q --depth 1 -b "$COMMON_VENDOR_BRANCH" "$COMMON_VENDOR" "$CV" \
  || die "common vendor clone failed"
python3 - "$CV/proprietary" "$OUTV" device/xiaomi/selene/proprietary-files.txt <<'PY'
import hashlib, os, shutil, sys
src, out, lst = sys.argv[1:]
seeded = missing = 0
for line in open(lst):
    line = line.strip()
    if not line or line.startswith('#') or '|' not in line:
        continue
    spec, *hashes = line.split('|')
    spec = spec.lstrip('-').split(';')[0]
    s, _, d = spec.partition(':')
    d = d or s
    for cand in (d, s):
        p = os.path.join(src, cand)
        if os.path.isfile(p) and hashlib.sha1(open(p, 'rb').read()).hexdigest() in hashes:
            os.makedirs(os.path.dirname(os.path.join(out, d)), exist_ok=True)
            shutil.copy2(p, os.path.join(out, d))
            seeded += 1
            break
    else:
        missing += 1
        print('  not seeded:', d)
print('pinned seeded=%d missing=%d' % (seeded, missing))
PY

( cd device/xiaomi/selene && ./extract-files.py "$ROM" ) 2>&1 | tee /tmp/extract.log
rc=$?
echo "EXTRACT_RC=$rc"
grep -i -E 'mismatch|error|failed' /tmp/extract.log | head -40
[ $rc -eq 0 ] || die "extract-files failed"
[ -f vendor/xiaomi/selene/BoardConfigVendor.mk ] || die "BoardConfigVendor.mk missing"
echo "vendor files: $(find vendor/xiaomi/selene/proprietary -type f | wc -l)"
rm -f "$ROM"

# --- build ----------------------------------------------------------------
say "envsetup + lunch $LUNCH_TARGET"
source build/envsetup.sh >/dev/null 2>&1
lunch "$LUNCH_TARGET" || die "lunch failed"

say "m nothing (soong analysis)"
T0=$(date +%s)
m nothing
rc=$?
echo "M_NOTHING_RC=$rc ($(( $(date +%s) - T0 ))s)"
[ $rc -eq 0 ] || die "soong analysis failed"
[ "$STAGE" = nothing ] && { say "done (stage nothing)"; exit 0; }

say "m evolution"
m evolution -j"$(nproc)"
rc=$?
echo "BUILD_RC=$rc (total $(( ($(date +%s) - T0) / 60 )) min)"

say "output"
ls -lh out/target/product/selene/EvolutionX-*.zip out/target/product/selene/*.img 2>/dev/null | head -20
say "done rc=$rc"
exit $rc
