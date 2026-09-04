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
// kernel schedules it through `Thread::Entry::Posix`, which delivers the pinned
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
    ldr     r0, =main               // r0 = application main (via GOT/RELATIVE)
    b       __librs_start_main      // tail-call; never returns

    .ltorg
    .size   _start, .-_start
