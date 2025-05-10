# Makefile for Balde.

NIM = nim
VERSION = $(shell nimble dump | grep -oP 'version: "\K[^\"]*')
NIMFLAGS =
CXX = gcc

ifeq ($(RELEASE), 1)
	NIMFLAGS += \
		--define:release \
		--define:speed
endif

ifeq ($(DEBUG), 1)
	NIMFLAGS += \
		    --define:gdb
endif

balde:
	$(NIM) cpp $(NIMFLAGS) --define:NimblePkgVersion=$(VERSION) --cc:$(CXX) --out:bin/balde src/balde.nim

clean:
	rm bin/balde
