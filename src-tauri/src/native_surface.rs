use tauri::command;
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU64, Ordering};

// Use the core renderer from the workspace
use bunnyshell_core::renderer::TerminalRenderer;

// Global handle map storing TerminalRenderer instances
static HANDLES: once_cell::sync::Lazy<Mutex<HashMap<u64, Arc<TerminalRenderer>>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(HashMap::new()));

static HANDLE_COUNTER: AtomicU64 = AtomicU64::new(1);

#[tauri::command]
pub fn ns_create_surface(nsview_ptr: u64, width: u32, height: u32) -> Result<u64, String> {
    // Create a new TerminalRenderer targeting the provided NSView pointer.
    let renderer = TerminalRenderer::new(nsview_ptr, width, height).map_err(|e| e.to_string())?;
    let handle = HANDLE_COUNTER.fetch_add(1, Ordering::SeqCst);
    let arc = Arc::from(renderer);
    HANDLES.lock().map_err(|e| e.to_string())?.insert(handle, arc);
    Ok(handle)
}

#[tauri::command]
pub fn ns_destroy_surface(handle: u64) -> Result<(), String> {
    let mut map = HANDLES.lock().map_err(|e| e.to_string())?;
    map.remove(&handle);
    Ok(())
}

#[tauri::command]
pub fn ns_resize_surface(handle: u64, width: u32, height: u32) -> Result<(), String> {
    let map = HANDLES.lock().map_err(|e| e.to_string())?;
    let renderer = map.get(&handle).ok_or_else(|| "unknown handle".to_string())?;
    renderer.resize(width, height);
    Ok(())
}

#[tauri::command]
pub fn ns_render_lines(handle: u64, lines: Vec<String>) -> Result<(), String> {
    let map = HANDLES.lock().map_err(|e| e.to_string())?;
    let renderer = map.get(&handle).ok_or_else(|| "unknown handle".to_string())?;
    renderer.render(lines).map_err(|e| e.to_string())
}
