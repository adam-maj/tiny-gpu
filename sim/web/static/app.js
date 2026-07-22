/* tiny-gpu live / replay dashboard */
(() => {
  const STAGES = ["IDLE", "FETCH", "DECODE", "WAIT", "EXECUTE", "UPDATE", "DONE"];

  const els = {
    kernel: document.getElementById("kernel-name"),
    mode: document.getElementById("mode-badge"),
    cycle: document.getElementById("cycle-count"),
    conn: document.getElementById("conn-dot"),
    cores: document.getElementById("cores-container"),
    canvas: document.getElementById("mem-canvas"),
    legend: document.getElementById("mem-legend"),
    narration: document.getElementById("narration"),
    scrubWrap: document.getElementById("scrub-wrap"),
    scrub: document.getElementById("scrub-bar"),
    scrubLabel: document.getElementById("scrub-label"),
    btnPlay: document.getElementById("btn-play"),
    btnStep: document.getElementById("btn-step"),
    btnBack: document.getElementById("btn-back"),
    btnRestart: document.getElementById("btn-restart"),
    speed: document.getElementById("speed-slider"),
    autoFollow: document.getElementById("auto-follow"),
  };

  const state = {
    mode: "–",
    playing: true,
    length: 0,
    position: 0,
    snapshot: null,
    ws: null,
    canRestart: false,
  };

  function send(cmd) {
    if (state.ws && state.ws.readyState === WebSocket.OPEN) {
      state.ws.send(JSON.stringify(cmd));
    }
  }

  function speedToDelay(sliderVal) {
    // 0 = pause-ish fast wait, 200 = very slow. Map to seconds.
    const v = Number(sliderVal);
    if (v <= 0) return 0;
    return Math.pow(v / 200, 2) * 0.5;
  }

  function setConnected(ok) {
    els.conn.className = "dot " + (ok ? "dot-on" : "dot-off");
  }

  function renderPipeline(coreState) {
    return STAGES.map((s) => {
      const active = coreState === s;
      const cls = "stage" + (active ? (s === "DONE" ? " done-state active" : " active") : "");
      return `<div class="${cls}">${s}</div>`;
    }).join("");
  }

  function renderRegisters(regs) {
    if (!regs || !regs.length) return "–";
    // Snapshot stores registers[0..15] in order R0..R15
    return regs.slice(0, 8).map((v, i) => `R${i}=${v}`).join(" ");
  }

  function renderCore(core) {
    const threads = (core.threads || [])
      .filter((t) => t.enabled)
      .map((t) => {
        const active = core.active_mask && core.active_mask[t.slot];
        return `<tr class="${active ? "active-row" : "inactive"}">
          <td><span class="mask-pill ${active ? "on" : ""}"></span> T${t.slot}</td>
          <td>${t.pc}</td>
          <td>${t.lsu_state || "–"}</td>
          <td title="${(t.registers || []).map((v, i) => `R${i}=${v}`).join(", ")}">${renderRegisters(t.registers)}</td>
        </tr>`;
      })
      .join("");

    return `<div class="core-card">
      <div class="core-header">
        <div class="core-title">Core ${core.id}</div>
        <div class="core-meta">block ${core.block_id} · PC ${core.current_pc} · ${core.fetcher_state}${core.prefetch_hit ? " · prefetch" : ""}${core.done ? " · done" : ""}</div>
      </div>
      <div class="pipeline">${renderPipeline(core.core_state)}</div>
      <div class="instruction-line">${core.instruction || "NOP"}</div>
      <table class="thread-table">
        <thead><tr><th>thread</th><th>pc</th><th>lsu</th><th>regs</th></tr></thead>
        <tbody>${threads || '<tr><td colspan="4">no active threads</td></tr>'}</tbody>
      </table>
    </div>`;
  }

  function renderMemory(mem) {
    const ctx = els.canvas.getContext("2d");
    const W = els.canvas.width;
    const H = els.canvas.height;
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, W, H);
    if (!mem || !mem.length) {
      els.legend.textContent = "no data memory in this snapshot";
      return;
    }
    // Prefer 16-wide framebuffer layout when length suggests it
    const cols = 16;
    const rows = Math.ceil(Math.min(mem.length, 256) / cols);
    const cellW = W / cols;
    const cellH = H / Math.max(rows, cols);
    for (let i = 0; i < Math.min(mem.length, cols * rows); i++) {
      const v = mem[i] & 0xff;
      const x = (i % cols) * cellW;
      const y = Math.floor(i / cols) * cellH;
      ctx.fillStyle = `rgb(${v},${v},${v})`;
      ctx.fillRect(x, y, cellW + 0.5, cellH + 0.5);
    }
    els.legend.textContent = `${Math.min(mem.length, 256)} bytes · ${cols}×${rows} view (brighter = higher value)`;
  }

  function narrate(snap) {
    if (!snap || !snap.cores || !snap.cores.length) {
      els.narration.innerHTML = `<div class="line">Waiting for simulation snapshots…</div>`;
      return;
    }
    const lines = [];
    lines.push(`<div class="line"><strong>Cycle ${snap.cycle}</strong>${snap.done ? " — kernel done" : ""}</div>`);
    for (const core of snap.cores) {
      const activeCount = (core.active_mask || []).filter(Boolean).length;
      lines.push(`<div class="line">Core ${core.id} is in <strong>${core.core_state}</strong> at PC ${core.current_pc}: <code>${core.instruction || "NOP"}</code> (${activeCount} thread${activeCount === 1 ? "" : "s"} active)</div>`);
      if (core.prefetch_hit) {
        lines.push(`<div class="line">Fetcher served this instruction from the speculative prefetch buffer.</div>`);
      }
    }
    if (snap.icache_hit && snap.icache_hit.some(Boolean)) {
      lines.push(`<div class="line">Instruction cache hit on core(s): ${snap.icache_hit.map((h, i) => h ? i : null).filter((x) => x !== null).join(", ")}</div>`);
    }
    if (snap.icache_miss && snap.icache_miss.some(Boolean)) {
      lines.push(`<div class="line">Instruction cache miss → program memory fetch.</div>`);
    }
    if (snap.data_read_transactions != null) {
      lines.push(`<div class="line">External data mem transactions so far: ${snap.data_read_transactions} reads / ${snap.data_write_transactions} writes</div>`);
    }
    els.narration.innerHTML = lines.join("");
  }

  function applySnapshot(snap, meta = {}) {
    state.snapshot = snap;
    if (meta.position != null) state.position = meta.position;
    if (meta.length != null) {
      state.length = meta.length;
      els.scrub.max = Math.max(meta.length - 1, 0);
      els.scrub.value = state.position;
      els.scrubLabel.textContent = `${state.position} / ${Math.max(meta.length - 1, 0)}`;
    }
    els.cycle.textContent = snap.cycle ?? "–";
    if (snap.kernel) els.kernel.textContent = snap.kernel;
    els.cores.innerHTML = (snap.cores || []).map(renderCore).join("") || `<div class="dim">No cores in snapshot</div>`;
    renderMemory(snap.data_memory);
    narrate(snap);
  }

  function connect() {
    const proto = location.protocol === "https:" ? "wss" : "ws";
    const ws = new WebSocket(`${proto}://${location.host}/ws`);
    state.ws = ws;
    ws.onopen = () => setConnected(true);
    ws.onclose = () => {
      setConnected(false);
      setTimeout(connect, 1500);
    };
    ws.onerror = () => setConnected(false);
    ws.onmessage = (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.type === "meta") {
        state.mode = msg.mode || "–";
        els.mode.textContent = state.mode;
        els.mode.className = "badge " + (state.mode === "live" ? "live" : state.mode === "replay" ? "replay" : "");
        if (msg.kernel) els.kernel.textContent = msg.kernel;
        state.canRestart = !!msg.can_restart;
        updateRestartButton();
        if (state.mode === "replay") {
          els.scrubWrap.classList.remove("hidden");
          state.length = msg.length || 0;
          els.scrub.max = Math.max(state.length - 1, 0);
        } else {
          els.scrubWrap.classList.add("hidden");
        }
      } else if (msg.type === "hello") {
        if (msg.kernel) els.kernel.textContent = msg.kernel;
        state.playing = true;
        updatePlayButton();
      } else if (msg.type === "restarting") {
        resetViewForRestart();
      } else if (msg.type === "snapshot") {
        if (!els.autoFollow.checked && state.mode === "live") return;
        applySnapshot(msg.data, { position: msg.position, length: msg.length });
      } else if (msg.type === "done") {
        state.playing = false;
        updatePlayButton();
      }
    };
  }

  function updatePlayButton() {
    els.btnPlay.innerHTML = state.playing ? "&#10074;&#10074;" : "&#9654;";
    els.btnPlay.classList.toggle("active", state.playing);
  }

  function updateRestartButton() {
    els.btnRestart.disabled = !state.canRestart;
    els.btnRestart.title = state.canRestart
      ? (state.mode === "replay"
          ? "Restart playback from cycle 0"
          : "Kill and re-launch the simulation from the beginning")
      : "Restart needs make gui_* (live with --run) or replay mode";
  }

  function resetViewForRestart() {
    state.playing = true;
    state.position = 0;
    updatePlayButton();
    els.cycle.textContent = "0";
    els.cores.innerHTML = `<div class="dim">Restarting…</div>`;
    els.narration.innerHTML = `<div class="line">Restarting simulation from the beginning…</div>`;
    const ctx = els.canvas.getContext("2d");
    ctx.fillStyle = "#000";
    ctx.fillRect(0, 0, els.canvas.width, els.canvas.height);
    els.legend.textContent = "";
    if (state.mode === "replay") {
      els.scrub.value = 0;
      els.scrubLabel.textContent = `0 / ${Math.max(state.length - 1, 0)}`;
    }
  }

  els.btnPlay.addEventListener("click", () => {
    state.playing = !state.playing;
    send({ type: state.playing ? "play" : "pause" });
    updatePlayButton();
  });
  els.btnStep.addEventListener("click", () => {
    state.playing = false;
    updatePlayButton();
    send({ type: "step" });
  });
  els.btnBack.addEventListener("click", () => {
    state.playing = false;
    updatePlayButton();
    send({ type: "back" });
  });
  els.btnRestart.addEventListener("click", () => {
    if (!state.canRestart) return;
    resetViewForRestart();
    send({ type: "restart", value: speedToDelay(els.speed.value) });
  });
  els.speed.addEventListener("input", () => {
    send({ type: "speed", value: speedToDelay(els.speed.value) });
  });
  els.scrub.addEventListener("input", () => {
    send({ type: "scrub", value: Number(els.scrub.value) });
  });

  // Initial play state: live mode starts "playing" (sim runs); replay starts paused until user hits play
  updatePlayButton();
  updateRestartButton();
  connect();
})();
