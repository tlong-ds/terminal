use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::sync::atomic::{AtomicU64, Ordering};
use crate::renderer::TerminalRenderer;

static REGISTRY: once_cell::sync::Lazy<Mutex<HashMap<u64, Arc<TerminalRenderer>>>> =
    once_cell::sync::Lazy::new(|| Mutex::new(HashMap::new()));

static COUNTER: AtomicU64 = AtomicU64::new(1);

#[uniffi::export]
pub fn register_renderer(renderer: Arc<TerminalRenderer>) -> u64 {
    let handle = COUNTER.fetch_add(1, Ordering::SeqCst);
    REGISTRY.lock().unwrap().insert(handle, renderer);
    handle
}

#[uniffi::export]
pub fn unregister_renderer(handle: u64) {
    REGISTRY.lock().unwrap().remove(&handle);
}

pub fn get_renderer(handle: u64) -> Option<Arc<TerminalRenderer>> {
    REGISTRY.lock().unwrap().get(&handle).cloned()
}
