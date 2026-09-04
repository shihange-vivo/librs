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

//! Per-application runtime context (C28, §17.1).
//!
//! Every dynamic application gets one [`LibcApplicationContext`], built by the
//! dynamic entry from the pinned [`BlueOsApplicationStartInfo`] and installed on
//! the main thread's TCB. It owns the state that must stay application-local
//! rather than shared across two concurrently-running applications: the `auxv`
//! table, the atexit list, and the exit-coordinator flag (§17.5). The kernel's
//! start storage already pins the *bytes* behind `info` for the application
//! lifetime; the context additionally owns its own copy of the auxv entries so a
//! future larger `struct_size` (appended fields, §9.1) can never dangle.

use alloc::{boxed::Box, sync::Arc, vec::Vec};
use core::{
    slice,
    sync::atomic::{AtomicBool, Ordering},
};

use spin::RwLock;

use blueos_header::application::{
    ApplicationHandle, BlueOsApplicationStartInfo, BlueOsAuxvEntry,
    APPLICATION_START_INFO_ABI_VERSION,
};

/// An application-owned destructor registered through `atexit`.
pub type AtExitEntry = extern "C" fn();

/// The application-local runtime state (§17.1).
pub struct LibcApplicationContext {
    handle: ApplicationHandle,
    auxv: Box<[BlueOsAuxvEntry]>,
    atexit: RwLock<Vec<AtExitEntry>>,
    /// Set when the exit sequence begins; guards against running the atexit and
    /// fini plan twice (§17.2).
    exit_started: AtomicBool,
}

impl LibcApplicationContext {
    /// Build the context from the pinned start-information block (§17.1).
    ///
    /// Validates the versioned prefix (§9.1): a block smaller than the v1 prefix
    /// or with an unknown `abi_version` is rejected with `None`. On success the
    /// auxv table is copied into an owned slice so the context holds its own
    /// entries.
    pub fn new(info: &BlueOsApplicationStartInfo) -> Option<Arc<Self>> {
        if info.abi_version != APPLICATION_START_INFO_ABI_VERSION {
            return None;
        }
        if info.struct_size < core::mem::size_of::<BlueOsApplicationStartInfo>() as u32 {
            return None;
        }

        // SAFETY: `info.auxv`/`auxv_count` were validated when the kernel built
        // `ApplicationStartStorage` and are pinned for the application lifetime
        // (§15.3).
        let entries = unsafe { slice::from_raw_parts(info.auxv, info.auxv_count) };
        let mut auxv = Vec::new();
        auxv.try_reserve_exact(entries.len()).ok()?;
        auxv.extend_from_slice(entries);

        Some(Arc::new(Self {
            handle: info.handle,
            auxv: auxv.into_boxed_slice(),
            atexit: RwLock::new(Vec::new()),
            exit_started: AtomicBool::new(false),
        }))
    }

    /// The application handle this context was minted for.
    #[inline]
    pub fn handle(&self) -> ApplicationHandle {
        self.handle
    }

    /// Look up an auxiliary-vector entry by key (§17.3). Returns `0` when the
    /// key is absent, matching `getauxval`'s not-found convention.
    pub fn getauxval(&self, key: usize) -> usize {
        self.auxv
            .iter()
            .find(|entry| entry.key == key)
            .map_or(0, |entry| entry.value)
    }

    /// Register an application-owned destructor (§17.2 step 8). Returns `false`
    /// on allocation failure; destructors run in reverse registration order.
    pub fn register_atexit(&self, function: AtExitEntry) -> bool {
        let mut list = self.atexit.write();
        if list.try_reserve(1).is_err() {
            return false;
        }
        list.push(function);
        true
    }

    /// Run every registered destructor in reverse order (§17.2 step 8).
    pub fn run_atexit(&self) {
        let mut list = self.atexit.write();
        while let Some(function) = list.pop() {
            function();
        }
    }

    /// Mark the exit sequence started. Returns `false` if it already began, so a
    /// double exit can be detected before destructors run twice (§17.1).
    pub fn begin_exit(&self) -> bool {
        !self.exit_started.swap(true, Ordering::AcqRel)
    }
}
