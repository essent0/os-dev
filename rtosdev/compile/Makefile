# Out-of-tree FreeRTOS image for QEMU mps2-an385 (Cortex-M3).
# Invoke through ./build.sh so the toolchain overlay is visible.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
KERNEL := $(ROOT)/../FreeRTOS-Kernel
BUILD := $(ROOT)/build
ELF := $(BUILD)/freertos.elf

# Override a host CC from the environment. Command-line `make CC=` still wins.
CROSS ?= arm-none-eabi-
CC := $(CROSS)gcc
SIZE := $(CROSS)size

CPUFLAGS := -mthumb -mcpu=cortex-m3 -ffreestanding -fno-omit-frame-pointer
CFLAGS := $(CPUFLAGS) -g3 -Og -ffunction-sections -fdata-sections
CFLAGS += -Wall -Wextra -Wshadow -Wno-unused-parameter
CFLAGS += -I$(ROOT)/guest
CFLAGS += -I$(KERNEL)/include
CFLAGS += -I$(KERNEL)/portable/GCC/ARM_CM3
CFLAGS += -MMD -MP

LDFLAGS := $(CPUFLAGS) -nostartfiles
LDFLAGS += -specs=nano.specs -specs=nosys.specs
LDFLAGS += -Wl,--gc-sections
LDFLAGS += -Wl,-T,$(ROOT)/guest/link.ld
LDFLAGS += -Wl,-Map,$(BUILD)/freertos.map

KERNEL_SRCS := tasks.c list.c queue.c timers.c event_groups.c stream_buffer.c
KERNEL_OBJS := $(patsubst %.c,$(BUILD)/obj/kernel/%.o,$(KERNEL_SRCS))
PORT_OBJS := $(BUILD)/obj/port/port.o $(BUILD)/obj/port/heap_4.o
GUEST_SRCS := startup.c console.c semihost.c main.c shell.c hooks.c
GUEST_OBJS := $(patsubst %.c,$(BUILD)/obj/guest/%.o,$(GUEST_SRCS))
EXP_SRCS := $(wildcard $(ROOT)/share/experiments/src/*.c)
EXP_OBJS := $(patsubst $(ROOT)/share/experiments/src/%.c,$(BUILD)/obj/exp/%.o,$(EXP_SRCS))

OBJS := $(KERNEL_OBJS) $(PORT_OBJS) $(GUEST_OBJS) $(EXP_OBJS)
DEPS := $(OBJS:.o=.d)

ifeq ($(shell command -v $(CC) 2>/dev/null),)
$(error $(CC) is not on PATH. Run ./build.sh so deps.sh can expose the toolchain)
endif

.PHONY: all clean

all: $(ELF)

$(ELF): $(OBJS) $(ROOT)/guest/link.ld
	@mkdir -p $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) $(OBJS) -o $@
	$(SIZE) $@

$(BUILD)/obj/kernel/%.o: $(KERNEL)/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/obj/port/port.o: $(KERNEL)/portable/GCC/ARM_CM3/port.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/obj/port/heap_4.o: $(KERNEL)/portable/MemMang/heap_4.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/obj/guest/%.o: $(ROOT)/guest/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/obj/exp/%.o: $(ROOT)/share/experiments/src/%.c
	@mkdir -p $(dir $@)
	$(CC) $(CFLAGS) -c $< -o $@

clean:
	rm -rf $(BUILD)

-include $(DEPS)
