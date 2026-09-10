#!/bin/bash
# selene A17 (PixelOS seventeen) build for crave.io
#
# Crave jobs run in a fresh workspace, so nothing that was pushed over
# `crave ssh` is visible here. This script is fetched over HTTPS and is
# self-contained: it installs the local manifest, syncs the selene
# projects and builds.
#
#   crave run --projectID 82 --no-artifacts --no-patch --detached \
#     bash -c "curl -sL https://raw.githubusercontent.com/mt6768-S/crave-selene/main/build.sh | bash"

set -o pipefail

BASE="https://raw.githubusercontent.com/mt6768-S/crave-selene/main"
LUNCH_TARGET="custom_selene-cp1a-userdebug"

echo "########## selene build started $(date -u +%FT%TZ) ##########"
echo "cwd     : $(pwd)"
echo "cores   : $(nproc)"
free -g | head -2
df -h . | tail -1

# --- locate the workspace root -------------------------------------------
if [ ! -d .repo ]; then
  for d in /tmp/src/android "$HOME" .; do
    if [ -d "$d/.repo" ]; then cd "$d"; break; fi
  done
fi
if [ ! -d .repo ]; then
  echo "FATAL: no .repo found, cwd=$(pwd)"
  ls -la
  exit 1
fi
echo "workspace: $(pwd)"

# --- local manifest -------------------------------------------------------
echo "########## local manifest ##########"
mkdir -p .repo/local_manifests
curl -sL "$BASE/local_manifests/selene.xml" -o .repo/local_manifests/selene.xml || exit 1
echo "  $(wc -c < .repo/local_manifests/selene.xml) bytes, $(grep -c '<project' .repo/local_manifests/selene.xml) project entries"

# --- sync -----------------------------------------------------------------
echo "########## repo sync ##########"
date -u +'sync start %FT%TZ'
repo sync -c -j"$(nproc)" --no-clone-bundle --optimized-fetch --force-sync
rc=$?
date -u +'sync end   %FT%TZ'
echo "SYNC_RC=$rc"
if [ $rc -ne 0 ]; then
  echo "retrying sync once"
  find .repo -name '*.lock' -delete 2>/dev/null
  repo sync -c -j8 --no-clone-bundle --force-sync
  rc=$?
  echo "SYNC_RC2=$rc"
  [ $rc -ne 0 ] && { echo "FATAL: sync failed"; exit $rc; }
fi

echo "--- selene projects ---"
for p in device/xiaomi/selene vendor/xiaomi/selene kernel/xiaomi/selene \
         device/xiaomi/selene-kernel hardware/mediatek hardware/xiaomi \
         device/mediatek/sepolicy_vndr vendor/mediatek/ims; do
  printf '  %-34s %s\n' "$p" "$([ -d "$p" ] && find "$p" -type f 2>/dev/null | wc -l || echo MISSING)"
done

# --- build ----------------------------------------------------------------
echo "########## envsetup + lunch ##########"
source build/envsetup.sh >/dev/null 2>&1
lunch "$LUNCH_TARGET"
echo "LUNCH_RC=$?"

echo "########## m nothing (soong analysis) ##########"
T0=$(date +%s)
m nothing
rc_n=$?
echo "M_NOTHING_RC=$rc_n  ($(( $(date +%s) - T0 ))s)"
[ $rc_n -ne 0 ] && { echo "FATAL: soong analysis failed"; exit $rc_n; }

echo "########## full build ##########"
date -u +'build start %FT%TZ'
m -j"$(nproc)"
rc_b=$?
date -u +'build end   %FT%TZ'
echo "BUILD_RC=$rc_b  (total $(( ($(date +%s) - T0)/60 )) min)"

echo "########## output ##########"
ls -lh out/target/product/selene/*.zip 2>/dev/null || echo "  no zip"
ls -lh out/target/product/selene/{boot,dtbo,vbmeta}*.img 2>/dev/null | head

echo "########## done $(date -u +%FT%TZ) rc=$rc_b ##########"
exit $rc_b
