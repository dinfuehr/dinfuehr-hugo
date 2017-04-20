+++
date = "2017-04-20T20:33:37+02:00"
title = "Encoding of immediate values on AArch64"
draft = true

+++

AArch64 is an ISA with a fixed instruction width of 32-bit.
This obviously means there is not enough space to store a 64-bit immediate in a single instruction.
Before working with AArch64 I was only familiar with x86 where this is a bit easier since instructions can have variable-width.
A 64-bit immediate on x86-64 is really just a sequence 8 bytes (resoectively 4 bytes for 32-bits and 1-byte for 8-bits):

```
mov rax, 0x1122334455667788
# encoded as: 0x48, 0xB8, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11
```

A fixed-width ISA like ARM has to treat immediates differently.
AArch64 actually has multiple formats for encoding immediate values:

* Instructions like `add` or `sub` allow a 12-bit unsigned immediate that can be optionally shifted by 12 bits.
* The move instructions `movz`, `movn` and `movk` have space for a 16-bit unsigned immediate that can be shifted by either 0, 16, 32 or 48 bits. 

These move instructions can be combined to assign the value `0x1122334455667788` to the register `x0`:

```
movz x0, 0x7788
movk x0, 0x5566, lsl 16
movk x0, 0x3344, lsl 32
movk x0, 0x1122, lsl 48
```

`movz` assigns the given 16-bit value to the position given by the shift operand and `z`eroes all other bits.
`movk` does the same but `k`eeps the value of the other bits.
So in the worst case a 64-bit immediate needs 4 instructions.
But many common immediates can be encoded in less:

```
# x0 = 0x10000
movz x0, 0x1, lsl 16

# x0 = 0x10001
movz x0, 0x1
movk x0, 0x1, lsl 16
```  

It is only necessary to initialize the 16-bit parts of the 64-bit register that are non-zero.
Now that we have seen this, how can we encode -1?
All bits are 1 in this case, so with only `movz` and `movk` we would have to use 4 instructions again.

For such numbers AArch64 has the `movn` instruction that assigns the expression `~(imm16 << shift)` to the register.
-1 can so be encoded in one single instruction: `movn x0, 0`.
`movn` can also be combined with `movk`, use it to set parts of the number that are not all ones.

Some immediates can be encoded in less instructions with `movz`, some with `movk`, some need the same number of instructions.
[v8](https://github.com/v8/v8/blob/master/src/arm64/macro-assembler-arm64.cc#L164) for example really determines the shortest combination of instructions for the given immediate.

* The lastest encoding format is the most complicated and non-intuitive.