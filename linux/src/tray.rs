use std::sync::mpsc::Sender;

use ksni::blocking::TrayMethods;
use speakeasy_core::AppState;

use crate::daemon::DaemonMsg;
use crate::ipc::Command;

pub struct SpeakeasyTray {
    pub state: AppState,
    pub tx: Sender<DaemonMsg>,
}

impl ksni::Tray for SpeakeasyTray {
    fn id(&self) -> String {
        "speakeasy".into()
    }

    fn category(&self) -> ksni::Category {
        ksni::Category::ApplicationStatus
    }

    fn title(&self) -> String {
        format!("Speakeasy ({})", state_label(self.state))
    }

    fn icon_name(&self) -> String {
        match self.state {
            AppState::Recording => "media-record".into(),
            AppState::Transcribing | AppState::CleaningUp => "view-refresh".into(),
            AppState::NeedsModel => "dialog-warning".into(),
            AppState::Ready => "audio-input-microphone".into(),
        }
    }

    fn status(&self) -> ksni::Status {
        match self.state {
            AppState::Recording | AppState::Transcribing => ksni::Status::NeedsAttention,
            AppState::NeedsModel => ksni::Status::NeedsAttention,
            _ => ksni::Status::Active,
        }
    }

    fn tool_tip(&self) -> ksni::ToolTip {
        ksni::ToolTip {
            title: "Speakeasy".into(),
            description: format!("State: {}", state_label(self.state)),
            ..Default::default()
        }
    }

    fn activate(&mut self, _x: i32, _y: i32) {
        let _ = self.tx.send(DaemonMsg::Tray {
            command: Command::Toggle,
        });
    }

    fn menu(&self) -> Vec<ksni::MenuItem<Self>> {
        use ksni::menu::*;

        let recording = matches!(self.state, AppState::Recording);
        let busy = matches!(
            self.state,
            AppState::Recording | AppState::Transcribing | AppState::CleaningUp
        );

        vec![
            StandardItem {
                label: format!("Status: {}", state_label(self.state)),
                enabled: false,
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: if recording {
                    "Stop & Transcribe".into()
                } else {
                    "Start Recording".into()
                },
                icon_name: if recording {
                    "media-playback-stop".into()
                } else {
                    "media-record".into()
                },
                enabled: !matches!(
                    self.state,
                    AppState::Transcribing | AppState::CleaningUp | AppState::NeedsModel
                ),
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(DaemonMsg::Tray {
                        command: Command::Toggle,
                    });
                }),
                ..Default::default()
            }
            .into(),
            StandardItem {
                label: "Cancel".into(),
                icon_name: "process-stop".into(),
                enabled: busy,
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(DaemonMsg::Tray {
                        command: Command::Cancel,
                    });
                }),
                ..Default::default()
            }
            .into(),
            MenuItem::Separator,
            StandardItem {
                label: "Quit".into(),
                icon_name: "application-exit".into(),
                activate: Box::new(|this: &mut Self| {
                    let _ = this.tx.send(DaemonMsg::Tray {
                        command: Command::Quit,
                    });
                }),
                ..Default::default()
            }
            .into(),
        ]
    }
}

pub fn spawn(
    tx: Sender<DaemonMsg>,
    state: AppState,
) -> Result<ksni::blocking::Handle<SpeakeasyTray>, ksni::Error> {
    let tray = SpeakeasyTray { state, tx };
    tray.spawn()
}

fn state_label(state: AppState) -> &'static str {
    match state {
        AppState::NeedsModel => "Needs Model",
        AppState::Ready => "Ready",
        AppState::Recording => "Recording",
        AppState::Transcribing => "Transcribing",
        AppState::CleaningUp => "Cleaning Up",
    }
}
