pub mod fs;
pub mod pty;
pub mod renderer;
pub mod workspace;
pub mod surface_registry;

uniffi::setup_scaffolding!();

#[derive(Debug, uniffi::Error)]
pub enum BunError {
    Error { message: String },
}

impl std::fmt::Display for BunError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Error { message } => write!(f, "{}", message),
        }
    }
}

impl From<String> for BunError {
    fn from(message: String) -> Self {
        Self::Error { message }
    }
}

impl From<&str> for BunError {
    fn from(message: &str) -> Self {
        Self::Error { message: message.to_string() }
    }
}

