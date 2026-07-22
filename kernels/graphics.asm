; graphics.asm - filled-circle framebuffer kernel for tiny-gpu
;
; Treats data memory as a 16x15 (240-byte) grayscale framebuffer. Each thread
; owns one pixel: computes i = blockIdx*blockDim + threadIdx, converts to
; (row, col), then paints intensity 255 if inside a circle centered at (7,7)
; with radius 6, otherwise 50.
;
; Uses CMP + BRn for a real divergent branch (inside vs outside path lengths
; differ by one instruction before reconverging on a common STR). A full
; 16x16=256 grid would overflow the 8-bit thread_count DCR, so we render
; 16x15 instead.
;
; Encoded program lives in test/test_graphics.py (build_program()).

.threads 240

; i = blockIdx * blockDim + threadIdx
MUL R0, %blockIdx, %blockDim
ADD R0, R0, %threadIdx

CONST R1, #16                  ; GRID
DIV R2, R0, R1                 ; row = i / 16
MUL R7, R2, R1
SUB R3, R0, R7                 ; col = i % 16

CONST R5, #49                  ; CENTER^2
CONST R6, #14                  ; 2*CENTER

; dx_sq = (row - CENTER)^2  via algebraic expansion (unsigned-safe)
MUL R7, R2, R2
MUL R8, R2, R6
SUB R7, R7, R8
ADD R7, R7, R5

; dy_sq = (col - CENTER)^2
MUL R9, R3, R3
MUL R10, R3, R6
SUB R9, R9, R10
ADD R9, R9, R5

ADD R11, R7, R9                ; dist_sq
CONST R12, #37                 ; RADIUS^2 + 1
CMP R11, R12
BRn INSIDE                     ; if dist_sq < 37 (i.e. <= 36)

CONST R12, #50                 ; outside intensity
BRnzp STORE

INSIDE:
CONST R12, #255                ; inside intensity

STORE:
STR R0, R12                    ; framebuffer[i] = intensity
RET
