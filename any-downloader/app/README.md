# any-downloader app

This folder contains the tool's Python application.

## Stack

- Python 3.12
- FastAPI (backend API)
- pywebview + Edge WebView2 (native window)
- Plain HTML / CSS / JS (frontend UI in static/)
- yt-dlp (download engine)

## Dev

```bash
pip install -r requirements.txt
python main.py
```

## Files

- `main.py` — FastAPI server + pywebview window launcher
- `requirements.txt` — Python dependencies
- `static/index.html` — UI frontend

> Note: `venv/` is gitignored. Never commit it.
