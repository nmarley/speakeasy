mod download;
mod paths;

use std::env;
use std::process::ExitCode;

use download::{DownloadError, download_default_model};
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
            Err(err) => {
                eprintln!("error: {err}");
                ExitCode::FAILURE
            }
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
                Err(err) => {
                    eprintln!("error: {err}");
                    ExitCode::FAILURE
                }
            }
        }
        other => {
            eprintln!("unknown command: {other}");
            print_usage();
            ExitCode::FAILURE
        }
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
    println!("  speakeasy version            Print version");
    println!("  speakeasy help               Show this help");
}

fn cmd_paths() -> Result<(), Box<dyn std::error::Error>> {
    let paths = Paths::resolve()?;
    println!("data:   {}", paths.data_dir.display());
    println!("config: {}", paths.config_dir.display());
    println!("cache:  {}", paths.cache_dir.display());
    println!("models: {}", paths.models_dir.display());
    println!("model:  {}", paths.default_model_path().display());
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
