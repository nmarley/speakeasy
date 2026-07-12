use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;

use speakeasy_core::AppState;

use crate::engine::{Engine, ToggleResult};
use crate::ipc::{Command, Response};
use crate::paths::Paths;

pub fn run() -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::resolve()?;
    let socket_path = Paths::socket_path()?;

    if crate::ipc::is_daemon_alive(&socket_path) {
        return Err("daemon already running".into());
    }
    if socket_path.exists() {
        let _ = fs::remove_file(&socket_path);
    }

    if let Some(parent) = socket_path.parent() {
        fs::create_dir_all(parent)?;
    }

    let listener = UnixListener::bind(&socket_path)?;
    eprintln!("speakeasy daemon listening on {}", socket_path.display());

    let mut engine = Engine::open(paths)?;
    eprintln!("model loaded (state={:?})", engine.state());

    let cleanup_path = socket_path.clone();
    let _guard = SocketGuard { path: cleanup_path };

    for connection in listener.incoming() {
        match connection {
            Ok(stream) => {
                let should_quit = handle_client(stream, &mut engine);
                if should_quit {
                    eprintln!("shutdown requested");
                    break;
                }
            }
            Err(err) => {
                eprintln!("accept error: {err}");
            }
        }
    }

    Ok(())
}

fn handle_client(stream: UnixStream, engine: &mut Engine) -> bool {
    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    if reader.read_line(&mut line).is_err() {
        return false;
    }

    let command = match Command::parse(&line) {
        Some(cmd) => cmd,
        None => {
            let _ = write_response(&stream, &Response::Err(format!("unknown command: {line}")));
            return false;
        }
    };

    let (response, quit) = dispatch(command, engine);
    let _ = write_response(&stream, &response);
    quit
}

fn dispatch(command: Command, engine: &mut Engine) -> (Response, bool) {
    match command {
        Command::Status => (Response::Status(format_state(engine.state())), false),
        Command::Start => match engine.start_recording() {
            Ok(()) => (Response::OkMsg("recording".into()), false),
            Err(err) => (Response::Err(err.to_string()), false),
        },
        Command::Stop => match engine.stop_transcribe_and_copy() {
            Ok(text) => (
                Response::OkMsg(format!("transcribed {} chars", text.chars().count())),
                false,
            ),
            Err(err) => (Response::Err(err.to_string()), false),
        },
        Command::Toggle => match engine.toggle() {
            Ok(ToggleResult::Started) => (Response::OkMsg("recording".into()), false),
            Ok(ToggleResult::Stopped(text)) => (
                Response::OkMsg(format!("transcribed {} chars", text.chars().count())),
                false,
            ),
            Err(err) => (Response::Err(err.to_string()), false),
        },
        Command::Cancel => match engine.cancel_recording() {
            Ok(()) => (Response::OkMsg("cancelled".into()), false),
            Err(err) => (Response::Err(err.to_string()), false),
        },
        Command::Quit => (Response::OkMsg("shutting down".into()), true),
    }
}

fn format_state(state: AppState) -> String {
    match state {
        AppState::NeedsModel => "NeedsModel".into(),
        AppState::Ready => "Ready".into(),
        AppState::Recording => "Recording".into(),
        AppState::Transcribing => "Transcribing".into(),
        AppState::CleaningUp => "CleaningUp".into(),
    }
}

fn write_response(mut stream: &UnixStream, response: &Response) -> std::io::Result<()> {
    stream.write_all(response.encode().as_bytes())?;
    stream.flush()
}

struct SocketGuard {
    path: PathBuf,
}

impl Drop for SocketGuard {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}
