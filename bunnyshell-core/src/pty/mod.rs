pub mod da_filter;
pub mod session;
pub mod shell_init;

use std::collections::HashMap;
use std::io::Write;
use std::sync::{Arc, RwLock};
use crate::BunError;
use portable_pty::PtySize;

// Re-export trait so it is picked up by UniFFI
pub use session::PtyCallback;
use session::Session;

#[derive(uniffi::Object)]
pub struct PtyManager {
    sessions: RwLock<HashMap<u32, Arc<Session>>>,
}

#[uniffi::export]
impl PtyManager {
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            sessions: RwLock::new(HashMap::new()),
        })
    }

    pub fn spawn(
        &self,
        id: u32,
        cols: u16,
        rows: u16,
        cwd: Option<String>,
        callback: Box<dyn PtyCallback>,
    ) -> Result<(), BunError> {
        let callback_arc: Arc<dyn PtyCallback> = Arc::from(callback);
        let session = session::spawn(id, cols, rows, cwd, callback_arc)?;
        self.sessions.write().unwrap().insert(id, session);
        Ok(())
    }

    pub fn write(&self, id: u32, data: Vec<u8>) -> Result<(), BunError> {
        let session = self
            .sessions
            .read()
            .unwrap()
            .get(&id)
            .cloned()
            .ok_or_else(|| "no session found".to_string())?;

        let mut writer = session.writer.lock().unwrap();
        writer.write_all(&data).map_err(|e| e.to_string())?;
        writer.flush().map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn resize(&self, id: u32, cols: u16, rows: u16) -> Result<(), BunError> {
        let session = self
            .sessions
            .read()
            .unwrap()
            .get(&id)
            .cloned()
            .ok_or_else(|| "no session found".to_string())?;

        session
            .master
            .lock()
            .unwrap()
            .resize(PtySize {
                rows,
                cols,
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|e| e.to_string())?;
        Ok(())
    }

    pub fn close(&self, id: u32) -> Result<(), BunError> {
        let session = self.sessions.write().unwrap().remove(&id);
        if let Some(s) = session {
            if let Ok(mut k) = s.killer.lock() {
                let _ = k.kill();
            }
        }
        Ok(())
    }
}
