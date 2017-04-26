+++
date = "2017-04-20T20:33:37+02:00"
title = "Encoding of immediate values on AArch64"
draft = true

+++

AArch64 is an ISA with a fixed instruction width of 32-bit.
This obviously means there is not enough space to store a 64-bit immediate in a single instruction.
Before working with AArch64 I was only familiar with x86 where this is a bit easier since instructions can have variable-width.
A 64-bit immediate on x86-64 is really just the sequence of bytes:

```
mov rax, 0x1122334455667788
# encoded as: 0x48, 0xB8, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11
```

A fixed-width ISA like ARM has to treat immediates differently.
AArch64 actually has multiple formats for encoding immediate values:

Instructions like `add` or `sub` allow a 12-bit unsigned immediate that can optionally be shifted by 12 bits.
This allows to encode some numbers directly into the instruction, instead of using a temporary register.
Negative numbers e.g. -1 (which is all ones) cannot be encoded with an `add` instruction.
But since `sub` is just an addition of the [two's complement](https://en.wikipedia.org/wiki/Two%27s_complement), we can use sub for that: `sub x0, x0, 1`.

The move instructions `movz`, `movn` and `movk` have space for a 16-bit unsigned immediate that can be shifted by either 0, 16, 32 or 48 bits.

These move instructions can be combined to assign the value `0x1122334455667788` to the register `x0`:

```
movz x0, 0x7788
movk x0, 0x5566, lsl 16
movk x0, 0x3344, lsl 32
movk x0, 0x1122, lsl 48
```

`movz` assigns the given 16-bit value to the position given by the shift operand and `z`eroes all other bits.
`movk` does the same but `k`eeps the value of the other bits instead of zeroing them.
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

[v8](https://github.com/v8/v8/blob/master/src/arm64/macro-assembler-arm64.cc#L164) for example really determines whether it is more beneficial (this means less instructions) to encode an immediate via `movn` or `movz`.

The last encoding format is the logical immediate instruction class is the most complicated and non-intuitive (at least for me).
This is the definition from the ARM Reference Manual:

> The logical immediate instructions accept a bitmask immediate bimm32 or bimm64.
> Such an immediate consists EITHER of a single consecutive sequence with at least one non-zero bit, and at least one zero bit, within an element of 2, 4, 8, 16, 32 or 64 bits;
> the element then being replicated across the register width, or the bitwise inverse of such a value.
> The immediate values of all-zero and all-ones may not be encoded as a bitmask immediate, so an assembler must either generate an error for a logical instruction with such an immediate,
> or a programmer-friendly assembler may transform it into some other instruction which achieves the intended result.

Now I try to given an overview in my own words:
Logical immediate instructions have 13-bits for encoding the immediate, it consists of three fields `N` (1 bit), `immr` (6 bits) and `imms` (6 bits).
This format does not allow to encode 0 or ~0 (all ones) as an immediate.
Although this sounds problematic at first, this isn't actually a restriction: this format is only used for instructions such as bitwise `and` and `or` where these constants are not really useful (e.g. `x0 | 0` can be optimized to `x0` while `x0 | ~0` can be optimized to `~0`).

This format allows to specify an element of 2-, 4-, 8-, 16-, 32- or 64-bits.
Both the element size and the element value is stored in the `N` and `imms` fields.
The element value needs to be a consecutive sequence of (at least one) zeroes, followed by a consecutive sequence of (at least one) ones (regex would be `0+1+`).
The format doesn't really store the element value but just needs the number of consecutive ones in the element.

The so specified element value can be right rotated up to element size minus 1 to move the start of the sequence of ones to any other point in the element.
The number of rotations is stored in `immr` which has 6 bits, so it allows up to 63 rotations in the case of an element size of 64 bits.
An element size of 2 only allows 0 or 1 rotations, in this case only the least significant bit is considered, the upper 5 bits of `immr` are simply ignored.

The element gets replicated until it reaches 32- or 64-bits.
13-bits could store 8192 different values, but since e.g. the rotation is not always used to its full potential with smaller element sizes it actually allows less different values but probably a more useful set of bit patterns.

Since `immr` is actually quite boring (just stores the number of rotations), let's look into how `N` and `imms` can store both the element size and the number of consecutive ones at the same time:

<table>
  <tr>
    <td>N</td>
    <td colspan="6">immr</td>
    <td>element size</td>
  </tr>
  <tr>
    <td>0</td>
    <td>1</td>
    <td>1</td>
    <td>1</td>
    <td>1</td>
    <td>0</td>
    <td>x</td>
    <td>2 bits</td>
  </tr>
  <tr>
    <td>0</td>
    <td>1</td>
    <td>1</td>
    <td>1</td>
    <td>0</td>
    <td>x</td>
    <td>x</td>
    <td>4 bits</td>
  </tr>
  <tr>
    <td>0</td>
    <td>1</td>
    <td>1</td>
    <td>0</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>8 bits</td>
  </tr>
  <tr>
    <td>0</td>
    <td>1</td>
    <td>0</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>16 bits</td>
  </tr>
  <tr>
    <td>0</td>
    <td>0</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>32 bits</td>
  </tr>
  <tr>
    <td>1</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>x</td>
    <td>64 bits</td>
  </tr>
</table>

The upper bits specify the element size, while the lower bits marked with `x` are used to store the consecutive sequence of ones.
0 means there is one 1, 1 means there are 1's and so on.
Remember: The format doesn't allow 0 or all ones to be encoded.
At the same time it is not allowed to set all `x` to 1, since this would allow to create all ones.

Let's see some examples:

* `0|111100` represents element `01` (2 bits element size, one 1)
* `0|110101` represents element `00111111` (8 bits element size, six 1's)