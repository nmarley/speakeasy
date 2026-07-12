use std::fs;
use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::PathBuf;
use std::sync::mpsc::{self, Receiver, Sender};

use speakeasy_core::AppState;

use crate::engine::{Engine, ToggleResult};
use crate::ipc::{Command, Response};
use crate::paths::Paths;
use crate::tray;

pub enum DaemonMsg {
    Ipc {
        command: Command,
        reply: Sender<Response>,
    },
    Tray {
        command: Command,
    },
}

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

    let (tx, rx) = mpsc::channel::<DaemonMsg>();
    let socket_tx = tx.clone();

    let tray_handle = match tray::spawn(tx, engine.state()) {
        Ok(handle) => {
            eprintln!("status notifier tray started");
            Some(handle)
        }
        Err(err) => {
            eprintln!("tray unavailable (continuing without tray): {err}");
            None
        }
    };

    let cleanup_path = socket_path.clone();
    let _guard = SocketGuard { path: cleanup_path };

    std::thread::spawn(move || socket_loop(listener, socket_tx));

    engine_loop(&mut engine, rx, tray_handle.as_ref());

    if let Some(handle) = tray_handle {
        handle.shutdown().wait();
    }

    Ok(())
}

fn socket_loop(listener: UnixListener, tx: Sender<DaemonMsg>) {
    for connection in listener.incoming() {
        match connection {
            Ok(stream) => {
                if let Err(err) = handle_socket_client(stream, &tx) {
                    eprintln!("socket client error: {err}");
                }
            }
            Err(err) => {
                eprintln!("accept error: {err}");
            }
        }
    }
}

fn handle_socket_client(
    stream: UnixStream,
    tx: &Sender<DaemonMsg>,
) -> Result<(), Box<dyn std::error::Error>> {
    let mut reader = BufReader::new(&stream);
    let mut line = String::new();
    reader.read_line(&mut line)?;

    let command = match Command::parse(&line) {
        Some(cmd) => cmd,
        None => {
            write_response(&stream, &Response::Err(format!("unknown command: {line}")))?;
            return Ok(());
        }
    };

    let (reply_tx, reply_rx) = mpsc::channel();
    tx.send(DaemonMsg::Ipc {
        command,
        reply: reply_tx,
    })?;

    let response = reply_rx.recv()?;
    write_response(&stream, &response)?;
    Ok(())
}

fn engine_loop(
    engine: &mut Engine,
    rx: Receiver<DaemonMsg>,
    tray_handle: Option<&ksni::blocking::Handle<tray::SpeakeasyTray>>,
) {
    while let Ok(msg) = rx.recv() {
        let (command, reply) = match msg {
            DaemonMsg::Ipc { command, reply } => (command, Some(reply)),
            DaemonMsg::Tray { command } => (command, None),
        };

        let (response, quit) = dispatch(command, engine);
        if reply.is_none() {
            match &response {
                Response::Ok | Response::OkMsg(_) | Response::Status(_) => {
                    eprintln!("tray: {}", response_log(&response));
                }
                Response::Err(msg) => eprintln!("tray error: {msg}"),
            }
        }

        if let Some(reply) = reply {
            let _ = reply.send(response);
        }

        if let Some(handle) = tray_handle {
            let state = engine.state();
            handle.update(|tray| {
                tray.state = state;
            });
        }

        if quit {
            eprintln!("shutdown requested");
            break;
        }
    }
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

fn response_log(response: &Response) -> String {
    match response {
        Response::Ok => "ok".into(),
        Response::OkMsg(msg) => format!("ok {msg}"),
        Response::Status(state) => format!("status {state}"),
        Response::Err(msg) => format!("err {msg}"),
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
