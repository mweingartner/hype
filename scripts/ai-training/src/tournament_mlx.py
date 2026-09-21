#!/usr/bin/env python3
"""MLX-served variant of the multi-turn tournament.

Runs the SAME 127-prompt multi-turn tool-calling benchmark as
`tournament_multiturn.py`, but against a locally-cached MLX model
served by `mlx_lm`'s OpenAI-compatible HTTP server instead of Ollama.

This script does NOT reimplement the benchmark. It imports the prompt
construction, tool schema, grading, and multi-turn-loop *logic* from
`eval.py` and `tournament_multiturn.py` so the two harnesses stay
faithful to each other:

  - `eval.py` supplies: tool catalog loading, the authoring/script
    system prompts, the HypeTalkGuide injection, substring grading,
    and the pass-rate summarizer.
  - `tournament_multiturn.py` supplies: the STORAGE_TOOLS / *
    SIMULATED_RESULTS tables, the synthetic CURRENT STATE block, the
    turn cap, and the storage-call termination rule.
  - `tournament.py` supplies: per-category bucketing and the
    markdown leaderboard renderer.

The only new code here is the transport (`/v1/chat/completions`
instead of Ollama's `/api/chat`), MLX server process lifecycle
management, thinking/reasoning-mode toggling via
`chat_template_kwargs`, a stratified-subset fallback for models that
are too slow to run the full 127 prompts in the time budget, and
telemetry capture (latency, token counts, prompt-cache hits, peak
server memory).

Usage:
  python3 src/tournament_mlx.py --model-key qwen3_5-27b-4bit
  python3 src/tournament_mlx.py --model-key gpt-oss-120b-mxfp4 --subset-n 60
"""
from __future__ import annotations

import argparse
import json
import os
import re
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import (  # noqa: E402
    OUT_DIR,
    ROOT,
    hypetalk_guide_text,
    load_tools,
    normalize_chat_output,
    prompt_expects_tool_use,
    score_prompt,
    summarize,
    system_prompt_for,
)
from tournament import format_leaderboard, per_category  # noqa: E402
import tournament_multiturn as tm  # noqa: E402  -- reuse constants/helpers, not the Ollama transport

# Everything this harness writes lands in the git-ignored out/ directory.
SUMMARY_PATH = OUT_DIR / "mlx_tournament_SUMMARY.md"
LOG_DIR = OUT_DIR / "mlx_tournament_logs"

# ---------------------------------------------------------------------------
# Model catalog — local HF cache snapshots only. HF_HUB_OFFLINE=1 is set by
# main() before anything touches huggingface_hub so no weights are ever
# fetched over the network.
# ---------------------------------------------------------------------------
MODEL_CATALOG: dict[str, dict] = {
    "qwen3_5-27b-4bit": {
        "repo": "mlx-community/Qwen3.8-27B-4bit",
        "arch": "qwen3_5 (dense hybrid linear/full attention)",
        "tier": "32GB Mac candidate",
        "chat_template_kwargs": {"enable_thinking": False},
    },
    "nemotron-30b-a3b-4bit": {
        "repo": "mlx-community/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-4bit",
        "arch": "nemotron_h (hybrid MoE, Mamba2 + attention)",
        "tier": "32GB Mac candidate",
        "chat_template_kwargs": {"enable_thinking": False},
    },
    "qwen3-coder-next-4bit": {
        "repo": "mlx-community/Qwen3-Coder-Next-4bit",
        "arch": "qwen3_next (80B-A3B MoE)",
        "tier": "128GB Mac candidate",
        "chat_template_kwargs": {},  # non-thinking only
    },
    "gpt-oss-120b-mxfp4": {
        "repo": "mlx-community/gpt-oss-120b-MXFP4-Q4",
        "arch": "gpt_oss (MoE, Harmony tool-call format)",
        "tier": "128GB Mac candidate",
        "chat_template_kwargs": {"reasoning_effort": "low"},
    },
    # IBM's own MLX builds. The template speaks the same <function=…> XML
    # tool-call dialect as Qwen3-Coder and thinks unless told not to.
    "granite-4.2-30b-q4": {
        "repo": "ibm-granite/granite-4.2-30b-q4-mlx",
        "arch": "granite (dense 30B, full attention, 4-bit)",
        "tier": "128GB Mac candidate",
        "chat_template_kwargs": {"enable_thinking": False},
        "prompt_cache_bytes": 30 << 30,
    },
    "granite-4.2-30b-q8": {
        "repo": "ibm-granite/granite-4.2-30b-q8-mlx",
        "arch": "granite (dense 30B, full attention, 8-bit)",
        "tier": "128GB Mac candidate",
        "chat_template_kwargs": {"enable_thinking": False},
        "prompt_cache_bytes": 30 << 30,
    },
    "qwen3-coder-next-8bit": {
        "repo": "mlx-community/Qwen3-Coder-Next-8bit",
        "arch": "qwen3_next (80B-A3B MoE, 8-bit)",
        "tier": "128GB Mac candidate (E, only if time remains)",
        "chat_template_kwargs": {},
    },
}

THINK_RE = re.compile(r"<think>.*?</think>", re.DOTALL | re.IGNORECASE)


def _normalize_tool_call_arguments(tool_calls: list[dict]) -> list[dict]:
    """mlx_lm.server's OpenAI-compatible endpoint always JSON-encodes
    `function.arguments` as a STRING (per ToolCallFormatter._format in
    mlx_lm/server.py). Ollama's /api/chat returns it as an already-parsed
    DICT. `normalize_chat_output` (reused verbatim from eval.py) has a
    string branch that dumps that raw JSON text as-is, so any quoted
    HypeTalk literal in a must_contain check (e.g. `field "score"`) shows
    up in the graded text as the JSON-escaped `field \\"score\\"` and
    silently fails the substring match — deflating scores for reasons
    that have nothing to do with model quality. Parse back into a dict
    here so grading sees the same shape Ollama provides."""
    normalized = []
    for c in tool_calls:
        c = dict(c)
        func = dict(c.get("function") or {})
        args = func.get("arguments")
        if isinstance(args, str):
            try:
                func["arguments"] = json.loads(args)
            except json.JSONDecodeError:
                pass  # leave as string; normalize_chat_output falls back to raw text
        c["function"] = func
        normalized.append(c)
    return normalized


