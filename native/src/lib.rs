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

/// Terminal job control, so a script in its own process group can still read
/// the terminal.
#[cfg(unix)]
mod tty {
    const STDIN: std::os::unix::io::RawFd = 0;

    /// Points the terminal at `pgid` for as long as it is held, and gives it
    /// back to whoever had it on drop.
    pub struct ForegroundGuard {
        previous: libc::pid_t,
    }

    impl ForegroundGuard {
        /// Returns `None` when stdin is not a terminal — there is no
        /// foreground group to hand over, and the Ctrl+C handler stays the
        /// mechanism that cleans the tree up.
        pub fn hand_over(pgid: libc::pid_t) -> Option<Self> {
            // SAFETY: isatty and tcgetpgrp take a raw fd and report failure
            // through their return value; neither dereferences anything.
            let previous = unsafe {
                if libc::isatty(STDIN) != 1 {
                    return None;
                }
                libc::tcgetpgrp(STDIN)
            };

            if previous < 0 || !set_foreground(pgid) {
                return None;
            }

            Some(ForegroundGuard { previous })
        }
    }

    impl Drop for ForegroundGuard {
        fn drop(&mut self) {
            set_foreground(self.previous);
        }
    }

    /// Hands the terminal to `pgid`.
    ///
    /// tcsetpgrp raises SIGTTOU at the caller once the caller is no longer the
    /// foreground group — which is exactly the case when reclaiming the
    /// terminal from the child — and the default action would stop us. Ignore
    /// it across the call and put the old disposition back.
    fn set_foreground(pgid: libc::pid_t) -> bool {
        // SAFETY: signal and tcsetpgrp are safe to call here; SIG_IGN is a
        // valid disposition and the previous one is restored verbatim.
        unsafe {
            let previous_handler = libc::signal(libc::SIGTTOU, libc::SIG_IGN);
            let handed_over = libc::tcsetpgrp(STDIN, pgid) == 0;
            libc::signal(libc::SIGTTOU, previous_handler);
            handed_over
        }
    }
}

/// Terminates `child` and everything it spawned.
///
/// ponytail: on Unix the child leads its own process group (see
/// `process_group(0)` below), so one `killpg` reaches the whole tree. Windows
/// has no equivalent and only the shell itself is killed — grandchildren of a
/// compound script can survive. The upgrade path there is a Job Object.
fn kill_tree(child: &SharedChild) {
    #[cfg(unix)]
    kill_group(child.id() as libc::pid_t);

    #[cfg(not(unix))]
    {
        let _ = child.kill();
    }
}

/// Terminates every process still in the group led by `pgid`.
#[cfg(unix)]
fn kill_group(pgid: libc::pid_t) {
    // SAFETY: killpg takes no pointers and reports failure by return value; an
    // already-empty group just yields ESRCH, which we ignore.
    unsafe {
        libc::killpg(pgid, libc::SIGTERM);
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
    // the shell. On a terminal the group is then handed the foreground below,
    // which is what keeps interactive scripts able to read stdin.
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

    // Hand the terminal to the child's group so a prompt inside the script can
    // read stdin instead of being stopped by SIGTTIN. The guard takes the
    // terminal back when it drops, on every path out of this function.
    //
    // Ctrl+C then goes to the child's group directly, from the kernel — our
    // handler is for the case with no terminal to hand over.
    #[cfg(unix)]
    let pgid = child.id() as libc::pid_t;

    #[cfg(unix)]
    let _foreground = {
        // The child sets its own group before exec; setting it from here too
        // means the handover cannot lose that race. EACCES just means the child
        // got there first.
        // SAFETY: setpgid takes no pointers and reports failure by return value.
        unsafe { libc::setpgid(pgid, pgid) };
        tty::ForegroundGuard::hand_over(pgid)
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
        if let Some(signal) = status.signal() {
            // Ctrl+C on a terminal is delivered by the kernel straight to the
            // foreground group — the child's — so the handler above never runs.
            // Sweep the group here instead: a job the script backgrounded holds
            // SIGINT ignored and would otherwise be left behind.
            kill_group(pgid);
            return 128 + signal;
        }
        return status.code().unwrap_or(ERR_SPAWN);
    }

    #[cfg(not(unix))]
    status.code().unwrap_or(ERR_SPAWN)
}

/// Drops the registration of a reaped child, leaving any concurrent ones alone.
fn forget_child(child: &Arc<SharedChild>) {
    let mut guard = children().lock().expect("CHILDREN mutex poisoned");
    guard.retain(|registered| !Arc::ptr_eq(registered, child));
}
