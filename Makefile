# Mechanical Revolution (Mechrevo) fork of uniwill-laptop
# Module name: uniwill-laptop-mr (modprobe uniwill-laptop-mr)
# Source: uniwill-acpi-mr.c + uniwill-wmi-mr.c (renamed to avoid clash with mainline)
CFLAGS_uniwill-acpi-mr.o := -DDEBUG
CFLAGS_uniwill-wmi-mr.o := -DDEBUG

obj-m += uniwill-laptop-mr.o
uniwill-laptop-mr-y := uniwill-acpi-mr.o uniwill-wmi-mr.o

all:
	make -C /lib/modules/`uname -r`/build M=`pwd` modules

clean:
	make -C /lib/modules/`uname -r`/build M=`pwd` clean