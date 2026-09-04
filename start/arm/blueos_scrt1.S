// Copyright (c) 2026 vivo Mobile Communication Co., Ltd.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//       http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// blueos_scrt1.S — minimal ARM32 Thumb dynamic-application start object (C21, §10.1).
//
// `_start` is the dynamic application's ELF entry (`e_entry`, bit 0 set). The
// kernel schedules it through `Thread::Entry::Raw`, which installs the
// relocated entry as the initial PC and delivers the pinned
// `BlueOsApplicationStartInfo *` in r0. It re-packs the argument order for the
// `libc.so.1` entry `__librs_start_main(main, info) -> !` and tail-calls it; the
// application's `main` is resolved by the loader as the app's own symbol.

    .syntax unified
    .thumb
    .text

    .globl  _start
    .type   _start, %function
    .thumb_func
_start:
    // r0 = info (BlueOsApplicationStartInfo *).
    mov     r1, r0                  // __librs_start_main(main, info): r1 = info
    // r0 = the application's `main`, which is defined in this image: the
    // PC-relative `adr` is resolved by the static linker and emits no dynamic
    // relocation at all. A literal `main(GOT)` reference instead relies on
    // the linker resolving the GOT-slot address into the pool word, which
    // LLD currently leaves zero — so the indirection is avoided entirely.
    adr     r0, main
    // Tail-call `__librs_start_main` (an undefined symbol, provided by
    // libc.so.1) through its GOT slot: a plain `b` makes LLD emit a
    // __ThumbV7PILongThunk whose `bx r12` carries an even address for the
    // Thumb PLT (an interworking violation on Cortex-M), so the GOT
    // indirection is spelled out here instead. The GOT slot is resolved by
    // an R_ARM_GLOB_DAT dynamic relocation at load time.
    //
    // The `ldr.w`/`add pc` pairing is the ABI's GOT_PREL idiom: the linker
    // encodes the slot address as `slot - (address of the pool word)`, and
    // the 16-bit `add r12, pc` reads PC as Align(addr+4, 4) — so the pool
    // word must sit exactly four bytes after the `add`. A 16-bit branch fills
    // the two bytes in between and skips over the literal; without that branch
    // the CPU would execute the GOT_PREL word as two Thumb instructions before
    // reaching the indirect call. The whole block must be 4-byte aligned.
    .align  2
    ldr.w   r12, .Lgot_slot
    add     r12, pc
    b       .Lcall
.Lgot_slot:
    .word   __librs_start_main(GOT_PREL)
.Lcall:
    ldr.w   r12, [r12]
    bx      r12
    .size   _start, .-_start
