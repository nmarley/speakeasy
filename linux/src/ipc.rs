use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::Path;
use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Command {
    Start,
    Stop,
    Toggle,
    Status,
    Quit,
    Cancel,
}

impl Command {
    pub fn parse(line: &str) -> Option<Self> {
        match line.trim().to_ascii_lowercase().as_str() {
            "start" => Some(Self::Start),
            "stop" => Some(Self::Stop),
            "toggle" => Some(Self::Toggle),
            "status" => Some(Self::Status),
            "quit" | "shutdown" => Some(Self::Quit),
            "cancel" => Some(Self::Cancel),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Start => "start",
            Self::Stop => "stop",
            Self::Toggle => "toggle",
            Self::Status => "status",
            Self::Quit => "quit",
            Self::Cancel => "cancel",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Response {
    Ok,
    OkMsg(String),
    Status(String),
    Err(String),
}

impl Response {
    pub fn encode(&self) -> String {
        match self {
            Self::Ok => "ok\n".to_owned(),
            Self::OkMsg(msg) => format!("ok {}\n", single_line(msg)),
            Self::Status(state) => format!("status {}\n", single_line(state)),
            Self::Err(msg) => format!("err {}\n", single_line(msg)),
        }
    }

    pub fn parse(line: &str) -> Self {
        let line = line.trim_end_matches(['\r', '\n']);
        if let Some(rest) = line.strip_prefix("ok ") {
            if rest.is_empty() {
                Self::Ok
            } else {
                Self::OkMsg(rest.to_owned())
            }
        } else if line == "ok" {
            Self::Ok
        } else if let Some(rest) = line.strip_prefix("status ") {
            Self::Status(rest.to_owned())
        } else if let Some(rest) = line.strip_prefix("err ") {
            Self::Err(rest.to_owned())
        } else {
            Self::Err(format!("malformed response: {line}"))
        }
    }

    pub fn is_err(&self) -> bool {
        matches!(self, Self::Err(_))
    }
}

fn single_line(s: &str) -> String {
    s.chars()
        .map(|c| if c == '\n' || c == '\r' { ' ' } else { c })
        .collect()
}

#[derive(Debug)]
pub enum IpcError {
    Io(std::io::Error),
    NotRunning,
    Protocol(String),
}

impl std::fmt::Display for IpcError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(err) => write!(f, "IPC I/O error: {err}"),
            Self::NotRunning => write!(f, "daemon not running (start with: speakeasy daemon)"),
            Self::Protocol(msg) => write!(f, "IPC protocol error: {msg}"),
        }
    }
}

impl std::error::Error for IpcError {}

impl From<std::io::Error> for IpcError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

pub fn send_command(socket_path: &Path, command: Command) -> Result<Response, IpcError> {
    if !socket_path.exists() {
        return Err(IpcError::NotRunning);
    }

    let stream = UnixStream::connect(socket_path).map_err(|err| {
        if err.kind() == std::io::ErrorKind::ConnectionRefused
            || err.kind() == std::io::ErrorKind::NotFound
        {
            IpcError::NotRunning
        } else {
            IpcError::Io(err)
        }
    })?;
    stream.set_read_timeout(Some(Duration::from_secs(600)))?;
    stream.set_write_timeout(Some(Duration::from_secs(5)))?;

    let mut stream = stream;
    write!(stream, "{}\n", command.as_str())?;
    stream.flush()?;

    let mut reader = BufReader::new(stream);
    let mut line = String::new();
    let n = reader.read_line(&mut line)?;
    if n == 0 {
        return Err(IpcError::Protocol("empty response from daemon".into()));
    }
    Ok(Response::parse(&line))
}

pub fn is_daemon_alive(socket_path: &Path) -> bool {
    if !socket_path.exists() {
        return false;
    }
    match UnixStream::connect(socket_path) {
        Ok(mut stream) => {
            let _ = write!(stream, "status\n");
            let _ = stream.flush();
            let mut reader = BufReader::new(stream);
            let mut line = String::new();
            reader.read_line(&mut line).is_ok_and(|n| n > 0)
        }
        Err(_) => false,
    }
}
