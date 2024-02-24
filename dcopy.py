import sys
import serial
import binascii
import argparse
import pathlib

BLOCK_SIZE = 128

BLOCK_T_DATA          = 1
BLOCK_T_DATA_LAST     = 2
BLOCK_T_OPEN_SEND     = 3
BLOCK_T_OPEN_RECEIVE  = 4
BLOCK_T_CLOSE         = 5
BLOCK_T_BLOCK_NEXT    = 6
BLOCK_T_BLOCK_RETRANS = 7
BLOCK_T_ANSWER        = 8

RESULT_OK = 0
RESULT_RETRANSMIT = 1
RESULT_FAILURE = 2

STATE_NAME_WAIT_OPEN = "WaitOpen"
STATE_NAME_OPENED = "Opened"
STATE_NAME_CLOSING = "Closing"
STATE_NAME_END = "Done"

class Block:
    def __init__(self, id):
        self._id = id
    
    @property
    def id(self):
        return self._id

    def recognize(self, data):
        return data[0] == self._id

    # returns true if successfull
    def parse(self, data):
        verify_success = self.verify_crc(data)
        if not verify_success:
            return False

        return self.decode(data[:-2])

    def verify_crc(self, data):
        h = data[-2:]
        crc = h[0] + 256 * h[1]
        crc_ref = binascii.crc_hqx(bytes(data[:-2]), 0xFFFF)

        return crc == crc_ref

    def send(self, frame):
        data = self.add_crc(self.encode())
        frame.write(data)

    def encode(self):
        pass

    # returns true if successfull
    def decode(self, data):
        pass

    def add_crc(self, data):
        v = binascii.crc_hqx(bytes(data), 0xFFFF)
        hi, lo = divmod(v, 256)

        return bytes(data + bytes([lo, hi]))


class BaseBlockData(Block):
    def __init__(self, id):
        super().__init__(id)
        self.data = [0]
    
    @property
    def data(self):
        return self.__data
    
    @data.setter
    def data(self, d):
        if len(d) == 0:
            self.__data = [0]
        elif len(d) <= BLOCK_SIZE:
            self.__data = d
        else:
            self.__data = d[:BLOCK_SIZE]
    
    def encode(self):
        return bytes([self.id, len(self.data)]) + self.data + bytes([0] * (BLOCK_SIZE - len(self.data)))

    def decode(self, data):
        if len(data) != (BLOCK_SIZE + 2):
            return False

        if data[0] != self.id:
            return False
        
        data_len = data[1]

        if data_len > BLOCK_SIZE:
            return False
        
        self.data = data[2: 2 + data_len]

        return True


class BaseBlockOpen(Block):
    def __init__(self, id):
        super().__init__(id)
        self.file_name = " "

    @property
    def file_name(self):
        return self.__file_name

    @file_name.setter
    def file_name(self, d):
        if len(d) == 0:
            self.__file_name = " "
        elif len(d) <= BLOCK_SIZE:
            self.__file_name = d
        else:
            self.__file_name = d[:BLOCK_SIZE]

    def encode(self):
        encoded_name = self.file_name.encode('ascii')
        return bytes([self.id, len(encoded_name)] + encoded_name + ([0] * (BLOCK_SIZE - len(encoded_name))))
    
    def decode(self, data):
        if len(data) != (BLOCK_SIZE + 2):
            return False

        if data[0] != self.id:
            return False
        
        data_len = data[1]

        if data_len > BLOCK_SIZE:
            return False
        
        self.file_name = data[2: 2 + data_len].decode('ascii')

        return True        


class TaggedBlock(Block):
    def __init__(self, id):
        super().__init__(id)

    def encode(self):
        return bytes([self.id])

    # returns true if successfull
    def decode(self, data):
        if len(data) != 1:
            return False

        if data[0] != self.id:
            return False        
        
        return True


class BlockAnswer(Block):
    def __init__(self, code):
        super().__init__(BLOCK_T_ANSWER)
        self.res_code = code
    
    @property
    def res_code(self):
        return self.__res_code
    
    @res_code.setter
    def res_code(self, v):
        self.__res_code = v

    def encode(self):
        return bytes([self.id, self.res_code])
    
    def decode(self, data):
        if len(data) != 2:
            return False

        if data[0] != self.id:
            return False        
        
        self.res_code = data[1]

        return True        


class Frame:
    def __init__(self, port):
        self._port = port

    def read(self):
        b1 = bytes()
        while len(b1) == 0:
            b1 = self._port.read()
        
        num_bytes = b1[0]

        res = bytes()
        while len(res) != num_bytes:
            read_now = self._port.read(num_bytes - len(res))
            res = res + read_now

        return res

    def write(self, data):
        header = bytes([len(data)])
        packet = header + data

        while len(packet) != 0:
            bytes_written = self._port.write(packet)
            packet = packet[bytes_written:]


