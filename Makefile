# vim: ft=make

comma := ,
empty :=
space := $(empty) $(empty)

CC       ?= gcc
CFLAGS    = -Wall -g -O1 -Wl,--as-needed

UNAME    := $(shell uname)
HOSTNAME := $(shell hostname)
MACHTYPE := $(shell dist/prepare -m)

OBJ      ?= obj/host.$(HOSTNAME)

ifeq ($(UNAME),Linux)
	OSFLAGS := -DHAVE_LINUX
	KRB_LDLIBS := -lkrb5 -lcom_err
endif
ifeq ($(UNAME),FreeBSD)
	OSFLAGS := -DHAVE_FREEBSD
	KRB_LDLIBS := -lkrb5 -lcom_err
endif
ifeq ($(UNAME),NetBSD)
	OSFLAGS := -DHAVE_NETBSD
	KRB_LDLIBS := -lkrb5 -lcom_err
endif
ifeq ($(UNAME),CYGWIN_NT-5.1)
	OSFLAGS := -DHAVE_CYGWIN
	KRB_LDLIBS := -lkrb5 -lcom_err
endif
ifeq ($(UNAME),SunOS)
	OSFLAGS := -DHAVE_SOLARIS
	KRB_LDLIBS := -lkrb5
endif

override CFLAGS += -I./misc $(OSFLAGS)

# misc targets

.PHONY: default pre clean mrproper

ifdef obj
default: $(addprefix $(OBJ)/,$(subst $(comma),$(space),$(obj)))
endif

ifndef obj
default: basic
endif

pre:
	@dist/prepare

clean:
	rm -rf obj/arch.* obj/dist.* obj/host.*

mrproper:
	git clean -dfX

# compile targets

BASIC_BINS := args pause proctool silentcat spawn strtool
KRB_BINS   := k5userok pklist
LINUX_BINS := linux26 setns subreaper tapchown
MISC_BINS  := bgrep logwipe natsort ttysize writevt xor xors

.PHONY: all basic krb linux misc

basic: $(addprefix $(OBJ)/,$(BASIC_BINS))
krb:   $(addprefix $(OBJ)/,$(KRB_BINS))
linux: $(addprefix $(OBJ)/,$(LINUX_BINS))
misc:  $(addprefix $(OBJ)/,$(MISC_BINS))

all: basic krb misc

ifeq ($(UNAME),Linux)
all: linux
endif

$(OBJ)/args:		misc/args.c
$(OBJ)/bgrep:		thirdparty/bgrep.c
$(OBJ)/k5userok:	kerberos/k5userok.c | kerberos/krb5.h
$(OBJ)/linux26:		thirdparty/linux26.c
$(OBJ)/logwipe:		thirdparty/logwipe.c
$(OBJ)/natsort:		thirdparty/natsort.c thirdparty/strnatcmp.c
$(OBJ)/pklist:		kerberos/pklist.c | kerberos/krb5.h
$(OBJ)/pause:		system/pause.c
$(OBJ)/proctool:	system/proctool.c misc/util.c
$(OBJ)/setns:		system/setns.c
$(OBJ)/silentcat:	misc/silentcat.c
$(OBJ)/snappy:		LDLIBS = -lsnappy
$(OBJ)/snappy:		misc/snappy.c thirdparty/crc32.c
$(OBJ)/spawn:		system/spawn.c misc/util.c
$(OBJ)/strtool:		misc/strtool.c misc/util.c
$(OBJ)/subreaper:	system/subreaper.c
$(OBJ)/tapchown:	net/tapchown.c
$(OBJ)/ttysize:		system/ttysize.c
$(OBJ)/writevt:		thirdparty/writevt.c
$(OBJ)/xor:		misc/xor.c
$(OBJ)/xors:		misc/xors.c

misc/util.c:		| misc/util.h

$(OBJ)/%:		| dist/empty.c
	@echo [$(CC)] $@ : $^
	@$(LINK.c) $^ $(LOADLIBES) $(LDLIBS) -o $@

$(addprefix $(OBJ)/,$(KRB_BINS)): LDLIBS = $(KRB_LDLIBS)

# hack for old Make (unsupported order-only deps)
dist/empty.c: pre
