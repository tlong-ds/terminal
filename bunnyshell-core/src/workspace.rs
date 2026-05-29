use std::path::PathBuf;
use crate::BunError;

fn get_state_file_path() -> Result<PathBuf, BunError> {
    let mut p = dirs::data_dir()
        .or_else(|| dirs::home_dir())
        .ok_or_else(|| BunError::Error { message: "cannot find data or home directory".to_string() })?;
    p.push("bunnyshell");
    std::fs::create_dir_all(&p).map_err(|e| BunError::Error { message: e.to_string() })?;
    p.push("workspace-state.json");
    Ok(p)
}

#[uniffi::export]
pub fn save_workspace_state(state_json: String) -> Result<(), BunError> {
    let p = get_state_file_path()?;
    std::fs::write(&p, state_json).map_err(|e| BunError::Error { message: e.to_string() })
}

#[uniffi::export]
pub fn load_workspace_state() -> Result<String, BunError> {
    let p = get_state_file_path()?;
    if !p.exists() {
        return Ok("{}".to_string());
    }
    std::fs::read_to_string(&p).map_err(|e| BunError::Error { message: e.to_string() })
}