class Transaction:
    def __init__(self, block, proc_func):
        self.block = block
        self.proc_func = proc_func

    @property
    def block(self):
        return self.__block

    @block.setter
    def block(self, value):
        self.__block = value

    @property
    def proc_func(self):
        return self.__proc_func

    @proc_func.setter
    def proc_func(self, value):
        self.__proc_func = value
    
    def next_state(self, state_machine):
        pass

def is_file_in_dir(d, f):
    h1 = (d / f).resolve()
    h2 = d.resolve()
    
    res = str(h1).startswith(str(h2))

    return res


class FileSender:
    def __init__(self, home_dir):
        self._current_block = 0
        self._num_blocks = 0
        self._file_data = bytes()
        self._file_name = ""
        self._weely_state = False
        self._last_block_send = False
        self._home_dir = pathlib.Path(home_dir)
    
    @property
    def last_block(self):
        return self._last_block_send

    def open(self, block, frame):
        terminate = False

        try:
            self._file_name = block.file_name
            file_path = pathlib.Path(block.file_name)

            if not is_file_in_dir(self._home_dir, file_path):
                raise Exception("Illegal path")

            print(f"Sending file '{block.file_name}'")
            with open((self._home_dir / file_path).resolve(), "rb") as f:
                self._file_data = f.read()
            
            BlockAnswer(RESULT_OK).send(frame)
            self._current_block = -1
        except Exception as e:
            BlockAnswer(RESULT_FAILURE).send(frame)
            print(f"Unable to open '{block.file_name}' as source:", e)
            terminate = True
        
        return terminate

    def send_current_block(self, block, frame):        
        if self._current_block < 0:
            BlockAnswer(RESULT_FAILURE).send(frame)
            print(f"Unable to send block {self._current_block}")
            return True

        answer = BaseBlockData(BLOCK_T_DATA)

        if ((self._current_block + 1) * BLOCK_SIZE) >= len(self._file_data):
            answer = BaseBlockData(BLOCK_T_DATA_LAST) 
            self._last_block_send = True
        
        start_index = self._current_block * BLOCK_SIZE
        answer.data = self._file_data[start_index:start_index + BLOCK_SIZE]
        answer.send(frame)        

        return False

    def send_next_block(self, block, frame):
        self._weely_state = not self._weely_state
        if not self._weely_state:
            sys.stdout.write(".")
            sys.stdout.flush()
        
        self._current_block += 1
        return self.send_current_block(block, frame)

    def close(self, block, frame):
        BlockAnswer(RESULT_OK).send(frame)
        print()
        print(f"Transfer of '{self._file_name}' successfull")
        
        return False


class FileReceiver:
    def __init__(self, home_dir):
        self._open_file = None
        self._file_name = ""
        self._weely_state = False
        self._home_dir = pathlib.Path(home_dir)

    def open(self, block, frame):
        terminate = False

        try:
            self._file_name = block.file_name
            file_path = pathlib.Path(block.file_name)

            if not is_file_in_dir(self._home_dir, file_path):
                raise Exception("Illegal path")

            print(f"Receiving file '{block.file_name}'")
            self._open_file = open((self._home_dir / file_path).resolve(), "wb")
            self._file_name = block.file_name
            BlockAnswer(RESULT_OK).send(frame)
        except Exception as e:
            BlockAnswer(RESULT_FAILURE).send(frame)
            print(f"Unable to open '{block.file_name}' as target:", e)
            terminate = True
        
        return terminate

    def close(self, block, frame):
        terminate = False

        try:
            self._open_file.close()
            BlockAnswer(RESULT_OK).send(frame)
            print()
            print(f"Transfer of '{self._file_name}' successfull")
        except:
            BlockAnswer(RESULT_FAILURE).send(frame)
            terminate = True
        
        return terminate

    def write_block(self, block, frame):
        terminate = False
        self._weely_state = not self._weely_state

        if not self._weely_state:
            sys.stdout.write(".")
            sys.stdout.flush()

        try:            
            self._open_file.write(block.data)
            BlockAnswer(RESULT_OK).send(frame)
        except:
            BlockAnswer(RESULT_FAILURE).send(frame)
            terminate = True

        return terminate


class OpenTransaction(Transaction):
    def __init__(self, open_type, file_proc):
        super().__init__(BaseBlockOpen(open_type), file_proc.open)
    
    def next_state(self, state_machine):
        state_machine.next_state(STATE_NAME_OPENED)


class BlockReceiveTransaction(Transaction):
    def __init__(self, data_block_type, file_receiver):
        super().__init__(BaseBlockData(data_block_type), file_receiver.write_block)
    
    def next_state(self, state_machine):
        if self.block.id == BLOCK_T_DATA:
            state_machine.next_state(STATE_NAME_OPENED)
        else:
            state_machine.next_state(STATE_NAME_CLOSING)


class BlockCloseTransaction(Transaction):
    def __init__(self, file_proc):
        super().__init__(TaggedBlock(BLOCK_T_CLOSE), file_proc.close)
    
    def next_state(self, state_machine):
        state_machine.end()