def _reencode_tool_calls_for_wire(tool_calls: list[dict]) -> list[dict]:
    """Inverse of `_normalize_tool_call_arguments`: mlx_lm.server's
    `process_message_content()` calls `json.loads(func['arguments'])` on
    inbound conversation history before handing it to the chat template,
    so re-serialize dict arguments back to a JSON string before sending
    an assistant turn back as history."""
    reencoded = []
    for c in tool_calls:
        c = dict(c)
        func = dict(c.get("function") or {})
        args = func.get("arguments")
        if isinstance(args, dict):
            func["arguments"] = json.dumps(args, ensure_ascii=False)
        c["function"] = func
        reencoded.append(c)
    return reencoded


def resolve_snapshot(repo_id: str) -> Path:
    cache_dir = Path.home() / ".cache" / "huggingface" / "hub"
    dirname = "models--" + repo_id.replace("/", "--")
    snap_dir = cache_dir / dirname / "snapshots"
    if not snap_dir.exists():
        raise SystemExit(f"No local snapshot cache dir for {repo_id}: {snap_dir}")
    candidates = sorted(p for p in snap_dir.iterdir() if p.is_dir())
    if not candidates:
        raise SystemExit(f"No snapshot found for {repo_id} under {snap_dir}")
    return candidates[-1]


def find_free_port(preferred: int = 8811) -> int:
    import socket

    for port in [preferred] + list(range(8812, 8850)):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("127.0.0.1", port))
                return port
            except OSError:
                continue
    raise SystemExit("Could not find a free localhost port")


STRAY_THINK_CLOSE_RE = re.compile(r"</think>", re.IGNORECASE)
STRAY_THINK_OPEN_RE = re.compile(r"<think>", re.IGNORECASE)


def strip_think(text: str | None) -> tuple[str, bool]:
    """Strip <think>...</think> blocks before grading. Some models (observed
    with Nemotron even with enable_thinking:false) leak a bare `</think>`
    with no matching opening tag — e.g. a short pre-tool-call narration that
    the model terminates with a closing think tag out of habit even though
    the chat template already primed an empty `<think></think>` pair. Catch
    that case too so telemetry's had_think_leak reflects it, even though it
    doesn't materially change grading (the stray tag is inert text)."""
    if not text:
        return (text or ""), False
    lower = text.lower()
    if "<think" not in lower and "</think>" not in lower:
        return text, False
    cleaned = THINK_RE.sub("", text)
    cleaned = STRAY_THINK_CLOSE_RE.sub("", cleaned)
    cleaned = STRAY_THINK_OPEN_RE.sub("", cleaned)
    return cleaned, cleaned != text


# ---------------------------------------------------------------------------
# Server lifecycle
# ---------------------------------------------------------------------------
class MlxServer:
    def __init__(
        self,
        model_path: Path,
        port: int,
        host: str = "127.0.0.1",
        temperature: float = 0.2,
        top_p: float = 0.9,
        max_tokens: int = 512,
        log_path: Path | None = None,
        prompt_cache_bytes: int | None = None,
    ):
        self.prompt_cache_bytes = prompt_cache_bytes
        self.model_path = model_path
        self.port = port
        self.host = host
        self.temperature = temperature
        self.top_p = top_p
        self.max_tokens = max_tokens
        self.log_path = log_path
        self.proc: subprocess.Popen | None = None
        self._logfile = None

    @property
    def base_url(self) -> str:
        return f"http://{self.host}:{self.port}"

    def start(self, load_timeout_s: float = 1800.0) -> None:
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self._logfile = open(self.log_path, "w")
        cmd = [
            sys.executable, "-m", "mlx_lm", "server",
            "--model", str(self.model_path),
            "--host", self.host,
            "--port", str(self.port),
            "--temp", str(self.temperature),
            "--top-p", str(self.top_p),
            "--max-tokens", str(self.max_tokens),
            "--log-level", "INFO",
        ]
        if self.prompt_cache_bytes:
            # mlx_lm.server keeps a full KV cache per cached conversation (default:
            # 10 of them). A dense model's ~46K-token authoring prompt costs ~12 GB
            # each, which swaps a 128 GB Mac; bound it by bytes instead.
            cmd += ["--prompt-cache-bytes", str(self.prompt_cache_bytes)]
        env = dict(os.environ)
        env["HF_HUB_OFFLINE"] = "1"
        print(f"[server] launching: {' '.join(cmd)}", flush=True)
        print(f"[server] log: {self.log_path}", flush=True)
        self.proc = subprocess.Popen(
            cmd, stdout=self._logfile, stderr=subprocess.STDOUT, env=env,
        )
        deadline = time.monotonic() + load_timeout_s
        url = f"{self.base_url}/health"
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise SystemExit(
                    f"mlx_lm server exited early (code {self.proc.returncode}). "
                    f"See {self.log_path}"
                )
            try:
                with urllib.request.urlopen(url, timeout=3) as resp:
                    if resp.status == 200:
                        print(f"[server] healthy after "
                              f"{load_timeout_s - (deadline - time.monotonic()):.1f}s",
                              flush=True)
                        return
            except (urllib.error.URLError, ConnectionError, TimeoutError):
                pass
            time.sleep(2)
        raise SystemExit(f"mlx_lm server did not become healthy within {load_timeout_s}s")

    def stop(self) -> None:
        if self.proc is None:
            return
        if self.proc.poll() is None:
            print("[server] terminating...", flush=True)
            self.proc.terminate()
            try:
                self.proc.wait(timeout=20)
            except subprocess.TimeoutExpired:
                print("[server] force-killing...", flush=True)
                self.proc.kill()
                self.proc.wait(timeout=10)
        if self._logfile:
            self._logfile.close()
        self.proc = None


