"""A disposable, detached terminal client for the live SSH contract test."""
import hashlib
import os
import termios
import tty


def screen(message):
    os.write(1, b"\x1b[2J\x1b[H" + message.encode("utf-8"))


def read_until(end):
    data = bytearray()
    while not data.endswith(end):
        byte = os.read(0, 1)
        if not byte:
            raise EOFError
        data.extend(byte)
    return bytes(data[:-len(end)])


def paste():
    start = b"\x1b[200~"
    if read_until(start):
        raise ValueError("Unexpected input before bracketed paste")
    data = read_until(b"\x1b[201~")
    if os.read(0, 1) != b"\r":
        raise ValueError("Missing submit key")
    return data


def main():
    old = termios.tcgetattr(0)
    tty.setraw(0)
    try:
        os.write(1, b"\x1b[?2004h")
        screen("RPC fixture ready")
        checksum = hashlib.sha256(paste()).hexdigest()
        screen(f"{checksum} Continue? [y/N]")
        if paste() != b"y":
            raise ValueError("Incorrect approval response")
        screen("Fixture approval received.\r\n\u276f ")
        while True:
            if os.read(0, 1) == b"\x03":
                screen("Fixture interrupt received.\r\n\u276f ")
    finally:
        termios.tcsetattr(0, termios.TCSANOW, old)


if __name__ == "__main__":
    main()
