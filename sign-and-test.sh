#!/bin/bash
# sign-and-test.sh — build + DKMS MOK-sign + load + verify uniwill-laptop-mr
#
# Secure Boot 已开启，模块必须用已注册到固件的 DKMS MOK 密钥签名后才能 insmod。
# 用法:  sudo ./sign-and-test.sh [insmod|modprobe]
#   insmod   直接加载测试（默认，卸载用 rmmod uniwill-laptop-mr）
#   modprobe 安装到 /lib/modules 并加载（持久化，重启也自动加载）
set -euo pipefail
cd "$(dirname "$0")"

KVER="$(uname -r)"
SIGN_TOOL="/usr/src/kernels/$KVER/scripts/sign-file"
MOK_KEY="/var/lib/dkms/mok.key"
MOK_PUB="/var/lib/dkms/mok.pub"
KO="uniwill-laptop-mr.ko"

mode="${1:-insmod}"

echo "==> [1/6] Secure Boot 状态"
mokutil --sb-state
mokutil --test-key "$MOK_PUB" || true

echo "==> [2/6] 重新编译 (kernel $KVER)"
make clean >/dev/null 2>&1 || true
make -j"$(nproc)"

echo "==> [3/6] 用 DKMS MOK 密钥签名"
if [ ! -r "$MOK_KEY" ]; then
    echo "错误: 无法读取 $MOK_KEY（需要 root，脚本请以 sudo 运行）" >&2
    exit 1
fi
"$SIGN_TOOL" sha256 "$MOK_KEY" "$MOK_PUB" "$KO"
echo "签名完成: $KO"

echo "==> [4/6] 验证签名"
if modinfo "$KO" | grep -q '^signer:'; then
    modinfo "$KO" | grep -E '^(signer|sig_key|filename):'
else
    echo "错误: 签名验证失败（无 signer 字段）" >&2
    exit 1
fi

if [ "$mode" = "modprobe" ]; then
    echo "==> [5/6] 安装到 /lib/modules/$KVER/extra 并 modprobe"
    install -D -m 0644 "$KO" "/lib/modules/$KVER/extra/$KO"
    depmod -a
    modprobe uniwill-laptop-mr
    echo "已安装并加载（重启后自动加载）。"
else
    echo "==> [5/6] insmod 加载（仅本次，不持久）"
    # insmod 不解析依赖：先载入本模块的依赖（modprobe 会处理依赖链）。
    # 依赖来源: modinfo $KO 的 depends 字段 (sparse-keymap, wmi, led-class-multicolor)
    for dep in sparse-keymap wmi led-class-multicolor; do
        if ! lsmod | grep -q "^$(echo "$dep" | tr - _)"; then
            echo "  加载依赖: $dep"
            modprobe "$dep" || { echo "错误: modprobe $dep 失败" >&2; exit 1; }
        else
            echo "  依赖已加载: $dep"
        fi
    done
    if lsmod | grep -q '^uniwill_laptop_mr'; then
        echo "模块已加载，先卸载再重载"
        rmmod uniwill_laptop_mr || true
    fi
    insmod "./$KO"
fi

echo "==> [6/6] 验证驱动状态"
echo "--- lsmod ---"
lsmod | grep -i uniwill || echo "(lsmod 未找到 uniwill*)"
echo "--- 最近 dmesg ---"
dmesg | grep -iE "uniwill|INOU0000|ABBC0F72" | tail -20 || echo "(dmesg 无相关行)"
echo "--- 平台/驱动绑定 ---"
ls -l /sys/bus/platform/drivers/uniwill_acpi_mr 2>/dev/null \
    && ls /sys/bus/platform/drivers/uniwill_acpi_mr/*/ 2>/dev/null
ls -l /sys/bus/wmi/drivers/uniwill-wmi-mr 2>/dev/null
echo "--- platform_profile ---"
for p in /sys/firmware/acpi/platform_profile /sys/class/platform-profile/*/platform_profile; do
    if [ -f "$p" ]; then
        echo "  $p -> $(cat "$p")"
    fi
done
[ -d /sys/class/platform-profile ] && ls /sys/class/platform-profile/ | sed 's/^/  class device: /'
echo "--- silent_boost (EC 0x728) ---"
cat /sys/bus/platform/devices/INOU0000:00/silent_boost 2>/dev/null \
    && echo "  (写入测试: echo 1 > .../silent_boost; echo 0 > .../silent_boost)"

echo
echo "完成。性能模式测试:"
echo "  cat /sys/firmware/acpi/platform_profile   # 当前模式"
echo "  echo performance > /sys/firmware/acpi/platform_profile   # 切狂暴"
echo "性能键测试: 按性能键(电源旁物理键)，再 cat platform_profile 看是否轮换。"
echo "卸载: sudo rmmod uniwill_laptop_mr"