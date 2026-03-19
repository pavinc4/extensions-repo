import { useState, useCallback, useRef, useEffect } from "react";
import { invoke } from "@tauri-apps/api/core";
import { listen, type UnlistenFn } from "@tauri-apps/api/event";

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

interface AudioCard {
  key: string;
  label: string;
  sub: string;
  size: string;
  tag: "best" | "small" | "lossless" | "original";
  args: string[];
}

interface VideoCard {
  key: string;
  label: string;
  sub: string;
  args: string[];
}

interface ProbeResult {
  title: string;
  duration: number;
  thumbnail?: string;
  audioLeft: AudioCard[];
  audioRight: AudioCard[];
  video: VideoCard[];
}

interface DlState {
  status: "idle" | "running" | "done" | "error";
  pct: number;
  speed: string;
  eta: string;
  error?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const fmtSize = (b?: number) => {
  if (!b) return "—";
  return b < 1_048_576
    ? `${(b / 1024).toFixed(0)} KB`
    : `${(b / 1_048_576).toFixed(1)} MB`;
};
const estSize = (kbps: number, dur: number) =>
  fmtSize((kbps * 1000 * dur) / 8);
const fmtDur = (s: number) =>
  `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}`;

function buildAudio(formats: RawFormat[], dur: number, url: string) {
  const audio = formats
    .filter(
      (f) =>
        f.acodec &&
        f.acodec !== "none" &&
        (!f.vcodec || f.vcodec === "none")
    )
    .sort((a, b) => {
      const da = a.abr ?? a.tbr ?? 0;
      const db = b.abr ?? b.tbr ?? 0;
      if (db !== da) return db - da;
      const cp = (c?: string) =>
        c?.includes("opus") ? 3 : c?.includes("aac") ? 2 : 1;
      return cp(b.acodec) - cp(a.acodec);
    });

  const best = audio[0];
  if (!best) return { left: [], right: [] };

  const fid = best.format_id;
  const abr = best.abr ?? best.tbr ?? 0;
  const left: AudioCard[] = [];
  const right: AudioCard[] = [];

  if (abr >= 200) {
    left.push({
      key: "mp3-320",
      label: "320 kbps",
      sub: "MP3 · highest quality",
      tag: "best",
      size: best.filesize
        ? fmtSize(best.filesize)
        : estSize(abr, dur),
      args: [
        "-f", fid, "-x",
        "--audio-format", "mp3",
        "--audio-quality", "0",
        "--no-playlist", url,
      ],
    });
  }

  left.push({
    key: "mp3-128",
    label: abr > 128 && abr < 200 ? "128 kbps+" : "128 kbps",
    sub: "MP3 · smaller file",
    tag: "small",
    size: estSize(Math.min(abr, 128), dur),
    args: [
      "-f", fid, "-x",
      "--audio-format", "mp3",
      "--audio-quality", "5",
      "--no-playlist", url,
    ],
  });

  right.push({
    key: "wav",
    label: "WAV",
    sub: "Lossless · uncompressed",
    tag: "lossless",
    size: estSize(1411, dur),
    args: ["-f", fid, "-x", "--audio-format", "wav", "--no-playlist", url],
  });

  right.push({
    key: "original",
    label: `Original · ${(best.ext ?? "webm").toUpperCase()}`,
    sub: `${abr.toFixed(0)} kbps · no conversion`,
    tag: "original",
    size: best.filesize
      ? fmtSize(best.filesize)
      : estSize(abr, dur),
    args: ["-f", fid, "--no-playlist", url],
  });

  return { left, right };
}

function buildVideo(formats: RawFormat[], url: string): VideoCard[] {
  const seen = new Map<number, string>();
  formats
    .filter((f) => f.vcodec && f.vcodec !== "none" && f.height)
    .sort((a, b) => (b.height ?? 0) - (a.height ?? 0))
    .forEach((f) => {
      if (!seen.has(f.height!)) seen.set(f.height!, f.format_id);
    });

  return Array.from(seen.entries()).map(([h, fid]) => {
    const aq =
      h >= 1080
        ? "bestaudio"
        : h >= 720
        ? "bestaudio[abr>=128]"
        : "bestaudio[abr>=96]";
    const labels: Record<number, string> = {
      2160: "4K", 1440: "1440p", 1080: "1080p",
      720: "720p", 480: "480p", 360: "360p",
    };
    const note =
      h >= 1080 ? "best audio" : h >= 720 ? "high audio" : "decent audio";
    return {
      key: `video-${h}`,
      label: labels[h] ?? `${h}p`,
      sub: `MP4 · merged · ${note}`,
      args: [
        "-f", `${fid}+${aq}`,
        "--merge-output-format", "mp4",
        "--no-playlist", url,
      ],
    };
  });
}

// ── Tag styles ────────────────────────────────────────────────────────────────

const TAGS = {
  best:     { color: "#10b981", bg: "#10b98118", label: "Best" },
  small:    { color: "#3b8bdb", bg: "#3b8bdb18", label: "Smaller" },
  lossless: { color: "#a78bfa", bg: "#a78bfa18", label: "Lossless" },
  original: { color: "#f59e0b", bg: "#f59e0b18", label: "Original" },
};

// ── Download card ─────────────────────────────────────────────────────────────

function Card({
  label, sub, size, tag, dl, onClick,
}: {
  label: string; sub: string; size: string;
  tag?: keyof typeof TAGS; dl: DlState; onClick: () => void;
}) {
  const t       = tag ? TAGS[tag] : null;
  const running = dl.status === "running";
  const done    = dl.status === "done";
  const err     = dl.status === "error";

  return (
    <button
      onClick={onClick}
      disabled={running}
      className="w-full text-left group flex items-center justify-between px-3 py-3 rounded-lg border transition-all duration-150 disabled:opacity-50 disabled:cursor-not-allowed"
      style={{
        background: "#0f0f0f",
        borderColor: done ? "#10b98140" : err ? "#ef444440" : "#1e1e1e",
      }}
      onMouseEnter={(e) => {
        if (!running)
          (e.currentTarget as HTMLElement).style.borderColor =
            done ? "#10b98160" : "#2a2a2a";
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLElement).style.borderColor =
          done ? "#10b98140" : err ? "#ef444440" : "#1e1e1e";
      }}
    >
      <div className="flex flex-col gap-0.5 flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="text-[12px] font-semibold text-[#e8e8e8]">{label}</span>
          {t && (
            <span
              className="px-1.5 py-px rounded text-[10px] font-medium flex-shrink-0"
              style={{ color: t.color, background: t.bg }}
            >
              {t.label}
            </span>
          )}
        </div>
        <span className="text-[11px] text-[#555]">{sub}</span>

        {running && (
          <div className="mt-1.5">
            <div className="h-px bg-[#1e1e1e] rounded-full overflow-hidden">
              <div
                className="h-full bg-[#3b8bdb] rounded-full transition-all duration-300"
                style={{ width: `${dl.pct}%` }}
              />
            </div>
            <div className="flex gap-2 mt-1">
              <span className="text-[10px] text-[#444]">{dl.pct.toFixed(0)}%</span>
              {dl.speed && <span className="text-[10px] text-[#444]">{dl.speed}</span>}
              {dl.eta   && <span className="text-[10px] text-[#444]">ETA {dl.eta}</span>}
            </div>
          </div>
        )}
        {done && <span className="text-[10px] text-[#10b981] mt-0.5">Saved</span>}
        {err  && (
          <span className="text-[10px] text-[#ef4444] mt-0.5 truncate">
            {dl.error ?? "Failed"}
          </span>
        )}
      </div>

      <div className="flex items-center gap-2 flex-shrink-0 ml-2">
        <span className="text-[11px] font-mono text-[#333]">{size}</span>
        <div
          className="w-6 h-6 rounded flex items-center justify-center"
          style={{ background: "#1a1a1a" }}
        >
          {running ? (
            <svg className="spin w-3 h-3 text-[#555]" viewBox="0 0 24 24" fill="none">
              <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" opacity=".2" />
              <path fill="currentColor" d="M4 12a8 8 0 018-8v3a5 5 0 00-5 5H4z" />
            </svg>
          ) : done ? (
            <svg className="w-3 h-3 text-[#10b981]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5">
              <polyline points="20 6 9 17 4 12" />
            </svg>
          ) : (
            <svg
              className="w-3 h-3 text-[#444] group-hover:text-[#888] transition-colors"
              viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
            >
              <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3" />
            </svg>
          )}
        </div>
      </div>
    </button>
  );
}

// ── Main App ──────────────────────────────────────────────────────────────────

export default function App() {
  const [url,      setUrl]      = useState("");
  const [probing,  setProbing]  = useState(false);
  const [result,   setResult]   = useState<ProbeResult | null>(null);
  const [probeErr, setProbeErr] = useState("");
  const [tab,      setTab]      = useState<"audio" | "video">("audio");
  const [outDir,   setOutDir]   = useState("");
  const [dlStates, setDlStates] = useState<Record<string, DlState>>({});
  const unlistens = useRef<Record<string, UnlistenFn[]>>({});
  const counter   = useRef(0);

  // Escape hides window
  useEffect(() => {
    const h = (e: KeyboardEvent) => {
      if (e.key === "Escape") invoke("hide_window");
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  const getDl = (key: string): DlState =>
    dlStates[key] ?? { status: "idle", pct: 0, speed: "", eta: "" };

  // ── Probe ──────────────────────────────────────────────────────────────────
  const handleProbe = useCallback(async () => {
    const u = url.trim();
    if (!u) return;
    setProbing(true);
    setProbeErr("");
    setResult(null);
    setDlStates({});
    try {
      const raw  = await invoke<string>("probe_url", { url: u });
      const json = JSON.parse(raw);
      const fmts: RawFormat[] = json.formats ?? [];
      const dur: number = json.duration ?? 0;
      const { left, right } = buildAudio(fmts, dur, u);
      setResult({
        title: json.title ?? "Unknown",
        duration: dur,
        thumbnail: json.thumbnail,
        audioLeft: left,
        audioRight: right,
        video: buildVideo(fmts, u),
      });
    } catch (e) {
      setProbeErr(
        String(e)
          .replace(/^Error:\s*/, "")
          .slice(0, 300)
      );
    } finally {
      setProbing(false);
    }
  }, [url]);

  // ── Download ───────────────────────────────────────────────────────────────
  const handleDownload = useCallback(
    async (key: string, args: string[]) => {
      unlistens.current[key]?.forEach((u) => u());
      const id = `${key}-${++counter.current}`;

      setDlStates((p) => ({
        ...p,
        [key]: { status: "running", pct: 0, speed: "", eta: "" },
      }));

      const u1 = await listen<string>(
        `dl-progress-${id}`,
        ({ payload: line }) => {
          const pct   = line.match(/(\d+\.?\d*)%/)?.[1];
          const speed = line.match(/([\d.]+\s*[KMGk]iB\/s)/)?.[1];
          const eta   = line.match(/ETA\s+(\d+:\d+)/)?.[1];
          setDlStates((p) => ({
            ...p,
            [key]: {
              ...p[key],
              pct:   pct   ? parseFloat(pct) : p[key]?.pct   ?? 0,
              speed: speed ?? p[key]?.speed  ?? "",
              eta:   eta   ?? p[key]?.eta    ?? "",
            },
          }));
        }
      );

      const u2 = await listen<string>(
        `dl-done-${id}`,
        ({ payload }) => {
          setDlStates((p) => ({
            ...p,
            [key]: {
              ...p[key],
              status: payload === "ok" ? "done" : "error",
              pct:    payload === "ok" ? 100 : p[key]?.pct ?? 0,
              error:  payload !== "ok" ? "Download failed" : undefined,
            },
          }));
        }
      );

      unlistens.current[key] = [u1, u2];

      try {
        await invoke("start_download", {
          args,
          outputDir: outDir,
          key: id,
        });
      } catch (e) {
        setDlStates((p) => ({
          ...p,
          [key]: {
            status: "error",
            pct: 0,
            speed: "",
            eta: "",
            error: String(e),
          },
        }));
      }
    },
    [outDir]
  );

  // ── Render ─────────────────────────────────────────────────────────────────
  return (
    <div className="flex flex-col h-full" style={{ background: "#0d0d0d" }}>

      {/* Custom title bar */}
      <div
        className="flex items-center justify-between px-4 flex-shrink-0"
        style={{ height: 44, borderBottom: "1px solid #1a1a1a" }}
        data-tauri-drag-region
      >
        <div className="flex items-center gap-2" data-tauri-drag-region>
          <div
            className="w-5 h-5 rounded flex items-center justify-center flex-shrink-0"
            style={{ background: "#1a0505" }}
          >
            <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="#ef4444" strokeWidth="2.5">
              <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3" />
            </svg>
          </div>
          <span className="text-[13px] font-semibold text-[#e8e8e8]" data-tauri-drag-region>
            Any Downloader
          </span>
        </div>
        <button
          onClick={() => invoke("hide_window")}
          className="w-6 h-6 rounded flex items-center justify-center text-[#444] hover:text-[#888] hover:bg-[#1a1a1a] transition-all duration-150"
        >
          <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      </div>

      {/* Scrollable content */}
      <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-3">

        {/* URL input */}
        <div className="flex gap-2">
          <div
            className="flex-1 flex items-center gap-2 px-3 rounded-lg border"
            style={{ background: "#0a0a0a", borderColor: "#1e1e1e", height: 36 }}
          >
            <svg className="w-3.5 h-3.5 text-[#333] flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M10 13a5 5 0 007.54.54l3-3a5 5 0 00-7.07-7.07l-1.72 1.71" />
              <path d="M14 11a5 5 0 00-7.54-.54l-3 3a5 5 0 007.07 7.07l1.71-1.71" />
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
              <button
                onClick={() => { setUrl(""); setResult(null); setProbeErr(""); }}
                className="text-[#333] hover:text-[#555] transition-colors"
              >
                <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <line x1="18" y1="6" x2="6" y2="18" /><line x1="6" y1="6" x2="18" y2="18" />
                </svg>
              </button>
            )}
          </div>
          <button
            onClick={handleProbe}
            disabled={!url.trim() || probing}
            className="px-3.5 rounded-lg text-[12px] font-medium transition-all disabled:opacity-40 disabled:cursor-not-allowed flex items-center gap-1.5 flex-shrink-0"
            style={{ background: "#ef4444", color: "white", height: 36 }}
          >
            {probing ? (
              <>
                <svg className="spin w-3.5 h-3.5" viewBox="0 0 24 24" fill="none">
                  <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="3" opacity=".2" />
                  <path fill="currentColor" d="M4 12a8 8 0 018-8v3a5 5 0 00-5 5H4z" />
                </svg>
                Fetching...
              </>
            ) : (
              <>
                <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" />
                </svg>
                Fetch
              </>
            )}
          </button>
        </div>

        {/* Error */}
        {probeErr && (
          <div
            className="px-3 py-2.5 rounded-lg border flex items-start gap-2 fade-in"
            style={{ background: "#1a0505", borderColor: "#ef444430" }}
          >
            <svg className="w-3.5 h-3.5 text-[#ef4444] flex-shrink-0 mt-0.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10" />
              <line x1="12" y1="8" x2="12" y2="12" />
              <line x1="12" y1="16" x2="12.01" y2="16" />
            </svg>
            <p className="text-[11px] text-[#ef4444] leading-relaxed">{probeErr}</p>
          </div>
        )}

        {/* Meta strip */}
        {result && (
          <div
            className="flex items-center gap-2.5 px-3 py-2 rounded-lg border fade-in"
            style={{ background: "#0a0a0a", borderColor: "#1a1a1a" }}
          >
            {result.thumbnail && (
              <img
                src={result.thumbnail} alt=""
                className="w-10 h-7 object-cover flex-shrink-0"
                style={{ borderRadius: 3 }}
              />
            )}
            <div className="flex-1 min-w-0">
              <p className="text-[12px] font-medium text-[#e8e8e8] truncate">{result.title}</p>
              <p className="text-[10px] text-[#444] mt-0.5">
                {fmtDur(result.duration)}
                {" · "}
                {result.audioLeft.length + result.audioRight.length} audio options
                {" · "}
                {result.video.length} resolutions
              </p>
            </div>
          </div>
        )}

        {/* Tabs */}
        {result && (
          <div className="flex items-center gap-4 border-b" style={{ borderColor: "#1a1a1a" }}>
            {(["audio", "video"] as const).map((t) => (
              <button
                key={t}
                onClick={() => setTab(t)}
                className="pb-2.5 text-[12px] font-medium transition-colors duration-150 relative capitalize"
                style={{ color: tab === t ? "#ef4444" : "#555" }}
              >
                {t}
                {tab === t && (
                  <div className="absolute bottom-0 left-0 right-0 h-0.5 rounded-full" style={{ background: "#ef4444" }} />
                )}
              </button>
            ))}
          </div>
        )}

        {/* Audio panel */}
        {result && tab === "audio" && (
          <div className="flex gap-3 fade-in">
            <div className="flex-1 flex flex-col gap-2">
              <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold">MP3</p>
              {result.audioLeft.length === 0 ? (
                <p className="text-[11px] text-[#333]">No MP3 options available</p>
              ) : (
                result.audioLeft.map((c) => (
                  <Card key={c.key} label={c.label} sub={c.sub} size={c.size} tag={c.tag}
                    dl={getDl(c.key)} onClick={() => handleDownload(c.key, c.args)} />
                ))
              )}
            </div>
            <div className="flex-1 flex flex-col gap-2">
              <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold">Lossless / Original</p>
              {result.audioRight.map((c) => (
                <Card key={c.key} label={c.label} sub={c.sub} size={c.size} tag={c.tag}
                  dl={getDl(c.key)} onClick={() => handleDownload(c.key, c.args)} />
              ))}
            </div>
          </div>
        )}

        {/* Video panel */}
        {result && tab === "video" && (
          <div className="flex flex-col gap-2 fade-in">
            <p className="text-[10px] uppercase tracking-wider text-[#333] font-semibold">Video · MP4</p>
            {result.video.length === 0 ? (
              <p className="text-[11px] text-[#333]">No video streams found</p>
            ) : (
              result.video.map((c) => (
                <Card key={c.key} label={c.label} sub={c.sub} size="—"
                  dl={getDl(c.key)} onClick={() => handleDownload(c.key, c.args)} />
              ))
            )}
          </div>
        )}

        {/* Empty state */}
        {!result && !probing && !probeErr && (
          <div className="flex flex-col items-center justify-center flex-1 gap-3 py-12">
            <div
              className="w-12 h-12 rounded-xl flex items-center justify-center"
              style={{ background: "#111", border: "1px solid #1e1e1e" }}
            >
              <svg className="w-6 h-6 text-[#2a2a2a]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
                <path d="M21 15v4a2 2 0 01-2 2H5a2 2 0 01-2-2v-4M7 10l5 5 5-5M12 15V3" />
              </svg>
            </div>
            <div className="text-center">
              <p className="text-[13px] text-[#555] font-medium">Paste a URL to get started</p>
              <p className="text-[11px] text-[#333] mt-1">YouTube, Instagram, Twitter, Reddit, and 1000+ more</p>
            </div>
          </div>
        )}
      </div>

      {/* Footer — output folder */}
      <div
        className="flex items-center gap-2 px-4 py-2.5 flex-shrink-0"
        style={{ borderTop: "1px solid #1a1a1a", background: "#0a0a0a" }}
      >
        <svg className="w-3 h-3 text-[#333] flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path d="M22 19a2 2 0 01-2 2H4a2 2 0 01-2-2V5a2 2 0 012-2h5l2 3h9a2 2 0 012 2z" />
        </svg>
        <span className="flex-1 text-[11px] text-[#444] truncate min-w-0">
          {outDir || "Default — Downloads folder"}
        </span>
        <button
          onClick={async () => {
            try {
              // Use showDirectoryPicker — no Tauri plugin needed, built into WebView2
              const handle = await (window as any).showDirectoryPicker({ mode: "readwrite" });
              setOutDir(handle.name);
            } catch {
              // User cancelled or not supported
            }
          }}
          className="text-[11px] text-[#444] hover:text-[#888] hover:bg-[#1a1a1a] px-2 py-1 rounded transition-all flex-shrink-0"
        >
          Browse
        </button>
        {outDir && (
          <button
            onClick={() => setOutDir("")}
            className="text-[11px] text-[#333] hover:text-[#555] transition-colors flex-shrink-0"
          >
            Reset
          </button>
        )}
      </div>
    </div>
  );
}
