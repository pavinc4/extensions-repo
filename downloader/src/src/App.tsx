import { useState, useCallback, useRef, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";

// ── Types ─────────────────────────────────────────────────────────────────────

interface RawFormat {
  format_id: string;
  acodec?: string;
  vcodec?: string;
  abr?: number;
  tbr?: number;
  ext?: string;
  height?: number;
  filesize?: number;
  filesize_approx?: number;
}

interface AudioOption {
  key: string;
  label: string;
  sublabel: string;
  size: string;
  args: string[];
  tag: "best" | "small" | "lossless" | "original";
}

interface VideoOption {
  key: string;
  label: string;
  sublabel: string;
  args: string[];
}

interface ProbeData {
  title: string;
  duration: number;
  thumbnail?: string;
  audioLeft: AudioOption[];
  audioRight: AudioOption[];
  videoOptions: VideoOption[];
}

interface DlState {
  status: "idle" | "running" | "done" | "error";
  progress: number;
  speed: string;
  eta: string;
  error?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtSize(b?: number): string {
  if (!b) return "—";
  if (b < 1024 * 1024) return `${(b / 1024).toFixed(0)} KB`;
  return `${(b / (1024 * 1024)).toFixed(1)} MB`;
}

function estSize(kbps: number, dur: number): string {
  return fmtSize((kbps * 1000 * dur) / 8);
}

function fmtDur(s: number): string {
  const m = Math.floor(s / 60);
  const sec = Math.floor(s % 60);
  return `${m}:${String(sec).padStart(2, "0")}`;
}

function buildAudioOptions(
  formats: RawFormat[],
  dur: number,
  url: string
): { left: AudioOption[]; right: AudioOption[] } {
  const audioOnly = formats.filter(
    (f) => f.acodec && f.acodec !== "none" && (!f.vcodec || f.vcodec === "none")
  );
  audioOnly.sort((a, b) => {
    const aAbr = a.abr ?? a.tbr ?? 0;
    const bAbr = b.abr ?? b.tbr ?? 0;
    if (bAbr !== aAbr) return bAbr - aAbr;
    const cp = (c?: string) =>
      c?.includes("opus") ? 3 : c?.includes("aac") ? 2 : 1;
    return cp(b.acodec) - cp(a.acodec);
  });

  const best = audioOnly[0];
  if (!best) return { left: [], right: [] };

  const bestFid = best.format_id;
  const bestAbr = best.abr ?? best.tbr ?? 0;
  const left: AudioOption[] = [];
  const right: AudioOption[] = [];

  // 320kbps MP3 — only if source ≥ 200kbps
  if (bestAbr >= 200) {
    const sz = best.filesize ?? best.filesize_approx;
    left.push({
      key: "mp3-320",
      label: "320 kbps",
      sublabel: "MP3 · highest quality",
      size: sz ? fmtSize(sz) : estSize(bestAbr, dur),
      args: ["-f", bestFid, "-x", "--audio-format", "mp3", "--audio-quality", "0", "--no-playlist", url],
      tag: "best",
    });
  }

  // 128kbps MP3 — always
  const label128 = bestAbr > 128 && bestAbr < 200 ? "128 kbps+" : "128 kbps";
  left.push({
    key: "mp3-128",
    label: label128,
    sublabel: "MP3 · smaller file",
    size: estSize(Math.min(bestAbr, 128), dur),
    args: ["-f", bestFid, "-x", "--audio-format", "mp3", "--audio-quality", "5", "--no-playlist", url],
    tag: "small",
  });

  // WAV
  right.push({
    key: "wav",
    label: "WAV",
    sublabel: "Lossless · uncompressed",
    size: estSize(1411, dur),
    args: ["-f", bestFid, "-x", "--audio-format", "wav", "--no-playlist", url],
    tag: "lossless",
  });

  // Original
  const origAbr = best.abr ?? best.tbr ?? bestAbr;
  const origSz = best.filesize ?? best.filesize_approx;
  right.push({
    key: "original",
    label: `Original · ${(best.ext ?? "webm").toUpperCase()}`,
    sublabel: `${origAbr.toFixed(0)} kbps · no conversion`,
    size: origSz ? fmtSize(origSz) : estSize(origAbr, dur),
    args: ["-f", bestFid, "--no-playlist", url],
    tag: "original",
  });

  return { left, right };
}

function buildVideoOptions(formats: RawFormat[], url: string): VideoOption[] {
  const seen = new Map<number, RawFormat>();
  formats
    .filter((f) => f.vcodec && f.vcodec !== "none" && f.height)
    .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))
    .forEach((f) => { if (!seen.has(f.height!)) seen.set(f.height!, f); });

  return Array.from(seen.entries()).map(([h, f]) => {
    const audioQ = h >= 1080 ? "bestaudio" : h >= 720 ? "bestaudio[abr>=128]" : "bestaudio[abr>=96]";
    const resLabel = { 2160: "4K", 1440: "1440p", 1080: "1080p", 720: "720p", 480: "480p", 360: "360p" }[h] ?? `${h}p`;
    const audioNote = h >= 1080 ? "best audio" : h >= 720 ? "high audio" : "decent audio";
    return {
      key: `video-${h}`,
      label: resLabel,
      sublabel: `MP4 · merged · ${audioNote}`,
      args: ["-f", `${f.format_id}+${audioQ}`, "--merge-output-format", "mp4", "--no-playlist", url],
    };
  });
}

