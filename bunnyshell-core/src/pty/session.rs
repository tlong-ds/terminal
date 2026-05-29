use std::io::{Read, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use crate::BunError;
use std::thread;
use std::time::{Duration, Instant};

use portable_pty::{native_pty_system, ChildKiller, MasterPty, PtySize};

use super::da_filter::DaFilter;
use super::shell_init;

const FLUSH_COALESCE: Duration = Duration::from_millis(4);
const FLUSH_MAX_IDLE: Duration = Duration::from_millis(50);
const READ_BUF: usize = 16 * 1024;
const MAX_PENDING: usize = 4 * 1024 * 1024;
const OVERFLOW_NOTICE: &[u8] =
    b"\x1bc\x1b[2m[bunnyshell: dropped output due to backpressure]\x1b[0m\r\n";

#[uniffi::export(callback_interface)]
pub trait PtyCallback: Send + Sync {
    fn on_data(&self, id: u32, data: Vec<u8>);
    fn on_exit(&self, id: u32, exit_code: i32);
}

pub struct Session {
    pub killer: Mutex<Box<dyn ChildKiller + Send + Sync>>,
    pub writer: Arc<Mutex<Box<dyn Write + Send>>>,
    pub master: Mutex<Box<dyn MasterPty + Send>>,
}

impl Drop for Session {
    fn drop(&mut self) {
        if let Ok(mut k) = self.killer.lock() {
            let _ = k.kill();
        }
    }
}

pub fn spawn(
    id: u32,
    cols: u16,
    rows: u16,
    cwd: Option<String>,
    callback: Arc<dyn PtyCallback>,
) -> Result<Arc<Session>, BunError> {
    let pty_system = native_pty_system();
    let size = PtySize {
        rows,
        cols,
        pixel_width: 0,
        pixel_height: 0,
    };
    let pair = pty_system.openpty(size).map_err(|e| e.to_string())?;

    let cmd = shell_init::build_command(cwd)?;
    let mut child = pair.slave.spawn_command(cmd).map_err(|e| e.to_string())?;
    drop(pair.slave);

    let killer = child.clone_killer();
    let mut reader = pair.master.try_clone_reader().map_err(|e| e.to_string())?;
    let writer: Arc<Mutex<Box<dyn Write + Send>>> = Arc::new(Mutex::new(
        pair.master.take_writer().map_err(|e| e.to_string())?,
    ));

    let session = Arc::new(Session {
        killer: Mutex::new(killer),
        writer: writer.clone(),
        master: Mutex::new(pair.master),
    });

    let pending: Arc<(Mutex<Vec<u8>>, Condvar)> = Arc::new((
        Mutex::new(Vec::with_capacity(READ_BUF)),
        Condvar::new(),
    ));
    let done = Arc::new(AtomicBool::new(false));
    let spawn_at = Instant::now();

    let pending_r = pending.clone();
    let writer_for_da = writer.clone();
    let reader_thread = thread::Builder::new()
        .name("bunnyshell-pty-reader".into())
        .spawn(move || {
            let mut buf = [0u8; READ_BUF];
            let mut filtered: Vec<u8> = Vec::with_capacity(READ_BUF);
            let mut da_filter = DaFilter::new();
            let mut dropped_bytes: u64 = 0;
            let mut logged_first = false;
            loop {
                match reader.read(&mut buf) {
                    Ok(0) => break,
                    Ok(n) => {
                        if !logged_first {
                            logged_first = true;
                            log::debug!("pty first byte after {}ms", spawn_at.elapsed().as_millis());
                        }
                        filtered.clear();
                        da_filter.process(&buf[..n], &mut filtered, |reply| {
                            if let Ok(mut w) = writer_for_da.lock() {
                                let _ = w.write_all(reply);
                            }
                        });
                        if filtered.is_empty() {
                            continue;
                        }
                        let (lock, cv) = &*pending_r;
                        let mut g = lock.lock().unwrap();
                        if g.len() + filtered.len() > MAX_PENDING {
                            dropped_bytes += g.len() as u64;
                            g.clear();
                            g.extend_from_slice(OVERFLOW_NOTICE);
                        }
                        g.extend_from_slice(&filtered);
                        cv.notify_one();
                    }
                    Err(e) => {
                        log::debug!("pty reader ended: {e}");
                        break;
                    }
                }
            }
            pending_r.1.notify_one();
            if dropped_bytes > 0 {
                log::warn!("pty backpressure: dropped {dropped_bytes} bytes (cap {MAX_PENDING})");
            }
        })
        .expect("spawn pty reader thread");

    let callback_flush = callback.clone();
    let pending_f = pending.clone();
    let done_f = done.clone();
    thread::Builder::new()
        .name("bunnyshell-pty-flusher".into())
        .spawn(move || {
            let (lock, cv) = &*pending_f;
            loop {
                {
                    let mut g = lock.lock().unwrap();
                    while g.is_empty() {
                        if done_f.load(Ordering::Acquire) {
                            return;
                        }
                        let (next, _) = cv.wait_timeout(g, FLUSH_MAX_IDLE).unwrap();
                        g = next;
                    }
                }
                thread::sleep(FLUSH_COALESCE);
                let chunk = std::mem::take(&mut *lock.lock().unwrap());
                if chunk.is_empty() {
                    continue;
                }
                callback_flush.on_data(id, chunk);
            }
        })
        .expect("spawn pty flusher thread");

    let callback_exit = callback;
    let pending_e = pending;
    let done_e = done;
    thread::Builder::new()
        .name("bunnyshell-pty-waiter".into())
        .spawn(move || {
            let code = match child.wait() {
                Ok(status) => status.exit_code() as i32,
                Err(e) => {
                    log::warn!("pty child wait failed: {e}");
                    -1
                }
            };
            if let Err(e) = reader_thread.join() {
                log::error!("pty reader thread panicked: {e:?}");
            }
            let (lock, cv) = &*pending_e;
            let tail = std::mem::take(&mut *lock.lock().unwrap());
            if !tail.is_empty() {
                callback_exit.on_data(id, tail);
            }
            done_e.store(true, Ordering::Release);
            cv.notify_all();
            callback_exit.on_exit(id, code);
        })
        .expect("spawn pty waiter thread");

    Ok(session)
}