class MemSampler:
    """Samples RSS of the server PID periodically. Falls back silently if
    `ps` is unavailable. `footprint` is more accurate for Metal/unified
    memory on macOS but usually needs elevated privileges, so it's tried
    once opportunistically and otherwise skipped."""

    def __init__(self, pid: int, interval_s: float = 5.0):
        self.pid = pid
        self.interval_s = interval_s
        self.samples: list[tuple[float, float]] = []  # (t, rss_mb)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self.method = "ps_rss"

    def _rss_mb(self) -> float | None:
        try:
            out = subprocess.run(
                ["ps", "-o", "rss=", "-p", str(self.pid)],
                capture_output=True, text=True, timeout=5,
            )
            val = out.stdout.strip()
            if not val:
                return None
            return int(val) / 1024.0
        except Exception:
            return None

    def _run(self) -> None:
        t0 = time.monotonic()
        while not self._stop.is_set():
            mb = self._rss_mb()
            if mb is not None:
                self.samples.append((round(time.monotonic() - t0, 1), round(mb, 1)))
            self._stop.wait(self.interval_s)

    def start(self) -> None:
        self._thread.start()

    def stop(self) -> dict:
        self._stop.set()
        self._thread.join(timeout=5)
        peak = max((mb for _, mb in self.samples), default=None)
        return {
            "method": self.method,
            "samples_n": len(self.samples),
            "peak_rss_mb": peak,
            "mean_rss_mb": round(statistics.mean(mb for _, mb in self.samples), 1)
            if self.samples else None,
        }


# ---------------------------------------------------------------------------
# HTTP client for mlx_lm.server's /v1/chat/completions
# ---------------------------------------------------------------------------
def mlx_chat(
    base_url: str,
    messages: list[dict],
    *,
    tools: list[dict] | None,
    temperature: float,
    top_p: float,
    max_tokens: int,
    chat_template_kwargs: dict,
    timeout_s: float,
) -> tuple[dict, dict]:
    """POST /v1/chat/completions. Returns (message_dict, telemetry_dict).

    `message_dict` mirrors what `tournament_multiturn.py` expects from
    Ollama's `/api/chat`: {"content": str, "tool_calls": [...]}. mlx_lm's
    tool_calls already carry OpenAI-shaped
    {"function": {"name", "arguments": "<json string>"}, "type", "id"} —
    passing that list straight back as an assistant turn's `tool_calls` on
    the next request round-trips correctly because mlx_lm.server's own
    `process_message_content()` does `json.loads()` on `arguments` before
    handing messages to the Jinja chat template.
    """
    payload = {
        # "default_model" (not a real repo id) routes to the single model
        # ModelProvider preloaded from --model at server startup — see
        # ModelProvider.load()'s default_model_map handling in mlx_lm/server.py.
        "model": "default_model",
        "messages": messages,
        "temperature": temperature,
        "top_p": top_p,
        "max_tokens": max_tokens,
        "stream": False,
    }
    if tools:
        payload["tools"] = tools
    if chat_template_kwargs:
        payload["chat_template_kwargs"] = chat_template_kwargs

    body = json.dumps(payload).encode()
    start = time.monotonic()
    telemetry: dict = {"elapsed_s": None, "error": None}
    # Observed on qwen3_5-27b-4bit's full run: mlx_lm.server occasionally
    # drops the connection ("Remote end closed connection without
    # response") under sustained sequential load with no HTTP error code —
    # a transport hiccup, not a model-quality signal. One retry after a
    # short backoff resolves it without materially affecting latency
    # telemetry for the (common) non-retried case.
    last_exc: Exception | None = None
    for attempt in range(2):
        req = urllib.request.Request(
            f"{base_url}/v1/chat/completions",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            # nosemgrep: python.lang.security.audit.insecure-transport.urllib.insecure-request-object.insecure-request-object -- loopback-only mlx_lm server (http://127.0.0.1); TLS is not applicable over loopback.
            with urllib.request.urlopen(req, timeout=timeout_s) as resp:
                raw = json.loads(resp.read().decode())
            last_exc = None
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:500]
            telemetry["elapsed_s"] = round(time.monotonic() - start, 2)
            telemetry["error"] = f"HTTP {e.code}: {detail}"
            return {"content": f"<mlx HTTP error {e.code}: {detail}>", "tool_calls": []}, telemetry
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            last_exc = e
            if attempt == 0:
                telemetry["retried"] = True
                time.sleep(1.5)
                continue
    if last_exc is not None:
        telemetry["elapsed_s"] = round(time.monotonic() - start, 2)
        telemetry["error"] = str(last_exc)
        return {"content": f"<mlx request error: {last_exc}>", "tool_calls": []}, telemetry

    telemetry["elapsed_s"] = round(time.monotonic() - start, 2)
    choice = (raw.get("choices") or [{}])[0]
    message = choice.get("message") or {}
    usage = raw.get("usage") or {}
    telemetry["prompt_tokens"] = usage.get("prompt_tokens")
    telemetry["completion_tokens"] = usage.get("completion_tokens")
    cached = (usage.get("prompt_tokens_details") or {}).get("cached_tokens")
    telemetry["cached_tokens"] = cached
    telemetry["finish_reason"] = choice.get("finish_reason")

    content, had_think = strip_think(message.get("content"))
    telemetry["had_think_leak"] = had_think
    return {
        "content": content,
        "tool_calls": _normalize_tool_call_arguments(message.get("tool_calls") or []),
    }, telemetry


