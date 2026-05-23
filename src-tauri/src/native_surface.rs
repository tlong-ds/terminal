use tauri::command;

// Native surface scaffolding for macOS. These commands are placeholders
// to be implemented: they will allocate/destroy native Metal surfaces and
// proxy render/resize calls into bunnyshell-core's TerminalRenderer.

#[tauri::command]
pub fn ns_create_surface(_nsview_ptr: u64, _width: u32, _height: u32) -> Result<u64, String> {
    Err("ns_create_surface: not implemented".into())
}

#[tauri::command]
pub fn ns_destroy_surface(_handle: u64) -> Result<(), String> {
    Err("ns_destroy_surface: not implemented".into())
}

#[tauri::command]
pub fn ns_resize_surface(_handle: u64, _width: u32, _height: u32) -> Result<(), String> {
    Err("ns_resize_surface: not implemented".into())
}

#[tauri::command]
pub fn ns_render_lines(_handle: u64, _lines: Vec<String>) -> Result<(), String> {
    Err("ns_render_lines: not implemented".into())
}