// ── Sub-components ────────────────────────────────────────────────────────────

const TAG_STYLES: Record<string, { color: string; bg: string; label: string }> = {
  best:     { color: "#10b981", bg: "#10b98118", label: "Best" },
  small:    { color: "#3b8bdb", bg: "#3b8bdb18", label: "Smaller" },
  lossless: { color: "#a78bfa", bg: "#a78bfa18", label: "Lossless" },
  original: { color: "#f59e0b", bg: "#f59e0b18", label: "Original" },
};

function DownloadCard({
  label, sublabel, size, tag, onDownload, dlState,
}: {
  label: string; sublabel: string; size: string;
  tag?: string; onDownload: () => void; dlState: DlState;
}) {
  const running = dlState.status === "running";
  const done    = dlState.status === "done";
  const error   = dlState.status === "error";
  const ts = tag ? TAG_STYLES[tag] : null;

  return (
    <button
      onClick={onDownload}
      disabled={running}
      className="w-full text-left flex items-center justify-between px-3.5 py-3 rounded-lg border transition-all duration-150 disabled:opacity-50 disabled:cursor-not-allowed group"
      style={{ background: "#0f0f0f", borderColor: done ? "#10b98140" : error ? "#ef444440" : "#1e1e1e" }}
      onMouseEnter={(e) => { if (!running) (e.currentTarget as HTMLElement).style.borderColor = done ? "#10b98160" : "#2a2a2a"; }}
      onMouseLeave={(e) => { (e.currentTarget as HTMLElement).style.borderColor = done ? "#10b98140" : error ? "#ef444440" : "#1e1e1e"; }}
    >
      <div className="flex flex-col gap-0.5 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-[13px] font-semibold text-[#e8e8e8]">{label}</span>
          {ts && (
            <span className="px-1.5 py-0.5 rounded text-[10px] font-medium flex-shrink-0"
              style={{ color: ts.color, background: ts.bg }}>
              {ts.label}
            </span>
          )}
        </div>
        <span className="text-[11px] text-[#555]">{sublabel}</span>
        {running && (
          <div className="mt-1.5">
            <div className="h-0.5 bg-[#1e1e1e] rounded-full overflow-hidden w-full">
              <div className="h-full rounded-full transition-all duration-300"
                style={{ width: `${dlState.progress}%`, background: "#3b8bdb" }} />
            </div>
            <div className="flex gap-2 mt-1">
              <span className="text-[10px] text-[#333]">{dlState.progress.toFixed(0)}%</span>
              {dlState.speed && <span className="text-[10px] text-[#333]">{dlState.speed}</span>}
              {dlState.eta   && <span className="text-[10px] text-[#333]">ETA {dlState.eta}</span>}
            </div>
          </div>
        )}
        {done  && <span className="text-[10px] text-[#10b981] mt-0.5">Done</span>}
        {error && <span className="text-[10px] text-[#ef4444] mt-0.5 truncate">{dlState.error ?? "Failed"}</span>}
      </div>

      <div className="flex items-center gap-2.5 flex-shrink-0 ml-3">
        <span className="text-[11px] font-mono text-[#333]">{size}</span>
        <div className="w-6 h-6 rounded flex items-center justify-center" style={{ background: "#1a1a1a" }}>
          {running ? (
            <svg className="spin w-3 h-3 text-[#555]" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" opacity="0.2"/>
              <path fill="currentColor" d="M4 12a8 8 0 018-8v3a5 5 0 00-5 5H4z" opacity="0.8"/>
            </svg>
          ) : done ? (
            <svg className="w-3 h-3 text-[#10b981]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <polyline points="20 6 9 17 4 12"/>
            </svg>
          ) : (
            <svg className="w-3 h-3 text-[#444] group-hover:text-[#888] transition-colors" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>
            </svg>
          )}
        </div>
      </div>
    </button>
  );
}