# ---------------------------------------------------------------------------
# Multi-turn loop — mirrors tournament_multiturn.evaluate_model_multiturn,
# reusing its constants/helpers, swapping the Ollama transport for mlx_chat
# and adding per-request telemetry with prompt/turn attribution.
# ---------------------------------------------------------------------------
def evaluate_model_multiturn_mlx(
    base_url: str,
    prompts: list[dict],
    tools: list[dict],
    known_tool_names: set[str],
    guide: str,
    *,
    chat_template_kwargs: dict,
    temperature: float,
    top_p: float,
    max_tokens: int,
    request_timeout_s: float,
    telemetry_log: list[dict],
) -> list[dict]:
    results: list[dict] = []
    for i, row in enumerate(prompts, 1):
        start = time.monotonic()
        use_tools = prompt_expects_tool_use(row, known_tool_names)
        mode = "tool" if use_tools else "script"

        messages = [
            {"role": "system", "content": tm._augment_system(
                system_prompt_for("mlx", mode, guide)
            )},
            {"role": "user", "content": row["prompt"]},
        ]

        all_outputs: list[str] = []
        turns_taken = 0
        terminated_by = "no_tool_calls"

        for turn in range(tm.MAX_TURNS):
            turns_taken = turn + 1
            message, req_telemetry = mlx_chat(
                base_url, messages,
                tools=tools if use_tools else None,
                temperature=temperature, top_p=top_p, max_tokens=max_tokens,
                chat_template_kwargs=chat_template_kwargs,
                timeout_s=request_timeout_s,
            )
            req_telemetry.update({"prompt_id": row["id"], "turn": turn + 1, "mode": mode})
            telemetry_log.append(req_telemetry)

            all_outputs.append(normalize_chat_output(message))
            calls = tm._tool_calls_of(message)
            if not calls:
                terminated_by = "no_tool_calls"
                break
            if tm._has_storage_call(message):
                terminated_by = "storage_call"
                break
            assistant_msg = {
                "role": "assistant",
                "content": message.get("content") or "",
                # calls has dict-form arguments (normalized for grading);
                # re-encode to JSON-string form before it goes back on the
                # wire, matching what mlx_lm.server's process_message_content
                # expects to json.loads() out of inbound history.
                "tool_calls": _reencode_tool_calls_for_wire(calls),
            }
            messages.append(assistant_msg)
            for c in calls:
                tool_name = (c.get("function") or {}).get("name") or ""
                tool_call_id = c.get("id") or f"call_{turn}_{tool_name}"
                fake_result = tm.SIMULATED_RESULTS.get(tool_name, "OK")
                messages.append({
                    "role": "tool",
                    "tool_call_id": tool_call_id,
                    "name": tool_name,
                    "content": fake_result,
                })
        else:
            terminated_by = "turn_cap"

        merged_output = "\n---\n".join(all_outputs)
        elapsed = time.monotonic() - start
        score = score_prompt(row, merged_output)
        score["elapsed_s"] = round(elapsed, 2)
        score["output"] = merged_output
        score["mode"] = mode
        score["turns"] = turns_taken
        score["terminated_by"] = terminated_by
        results.append(score)
        mark = "PASS" if score["passed"] else "FAIL"
        print(
            f"  [{i}/{len(prompts)}] {mark}  {row['id']}  "
            f"[{score['mode']}, {turns_taken}t/{terminated_by}] "
            f"({elapsed:.1f}s)",
            flush=True,
        )
    return results


# ---------------------------------------------------------------------------
# Stratified subset selection — proportional per category, fixed seed, so
# the SAME subset is used for every model when the full 127 is too slow.
# ---------------------------------------------------------------------------
def stratified_subset(prompts: list[dict], n: int, seed: int) -> list[dict]:
    import random
    from collections import defaultdict

    if n >= len(prompts):
        return list(prompts)

    by_cat: dict[str, list[dict]] = defaultdict(list)
    for p in prompts:
        by_cat[p.get("category", "uncategorized")].append(p)

    total = len(prompts)
    raw = {c: len(v) * n / total for c, v in by_cat.items()}
    base = {c: int(raw[c]) for c in raw}
    remainder = n - sum(base.values())
    for c, _ in sorted(raw.items(), key=lambda kv: kv[1] - int(kv[1]), reverse=True):
        if remainder <= 0:
            break
        base[c] += 1
        remainder -= 1

    rng = random.Random(seed)
    selected_ids: set[str] = set()
    for c, plist in by_cat.items():
        k = min(base.get(c, 0), len(plist))
        selected_ids.update(p["id"] for p in rng.sample(plist, k))

    return [p for p in prompts if p["id"] in selected_ids]


# ---------------------------------------------------------------------------
# Failure-signature classification for the summary report
# ---------------------------------------------------------------------------
# NOTE: "let " and "var " double as ordinary English ("let me...", "let's...",
# "var"-as-in-variable-discussion is rarer but "let me"/"let's" is common).
# A prompt's must_not_contain check is a dumb substring match, so a model
# that prefaces its tool call with "Let me validate the script first." trips
# the same forbidden-token check as one that emitted real `let x = 1;`
# JS. Both count as a real FAIL under the shared grading logic (unchanged,
# for comparability with the Ollama baseline harness), but conflating them
# under one "js_flavored_hypetalk" tag would misrepresent how often models
# actually leak JS syntax vs. just talk like a chatbot. Distinguish them.
JS_TOKENS = ("function ", "let ", "const ", "=>", "console.log", "self.",
             "document.", "addEventListener", "var ", "innerHTML", "alert(")
_NL_PREAMBLE_TOKENS = ("let ", "var ")
_NL_PREAMBLE_CONTEXTS = ("let me", "let's", "lets ", "variable", "various")


def _forbidden_hit_is_nl_preamble(token: str, output_lower: str) -> bool:
    if token not in _NL_PREAMBLE_TOKENS:
        return False
    idxs = [m.start() for m in re.finditer(re.escape(token), output_lower)]
    if not idxs:
        return False
    return all(
        output_lower[i: i + 10].startswith(_NL_PREAMBLE_CONTEXTS)
        for i in idxs
    )


