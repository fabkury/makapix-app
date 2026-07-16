//! `mem.os` probe backend: OS-level resident/peak memory of this process — the ground truth the
//! engine's accounted census (`mem` probe) is compared against. Linux/Android read
//! `/proc/self/status` (`VmRSS`/`VmHWM`); Windows calls `K32GetProcessMemoryInfo` (hand-declared —
//! no dependency); other platforms report zeros.

pub struct OsMem {
    pub resident: u64,
    pub peak: u64,
}

#[cfg(any(target_os = "linux", target_os = "android"))]
pub fn os_mem() -> OsMem {
    let s = std::fs::read_to_string("/proc/self/status").unwrap_or_default();
    let grab = |key: &str| {
        s.lines()
            .find(|l| l.starts_with(key))
            .and_then(|l| l.split_whitespace().nth(1))
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(0)
            * 1024 // the fields are reported in KiB
    };
    OsMem { resident: grab("VmRSS:"), peak: grab("VmHWM:") }
}

#[cfg(windows)]
pub fn os_mem() -> OsMem {
    use core::ffi::c_void;
    // PROCESS_MEMORY_COUNTERS (psapi.h); K32GetProcessMemoryInfo lives in kernel32 on Win7+.
    #[repr(C)]
    struct Pmc {
        cb: u32,
        page_fault_count: u32,
        peak_working_set_size: usize,
        working_set_size: usize,
        quota_peak_paged_pool_usage: usize,
        quota_paged_pool_usage: usize,
        quota_peak_non_paged_pool_usage: usize,
        quota_non_paged_pool_usage: usize,
        pagefile_usage: usize,
        peak_pagefile_usage: usize,
    }
    #[link(name = "kernel32")]
    extern "system" {
        fn GetCurrentProcess() -> *mut c_void;
        fn K32GetProcessMemoryInfo(h: *mut c_void, c: *mut Pmc, cb: u32) -> i32;
    }
    let mut c = Pmc {
        cb: std::mem::size_of::<Pmc>() as u32,
        page_fault_count: 0,
        peak_working_set_size: 0,
        working_set_size: 0,
        quota_peak_paged_pool_usage: 0,
        quota_paged_pool_usage: 0,
        quota_peak_non_paged_pool_usage: 0,
        quota_non_paged_pool_usage: 0,
        pagefile_usage: 0,
        peak_pagefile_usage: 0,
    };
    let ok = unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(), &mut c, c.cb) };
    if ok != 0 {
        OsMem { resident: c.working_set_size as u64, peak: c.peak_working_set_size as u64 }
    } else {
        OsMem { resident: 0, peak: 0 }
    }
}

#[cfg(not(any(windows, target_os = "linux", target_os = "android")))]
pub fn os_mem() -> OsMem {
    OsMem { resident: 0, peak: 0 }
}
