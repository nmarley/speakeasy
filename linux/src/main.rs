mod audio;
mod clipboard;
mod daemon;
mod download;
mod engine;
mod ipc;
mod paths;
mod tray;

use std::env;
use std::process::ExitCode;
use std::time::Duration;

use audio::record_for_duration;
use download::{DownloadError, download_default_model};
use engine::Engine;
use ipc::{Command, IpcError, Response, send_command};
use paths::Paths;

fn main() -> ExitCode {
    let mut args = env::args().skip(1);
    let cmd = args.next().unwrap_or_default();

    match cmd.as_str() {
        "" | "help" | "-h" | "--help" => {
            print_usage();
            ExitCode::SUCCESS
        }
        "version" | "-V" | "--version" => {
            println!("speakeasy {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        "paths" => match cmd_paths() {
            Ok(()) => ExitCode::SUCCESS,
            Err(err) => fail(err),
        },
        "download-model" => {
            let force = args.any(|a| a == "--force" || a == "-f");
            match cmd_download_model(force) {
                Ok(()) => ExitCode::SUCCESS,
                Err(DownloadError::AlreadyPresent(path)) => {
                    eprintln!("Model already present at {}", path.display());
                    eprintln!("Re-run with --force to download again.");
                    ExitCode::SUCCESS
                }
                Err(err) => fail(err),
            }
        }
        "record" => {
            let seconds = args.next().and_then(|s| s.parse::<u64>().ok()).unwrap_or(3);
            match cmd_record(seconds) {
                Ok(path) => {
                    println!("{}", path.display());
                    ExitCode::SUCCESS
                }
                Err(err) => fail(err),
            }
        }
        "once" => {
            let seconds = args.next().and_then(|s| s.parse::<u64>().ok()).unwrap_or(3);
            match cmd_once(seconds) {
                Ok(text) => {
                    println!("{text}");
                    ExitCode::SUCCESS
                }
                Err(err) => fail(err),
            }
        }
        "daemon" => match daemon::run() {
            Ok(()) => ExitCode::SUCCESS,
            Err(err) => fail(err),
        },
        "start" => client_cmd(Command::Start),
        "stop" => client_cmd(Command::Stop),
        "toggle" => client_cmd(Command::Toggle),
        "status" => client_cmd(Command::Status),
        "cancel" => client_cmd(Command::Cancel),
        "quit" => client_cmd(Command::Quit),
        other => {
            eprintln!("unknown command: {other}");
            print_usage();
            ExitCode::FAILURE
        }
    }
}

fn fail(err: impl std::fmt::Display) -> ExitCode {
    eprintln!("error: {err}");
    ExitCode::FAILURE
}

fn client_cmd(command: Command) -> ExitCode {
    match cmd_client(command) {
        Ok(response) => {
            print_response(&response);
            if response.is_err() {
                ExitCode::FAILURE
            } else {
                ExitCode::SUCCESS
            }
        }
        Err(err) => fail(err),
    }
}

fn print_response(response: &Response) {
    match response {
        Response::Ok => println!("ok"),
        Response::OkMsg(msg) => println!("ok {msg}"),
        Response::Status(state) => println!("status {state}"),
        Response::Err(msg) => eprintln!("error: {msg}"),
    }
}

fn print_usage() {
    println!(
        "speakeasy {} — local speech-to-text (Linux)",
        env!("CARGO_PKG_VERSION")
    );
    println!();
    println!("Usage:");
    println!("  speakeasy paths              Show XDG data/config/model paths");
    println!("  speakeasy download-model     Download default Whisper model");
    println!("  speakeasy download-model -f  Re-download even if present");
    println!("  speakeasy record [seconds]   Record mic to 16 kHz mono WAV (default 3s)");
    println!("  speakeasy once [seconds]     Record, transcribe, copy to clipboard");
    println!("  speakeasy daemon             Run daemon with tray + socket IPC");
    println!("  speakeasy start|stop|toggle  Control recording via daemon socket");
    println!("  speakeasy status|cancel|quit Daemon status / cancel / shutdown");
    println!("  speakeasy version            Print version");
    println!("  speakeasy help               Show this help");
}

fn cmd_paths() -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::resolve()?;
    let socket = Paths::socket_path()?;
    println!("data:   {}", paths.data_dir.display());
    println!("config: {}", paths.config_dir.display());
    println!("cache:  {}", paths.cache_dir.display());
    println!("models: {}", paths.models_dir.display());
    println!("model:  {}", paths.default_model_path().display());
    println!("socket: {}", socket.display());
    println!(
        "status: {}",
        if paths.model_is_present() {
            "present"
        } else {
            "missing"
        }
    );
    Ok(())
}

fn cmd_download_model(force: bool) -> Result<(), DownloadError> {
    let paths = Paths::resolve()
        .map_err(|err| DownloadError::Io(std::io::Error::other(err.to_string())))?;
    download_default_model(&paths, force)?;
    Ok(())
}

fn cmd_record(seconds: u64) -> Result<std::path::PathBuf, Box<dyn std::error::Error>> {
    let paths = Paths::resolve()?;
    paths.ensure_dirs()?;

    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let output = paths.cache_dir.join(format!("recording-{stamp}.wav"));

    eprintln!("Recording for {seconds}s…");
    let path = record_for_duration(&output, Duration::from_secs(seconds))?;
    eprintln!("Wrote {}", path.display());
    Ok(path)
}

fn cmd_once(seconds: u64) -> Result<String, Box<dyn std::error::Error>> {
    let paths = Paths::resolve()?;
    let mut engine = Engine::open(paths)?;
    eprintln!("Recording for {seconds}s…");
    let text = engine.run_once(Duration::from_secs(seconds))?;
    eprintln!(
        "Copied transcript to clipboard (state={:?})",
        engine.state()
    );
    Ok(text)
}

fn cmd_client(command: Command) -> Result<Response, IpcError> {
    let socket =
        Paths::socket_path().map_err(|err| IpcError::Io(std::io::Error::other(err.to_string())))?;
    send_command(&socket, command)
}