def classify_failure(row: dict, score: dict) -> list[str]:
    tags: list[str] = []
    missing = score.get("missing_required") or []
    forbidden = score.get("present_forbidden") or []
    output = (score.get("output") or "").lower()

    if score.get("terminated_by") == "turn_cap":
        tags.append("turn_cap_exhausted")

    # Only classify JS-leakage off the substrings that actually TRIGGERED
    # the forbidden-content grading (not a fresh re-scan of the whole
    # output for any JS-looking token, which over-tags unrelated failures).
    real_js_hits = [f for f in forbidden if not _forbidden_hit_is_nl_preamble(f.lower(), output)]
    nl_preamble_hits = [f for f in forbidden if _forbidden_hit_is_nl_preamble(f.lower(), output)]
    if real_js_hits:
        tags.append("js_flavored_hypetalk")
    elif nl_preamble_hits:
        tags.append("nl_preamble_false_positive")

    if any("name=" in m or m == "name" for m in missing):
        tags.append("missing_name_arg")
    known_storage = tm.STORAGE_TOOLS
    wanted_tools = [m for m in missing if m in known_storage or "create_" in m or "set_" in m]
    if wanted_tools and any(t + "(" in output for t in known_storage if t not in wanted_tools):
        tags.append("wrong_tool_called")
    if "<tool_call" in output or "<function=" in output or "functions." in output and "channel" in output:
        tags.append("malformed_or_leaked_tool_syntax")
    if not tags and missing:
        tags.append("missing_required_content")
    if not tags and forbidden:
        tags.append("forbidden_content_present")
    if not tags:
        tags.append("other")
    return tags


