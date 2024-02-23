import serial
import binascii

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
        return bytes([self.id, len(self.data)] + self.data + ([0] * (BLOCK_SIZE - len(self.data))))

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


class BlockData(BaseBlockData):
    def __init__(self):
        super().__init__(BLOCK_T_DATA)


class BlockLastData(BaseBlockData):
    def __init__(self):
        super().__init__(BLOCK_T_DATA_LAST)


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


class BlockOpenSend(BaseBlockOpen):
    def __init__(self):
        super().__init__(BLOCK_T_OPEN_SEND)


class BlockOpenReceive(BaseBlockOpen):
    def __init__(self):
        super().__init__(BLOCK_T_OPEN_RECEIVE)


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


class BlockClose(TaggedBlock):
    def __init__(self):
        super().__init__(BLOCK_T_CLOSE)


class BlockNext(TaggedBlock):
    def __init__(self):
        super().__init__(BLOCK_T_BLOCK_NEXT)


class BlockRetrans(TaggedBlock):
    def __init__(self):
        super().__init__(BLOCK_T_BLOCK_RETRANS)


class BlockAnswer(Block):
    def __init__(self):
        super().__init__(BLOCK_T_ANSWER)
        self.res_code = RESULT_OK
    
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


def receive_file(f, data_in):
    open_block = BlockOpenSend()
    data_block = BlockData()
    last_block = BlockLastData()
    close_block = BlockClose()
    answer_block = BlockAnswer()
    answer_block.res_code = RESULT_OK
    
    if not open_block.recognize(data_in):
        print(f"Expected block {open_block.id}, got {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    if not open_block.parse(data_in):
        print(f"Could not parse open request")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    answer_block.send(f)
    print(f"Open request for file {open_block.file_name}")

    stop = False
    while not stop:
        data_in = f.read()

        if data_block.recognize(data_in):
            if not data_block.parse(data_in):
                answer_block.res_code = RESULT_FAILURE
                answer_block.send(f)
                stop = True
                
            print(binascii.hexlify(data_block.data))
            answer_block.send(f)
        elif last_block.recognize(data_in):
            if not last_block.parse(data_in):
                answer_block.res_code = RESULT_FAILURE
                answer_block.send(f)
                stop = True
                
            print(binascii.hexlify(last_block.data))
            answer_block.send(f)
            stop = True
        else:
            print(f"Unexpected block {data_in[0]}")
            answer_block.res_code = RESULT_FAILURE
            answer_block.send(f)
            stop = True

    data_in = f.read()
    if not close_block.recognize(data_in):
        print(f"Unexpected block {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)        
    else:
        answer_block.send(f)
        print("Received close request")    


def send_file(f, data_in):
    open_block = BlockOpenReceive()
    data_block = BlockData()
    last_block = BlockLastData()
    next_request = BlockNext()
    close_block = BlockClose()
    answer_block = BlockAnswer()
    answer_block.res_code = RESULT_OK

    if not open_block.recognize(data_in):
        print(f"Expected block {open_block.id}, got {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    if not open_block.parse(data_in):
        print(f"Could not parse open request")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    answer_block.send(f)
    print(f"Open request for file {open_block.file_name}")

    # request first block
    data_in = f.read()

    if not next_request.recognize(data_in):
        print(f"Expected block {open_block.id}, got {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    if not next_request.parse(data_in):
        print(f"Could not parse request for block")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    data_block.data = [0] * 128
    data_block.send(f)

    # request second block
    data_in = f.read()

    if not next_request.recognize(data_in):
        print(f"Expected block {open_block.id}, got {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    if not next_request.parse(data_in):
        print(f"Could not parse request for block")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)          
        return

    last_block.data = [1] * 23
    last_block.send(f)

    data_in = f.read()
    if not close_block.recognize(data_in):
        print(f"Unexpected block {data_in[0]}")
        answer_block.res_code = RESULT_FAILURE
        answer_block.send(f)        
    else:
        answer_block.send(f)
        print("Received close request")


if __name__ == "__main__":
    print("Beware: This piece of software is in an intermediate state and is *not* useful at the moment!")
    open_send = BlockOpenSend()
    open_receive = BlockOpenReceive()
    answer_block = BlockAnswer()
    p = serial.Serial("/dev/ttyUSB1", 115200)
    f = Frame(p)

    while True:
        data_in = f.read()
        if open_send.recognize(data_in):
            receive_file(f, data_in)
        elif open_receive.recognize(data_in):
            send_file(f, data_in)
        else:                        
            answer_block.res_code = RESULT_FAILURE
            answer_block.send(f)

