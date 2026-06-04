from pathlib import Path
import sys

from isa import OPCODES, reg_number


def assemble_line(line: str) -> int:

    line = line.split("#")[0].strip()

    if not line:
        return None

    tokens = (
        line.replace(",", " ")
            .replace("[", " ")
            .replace("]", " ")
            .split()
    )

    op = tokens[0].upper()

    #
    # RET / HALT
    #

    if op in ("RET", "HALT"):
        return 0xF000

    #
    # CONST Rd, Imm
    #

    if op == "CONST":

        rd = reg_number(tokens[1])
        imm = int(tokens[2], 0) & 0xFF

        return (
            (OPCODES["CONST"] << 12)
            | (rd << 8)
            | imm
        )

    #
    # CMP Rs, Rt
    #

    if op == "CMP":

        rs = reg_number(tokens[1])
        rt = reg_number(tokens[2])

        return (
            (OPCODES["CMP"] << 12)
            | (rs << 4)
            | rt
        )

    #
    # ADD/SUB/MUL/DIV
    #

    if op in ("ADD", "SUB", "MUL", "DIV"):

        rd = reg_number(tokens[1])
        rs = reg_number(tokens[2])
        rt = reg_number(tokens[3])

        return (
            (OPCODES[op] << 12)
            | (rd << 8)
            | (rs << 4)
            | rt
        )

    #
    # LDR Rd, [Rs]
    #

    if op == "LDR":

        rd = reg_number(tokens[1])
        rs = reg_number(tokens[2])

        return (
            (OPCODES["LDR"] << 12)
            | (rd << 8)
            | (rs << 4)
        )

    #
    # STR [Rs], Rt
    #

    if op == "STR":

        rs = reg_number(tokens[1])
        rt = reg_number(tokens[2])

        return (
            (OPCODES["STR"] << 12)
            | (rs << 4)
            | rt
        )
    
        #
    # BRN offset
    #

    if op == "BRN":

        offset = int(tokens[1], 0) & 0xFF

        return (
            (OPCODES["BRN"] << 12)
            | offset
        )

    #
    # BRZ offset
    #

    if op == "BRZ":

        offset = int(tokens[1], 0) & 0xFF

        return (
            (OPCODES["BRZ"] << 12)
            | offset
        )

    #
    # BRP offset
    #

    if op == "BRP":

        offset = int(tokens[1], 0) & 0xFF

        return (
            (OPCODES["BRP"] << 12)
            | offset
        )

    #
    # JMP address
    #

    if op == "JMP":

        address = int(tokens[1], 0) & 0xFF

        return (
            (OPCODES["JMP"] << 12)
            | address
        )

    raise ValueError(f"Unsupported instruction: {line}")


def assemble_file(path: str):

    program = []

    with open(path, "r") as f:

        for line in f:

            word = assemble_line(line)

            if word is not None:
                program.append(word)

    return program


def main():

    if len(sys.argv) != 2:
        print("usage: assembler.py <file.asm>")
        sys.exit(1)

    program = assemble_file(sys.argv[1])

    for word in program:
        print(f"0x{word:04X}")


if __name__ == "__main__":
    main()