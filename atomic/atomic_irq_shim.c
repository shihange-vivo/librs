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

// C35 §14.2: the rv32imc DSO has no A extension, so clang/rustc lower the
// `core::sync::atomic` operations librs and its dependencies use into
// `__atomic_*` library calls. Those calls must resolve *inside* libc.so.1
// because the DSO may not reference kernel symbols (`--no-allow-shlib-
// undefined`).
//
// The kernel's `:atomic` archive solves the same problem for the kernel
// image by disabling machine interrupts around the non-lock-free path, but
// its `disable_local_irq_save`/`enable_local_irq_restore` are kernel
// exports. This shim reimplements them locally: BlueOS runs every image in
// M-mode, so the dynamic libc may touch `mstatus.MIE` itself. The saved
// value is returned so the restore keeps nested/pre-existing interrupt
// state intact, exactly like the kernel's
// `arch::riscv::disable_local_irq_save`.

#include <stddef.h>

#define MSTATUS_MIE (1UL << 3)

// Returns the pre-disable mstatus, and clears MIE (disables machine
// interrupts). The full value is preserved so the paired restore can put
// back whatever MIE state the caller entered with.
size_t disable_local_irq_save(void) {
    size_t mstatus;
    __asm__ volatile("csrrci %0, mstatus, %1" : "=r"(mstatus) : "i"(MSTATUS_MIE));
    return mstatus;
}

void enable_local_irq_restore(size_t mstatus) {
    __asm__ volatile("csrw mstatus, %0" : : "r"(mstatus));
}
