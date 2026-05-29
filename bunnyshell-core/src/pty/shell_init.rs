use std::path::{Path, PathBuf};
use std::fs;
use portable_pty::CommandBuilder;

const ZSHENV: &str = include_str!("scripts/zshenv.zsh");
const ZPROFILE: &str = include_str!("scripts/zprofile.zsh");
const ZLOGIN: &str = include_str!("scripts/zlogin.zsh");
const ZSHRC: &str = include_str!("scripts/zshrc.zsh");
const BASHRC: &str = include_str!("scripts/bashrc.bash");
const FISH_INIT: &str = include_str!("scripts/init.fish");

pub enum Shell {
    Zsh,
    Bash,
    Fish,
    Other,
}

impl Shell {
    pub fn detect() -> (Shell, String) {
        let path = login_shell()
            .or_else(|| std::env::var("SHELL").ok())
            .filter(|s| !s.is_empty())
            .unwrap_or_else(|| "/bin/zsh".into());
        let name = path.rsplit('/').next().unwrap_or("").to_string();
        let shell = match name.as_str() {
            "zsh" => Shell::Zsh,
            "bash" => Shell::Bash,
            "fish" => Shell::Fish,
            _ => Shell::Other,
        };
        (shell, path)
    }
}

fn login_shell() -> Option<String> {
    use std::ffi::CStr;
    unsafe {
        let uid = libc::getuid();
        let pw = libc::getpwuid(uid);
        if pw.is_null() {
            return None;
        }
        let shell_ptr = (*pw).pw_shell;
        if shell_ptr.is_null() {
            return None;
        }
        CStr::from_ptr(shell_ptr).to_str().ok().map(String::from)
    }
}

fn ensure_utf8_locale(cmd: &mut CommandBuilder) {
    let is_utf8 = |v: &str| {
        let up = v.to_ascii_uppercase();
        up.contains("UTF-8") || up.contains("UTF8")
    };
    let already_utf8 = ["LC_ALL", "LC_CTYPE", "LANG"]
        .iter()
        .any(|k| std::env::var(k).ok().as_deref().is_some_and(is_utf8));
    if already_utf8 {
        return;
    }
    cmd.env("LANG", "en_US.UTF-8");
}

fn apply_common(cmd: &mut CommandBuilder, cwd: Option<String>) {
    cmd.env("TERM", "xterm-256color");
    cmd.env("COLORTERM", "truecolor");
    cmd.env("BUNNYSHELL_TERMINAL", "1");
    ensure_utf8_locale(cmd);

    let resolved_cwd = cwd
        .map(PathBuf::from)
        .filter(|p| p.is_dir())
        .or_else(|| dirs::home_dir().filter(|p| p.is_dir()));
    if let Some(cwd) = resolved_cwd {
        cmd.cwd(cwd);
    }
}

static BUILD_COMMAND_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

