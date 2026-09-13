#!/usr/bin/env python3
"""Exercise the real installed libmodbus client against an isolated loopback fixture."""
import json
import socket
import struct
import subprocess
import sys
import threading

CLIENT = sys.argv[1] if len(sys.argv) > 1 else "/tmp/ddk-v3-validation/ddk-modbus-client"
registers = {100: 0x1234, 101: 0xABCD}
coils = {10: 1, 11: 0, 12: 1}
errors = []
stopping = threading.Event()
server = socket.socket()
server.bind(("127.0.0.1", 0))
server.listen(4)
server.settimeout(0.2)
port = server.getsockname()[1]


def receive(connection, count):
    data = b""
    while len(data) < count:
        chunk = connection.recv(count - len(data))
        if not chunk:
            return None
        data += chunk
    return data


def serve():
    try:
        while not stopping.is_set():
            try:
                connection, _ = server.accept()
            except socket.timeout:
                continue
            with connection:
                connection.settimeout(3)
                while True:
                    header = receive(connection, 7)
                    if header is None:
                        break
                    transaction, protocol, length, unit = struct.unpack("!HHHB", header)
                    assert protocol == 0 and unit == 7 and 2 <= length <= 254
                    request = receive(connection, length - 1)
                    function, address, count_or_value = struct.unpack("!BHH", request[:5])
                    if address == 65535:
                        reply = bytes((function | 128, 2))
                    elif function in (1, 2):
                        count = count_or_value
                        bits = bytearray((count + 7) // 8)
                        for index in range(count):
                            bits[index // 8] |= coils.get(address + index, 0) << (index % 8)
                        reply = bytes((function, len(bits))) + bits
                    elif function in (3, 4):
                        payload = b"".join(struct.pack("!H", registers.get(address + index, 0)) for index in range(count_or_value))
                        reply = bytes((function, len(payload))) + payload
                    elif function == 5:
                        assert count_or_value in (0, 0xFF00)
                        coils[address] = int(count_or_value == 0xFF00)
                        reply = request
                    elif function == 6:
                        registers[address] = count_or_value
                        reply = request
                    elif function == 15:
                        assert request[5] == (count_or_value + 7) // 8
                        for index in range(count_or_value):
                            coils[address + index] = (request[6 + index // 8] >> (index % 8)) & 1
                        reply = request[:5]
                    elif function == 16:
                        assert request[5] == count_or_value * 2
                        for index in range(count_or_value):
                            registers[address + index] = struct.unpack("!H", request[6 + index * 2:8 + index * 2])[0]
                        reply = request[:5]
                    else:
                        raise AssertionError("Unexpected Modbus function")
                    response = struct.pack("!HHHB", transaction, 0, len(reply) + 1, unit) + reply
                    # Deliberately fragment the header; the native library must frame it correctly.
                    connection.sendall(response[:3])
                    connection.sendall(response[3:])
    except Exception as error:
        errors.append(error)


thread = threading.Thread(target=serve, daemon=True)
thread.start()


def run(operation, address, *arguments, fail=False):
    result = subprocess.run([sys.executable, CLIENT, "--transport", "tcp", "--host", "127.0.0.1", "--port", str(port),
                             "--unit", "7", "--function", operation, "--address", str(address), "--timeout", "1", *arguments],
                            capture_output=True, text=True, timeout=8)
    assert not errors, errors
    if fail:
        assert result.returncode != 0 and "Illegal data address" in result.stderr, result.stderr
        return
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)


try:
    for operation in ("read_holding", "read_input"):
        assert run(operation, 100, "--count", "2")["values"] == [0x1234, 0xABCD]
    for operation in ("read_coils", "read_discrete"):
        assert run(operation, 10, "--count", "3")["values"] == [1, 0, 1]
    for operation, address, values in (("write_coil", 20, "1"), ("write_register", 200, "4660"),
                                       ("write_coils", 30, "1,0,1,1,0,0,1,0,1"), ("write_registers", 300, "0,32768,65535")):
        result = run(operation, address, "--values", values, "--verify")
        assert result["acknowledged"] and result["verified"]
    run("read_holding", 65535, fail=True)
    assert not errors, errors
    print("DDK_MODBUS_NATIVE_OK: FC 1, 2, 3, 4, 5, 6, 15, 16; fragmented TCP replies; write/readback; exception handling")
finally:
    stopping.set()
    thread.join(timeout=4)
    server.close()
