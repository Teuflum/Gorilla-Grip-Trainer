# Physics fields

The trainer reads the car's physics state straight from game memory. None of the offsets are fixed in the code: at load, `Physics::Locate` in `plugin/Physics.as` finds 13 code patterns in the game, takes each field's offset from the instruction that uses it, and checks that fields used more than once agree. If a pattern is missing or the offsets disagree, the plugin warns and unloads itself. `Physics::Read` then rejects any read whose position or steering disagrees with the game's vehicle state, or whose values are out of range.

## Fields

Offsets as measured on build `0x6980d607` (the PE timestamp of `Trackmania.exe`).

| Field | Offset | What it is |
| --- | --- | --- |
| `vehicle` | CSmPlayer + 0x1118 | The player's car: a handle at 0x1110 whose pointer sits 8 bytes in |
| `model` | car + 0x88 | The car model |
| `wheelCount` | car + 0x380 | Number of wheels; a read is rejected unless it is 4 |
| `rawSteer` | car + 0xa0 | Steering input |
| `smoothedSteer` | car + 0x1430 | Steering after the rate limiter (about 0.2 per tick on ice) |
| `contactClock` | car + 0x1414 | Last tick with ground contact; stays at the takeoff tick in flight |
| `modeAt` | car + 0x14d8 | Tick the stored slide direction last changed |
| `force` | car + 0x14dc | Tire-force multiplier (1.0 after a reset) |
| `neutralAt` | car + 0x14e0 | Start of the current neutral-steering spell, or -1 |
| `mode` | car + 0x14e5 | Stored slide direction: 0 neutral, 1 left, 2 right |
| `forceGate` | car + 0x1600 | Backwards-motion gate; nonzero holds the force at its baseline |
| `wheels` | car + 0x17b4 | First wheel's contact flag; the next wheel is 0xb8 further |
| `wheelChangedAt` | contact flag + 0x6c | Tick of that wheel's last touchdown or lift-off |
| `physicsClock` | car + 0x4f4 | The physics step's clock: the state block at 0x4e8, plus 0xc |
| `position` | car + 0x538 | Car position: the same state block, plus 0x50 |
| `recoveryDelay` | model + 0x1194 | Delay before the tire force recovers (400 ms) |
| `neutralTimeout` | model + 0x1198 | Neutral time after which the stored direction lapses (300 ms) |

## Where each offset is read

For every pattern, the instructions that carry an offset, as disassembled on the measured build. "Byte n" is the position in the pattern that `Physics::Locate` reads; `Offset` is a 32-bit field offset, `Byte` an 8-bit one, and `Target` a call whose destination is checked.

`python tests/test_physics_patterns.py` runs the same search and arithmetic over a game binary, so after a game update it shows which pattern stopped matching before the game is even started.

### wheel loop (`wheelLoop`)

Steering rate limiter: model and wheel count.

```
+0    mov rax, qword ptr [rdx + 0x88]                         ; byte 3 (Offset)
+23   mov r15d, dword ptr [rbx + 0x380]                       ; byte 26 (Offset)
```

### steering input (`steerInput`)

Same function: reverse gate, raw steer, smoothed steer.

```
+0    cmp dword ptr [rbx + 0x1600], 0                         ; byte 2 (Offset)
+69   movss xmm1, dword ptr [rbx + 0xa0]                      ; byte 73 (Offset)
+99   movss xmm2, dword ptr [rbx + 0x1430]                    ; byte 103 (Offset)
```

### contact flags (`contactFlags`)

Per-wheel contact test: model, wheel stride, first contact flag.

```
+6    mov rbx, qword ptr [rcx + 0x88]                         ; byte 9 (Offset)
+35   imul rdx, r10, 0xb8                                     ; byte 38 (Offset)
+51   cmp dword ptr [rdx + r8 + 0x17b4], 0                    ; byte 55 (Offset)
```

### steering mode (`steerMode`)

The +-0.1 steering comparison that stores the slide direction.

