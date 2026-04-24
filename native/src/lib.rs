use colored::*;
use shared_child::SharedChild;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};

const ERR_SPAWN: i32 = 1;
const ERR_NULL_PTR: i32 = 2;
const ERR_INVALID_UTF8: i32 = 3;

static CURRENT_CHILD: OnceLock<Mutex<Option<Arc<SharedChild>>>> = OnceLock::new();

fn current_child() -> &'static Mutex<Option<Arc<SharedChild>>> {
    CURRENT_CHILD.get_or_init(|| Mutex::new(None))
}

#[no_mangle]
pub extern "C" fn run_script(ptr: *const c_char) -> i32 {
    if ptr.is_null() {
        return ERR_NULL_PTR;
    }
    let c_str = unsafe { CStr::from_ptr(ptr) };
    let script = match c_str.to_str() {
        Ok(value) => String::from(value),
        Err(_) => return ERR_INVALID_UTF8,
    };

    println!("$ {}", script.dimmed());
    println!();

    let (shell, option): (&str, &str) = if cfg!(target_os = "windows") {
        ("cmd", "/C")
    } else {
        ("bash", "-c")
    };

    // Register the Ctrl+C handler exactly once for the process lifetime.
    // Subsequent calls return CtrlcError::MultipleHandlers, which we ignore.
    let _ = ctrlc::set_handler(move || {
        let mut guard = current_child()
            .lock()
            .expect("CURRENT_CHILD mutex poisoned");
        if let Some(child) = guard.take() {
            let _ = child.kill();
        }
        println!();
        std::process::exit(130);
    });

    // Acquire the lock before spawning so a Ctrl+C arriving between spawn and
    // storage cannot race past an empty CURRENT_CHILD.
    let mut cmd = Command::new(shell);
    cmd.arg(option).arg(&script);

    let child = {
        let mut guard = current_child()
            .lock()
            .expect("CURRENT_CHILD mutex poisoned");
        let child = match SharedChild::spawn(&mut cmd) {
            Ok(process) => Arc::new(process),
            Err(_) => return ERR_SPAWN,
        };
        *guard = Some(Arc::clone(&child));
        child
    };

    let status = match child.wait() {
        Ok(result) => result,
        Err(_) => {
            current_child()
                .lock()
                .expect("CURRENT_CHILD mutex poisoned")
                .take();
            return ERR_SPAWN;
        }
    };

    current_child()
        .lock()
        .expect("CURRENT_CHILD mutex poisoned")
        .take();

    #[cfg(unix)]
    {
        use std::os::unix::process::ExitStatusExt;
        return status
            .code()
            .unwrap_or_else(|| status.signal().map(|s| 128 + s).unwrap_or(ERR_SPAWN));
    }

    #[cfg(not(unix))]
    status.code().unwrap_or(ERR_SPAWN)
}
