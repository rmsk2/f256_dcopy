# f256_dcopy

A tool for the Foenix 256K and Jr. which allows to copy files from one drive to another. Of course
it also works for copying files to another location on the same drive. Additionally it is possible to 
transfer files between the F256 and a PC via an RS-232 serial connection.

Use the provided `makefile` to build the program as a `.pgz` file which can be started through `pexec`. 
You will need `64tass` and a `python3` interpreter in your path for the `makefile` to work.

# Usage on the F256

Start the program via `pexec`, i.e enter `/- dcopy.pgz` at the BASIC prompt. `dcopy` uses a simple user
interface which allows you to enter the drive number and file name of the file to copy *from*  and the
same information of the file to copy *to*. While copying a dot is drawn on the screen for each block
that has been copied. Valid drive numbers are 0, 1, 2 and S, where S is to be used when a file transfer
via RS-232 is desired.

Entering information can be aborted by simply entering an empty string into any of the text entry boxes.
When you press `Control+c` or the `RUN/STOP` key `dcopy` executes a soft reset which brings up the 
BASIC prompt again.

# Usage on your PC

When transferring data via a serial line you also need to run `dcopy.py` on your PC. Get help about
the software by entering `python dcopy.py --help`:

```
usage: dcopy [-h] -p PORT [-d DIR]

A program that allows to transfer files between your PC and your Foenix 256

options:
  -h, --help            show this help message and exit
  -p PORT, --port PORT  Serial port to use
  -d DIR, --dir DIR     Directory to use for sending and receiving files
```

Specify the COM-port to use via the `-p` or `--port` options. The `-d` or `--dir` options can be used to 
determine a "home directory" for the server where files sent from or requested by the F256 are stored. If 
neither `-d` nor `--dir` is given then the current directory is used aa a "home directory". 

# Caveats

- If you initiate a serial file transfer from the F256 when `dcopy.py` is not running, `dcopy` locks up.
If you experience this behavior please use the reset button to restart your Foenix. I have ideas about
how to prevent this but at the moment this is how things are. 
- You will not be warned when you overwrite existing files on the F256 or your PC
- Device S can not be used as source and target of a file transfer at the same time
- You will need additional hardware on the PC side in order to be able to use the serial line. You will
need at least a null modem cable and most likely a USB to RS-232 serial adapter.
- You can not use the WiFi module and serial transfers via `dcopy` at the same time, i.e. if you have an
active WiFi board in your F256 then serial data transfer via `dcopy` will not work. I guess you can deactivate 
the WiFi board by deactivating DIP switches 3 and 4. After that `dcopy` should work. If you simply transfer 
data between drives 0, 1 and 2 then it does not matter whether you have a WiFi board or not and 
`dcopy` works as expected.

# Speed

File transfer via the serial interface at 115200 BPS seems to be a little bit faster than reading from
SD card. I.e. reading a file of 301 blocks from an SD card takes about 11 seconds. Copying the same file
via `dcopy` over a serial lone takes about 20 seconds, i.e. the serial transfer is a bit faster than
reading from SD card.