pub fn build_command(cwd: Option<String>) -> Result<CommandBuilder, String> {
    let _guard = BUILD_COMMAND_LOCK.lock().unwrap();
    let (shell, shell_path) = Shell::detect();

    #[cfg(target_os = "macos")]
    let mut cmd = {
        // 1. Get login user name using getpwuid
        let uid = unsafe { libc::getuid() };
        let pw = unsafe { libc::getpwuid(uid) };
        if pw.is_null() {
            return Err("getpwuid failed".to_string());
        }
        let username_ptr = unsafe { (*pw).pw_name };
        if username_ptr.is_null() {
            return Err("pw_name is null".to_string());
        }
        let username = unsafe { std::ffi::CStr::from_ptr(username_ptr) }
            .to_string_lossy()
            .into_owned();

        // 2. Check for .hushlogin in home directory
        let home_ptr = unsafe { (*pw).pw_dir };
        let mut hush = false;
        if !home_ptr.is_null() {
            let home = unsafe { std::ffi::CStr::from_ptr(home_ptr) }
                .to_string_lossy()
                .into_owned();
            let hush_path = std::path::PathBuf::from(home).join(".hushlogin");
            if hush_path.exists() {
                hush = true;
            }
        }

        // 3. Build CommandBuilder using /usr/bin/login
        let mut c = CommandBuilder::new("/usr/bin/login");
        if hush {
            c.arg("-q");
        }
        c.arg("-flp");
        c.arg(&username);

        // 4. Wrap the shell launch in bash like Ghostty does
        // This makes sure it runs as a login shell
        let exec_cmd = format!("exec -l {}", shell_path);
        c.arg("/bin/bash");
        c.arg("--noprofile");
        c.arg("--norc");
        c.arg("-c");
        c.arg(&exec_cmd);
        c
    };

    #[cfg(not(target_os = "macos"))]
    let mut cmd = CommandBuilder::new(&shell_path);

    apply_common(&mut cmd, cwd);

    match shell {
        Shell::Zsh => {
            match prepare_zdotdir() {
                Ok(zdotdir) => {
                    if let Ok(user_zd) = std::env::var("ZDOTDIR") {
                        if Path::new(&user_zd) != zdotdir.as_path() {
                            cmd.env("BUNNYSHELL_USER_ZDOTDIR", user_zd);
                        }
                    }
                    cmd.env("ZDOTDIR", &zdotdir);
                }
                Err(e) => {
                    log::warn!("zsh shell integration disabled: {e}");
                }
            }
            #[cfg(not(target_os = "macos"))]
            cmd.arg("-l");
        }
        Shell::Bash => {
            match prepare_bash_rcfile() {
                Ok(rc) => {
                    cmd.arg("--rcfile");
                    cmd.arg(rc);
                }
                Err(e) => {
                    log::warn!("bash shell integration disabled: {e}");
                }
            }
            #[cfg(not(target_os = "macos"))]
            cmd.arg("-i");
        }
        Shell::Fish => {
            if let Err(e) = prepare_fish_conf_d() {
                log::warn!("fish shell integration disabled: {e}");
            }
            #[cfg(not(target_os = "macos"))]
            cmd.arg("-i");
        }
        Shell::Other => {
            log::info!(
                "unsupported shell '{}', spawning without integration",
                shell_path
            );
        }
    }
    Ok(cmd)
}

fn integration_root() -> Result<PathBuf, String> {
    let home = dirs::home_dir().ok_or_else(|| "could not resolve home dir".to_string())?;
    let root = home.join(".cache").join("bunnyshell").join("shell-integration");
    fs::create_dir_all(&root).map_err(|e| format!("create {}: {e}", root.display()))?;
    Ok(root)
}

fn prepare_zdotdir() -> Result<PathBuf, String> {
    let dir = integration_root()?.join("zsh");
    fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    write_if_changed(&dir.join(".zshenv"), ZSHENV)?;
    write_if_changed(&dir.join(".zprofile"), ZPROFILE)?;
    write_if_changed(&dir.join(".zshrc"), ZSHRC)?;
    write_if_changed(&dir.join(".zlogin"), ZLOGIN)?;
    Ok(dir)
}

fn prepare_bash_rcfile() -> Result<PathBuf, String> {
    let dir = integration_root()?.join("bash");
    fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    let rc = dir.join("bashrc");
    write_if_changed(&rc, BASHRC)?;
    Ok(rc)
}

fn prepare_fish_conf_d() -> Result<(), String> {
    let home = dirs::home_dir().ok_or_else(|| "could not resolve home dir".to_string())?;
    let dir = home.join(".config").join("fish").join("conf.d");
    fs::create_dir_all(&dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    write_if_changed(&dir.join("bunnyshell.fish"), FISH_INIT)?;
    Ok(())
}

fn write_if_changed(path: &Path, content: &str) -> Result<(), String> {
    if let Ok(existing) = fs::read_to_string(path) {
        if existing == content {
            return Ok(());
        }
    }
    let mut tmp = path.as_os_str().to_owned();
    tmp.push(".__bunnyshell_tmp__");
    let tmp = PathBuf::from(tmp);
    fs::write(&tmp, content).map_err(|e| format!("write {}: {e}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|e| {
        let _ = fs::remove_file(&tmp);
        format!("rename {} -> {}: {e}", tmp.display(), path.display())
    })
}
