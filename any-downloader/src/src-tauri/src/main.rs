#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::io::{BufRead, BufReader, Read};
use std::process::{Command, Stdio};
use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager, RunEvent, WindowEvent,
};

#[cfg(windows)]
use std::os::windows::process::CommandExt;
const CREATE_NO_WINDOW: u32 = 0x08000000;

// ── Resolve bundled binary path ───────────────────────────────────────────────

fn bin_path(app: &AppHandle, name: &str) -> std::path::PathBuf {
    app.path()
        .resource_dir()
        .unwrap()
        .join("bin")
        .join(format!("{}.exe", name))
}

// ── Commands ──────────────────────────────────────────────────────────────────

/// Check if ffmpeg exists in bin/; if not, download it automatically.
/// Called from React on app startup. Returns "ready" or "downloaded".
#[tauri::command]
async fn ensure_ffmpeg(app: AppHandle) -> Result<String, String> {
    let ffmpeg = bin_path(&app, "ffmpeg");
    if ffmpeg.exists() {
        return Ok("ready".to_string());
    }

    let bin_dir = ffmpeg.parent().unwrap().to_path_buf();
    std::fs::create_dir_all(&bin_dir).ok();

    // yt-dlp's own FFmpeg builds — always latest, small (~3MB for just ffmpeg.exe)
    let zip_url  = "https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip";
    let zip_path = bin_dir.join("ffmpeg-tmp.zip");

    // Download
    let resp = ureq::get(zip_url)
        .call()
        .map_err(|e| format!("Download failed: {}", e))?;

    let mut bytes: Vec<u8> = Vec::new();
    resp.into_reader()
        .read_to_end(&mut bytes)
        .map_err(|e| format!("Read failed: {}", e))?;

    std::fs::write(&zip_path, &bytes)
        .map_err(|e| format!("Write zip failed: {}", e))?;

    // Extract just ffmpeg.exe from the zip
    let zip_file  = std::fs::File::open(&zip_path)
        .map_err(|e| format!("Open zip failed: {}", e))?;
    let mut archive = zip::ZipArchive::new(zip_file)
        .map_err(|e| format!("Zip parse error: {}", e))?;

    let mut extracted = false;
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)
            .map_err(|e| format!("Zip entry error: {}", e))?;
        let name = entry.name().to_lowercase();
        // The zip contains  ffmpeg-master-.../bin/ffmpeg.exe
        if name.ends_with("/ffmpeg.exe") || name == "ffmpeg.exe" {
            let mut out = std::fs::File::create(&ffmpeg)
                .map_err(|e| format!("Create ffmpeg.exe failed: {}", e))?;
            std::io::copy(&mut entry, &mut out)
                .map_err(|e| format!("Extract failed: {}", e))?;
            extracted = true;
            break;
        }
    }

    let _ = std::fs::remove_file(&zip_path);

    if extracted && ffmpeg.exists() {
        Ok("downloaded".to_string())
    } else {
        Err("ffmpeg.exe not found inside the downloaded zip".to_string())
    }
}

/// Run yt-dlp -J and return the raw JSON string
#[tauri::command]
fn probe_url(app: AppHandle, url: String) -> Result<String, String> {
    let ytdlp = bin_path(&app, "yt-dlp");

    let mut cmd = Command::new(&ytdlp);
    cmd.args(["-J", "--no-playlist", &url]);

    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let out = cmd.output()
        .map_err(|e| format!("Failed to run yt-dlp: {}", e))?;

    if !out.status.success() {
        return Err(String::from_utf8_lossy(&out.stderr).to_string());
    }

    Ok(String::from_utf8_lossy(&out.stdout).to_string())
}

/// Start a download — streams progress events back to the window
#[tauri::command]
async fn start_download(
    app: AppHandle,
    args: Vec<String>,
    output_dir: String,
    download_id: String,
) -> Result<(), String> {
    let ytdlp  = bin_path(&app, "yt-dlp");
    let ffmpeg = bin_path(&app, "ffmpeg");

    let mut full_args = args.clone();

    // Always tell yt-dlp where our bundled ffmpeg is
    full_args.push("--ffmpeg-location".to_string());
    full_args.push(ffmpeg.to_string_lossy().to_string());

    // Output path — use chosen folder or system Downloads
    let template = if !output_dir.is_empty() {
        format!("{}\\%(title)s.%(ext)s", output_dir)
    } else {
        let dl = dirs_next::download_dir()
            .unwrap_or_else(|| std::path::PathBuf::from("."));
        format!("{}\\%(title)s.%(ext)s", dl.to_string_lossy())
    };
    full_args.push("-o".to_string());
    full_args.push(template);
    full_args.push("--newline".to_string());

    let mut cmd = Command::new(&ytdlp);
    cmd.args(&full_args);
    cmd.stdout(Stdio::piped());
    cmd.stderr(Stdio::piped());

    #[cfg(windows)]
    cmd.creation_flags(CREATE_NO_WINDOW);

    let mut child = cmd.spawn()
        .map_err(|e| format!("spawn failed: {}", e))?;

    let stdout    = child.stdout.take().unwrap();
    let reader    = BufReader::new(stdout);
    let app_clone = app.clone();
    let id_clone  = download_id.clone();

    std::thread::spawn(move || {
        for line in reader.lines().flatten() {
            let _ = app_clone.emit(&format!("dl-progress-{}", id_clone), &line);
        }
        let ok = child.wait().map(|s| s.success()).unwrap_or(false);
        let _ = app_clone.emit(
            &format!("dl-done-{}", id_clone),
            if ok { "ok" } else { "error" },
        );
    });

    Ok(())
}

/// Open a native folder picker, return the chosen path
#[tauri::command]
async fn pick_folder(app: AppHandle) -> Option<String> {
    use tauri_plugin_dialog::DialogExt;
    app.dialog()
        .file()
        .pick_folder()
        .blocking_pick()
        .map(|p| p.to_string_lossy().to_string())
}

// ── Main ──────────────────────────────────────────────────────────────────────

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            ensure_ffmpeg,
            probe_url,
            start_download,
            pick_folder,
        ])
        .setup(|app| {
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
        .run(|app, event| {
            if let RunEvent::WindowEvent {
                label,
                event: WindowEvent::CloseRequested { api, .. },
                ..
            } = event {
                if label == "main" {
                    api.prevent_close();
                    if let Some(win) = app.get_webview_window("main") {
                        let _ = win.hide();
                    }
                }
            }
        });
}

fn toggle_window(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("main") {
        if win.is_visible().unwrap_or(false) {
            let _ = win.hide();
        } else {
            let _ = win.show();
            let _ = win.set_focus();
        }
    }
}