# ---------------------------------------------------------------------------
# Latency probe / time-budget decision
# ---------------------------------------------------------------------------
def run_streaming_ttft_probe(
    base_url: str, messages: list[dict], tools: list[dict] | None,
    chat_template_kwargs: dict, temperature: float, top_p: float, max_tokens: int,
    timeout_s: float,
) -> dict:
    """One streaming request purely to measure time-to-first-token and a
    decode-only tokens/sec figure, separate from the bulk non-streaming run
    (which is simpler/more robust for tool-call parsing)."""
    payload = {
        "model": "default_model",
        "messages": messages,
        "temperature": temperature,
        "top_p": top_p,
        "max_tokens": max_tokens,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    if tools:
        payload["tools"] = tools
    if chat_template_kwargs:
        payload["chat_template_kwargs"] = chat_template_kwargs
    body = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"{base_url}/v1/chat/completions", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    start = time.monotonic()
    ttft = None
    n_chunks = 0
    usage = {}
    try:
        # nosemgrep: python.lang.security.audit.insecure-transport.urllib.insecure-request-object.insecure-request-object -- loopback-only mlx_lm server.
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            for line in resp:
                line = line.decode(errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[len("data:"):].strip()
                if data == "[DONE]":
                    break
                if ttft is None:
                    ttft = time.monotonic() - start
                n_chunks += 1
                try:
                    obj = json.loads(data)
                    if obj.get("usage"):
                        usage = obj["usage"]
                except json.JSONDecodeError:
                    pass
    except Exception as e:  # noqa: BLE001 -- best-effort probe, never fatal
        return {"error": str(e)}
    total = time.monotonic() - start
    completion_tokens = usage.get("completion_tokens")
    decode_tps = None
    # Guard against a near-zero denominator: the server can flush several
    # generated tokens in a single SSE chunk (it emits on every
    # normal/reasoning state transition, not strictly one token per event),
    # so a fast, fully-cached request can arrive as 1-2 chunks with
    # (total - ttft) ~= 0, which would blow up the division.
    if completion_tokens and ttft is not None and (total - ttft) > 0.1 and n_chunks >= 3:
        decode_tps = round(completion_tokens / (total - ttft), 1)
    return {
        "ttft_s": round(ttft, 3) if ttft is not None else None,
        "total_s": round(total, 3),
        "stream_chunks": n_chunks,
        "prompt_tokens": usage.get("prompt_tokens"),
        "completion_tokens": completion_tokens,
        "cached_tokens": (usage.get("prompt_tokens_details") or {}).get("cached_tokens"),
        "decode_tokens_per_s": decode_tps,
    }


# ---------------------------------------------------------------------------
# Report writers
# ---------------------------------------------------------------------------
def write_model_report(
    *, label: str, model_meta: dict, prompts_file: str, prompt_set_desc: str,
    results: list[dict], prompts_used: list[dict], telemetry: list[dict],
    ttft_probe: dict, mem_stats: dict, started_at: str, finished_at: str,
    elapsed_total_s: float, out_dir: Path,
) -> tuple[Path, Path]:
    s = summarize(results)
    cat = per_category(results, prompts_used)
    per_prompt_pass = {r["id"]: r["passed"] for r in results}

    prompts_by_id = {p["id"]: p for p in prompts_used}
    failures = []
    for r in results:
        if r["passed"]:
            continue
        row = prompts_by_id.get(r["id"], {})
        failures.append({
            "id": r["id"],
            "category": row.get("category"),
            "missing_required": r.get("missing_required"),
            "present_forbidden": r.get("present_forbidden"),
            "terminated_by": r.get("terminated_by"),
            "tags": classify_failure(row, r),
            "output_excerpt": (r.get("output") or "")[:400],
        })

    lat = [t["elapsed_s"] for t in telemetry if t.get("elapsed_s") is not None]
    errored = [t for t in telemetry if t.get("error")]
    cached_ratios = [
        (t["cached_tokens"] / t["prompt_tokens"])
        for t in telemetry
        if t.get("cached_tokens") not in (None, 0) and t.get("prompt_tokens")
    ]
    # Scan the FULL telemetry (not just the truncated sample persisted below)
    # for think-tag leakage so the quirk count in SUMMARY.md is accurate.
    think_leak_requests = sum(1 for t in telemetry if t.get("had_think_leak"))

    report = {
        "model_label": label,
        "model_meta": model_meta,
        "prompts_file": prompts_file,
        "prompt_set": prompt_set_desc,
        "prompts_count": len(prompts_used),
        "guide_injected_for_untuned": True,
        "harness": f"mlx multi-turn (synthesized tool results, max {tm.MAX_TURNS} turns) via mlx_lm OpenAI server",
        "started_at": started_at,
        "finished_at": finished_at,
        "ttft_probe": ttft_probe,
        "memory": mem_stats,
        "request_latency_s": {
            "n_requests": len(lat),
            "mean": round(statistics.mean(lat), 2) if lat else None,
            "p50": round(statistics.median(lat), 2) if lat else None,
            "p90": round(sorted(lat)[int(len(lat) * 0.9)], 2) if lat else None,
            "max": round(max(lat), 2) if lat else None,
            "errors": len(errored),
        },
        "prefix_cache": {
            "requests_with_cache_info": len(cached_ratios),
            "mean_cached_fraction": round(statistics.mean(cached_ratios), 3) if cached_ratios else None,
            "note": (
                "fraction of prompt_tokens served from mlx_lm's LRU KV cache "
                "(usage.prompt_tokens_details.cached_tokens / prompt_tokens), "
                "averaged over requests where mlx_lm reported it"
            ),
        },
        "failure_tag_counts": _tally_tags(failures),
        "think_leak": {
            "requests_with_leak": think_leak_requests,
            "requests_total": len(telemetry),
            "fraction": round(think_leak_requests / len(telemetry), 3) if telemetry else None,
        },
        "per_model": [{
            "model": label,
            "summary": s,
            "per_category": cat,
            "per_prompt_pass": per_prompt_pass,
            "results": results,
            "elapsed_total_s": round(elapsed_total_s, 2),
        }],
        "failures": failures,
        "raw_telemetry_sample": telemetry[:20],
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    json_path = out_dir / f"mlx_tournament_{label}.json"
    md_path = out_dir / f"mlx_tournament_{label}.md"
    json_path.write_text(json.dumps(report, indent=2))
    md = format_leaderboard({
        "prompts_file": prompts_file,
        "prompts_count": len(prompts_used),
        "per_model": report["per_model"],
    })
    md += "\n\n## MLX run metadata\n\n"
    md += f"- Prompt set: {prompt_set_desc}\n"
    md += f"- Architecture: {model_meta.get('arch')}\n"
    md += f"- Tier: {model_meta.get('tier')}\n"
    md += f"- chat_template_kwargs: `{model_meta.get('chat_template_kwargs')}`\n"
    md += f"- Mean request latency: {report['request_latency_s']['mean']}s " \
          f"(p90 {report['request_latency_s']['p90']}s, {report['request_latency_s']['n_requests']} requests, " \
          f"{report['request_latency_s']['errors']} errors)\n"
    md += f"- TTFT probe: {ttft_probe}\n"
    md += f"- Peak server RSS: {mem_stats.get('peak_rss_mb')} MB ({mem_stats.get('method')})\n"
    md += f"- Mean prefix-cache hit fraction: {report['prefix_cache']['mean_cached_fraction']}\n"
    md += f"- Think-tag leakage: {report['think_leak']['requests_with_leak']}/{report['think_leak']['requests_total']} requests\n"
    md += "\n## Failure tags\n\n"
    for tag, n in sorted(report["failure_tag_counts"].items(), key=lambda kv: -kv[1]):
        md += f"- `{tag}`: {n}\n"
    md_path.write_text(md)
    return json_path, md_path


def _tally_tags(failures: list[dict]) -> dict[str, int]:
    out: dict[str, int] = {}
    for f in failures:
        for t in f["tags"]:
            out[t] = out.get(t, 0) + 1
    return out


def update_global_summary(out_dir: Path, summary_path: Path) -> None:
    reports = sorted(out_dir.glob("mlx_tournament_*.json"))
    if not reports:
        return
    entries = []
    for p in reports:
        try:
            entries.append(json.loads(p.read_text()))
        except Exception:  # noqa: BLE001
            continue

    lines: list[str] = []
    lines.append("# MLX Model Tournament — Summary\n")
    lines.append(f"_Updated: {time.strftime('%Y-%m-%d %H:%M:%S')}_\n")
    lines.append(
        "Reference (Ollama, full 127 prompts, from "
        "`scripts/ai-training/TOURNAMENT_127_RESULTS.md`): "
        "`granite4.1:30b` 98.4%, `qwen3.6:35b` 88.2%, `granite4.1:8b` 54.3%.\n"
    )

    lines.append("## Leaderboard (overall)\n")
    lines.append("| Model | Pass rate | Prompt set | Mean latency | p90 | Peak RSS | Arch |")
    lines.append("|---|---|---|---|---|---|---|")
    rows = []
    for e in entries:
        pm = e["per_model"][0]
        rows.append((e, pm))
    rows.sort(key=lambda ep: -ep[1]["summary"]["pass_rate"])
    for e, pm in rows:
        s = pm["summary"]
        lat = e.get("request_latency_s", {})
        mem = e.get("memory", {})
        lines.append(
            f"| `{e['model_label']}` | {s['pass_rate']:.1%} ({s['passed']}/{s['total']}) "
            f"| {e.get('prompt_set', '?')} "
            f"| {lat.get('mean')}s | {lat.get('p90')}s "
            f"| {mem.get('peak_rss_mb')} MB | {e.get('model_meta', {}).get('arch', '?')} |"
        )

    lines.append("\n## Per-category pass rates\n")
    cats = sorted({c for e, _ in rows for c in e["per_model"][0]["per_category"]})
    lines.append("| Model | " + " | ".join(cats) + " |")
    lines.append("|---|" + "|".join("---" for _ in cats) + "|")
    for e, pm in rows:
        cells = []
        for c in cats:
            entry = pm["per_category"].get(c, {})
            cells.append(f"{entry['pass_rate']:.0%} ({entry['passed']}/{entry['total']})" if entry else "—")
        lines.append(f"| `{e['model_label']}` | " + " | ".join(cells) + " |")

    lines.append("\n## Latency / memory / prefix-cache\n")
    lines.append("| Model | Mean req (s) | p90 (s) | Max (s) | Errors | TTFT probe (s) | Decode tok/s (probe) | Peak RSS (MB) | Mean cached-prefix fraction |")
    lines.append("|---|---|---|---|---|---|---|---|---|")
    for e, pm in rows:
        lat = e.get("request_latency_s", {})
        ttft = e.get("ttft_probe", {}) or {}
        mem = e.get("memory", {})
        pc = e.get("prefix_cache", {})
        lines.append(
            f"| `{e['model_label']}` | {lat.get('mean')} | {lat.get('p90')} | {lat.get('max')} "
            f"| {lat.get('errors')} | {ttft.get('ttft_s')} | {ttft.get('decode_tokens_per_s')} "
            f"| {mem.get('peak_rss_mb')} | {pc.get('mean_cached_fraction')} |"
        )

    lines.append("\n## Failure signatures per model\n")
    for e, pm in rows:
        lines.append(f"\n### `{e['model_label']}`\n")
        tags = e.get("failure_tag_counts", {})
        if not tags:
            lines.append("- No failures.\n")
            continue
        for tag, n in sorted(tags.items(), key=lambda kv: -kv[1]):
            lines.append(f"- `{tag}`: {n}")
        lines.append("")
        lines.append("Example failures:")
        for f in e.get("failures", [])[:5]:
            lines.append(
                f"- `{f['id']}` ({f['category']}, tags={f['tags']}): "
                f"missing={f['missing_required']} forbidden={f['present_forbidden']} "
                f"terminated_by={f['terminated_by']}"
            )

    lines.append("\n## Tool-call formatting quirks observed\n")
    for e, pm in rows:
        quirks = []
        if e.get("request_latency_s", {}).get("errors"):
            quirks.append(f"{e['request_latency_s']['errors']} request-level HTTP/timeout errors")
        tl = e.get("think_leak") or {}
        if tl.get("requests_with_leak"):
            quirks.append(
                f"<think>/</think> leaked into content on "
                f"{tl['requests_with_leak']}/{tl['requests_total']} requests "
                f"({tl.get('fraction', 0):.0%})"
            )
        if e["model_meta"].get("arch", "").startswith("gpt_oss"):
            quirks.append(
                "gpt-oss uses the Harmony channel format "
                "(`<|channel|>commentary<|message|>functions.NAME...`); mlx_lm's "
                "_infer_tool_parser() does not recognize this template so "
                "has_tool_calling is False and no structured tool_calls are ever "
                "parsed out of the raw generation (matches mlx-lm issue #875)."
            )
        lines.append(f"- `{e['model_label']}`: " + ("; ".join(quirks) if quirks else "none observed"))

    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text("\n".join(lines) + "\n")
    print(f"[summary] wrote {summary_path}", flush=True)


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-key", required=True, choices=sorted(MODEL_CATALOG))
    parser.add_argument("--prompts", default=str(ROOT / "eval" / "comprehensive_prompts.jsonl"))
    parser.add_argument("--out-dir", default=str(OUT_DIR))
    parser.add_argument("--summary-path", default=str(SUMMARY_PATH))
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=0, help="0 = auto-pick a free port")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--top-p", type=float, default=0.9)
    parser.add_argument("--max-tokens", type=int, default=512)
    parser.add_argument("--request-timeout-s", type=float, default=300.0)
    parser.add_argument("--server-load-timeout-s", type=float, default=1800.0)
    parser.add_argument("--latency-probe-n", type=int, default=5)
    parser.add_argument("--time-budget-min", type=float, default=60.0,
                         help="If projected full-127 wall clock exceeds this, fall back to the stratified subset")
    parser.add_argument("--subset-n", type=int, default=60)
    parser.add_argument("--subset-seed", type=int, default=1234)
    parser.add_argument("--force-subset", action="store_true",
                         help="Skip the projection and always use the stratified subset")
    parser.add_argument("--force-full", action="store_true",
                         help="Skip the projection and always use all prompts")
    parser.add_argument("--mem-sample-interval-s", type=float, default=5.0)
    parser.add_argument("--limit", type=int, default=0, help="Debug: cap prompt count after set selection")
    parser.add_argument("--skip-summary", action="store_true")
    args = parser.parse_args()

    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ.setdefault("HF_HUB_DISABLE_TELEMETRY", "1")

    profile = MODEL_CATALOG[args.model_key]
    model_path = resolve_snapshot(profile["repo"])
    print(f"[model] {args.model_key} -> {model_path}", flush=True)

    all_prompts = [
        json.loads(line) for line in Path(args.prompts).read_text().splitlines() if line.strip()
    ]
    tools = load_tools()
    known_tool_names = {t["function"]["name"] for t in tools}
    guide = hypetalk_guide_text()

    port = args.port or find_free_port()
    server = MlxServer(
        model_path=model_path, port=port, host=args.host,
        temperature=args.temperature, top_p=args.top_p, max_tokens=args.max_tokens,
        log_path=LOG_DIR / f"{args.model_key}_server.log",
        prompt_cache_bytes=profile.get("prompt_cache_bytes"),
    )

    telemetry: list[dict] = []
    mem_sampler: MemSampler | None = None
    started_at = time.strftime("%Y-%m-%d %H:%M:%S")
    t_start = time.monotonic()

    try:
        server.start(load_timeout_s=args.server_load_timeout_s)
        mem_sampler = MemSampler(server.proc.pid, interval_s=args.mem_sample_interval_s)
        mem_sampler.start()

        ctk = profile["chat_template_kwargs"]

        # --- Latency probe -------------------------------------------------
        probe_prompts = all_prompts[: args.latency_probe_n]
        print(f"\n[probe] running {len(probe_prompts)}-prompt latency probe...", flush=True)
        probe_telemetry: list[dict] = []
        t_probe = time.monotonic()
        evaluate_model_multiturn_mlx(
            server.base_url, probe_prompts, tools, known_tool_names, guide,
            chat_template_kwargs=ctk, temperature=args.temperature, top_p=args.top_p,
            max_tokens=args.max_tokens, request_timeout_s=args.request_timeout_s,
            telemetry_log=probe_telemetry,
        )
        probe_elapsed = time.monotonic() - t_probe
        mean_per_prompt = probe_elapsed / max(1, len(probe_prompts))
        # The very first request of the whole run pays a one-time cold-cache
        # prefill cost (the ~20-60k token system prompt + tool schema isn't
        # in mlx_lm's LRU prompt cache yet). Every request after that reuses
        # the cached prefix and is dramatically faster. A naive mean over
        # the probe (which includes that cold request) wildly overestimates
        # the full-run projection, so: pull the one-time cost out, project
        # the rest from the warm per-REQUEST latency (multi-turn prompts
        # issue >1 request), and add the cold cost back once.
        req_lat = [t["elapsed_s"] for t in probe_telemetry if t.get("elapsed_s") is not None]
        cold_cost = req_lat[0] if req_lat else 0.0
        warm_lat = req_lat[1:] if len(req_lat) > 1 else req_lat
        mean_warm_req_s = statistics.mean(warm_lat) if warm_lat else cold_cost
        avg_requests_per_prompt = len(req_lat) / max(1, len(probe_prompts))
        projected_full_min = (
            cold_cost + mean_warm_req_s * avg_requests_per_prompt * (len(all_prompts) - 1)
        ) / 60.0
        print(f"[probe] {probe_elapsed:.1f}s for {len(probe_prompts)} prompts "
              f"({mean_per_prompt:.1f}s/prompt naive mean; cold first request "
              f"{cold_cost:.1f}s, warm mean {mean_warm_req_s:.1f}s/request, "
              f"{avg_requests_per_prompt:.1f} requests/prompt) "
              f"-> projected full-127: {projected_full_min:.1f} min",
              flush=True)
        think_leaks = sum(1 for t in probe_telemetry if t.get("had_think_leak"))
        if think_leaks:
            print(f"[probe] WARNING: <think> leaked into content on {think_leaks}/{len(probe_telemetry)} probe requests", flush=True)
        else:
            print("[probe] no <think> leakage observed in probe requests", flush=True)

        # One streaming request for a true TTFT + decode-only tok/s reading.
        probe_msgs = [
            {"role": "system", "content": tm._augment_system(
                system_prompt_for("mlx", "tool", guide)
            )},
            {"role": "user", "content": all_prompts[0]["prompt"]},
        ]
        ttft_probe = run_streaming_ttft_probe(
            server.base_url, probe_msgs, tools, ctk,
            args.temperature, args.top_p, args.max_tokens, args.request_timeout_s,
        )
        print(f"[probe] streaming TTFT probe: {ttft_probe}", flush=True)

        if args.force_subset:
            use_full = False
        elif args.force_full:
            use_full = True
        else:
            use_full = projected_full_min <= args.time_budget_min

        if use_full:
            prompts_used = all_prompts
            prompt_set_desc = f"full ({len(all_prompts)} prompts)"
        else:
            prompts_used = stratified_subset(all_prompts, args.subset_n, args.subset_seed)
            prompt_set_desc = (
                f"stratified subset (n={len(prompts_used)}, seed={args.subset_seed}, "
                f"proportional per category) — projected full-127 was "
                f"{projected_full_min:.1f} min > {args.time_budget_min:.0f} min budget"
            )
        print(f"[decision] prompt set: {prompt_set_desc}", flush=True)

        if args.limit:
            prompts_used = prompts_used[: args.limit]
            prompt_set_desc += f" [DEBUG LIMIT {args.limit}]"

        # --- Full run --------------------------------------------------------
        print(f"\n[run] evaluating {len(prompts_used)} prompts against {args.model_key}...", flush=True)
        t_run = time.monotonic()
        results = evaluate_model_multiturn_mlx(
            server.base_url, prompts_used, tools, known_tool_names, guide,
            chat_template_kwargs=ctk, temperature=args.temperature, top_p=args.top_p,
            max_tokens=args.max_tokens, request_timeout_s=args.request_timeout_s,
            telemetry_log=telemetry,
        )
        elapsed_total = time.monotonic() - t_run
        s = summarize(results)
        print(f"\n[run] -> {s['pass_rate']:.1%} ({s['passed']}/{s['total']}) in {elapsed_total:.1f}s", flush=True)

    finally:
        mem_stats = mem_sampler.stop() if mem_sampler else {"method": "none", "peak_rss_mb": None}
        server.stop()

    finished_at = time.strftime("%Y-%m-%d %H:%M:%S")

    json_path, md_path = write_model_report(
        label=args.model_key,
        model_meta=profile,
        prompts_file=args.prompts,
        prompt_set_desc=prompt_set_desc,
        results=results,
        prompts_used=prompts_used,
        telemetry=telemetry,
        ttft_probe=ttft_probe,
        mem_stats=mem_stats,
        started_at=started_at,
        finished_at=finished_at,
        elapsed_total_s=elapsed_total,
        out_dir=Path(args.out_dir),
    )
    print(f"[report] {json_path}", flush=True)
    print(f"[report] {md_path}", flush=True)

    if not args.skip_summary:
        update_global_summary(Path(args.out_dir), Path(args.summary_path))

    print(f"\n[done] {args.model_key}: {s['pass_rate']:.1%} "
          f"({s['passed']}/{s['total']}) — total wall time "
          f"{(time.monotonic() - t_start) / 60.0:.1f} min", flush=True)


if __name__ == "__main__":
    main()
