use tauri::command;
use tauri::AppHandle;

// Use the core renderer from the workspace
use bunnyshell_core::surface_registry::{get_renderer, register_renderer, unregister_renderer};

// Map from native handle to pty session id (u32)
static HANDLE_PTY: once_cell::sync::Lazy<std::sync::Mutex<std::collections::HashMap<u64, u32>>> =
    once_cell::sync::Lazy::new(|| std::sync::Mutex::new(std::collections::HashMap::new()));

#[tauri::command]
pub fn ns_create_surface(nsview_ptr: u64, width: u32, height: u32) -> Result<u64, String> {
    // Create a new TerminalRenderer via core library and register it
    let renderer = bunnyshell_core::renderer::TerminalRenderer::new(nsview_ptr, width, height)
        .map_err(|e| e.to_string())?;
    let arc = std::sync::Arc::from(renderer);
    let handle = register_renderer(arc);
    Ok(handle)
}

#[tauri::command]
pub fn ns_destroy_surface(handle: u64) -> Result<(), String> {
    unregister_renderer(handle);
    HANDLE_PTY.lock().map_err(|e| e.to_string())?.remove(&handle);
    Ok(())
}

#[tauri::command]
pub fn ns_resize_surface(handle: u64, width: u32, height: u32) -> Result<(), String> {
    let renderer = get_renderer(handle).ok_or_else(|| "unknown handle".to_string())?;
    renderer.resize(width, height);
    Ok(())
}

#[tauri::command]
pub fn ns_render_lines(handle: u64, lines: Vec<String>) -> Result<(), String> {
    let renderer = get_renderer(handle).ok_or_else(|| "unknown handle".to_string())?;
    renderer.render(lines).map_err(|e| e.to_string())
}

#[tauri::command]
pub fn ns_bind_pty(handle: u64, pty_id: u32) -> Result<(), String> {
    HANDLE_PTY
        .lock()
        .map_err(|e| e.to_string())?
        .insert(handle, pty_id);
    Ok(())
}

#[tauri::command]
pub fn ns_write_pty(app: AppHandle, handle: u64, data: String) -> Result<(), String> {
    let map = HANDLE_PTY.lock().map_err(|e| e.to_string())?;
    let pty_id = *map.get(&handle).ok_or_else(|| "unknown handle".to_string())?;

    // Access the global PtyState managed by the application
    let state = app
        .state::<crate::modules::pty::PtyState>()
        .inner();

    let session = state
        .sessions
        .read()
        .map_err(|e| e.to_string())?
        .get(&pty_id)
        .cloned()
        .ok_or_else(|| {
            log::warn!("ns_write_pty: unknown pty id={}", pty_id);
            "no session".to_string()
        })?;

    let result = session
        .writer
        .lock()
        .map_err(|e| e.to_string())?
        .write_all(data.as_bytes())
        .map_err(|e| {
            log::debug!("ns_write_pty id={} failed: {}", pty_id, e);
            e.to_string()
        });
    result
}
