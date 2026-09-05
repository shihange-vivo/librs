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

// RV32/RV64 PIC application entry. a0 is BlueOsApplicationStartInfo *.

    .text
    .p2align 2
    .globl  _start
    .type   _start, @function
_start:
    mv      a1, a0

    // Resolve both functions through GOT slots. The AUIPC/LO12 pairs are
    // consumed by LLD; only word-sized dynamic GOT relocations remain for the
    // loader. norelax prevents an accidental dependency on the kernel's gp.
    .option push
    .option norelax
.Lmain_hi:
    auipc   a0, %got_pcrel_hi(main)
#if __riscv_xlen == 64
    ld      a0, %pcrel_lo(.Lmain_hi)(a0)
#else
    lw      a0, %pcrel_lo(.Lmain_hi)(a0)
#endif
.Llibc_hi:
    auipc   t0, %got_pcrel_hi(__librs_start_main)
#if __riscv_xlen == 64
    ld      t0, %pcrel_lo(.Llibc_hi)(t0)
#else
    lw      t0, %pcrel_lo(.Llibc_hi)(t0)
#endif
    .option pop
    jr      t0
    .size   _start, .-_start
