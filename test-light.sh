#!/bin/bash
# test-light.sh — Linux 侧定位"性能灯"对应 EC 寄存器（0x7A5 vs 0x727 bit6 vs 0x726 bit7）
#
# 前提: 控制台在线位 0x741=1（软件接管态），否则固件可能覆写实验值/灯不受控。
#   驱动加载时自动置位；或手动: acpi_call 写 0x741=0x81。
# 用法: sudo ./test-light.sh
set -euo pipefail

ECRR_PATH=/proc/acpi/call

ecr() { # ecr <addr-hex> -> 打印值
    echo "\\_SB.INOU.ECRR 0x$1" > "$ECRR_PATH"
    cat "$ECRR_PATH"
}

ecw() { # ecw <addr-hex> <val-hex>
    echo "\\_SB.INOU.ECRW 0x$1 0x$2" > "$ECRR_PATH"
    echo "  Write(0x$1, 0x$2) OK, 回读=$(ecr "$1")"
}

pause() { echo "  >>> 现在看灯: $1，看完按回车继续"; read -r _; }

echo "==> 准备: modprobe acpi_call"
modprobe acpi_call 2>/dev/null || echo "  (acpi_call 已加载或加载失败，继续)"

echo "==> 检查在线位 0x741 (期望 bit0=1)"
v=$(ecr 741); echo "  0x741 = $v"
if [ $((0x$v & 1)) -eq 0 ]; then
    echo "  在线位=0，先置 0x81:"
    ecw 741 81
fi
echo "  0x751 = $(ecr 751)  (当前模式字节，注意不要碰)"

echo
echo "########## 实验 A: 0x7A5 低 2 位 ##########"
echo "  基线 0x7A5 = $(ecr 7A5)"
ecw 7A5 00;  pause "A1: 0x7A5=0x00"
ecw 7A5 01;  pause "A2: 0x7A5=0x01 (灯变了吗?)"
ecw 7A5 02;  pause "A3: 0x7A5=0x02"
ecw 7A5 03;  pause "A4: 0x7A5=0x03"
ecw 7A5 00;  echo "  恢复 0x7A5=0x00"
echo "(注: 0x7A5 高位有 FAN_QUIET 等位，本机基线 0x00，整字节写风险低)"

echo
echo "########## 实验 B: 0x727 bit6 (白灯?) ##########"
echo "  基线 0x727 = $(ecr 727)"
v=$(ecr 727); nv=$(( (0x$v & 0xBF) | 0x40 )); nv=$(printf '%02X' $nv)
ecw 727 "$nv"; pause "B1: 0x727 bit6=1 (0x$nv) 灯变了吗?"
v=$(ecr 727); nv=$(( 0x$v & 0xBF )); nv=$(printf '%02X' $nv)
ecw 727 "$nv"; pause "B2: 0x727 bit6=0 (0x$nv) 灯灭了吗?"

echo
echo "########## 实验 C: 0x726 bit7 (标志? 灯?) ##########"
echo "  基线 0x726 = $(ecr 726)"
v=$(ecr 726); nv=$(( (0x$v & 0x7F) | 0x80 )); nv=$(printf '%02X' $nv)
ecw 726 "$nv"; pause "C1: 0x726 bit7=1 (0x$nv)"
v=$(ecr 726); nv=$(( 0x$v & 0x7F )); nv=$(printf '%02X' $nv)
ecw 726 "$nv"; echo "  恢复 0x726=0x$nv"

echo
echo "==> 实验结束。对照记录:"
echo "  0x7A5 低2位(01/02/03) 灯有无变化？"
echo "  0x727 bit6 灯有无变化？"
echo "  0x726 bit7 灯有无变化？"
echo "  哪一步灯的变化 + 变化形态(亮/白/橙/闪) 就是答案。"