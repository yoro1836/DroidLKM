ifneq ($(KERNELRELEASE),)
include $(src)/vendor/kallrecon/deps.mk
SCX_DIR ?= src/scx61
ifeq ($(TARGET),btfprobe)
obj-m := droidspaces_btfprobe.o
droidspaces_btfprobe-y := $(SCX_DIR)/btfprobe.o
else
# Upstream's kernel/sched/ext.c (src/scx61/upstream, through
# scripts/gen-scx61.py) with its android14-6.1 glue.
obj-m := droidspaces_scx.o
droidspaces_scx-y := $(SCX_DIR)/main.o $(SCX_DIR)/ext-port.o $(SCX_DIR)/cpumask-port.o \
	$(SCX_DIR)/task-kfuncs.o $(SCX_DIR)/bpf-fixes.o $(SCX_DIR)/kptr.o $(SCX_DIR)/btf.o \
	$(SCX_DIR)/hooks.o \
	$(addprefix vendor/kallrecon/,$(DEPS_LIB_OBJS))
endif
ifneq ($(GKI_ANDROID),)
ccflags-y += -DDS_GKI_ANDROID='"$(GKI_ANDROID)"' -DDS_GKI_VERSION='"$(GKI_VERSION)"'
endif
ccflags-y += -I$(srctree) -I$(src)/vendor/kallrecon/lib -std=gnu11
ccflags-y += -Wno-declaration-after-statement

$(obj)/%.o: $(src)/%.c $(recordmcount_source) FORCE
	$(call if_changed_rule,cc_o_c)
	$(call cmd,force_checksrc)

$(obj)/%.o: $(src)/%.S FORCE
	$(call if_changed_rule,as_o_S)
else
.DEFAULT_GOAL := all
ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
OUT ?= $(ROOT)/out/default
.PHONY: all clean
all:
	@test -n "$(KDIR)" || { echo 'Set KDIR to a prepared kernel/DDK build directory.' >&2; exit 1; }
	@mkdir -p "$(OUT)"
	$(MAKE) -C "$(KDIR)" M="$(abspath $(OUT))" src="$(ROOT)" srcroot="$(ROOT)" modules
clean:
	@test -n "$(KDIR)" || { echo 'Set KDIR before cleaning.' >&2; exit 1; }
	$(MAKE) -C "$(KDIR)" M="$(abspath $(OUT))" src="$(ROOT)" srcroot="$(ROOT)" clean
endif
