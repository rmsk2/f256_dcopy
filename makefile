BINARY=dcopy
SUDO=
PORT=/dev/ttyUSB0
LOADER=loader.bin
LOADERTMP=loader_t.bin
PYTHON=python3
DEL=rm -f


# Default: build PGZ
.PHONY: all
all: $(BINARY).pgz

$(BINARY).pgz: $(BINARY)
	$(PYTHON) make_pgz.py $(BINARY)

$(BINARY): *.asm
	64tass --nostart -o $(BINARY) main.asm


# build and run dcopy
.PHONY: upload
upload: $(BINARY).pgz
	$(SUDO) $(PYTHON) fnxmgr.zip --port $(PORT) --run-pgz $(BINARY).pgz


# Build dcopy and store it in flash
.PHONY: flash
flash: $(LOADER)
	$(SUDO) $(PYTHON) fnxmgr.zip --port $(PORT) --flash-bulk bulk.csv

$(LOADER): $(LOADERTMP) $(BINARY) 
	$(PYTHON) pad_binary.py $(LOADERTMP) $(BINARY) $(LOADER)

$(LOADERTMP): flashloader.asm
	64tass --nostart -o $(LOADERTMP) flashloader.asm


# Clean all artifacts
.PHONY: clean
clean:
	$(DEL) $(BINARY)
	$(DEL) $(BINARY).pgz
	$(DEL) $(LOADER)
	$(DEL) $(LOADERTMP)