```
+13   mov byte ptr [rdi + 0x14e5], 1                          ; byte 15 (Offset)
+20   mov dword ptr [rdi + 0x14e0], 0xffffffff                ; byte 22 (Offset)
+37   mov byte ptr [rdi + 0x14e5], 2                          ; byte 39 (Offset)
+44   mov dword ptr [rdi + 0x14e0], 0xffffffff                ; byte 46 (Offset)
+56   mov ecx, dword ptr [rdi + 0x14e0]                       ; byte 58 (Offset)
+67   mov dword ptr [rdi + 0x14e0], edx                       ; byte 69 (Offset)
+86   mov byte ptr [rdi + 0x14e5], 0                          ; byte 88 (Offset)
+93   mov dword ptr [rdi + 0x14d8], 0xffffffff                ; byte 95 (Offset)
+110  cmp byte ptr [rdi + 0x14e5], al                         ; byte 112 (Offset)
+130  mov dword ptr [rdi + 0x14d8], edx                       ; byte 132 (Offset)
+136  mov dword ptr [rdi + 0x14dc], 0x3f800000                ; byte 138 (Offset)
```

### contact clock (`contactClock`)

Contact processing stamps the car's last grounded tick.

```
+0    mov dword ptr [rbx + 0x1414], r12d                      ; byte 3 (Offset)
```

### model defaults (`modelDefaults`)

Model defaults: 400 ms force recovery delay, 300 ms neutral timeout.

```
+0    mov dword ptr [r12 + 0x1194], 0x190                     ; byte 4 (Offset)
+16   mov dword ptr [r12 + 0x1198], 0x12c                     ; byte 20 (Offset)
```

### vehicle handle (`vehicleHandle`)

The player holds its car as a handle {id, ?, pointer}; both paths here resolve the same handle with the car-class resolver.

```
+0    movups xmm0, xmmword ptr [r14 + 0x1110]                 ; byte 4 (Offset)
+18   call 0xffffffffffffb406                                 ; byte 19 (Target)
+70   movups xmm0, xmmword ptr [r14 + 0x1110]                 ; byte 74 (Offset)
```

### vehicle resolver (`vehicleResolver`)

The resolver checks the id against class 0x0A020000 and returns the pointer, shifted out of the handle's upper bytes.

```
+42   psrldq xmm0, 8                                          ; byte 46 (Byte)
```

### wheel state (`wheelState`)

Per-wheel contact update: reads the contact flag, sets the state (1 on the ground, 2 in the air) and times the change against the clock stamp.

```
+0    mov r8d, dword ptr [rcx + 0x34]                         ; byte 3 (Byte)
+54   mov dword ptr [rcx + 0x9c], edx                         ; byte 56 (Offset)
+83   mov dword ptr [rcx + 0x9c], 2                           ; byte 85 (Offset)
+105  mov dword ptr [rcx + 0x9c], edx                         ; byte 107 (Offset)
+117  mov dword ptr [rcx + 0x9c], 1                           ; byte 119 (Offset)
+140  mov dword ptr [rcx + 0x9c], eax                         ; byte 142 (Offset)
+146  mov edx, dword ptr [rcx + 0x9c]                         ; byte 148 (Offset)
+179  sub eax, dword ptr [rcx + 0xa0]                         ; byte 181 (Offset)
```

### state caller (`stateCaller`)

The car's per-tick state: a caller passes its place in the car to the fill, which passes it and the clock on to the writer.

```
+17   lea r8, [rdi + 0x4e8]                                   ; byte 20 (Offset)
+24   call 0x2210                                             ; byte 25 (Target)
```

### state fill (`stateFill`)

```
+143  call 0xfffffffffffff3e0                                 ; byte 144 (Target)
```

### state writer (`stateWriter`)

The writer stores the clock in the state first...

```
+181  mov dword ptr [rdi + 0xc], r14d                         ; byte 184 (Byte)
```

### state location (`stateLocation`)

...and later the rotation, then the position copied from the physics body.

```
+28   lea rcx, [rdi + 0x50]                                   ; byte 31 (Byte)
```
