OPCODES = {
    "NOP":   0x0,
    "CMP":   0x2,
    "ADD":   0x3,
    "SUB":   0x4,
    "MUL":   0x5,
    "DIV":   0x6,
    "LDR":   0x7,
    "STR":   0x8,
    "CONST": 0x9,
    "BRN":   0xA,
    "BRZ":   0xB,
    "BRP":   0xC,
    "JMP":   0xD,
    "HALT":  0xF,
}


def reg_number(reg: str) -> int:

    reg = reg.upper().strip()

    if not reg.startswith("R"):
        raise ValueError(f"Invalid register: {reg}")

    idx = int(reg[1:])

    if idx < 0 or idx > 15:
        raise ValueError(f"Invalid register: {reg}")

    return idx