class BlockSendNextTransaction(Transaction):
    def __init__(self, file_sender):
        super().__init__(TaggedBlock(BLOCK_T_BLOCK_NEXT), file_sender.send_next_block)
        self._f_sender = file_sender
    
    def next_state(self, state_machine):
        if self._f_sender.last_block:
            state_machine.next_state(STATE_NAME_CLOSING)
        else:
            state_machine.next_state(STATE_NAME_OPENED)


class BlockSendCurrentTransaction(Transaction):
    def __init__(self, file_sender):
        super().__init__(TaggedBlock(BLOCK_T_BLOCK_RETRANS), file_sender.send_current_block)
        self._f_sender = file_sender
    
    def next_state(self, state_machine):
        if self._f_sender.last_block:
            state_machine.next_state(STATE_NAME_CLOSING)
        else:
            state_machine.next_state(STATE_NAME_OPENED)


class State:
    def __init__(self, name, transactions):
        self._transactions = transactions
        self._name = name

    @property
    def name(self):
        return self._name

    def process(self, data, frame, state_machine):
        found = False

        for i in self._transactions:
            if i.block.recognize(data):
                found = True

                if not i.block.verify_crc(data):
                    print("CRC Error. Requesting retransmssion.")
                    BlockAnswer(RESULT_RETRANSMIT).send(frame)
                    break

                if not i.block.parse(data):
                    print("Unable to parse block.")
                    BlockAnswer(RESULT_FAILURE).send(frame)
                    state_machine.end()
                    break
                
                terminate = i.proc_func(i.block, frame)
                if terminate:
                    print("Processing error. Stopping transfer.")
                    state_machine.end()
                else:
                    i.next_state(state_machine)
        
        if not found:
            print("Unexpected block. Stopping transfer.")
            BlockAnswer(RESULT_FAILURE).send(frame)
            state_machine.end()
                

class StateMachine:
    def __init__(self, states, state_start):
        self._states = {}
        self._do_end = False

        for i in states:
            self._states[i.name] = i

        self._state = self._states[state_start]
    
    def run(self, data, frame):
        self._state.process(data, frame, self)
        self._run_internal(frame)

    def _run_internal(self, frame):
        while not self._do_end:
            data = frame.read()
            self._state.process(data, frame, self)
    
    def next_state(self, state_name):
        self._state = self._states[state_name]

    def end(self):
        self._do_end = True


def receive_file(f, data_in, dir):
    receiver = FileReceiver(dir)
    wait_open_state = State(STATE_NAME_WAIT_OPEN, [OpenTransaction(BLOCK_T_OPEN_SEND, receiver)])
    opened_state = State(STATE_NAME_OPENED, [BlockReceiveTransaction(BLOCK_T_DATA, receiver), BlockReceiveTransaction(BLOCK_T_DATA_LAST, receiver)])
    closing_state = State(STATE_NAME_CLOSING, [BlockCloseTransaction(receiver)])

    state_machine = StateMachine([wait_open_state, opened_state, closing_state], STATE_NAME_WAIT_OPEN)
    state_machine.run(data_in, f)


def send_file(f, data_in, dir):
    sender = FileSender(dir)
    wait_open_state = State(STATE_NAME_WAIT_OPEN, [OpenTransaction(BLOCK_T_OPEN_RECEIVE, sender)])
    opened_state = State(STATE_NAME_OPENED, [BlockSendCurrentTransaction(sender), BlockSendNextTransaction(sender)])
    closing_state = State(STATE_NAME_CLOSING, [BlockSendCurrentTransaction(sender), BlockCloseTransaction(sender)])

    state_machine = StateMachine([wait_open_state, opened_state, closing_state], STATE_NAME_WAIT_OPEN)
    state_machine.run(data_in, f)


def main(port, dir):
    print("******* dcopy: Drive aware file copy 0.9.0 *******")
    print("Press Control+c to stop server")
    print(f"Serving from directory '{dir}'")
    print()
    open_send = BaseBlockOpen(BLOCK_T_OPEN_SEND)
    open_receive = BaseBlockOpen(BLOCK_T_OPEN_RECEIVE)
    p = serial.Serial(port, 115200)
    f = Frame(p)

    while True:
        data_in = f.read()
        if open_send.recognize(data_in):
            receive_file(f, data_in, dir)
        elif open_receive.recognize(data_in):
            send_file(f, data_in, dir)
        else:
            BlockAnswer(RESULT_FAILURE).send(f)                        


if __name__ == "__main__":
    try:
        parser = argparse.ArgumentParser(prog='dcopy', description='A program that allows to transfer files between your PC and your Foenix 256')
        parser.add_argument('-p', '--port', required=True, help="Serial port to use")
        parser.add_argument('-d', '--dir', default="./", help="Directory to use for sending and receiving files")
        args = parser.parse_args()    
        main(args.port, args.dir)
    except KeyboardInterrupt:
        print()
        print("Server stopped")
    except Exception as e:
        print(f"An exception occurred: {e}")