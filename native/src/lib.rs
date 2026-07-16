use colored::*;
use shared_child::SharedChild;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::process::Command;
use std::sync::{Arc, Mutex, OnceLock};

const ERR_SPAWN: i32 = 1;
const ERR_NULL_PTR: i32 = 2;
const ERR_INVALID_UTF8: i32 = 3;

/// Every child spawned by a `run_script` call that has not been reaped yet.
///
/// A single slot would be overwritten by a second concurrent call, so a Ctrl+C
/// could kill the wrong child or none at all. Callers are sequential today, so
/// this is defensive rather than load-bearing.
static CHILDREN: OnceLock<Mutex<Vec<Arc<SharedChild>>>> = OnceLock::new();

fn children() -> &'static Mutex<Vec<Arc<SharedChild>>> {
    CHILDREN.get_or_init(|| Mutex::new(Vec::new()))
}

/// Terminates `child` and everything it spawned.
///
/// ponytail: on Unix the child leads its own process group (see
/// `process_group(0)` below), so one `killpg` reaches the whole tree. Windows
/// has no equivalent and only the shell itself is killed — grandchildren of a
/// compound script can survive. The upgrade path there is a Job Object.
fn kill_tree(child: &SharedChild) {
    #[cfg(unix)]
    {
        // SAFETY: `killpg` is always safe to call; an already-exited group just
        // yields ESRCH, which we ignore.
        unsafe {
            libc::killpg(child.id() as libc::pid_t, libc::SIGTERM);
        }
    }

    #[cfg(not(unix))]
    {
        let _ = child.kill();
    }
}

/// Runs `script` in the platform shell, returning the child's exit code.
///
/// # Safety
///
/// `ptr` must be a non-null pointer to a NUL-terminated C string that stays
/// valid and unmodified for the duration of the call. A null `ptr` is reported
/// as [`ERR_NULL_PTR`] rather than dereferenced.
#[no_mangle]
pub unsafe extern "C" fn run_script(ptr: *const c_char) -> i32 {
    if ptr.is_null() {
        return ERR_NULL_PTR;
    }
    // SAFETY: the caller guarantees `ptr` is a valid NUL-terminated string for
    // the duration of this call; the borrow ends before we return.
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
        let mut guard = children().lock().expect("CHILDREN mutex poisoned");
        for child in guard.drain(..) {
            kill_tree(&child);
        }
        println!();
        std::process::exit(130);
    });

    let mut cmd = Command::new(shell);
    cmd.arg(option).arg(&script);

    // Lead a new process group so Ctrl+C can take down the whole tree, not just
    // the shell.
    //
    // ponytail: this also makes the child a *background* group for the tty, so
    // a script that reads the terminal (a `git`/`sudo` prompt) gets SIGTTIN and
    // stops. The upgrade path is full job control — hand the terminal over with
    // `tcsetpgrp` and reclaim it once the child exits.
    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        cmd.process_group(0);
    }

    // Acquire the lock before spawning so a Ctrl+C arriving between spawn and
    // registration cannot race past an unregistered child.
    let child = {
        let mut guard = children().lock().expect("CHILDREN mutex poisoned");
        let child = match SharedChild::spawn(&mut cmd) {
            Ok(process) => Arc::new(process),
            Err(_) => return ERR_SPAWN,
        };
        guard.push(Arc::clone(&child));
        child
    };

    let status = child.wait();
    forget_child(&child);

    let status = match status {
        Ok(result) => result,
        Err(_) => return ERR_SPAWN,
    };

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

/// Drops the registration of a reaped child, leaving any concurrent ones alone.
fn forget_child(child: &Arc<SharedChild>) {
    let mut guard = children().lock().expect("CHILDREN mutex poisoned");
    guard.retain(|registered| !Arc::ptr_eq(registered, child));
}