// ── Main App ──────────────────────────────────────────────────────────────────

export default function App() {
  const [url,         setUrl]         = useState("");
  const [probing,     setProbing]     = useState(false);
  const [probeData,   setProbeData]   = useState<ProbeData | null>(null);
  const [probeErr,    setProbeErr]    = useState<string | null>(null);
  const [tab,         setTab]         = useState<"audio" | "video">("audio");
  const [outputDir,   setOutputDir]   = useState("");
  const [dlStates,    setDlStates]    = useState<Record<string, DlState>>({});
  const [ffmpegReady, setFfmpegReady] = useState<"checking"|"downloading"|"ready"|"error">("checking");
  const unlistenRefs = useRef<Record<string, (() => void)[]>>({});
  const dlCounter    = useRef(0);

  // Escape hides window
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === "Escape") getCurrentWindow().hide(); };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  // Auto-download ffmpeg on first run if missing
  useEffect(() => {
    (async () => {
      try {
        const result = await invoke<string>("ensure_ffmpeg");
        if (result === "downloaded") {
          setFfmpegReady("downloading");
          await new Promise(r => setTimeout(r, 1200));
        }
        setFfmpegReady("ready");
      } catch {
        setFfmpegReady("error");
      }
    })();
  }, []);

  // ── Probe ──────────────────────────────────────────────────────────────────

  const handleProbe = useCallback(async () => {
    const u = url.trim();
    if (!u) return;
    setProbing(true);
    setProbeErr(null);
    setProbeData(null);
    setDlStates({});
    try {
      const raw = await invoke<string>("probe_url", { url: u });
      const json = JSON.parse(raw);
      const fmts: RawFormat[] = json.formats ?? [];
      const dur: number = json.duration ?? 0;
      const { left, right } = buildAudioOptions(fmts, dur, u);
      const video = buildVideoOptions(fmts, u);
      setProbeData({
        title: json.title ?? "Unknown",
        duration: dur,
        thumbnail: json.thumbnail,
        audioLeft: left,
        audioRight: right,
        videoOptions: video,
      });
    } catch (e) {
      setProbeErr(
        String(e).replace("Error: ", "").slice(0, 200) ||
        "Could not fetch info. Check the URL."
      );
    } finally {
      setProbing(false);
    }
  }, [url]);

  // ── Download ───────────────────────────────────────────────────────────────

  const handleDownload = useCallback(async (key: string, args: string[]) => {
    const id = `${key}-${++dlCounter.current}`;

    // Clean up old listeners for this key
    unlistenRefs.current[key]?.forEach((u) => u());

    setDlStates((prev) => ({
      ...prev,
      [key]: { status: "running", progress: 0, speed: "", eta: "" },
    }));

    const unlisten1 = await listen<string>(`dl-progress-${id}`, ({ payload: line }) => {
      const prog  = line.match(/(\d+\.?\d*)%/)?.[1];
      const speed = line.match(/([\d.]+\s*[KMG]iB\/s)/)?.[1];
      const eta   = line.match(/ETA\s+(\d+:\d+)/)?.[1];
      setDlStates((prev) => ({
        ...prev,
        [key]: {
          ...prev[key],
          progress: prog  ? parseFloat(prog) : prev[key]?.progress ?? 0,
          speed:    speed ?? prev[key]?.speed ?? "",
          eta:      eta   ?? prev[key]?.eta   ?? "",
        },
      }));
    });

    const unlisten2 = await listen<string>(`dl-done-${id}`, ({ payload }) => {
      setDlStates((prev) => ({
        ...prev,
        [key]: {
          ...prev[key],
          status:   payload === "ok" ? "done" : "error",
          progress: payload === "ok" ? 100 : prev[key]?.progress ?? 0,
          error:    payload !== "ok" ? "Download failed" : undefined,
        },
      }));
    });

    unlistenRefs.current[key] = [unlisten1, unlisten2];

    try {
      await invoke("start_download", {
        args,
        outputDir,
        downloadId: id,
      });
    } catch (e) {
      setDlStates((prev) => ({
        ...prev,
        [key]: { status: "error", progress: 0, speed: "", eta: "", error: String(e) },
      }));
    }
  }, [outputDir]);

  const handleBrowse = async () => {
    try {
      const dir = await invoke<string | null>("pick_folder");
      if (dir) setOutputDir(dir);
    } catch {}
  };

  const getDl = (key: string): DlState =>
    dlStates[key] ?? { status: "idle", progress: 0, speed: "", eta: "" };

  // ── Render ─────────────────────────────────────────────────────────────────

  return (
    <div className="flex flex-col h-full" style={{ background: "#0d0d0d" }}>

      {/* ── Custom title bar ─────────────────────────────────────────────── */}
      <div
        className="flex items-center justify-between px-4 flex-shrink-0"
        style={{ height: 44, background: "#0d0d0d", borderBottom: "1px solid #1a1a1a" }}
        data-tauri-drag-region
      >
        <div className="flex items-center gap-2.5" data-tauri-drag-region>
          <div className="w-5 h-5 rounded flex items-center justify-center flex-shrink-0"
            style={{ background: "#1a0505" }}>
            <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="#ef4444" strokeWidth="2.5">
              <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>
            </svg>
          </div>
          <span className="text-[13px] font-semibold text-[#e8e8e8]" data-tauri-drag-region>
            Any Downloader
          </span>
          {ffmpegReady === "checking" && (
            <span className="text-[10px] text-[#444]">checking ffmpeg...</span>
          )}
          {ffmpegReady === "downloading" && (
            <span className="text-[10px] text-[#f59e0b]">downloading ffmpeg...</span>
          )}
          {ffmpegReady === "error" && (
            <span className="text-[10px] text-[#ef4444]">ffmpeg missing — video/MP3 may fail</span>
          )}
        </div>
        <button
          onClick={() => getCurrentWindow().hide()}
          className="w-6 h-6 rounded flex items-center justify-center text-[#444] hover:text-[#888] hover:bg-[#1a1a1a] transition-all duration-150"
        >
          <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
          </svg>
        </button>
      </div>

      {/* ── Scrollable content ───────────────────────────────────────────── */}
      <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-3">

        {/* URL Input */}
        <div className="flex gap-2">
          <div className="flex-1 flex items-center gap-2 px-3 rounded-lg border"
            style={{ background: "#0a0a0a", borderColor: "#1e1e1e", height: 36 }}>
            <svg className="w-3.5 h-3.5 text-[#333] flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/>
              <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>
            </svg>
            <input
              type="text"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleProbe()}
              placeholder="Paste YouTube, Instagram, Twitter URL..."
              className="flex-1 bg-transparent text-[12px] text-[#e8e8e8] placeholder-[#2a2a2a] outline-none"
            />
            {url && (
              <button onClick={() => { setUrl(""); setProbeData(null); setProbeErr(null); }}
                className="text-[#2a2a2a] hover:text-[#555] transition-colors">
                <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                </svg>
              </button>
            )}
          </div>
          <button
            onClick={handleProbe}
            disabled={!url.trim() || probing}
            className="px-3.5 rounded-lg text-[12px] font-medium transition-all duration-150 disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1.5 flex-shrink-0"
            style={{ background: "#ef4444", color: "white", height: 36 }}
          >
            {probing ? (
              <svg className="spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" opacity="0.2"/>
                <path fill="currentColor" d="M4 12a8 8 0 018-8v3a5 5 0 00-5 5H4z"/>
              </svg>
            ) : (
              <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <circle cx="11" cy="11" r="8"/><path d="m21 21-4.35-4.35"/>
              </svg>
            )}
            {probing ? "Fetching..." : "Fetch"}
          </button>
        </div>

        {/* Error */}
        {probeErr && (
          <div className="px-3 py-2.5 rounded-lg border flex items-start gap-2 fade-in"
            style={{ background: "#1a0505", borderColor: "#ef444430" }}>
            <svg className="w-3.5 h-3.5 text-[#ef4444] flex-shrink-0 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
            </svg>
            <p className="text-[11px] text-[#ef4444] leading-relaxed">{probeErr}</p>
          </div>
        )}

        {/* Video info strip */}
        {probeData && (
          <div className="flex items-center gap-2.5 px-3 py-2 rounded-lg border fade-in"
            style={{ background: "#0a0a0a", borderColor: "#1a1a1a" }}>
            {probeData.thumbnail && (
              <img src={probeData.thumbnail} alt="" className="w-10 h-7 object-cover rounded flex-shrink-0"
                style={{ borderRadius: 4 }} />
            )}
            <div className="flex-1 min-w-0">
              <p className="text-[12px] font-medium text-[#e8e8e8] truncate">{probeData.title}</p>
              <p className="text-[10px] text-[#444] mt-0.5">
                {fmtDur(probeData.duration)} · {probeData.audioLeft.length + probeData.audioRight.length} audio options · {probeData.videoOptions.length} resolutions
              </p>
            </div>
          </div>
        )}

        {/* Tabs */}
        {probeData && (
          <div className="flex items-center gap-4 border-b" style={{ borderColor: "#1a1a1a" }}>
            {(["audio", "video"] as const).map((t) => (
              <button key={t} onClick={() => setTab(t)}
                className="pb-2.5 text-[12px] font-medium transition-colors duration-150 relative capitalize"
                style={{ color: tab === t ? "#ef4444" : "#555" }}>
                {t}
                {tab === t && (
                  <div className="absolute bottom-0 left-0 right-0 h-0.5 rounded-full" style={{ background: "#ef4444" }} />
                )}
              </button>
            ))}
          </div>
        )}

        {/* Audio tab */}
        {probeData && tab === "audio" && (
          <div className="flex gap-3 fade-in">
            {/* Left — MP3 */}
            <div className="flex-1 flex flex-col gap-2">
              <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold mb-0.5">MP3</p>
              {probeData.audioLeft.map((opt) => (
                <DownloadCard key={opt.key} {...opt} dlState={getDl(opt.key)}
                  onDownload={() => handleDownload(opt.key, opt.args)} />
              ))}
              {probeData.audioLeft.length === 0 && (
                <p className="text-[11px] text-[#333]">No MP3 options available</p>
              )}
            </div>
            {/* Right — Lossless */}
            <div className="flex-1 flex flex-col gap-2">
              <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold mb-0.5">Lossless / Original</p>
              {probeData.audioRight.map((opt) => (
                <DownloadCard key={opt.key} {...opt} dlState={getDl(opt.key)}
                  onDownload={() => handleDownload(opt.key, opt.args)} />
              ))}
            </div>
          </div>
        )}

        {/* Video tab */}
        {probeData && tab === "video" && (
          <div className="flex flex-col gap-2 fade-in">
            <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold">Video · MP4</p>
            {probeData.videoOptions.length === 0 ? (
              <p className="text-[11px] text-[#333]">No video streams found</p>
            ) : (
              probeData.videoOptions.map((opt) => (
                <DownloadCard key={opt.key} label={opt.label} sublabel={opt.sublabel}
                  size="—" dlState={getDl(opt.key)}
                  onDownload={() => handleDownload(opt.key, opt.args)} />
              ))
            )}
          </div>
        )}

        {/* Empty state */}
        {!probeData && !probing && !probeErr && (
          <div className="flex flex-col items-center justify-center flex-1 gap-3 py-10">
            <div className="w-12 h-12 rounded-xl flex items-center justify-center"
              style={{ background: "#111", border: "1px solid #1e1e1e" }}>
              <svg className="w-6 h-6 text-[#333]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3"/>
              </svg>
            </div>
            <div className="text-center">
              <p className="text-[13px] text-[#555] font-medium">Paste a URL to get started</p>
              <p className="text-[11px] text-[#333] mt-1">YouTube, Instagram, Twitter, Reddit, and 1000+ more</p>
            </div>
          </div>
        )}
      </div>

      {/* ── Output folder bar ─────────────────────────────────────────────── */}
      <div className="flex items-center gap-2 px-4 py-2.5 flex-shrink-0"
        style={{ borderTop: "1px solid #1a1a1a", background: "#0a0a0a" }}>
        <svg className="w-3 h-3 text-[#333] flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z"/>
        </svg>
        <span className="flex-1 text-[11px] text-[#444] truncate">
          {outputDir || "Default — Downloads folder"}
        </span>
        <button onClick={handleBrowse}
          className="text-[11px] text-[#444] hover:text-[#888] transition-colors px-2 py-1 rounded hover:bg-[#1a1a1a] flex-shrink-0">
          Browse
        </button>
        {outputDir && (
          <button onClick={() => setOutputDir("")}
            className="text-[11px] text-[#333] hover:text-[#555] transition-colors flex-shrink-0">
            Reset
          </button>
        )}
      </div>
    </div>
  );
}
