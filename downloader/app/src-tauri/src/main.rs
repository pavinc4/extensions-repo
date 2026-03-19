#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, RunEvent, WindowEvent,
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
const NO_WINDOW: u32 = 0x08000000;

// ── Find yt-dlp on the system ─────────────────────────────────────────────────

fn find_ytdlp() -> String {
    let candidates = vec![
        "yt-dlp".to_string(),
        format!(
            "{}\\Programs\\yt-dlp\\yt-dlp.exe",
            std::env::var("LOCALAPPDATA").unwrap_or_default()
        ),
    ];
    for c in &candidates {
        let mut cmd = Command::new(c);
        cmd.arg("--version");
        #[cfg(windows)]
        cmd.creation_flags(NO_WINDOW);
        if cmd.output().map(|o| o.status.success()).unwrap_or(false) {
            return c.clone();
        }
    }
    candidates[0].clone()
}

fn find_ffmpeg_dir() -> String {
    // Check next to yt-dlp first
    let local = format!(
        "{}\\Programs\\yt-dlp",
        std::env::var("LOCALAPPDATA").unwrap_or_default()
    );
    if std::path::Path::new(&format!("{}\\ffmpeg.exe", local)).exists() {
        return local;
    }
    // Check system PATH
    let mut cmd = Command::new("ffmpeg");
    cmd.arg("-version");
    #[cfg(windows)]
    cmd.creation_flags(NO_WINDOW);
    if cmd.output().map(|o| o.status.success()).unwrap_or(false) {
        return String::new(); // in PATH already, no --ffmpeg-location needed
    }
    String::new()
}

// ── Tauri commands ────────────────────────────────────────────────────────────

/// Probe a URL with yt-dlp -J, return raw JSON
#[tauri::command]
fn probe_url(url: String) -> Result<String, String> {
    let ytdlp = find_ytdlp();
    let mut cmd = Command::new(&ytdlp);
    cmd.args(["--no-warnings", "-J", "--no-playlist", &url]);
    #[cfg(windows)]
    cmd.creation_flags(NO_WINDOW);

    let out = cmd.output().map_err(|e| format!("yt-dlp not found: {}", e))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr)
            .lines()
            .filter(|l| !l.starts_with('['))
            .collect::<Vec<_>>()
            .join(" "))
    }
}

/// Start a download — emits progress events back to the frontend
#[tauri::command]
async fn start_download(
    app: AppHandle,
    args: Vec<String>,
    output_dir: String,
    key: String,
) -> Result<(), String> {
    let ytdlp   = find_ytdlp();
    let ff_dir  = find_ffmpeg_dir();

    let mut full = args;

    if !ff_dir.is_empty() {
        full.push("--ffmpeg-location".into());
        full.push(ff_dir);
    }

    let out_template = if !output_dir.is_empty() {
        format!("{}\\%(title)s.%(ext)s", output_dir)
    } else {
        let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into());
        format!("{}\\Downloads\\%(title)s.%(ext)s", home)
    };
    full.push("-o".into());
    full.push(out_template);
    full.push("--newline".into());

    let mut cmd = Command::new(&ytdlp);
    cmd.args(&full)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    cmd.creation_flags(NO_WINDOW);

    let mut child  = cmd.spawn().map_err(|e| e.to_string())?;
    let stdout     = child.stdout.take().unwrap();
    let key_clone  = key.clone();
    let app_clone  = app.clone();

    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().flatten() {
            let _ = app_clone.emit(&format!("dl-progress-{}", key_clone), &line);
        }
        let ok = child.wait().map(|s| s.success()).unwrap_or(false);
        let _ = app.emit(
            &format!("dl-done-{}", key),
            if ok { "ok" } else { "error" },
        );
    });

    Ok(())
}

/// Hide the main window (called from JS titlebar X button)
#[tauri::command]
fn hide_window(app: AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}

// ── Position window bottom-right above taskbar ────────────────────────────────

fn position_window(app: &AppHandle) {
    use tauri::PhysicalPosition;
    if let Some(win) = app.get_webview_window("main") {
        if let Some(monitor) = win.current_monitor().ok().flatten() {
            let s      = monitor.scale_factor();
            let screen = monitor.size();
            let w      = (520.0 * s) as i32;
            let h      = (620.0 * s) as i32;
            let margin = (16.0  * s) as i32;
            let taskbar= (48.0  * s) as i32;
            let x = screen.width  as i32 - w - margin;
            let y = screen.height as i32 - h - margin - taskbar;
            let _ = win.set_position(PhysicalPosition::new(x, y));
        }
    }
}

fn toggle_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        if win.is_visible().unwrap_or(false) {
            let _ = win.hide();
        } else {
            position_window(app);
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            probe_url,
            start_download,
            hide_window,
        ])
        .setup(|app| {
            // Tray icon — same pattern as Danhawk
            let open = MenuItem::with_id(app, "open", "Open Any Downloader", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit",                true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&open, &quit])?;

            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Any Downloader")
                .menu(&menu)
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event {
                        toggle_window(tray.app_handle());
                    }
                })
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "open" => toggle_window(app),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error building any-downloader")
        .run(|app, event| match event {
            RunEvent::WindowEvent {
                label,
                event: WindowEvent::CloseRequested { api, .. },
                ..
            } => {
                if label == "main" {
                    api.prevent_close();
                    if let Some(w) = app.get_webview_window("main") {
                        let _ = w.hide();
                    }
                }
            }
            _ => {}
        });
}
