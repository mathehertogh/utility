TARGET = example
SRCDIR = src
HDRDIR = include
OBJDIR = obj

CC = gcc
CFLAGS += -g -Wall -Wextra -I$(HDRDIR)
DFLAGS ?= -DEXAMPLE_PROJECT=1 -DMATHE=97
LDFLAGS += -lpthread -pthread -lm

SRC:=$(wildcard $(SRCDIR)/*.c)
HDR:=$(wildcard $(HDRDIR)/*.h)
TMP:=$(SRC:$(SRCDIR)/%=obj/%)
OBJ:=$(TMP:.c=.o)

default: $(OBJDIR) $(TARGET)

$(OBJDIR):
	@mkdir -p $@

$(TARGET): $(OBJ)
	@echo "LD $@"
	@$(CC) $^ -o $@

$(OBJDIR)/%.o : $(SRCDIR)/%.c $(HDR) 
	@echo "CC $<"
	@$(CC) $(CFLAGS) $(DFLAGS) -c -o $@ $<

.PHONY: clean
clean:
	rm -rf $(OBJDIR)
	rm -f $(TARGET)
