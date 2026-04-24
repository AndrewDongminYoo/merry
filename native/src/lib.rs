use colored::*;
use shared_child::SharedChild;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};

static CURRENT_CHILD: OnceLock<Mutex<Option<Arc<SharedChild>>>> = OnceLock::new();

fn current_child() -> &'static Mutex<Option<Arc<SharedChild>>> {
    CURRENT_CHILD.get_or_init(|| Mutex::new(None))
}

#[no_mangle]
pub extern "C" fn run_script(ptr: *const c_char) -> i32 {
    if ptr.is_null() {
        return 2;
    }
    let c_str = unsafe { CStr::from_ptr(ptr) };
    let script = match c_str.to_str() {
        Ok(value) => String::from(value),
        Err(_) => return 3,
    };

    println!("$ {}", script.dimmed());
    println!();

    #[cfg(target_os = "windows")]
    let shell: &str = "cmd";

    #[cfg(not(target_os = "windows"))]
    let shell: &str = "bash";

    #[cfg(target_os = "windows")]
    let option: &str = "/C";

    #[cfg(not(target_os = "windows"))]
    let option: &str = "-c";

    // Register the Ctrl+C handler exactly once for the process lifetime.
    // Subsequent calls return CtrlcError::MultipleHandlers, which we ignore.
    let _ = ctrlc::set_handler(move || {
        if let Ok(mut guard) = current_child().lock() {
            if let Some(child) = guard.take() {
                let _ = child.kill();
            }
        }
        println!();
        std::process::exit(130);
    });

    let mut cmd = Command::new(shell);
    cmd.arg(option).arg(script);
    let child = match SharedChild::spawn(&mut cmd) {
        Ok(process) => Arc::new(process),
        Err(_) => return 1,
    };

    if let Ok(mut guard) = current_child().lock() {
        *guard = Some(Arc::clone(&child));
    }

    let status = match child.wait() {
        Ok(result) => result,
        Err(_) => {
            if let Ok(mut guard) = current_child().lock() {
                *guard = None;
            }
            return 1;
        }
    };

    if let Ok(mut guard) = current_child().lock() {
        *guard = None;
    }

    status.code().unwrap_or(1)
}
