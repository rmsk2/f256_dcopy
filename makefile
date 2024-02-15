BINARY=dcopy

all: $(BINARY).pgz

$(BINARY): *.asm
	64tass --nostart -o $(BINARY) main.asm

upload: $(BINARY)
	sudo python3 fnxmgr.zip --binary $(BINARY) --address 4000 --port /dev/ttyUSB0

copy: $(BINARY).pgz
	sudo python3 fnxmgr.zip --copy $(BINARY).pgz --port /dev/ttyUSB0

clean:
	rm -f $(BINARY)
	rm -f $(BINARY).pgz

pgz: $(BINARY).pgz

$(BINARY).pgz: $(BINARY)
	python3 make_pgz.py $(BINARY)