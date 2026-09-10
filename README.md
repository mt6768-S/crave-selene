# crave-selene

Build scripts for Xiaomi Redmi 10 2022 (`selene`) on [crave.io](https://crave.io).

Crave jobs run in a fresh workspace, so anything pushed over `crave ssh` is
not visible to them. `build.sh` is fetched over HTTPS instead and is
self-contained: it installs the local manifest, syncs the selene projects
and builds.

## Usage

```bash
crave run --projectID 82 --no-artifacts --no-patch --detached \
  bash -c "curl -sL https://raw.githubusercontent.com/mt6768-S/crave-selene/main/build.sh | bash"
```

Project 82 is PixelOS; `build.sh` targets `custom_selene-cp1a-userdebug`
(A17, release config `cp1a`).

## What the local manifest pulls

| path | repo |
|---|---|
| `device/xiaomi/selene` | `mt6768-S/android_device_xiaomi_selene` |
| `vendor/xiaomi/selene` | `mt6768-S/android_vendor_xiaomi_selene` |
| `kernel/xiaomi/selene` | `xiaomi-selene/android_kernel_xiaomi_selene` (4.14) |
| `device/xiaomi/selene-kernel` | prebuilt dtbo |
| `hardware/mediatek`, `hardware/xiaomi` | `xiaomi-selene` |
| `device/mediatek/sepolicy_vndr` | `xiaomi-selene` |
| `vendor/mediatek/ims` | `xiaomi-selene` |

PixelOS already provides `vendor/lineage`, `vendor/custom`,
`hardware/lineage/*`, `tools/extract-utils` and `prebuilts/extract-tools`,
so those must not be listed again or `repo` fails with a duplicate path.
