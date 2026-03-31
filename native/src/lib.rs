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
    let c_str = unsafe { CStr::from_ptr(ptr) };
    let script: String = String::from(c_str.to_str().unwrap());

    println!("$ {}", script.dimmed());
    println!();

    #[cfg(target_os = "windows")]
    let shell: &str = "cmd";

    #[cfg(not(target_os = "windows"))]
    let shell: &str = "bash";

    let option: &str = match shell {
        "cmd" => "/C",
        "bash" => "-c",
        _ => "",
    };

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
    let child = Arc::new(
        SharedChild::spawn(&mut cmd).expect("Rust: Couldn't spawn the shared_child process!"),
    );

    *current_child().lock().unwrap() = Some(Arc::clone(&child));

    let status = child.wait().expect("Rust: Process can't be awaited");

    *current_child().lock().unwrap() = None;

    status.code().unwrap_or(1)
}
