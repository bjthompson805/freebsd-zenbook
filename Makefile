# Build FreeBSD's own mt76/mt7925 driver with the patches it needs.
#
# SRC is a releng/15.1 source tree; OBJ is where kernel and module objects go.
# The patches touch LinuxKPI code that is compiled into the kernel, so both a
# kernel and the modules are built.  The kernel is installed beside the stock
# one (/boot/${INSTKERNNAME}), which keeps pkgbase's /boot/kernel untouched.

SRC?=		/usr/src
OBJ?=		/usr/obj/mt7925
KERNCONF?=	GENERIC
INSTKERNNAME?=	mt7925
MODDIR?=	/boot/modules
JOBS!=		sysctl -n hw.ncpu

MT76=		${SRC}/sys/modules/mt76
MODS=		${OBJ}${MT76}/core/mt76_core.ko ${OBJ}${MT76}/mt7925/if_mt7925.ko

all: kernel modules

patch:
.for p in ${:!ls ${.CURDIR}/patches/*.patch!}
	patch -s -p1 -d ${SRC} -i ${p}
.endfor

kernel:
	cd ${SRC} && env MAKEOBJDIRPREFIX=${OBJ} \
	    make -j${JOBS} buildkernel KERNCONF=${KERNCONF}

modules:
.for d in core mt7925
	mkdir -p ${OBJ}${MT76}/${d}
	make -C ${MT76}/${d} SYSDIR=${SRC}/sys MAKEOBJDIRPREFIX=${OBJ} obj
	make -j${JOBS} -C ${MT76}/${d} SYSDIR=${SRC}/sys MAKEOBJDIRPREFIX=${OBJ}
.endfor

install: install-kernel install-modules

install-kernel:
	cd ${SRC} && env MAKEOBJDIRPREFIX=${OBJ} \
	    make installkernel KERNCONF=${KERNCONF} INSTKERNNAME=${INSTKERNNAME}

install-modules:
	install -m 555 ${MODS} ${MODDIR}/
	kldxref ${MODDIR}

.PHONY: all patch kernel modules install install-kernel install-modules
