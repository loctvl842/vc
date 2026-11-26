// Review panel injected into the served spec page by review.py. No dependencies.
// Click an element (annotate mode) or select text, write a note, queue it, then send the batch to the agent.
(() => {
  if (window.__specReview) return;
  window.__specReview = true;

  const TOKEN = window.__REVIEW_TOKEN;
  const STORE = "spec-review:" + location.pathname;
  const MARK = "data-review-note";

  const saved = (() => {
    try {
      return JSON.parse(sessionStorage.getItem(STORE) || "{}");
    } catch {
      return {};
    }
  })();
  const state = {
    open: saved.open ?? true,
    annotate: saved.annotate ?? true,
    queue: saved.queue || [],
    draft: saved.draft || "",
    messages: [],
    listening: false,
    approved: false,
    mtime: null,
  };
  const persist = () => {
    try {
      const { open, annotate, queue, draft } = state;
      sessionStorage.setItem(STORE, JSON.stringify({ open, annotate, queue, draft, scroll: scrollY }));
    } catch {
      /* storage unavailable: the panel still works, it just forgets across reloads */
    }
  };

  const api = (path, body) =>
    fetch("/__review/" + path, {
      method: body ? "POST" : "GET",
      headers: { "X-Review-Token": TOKEN, "Content-Type": "application/json" },
      body: body ? JSON.stringify(body) : undefined,
    }).then((r) => r.json());

  // -- anchoring ------------------------------------------------------------------------------------------------

  const selectorFor = (el) => {
    const parts = [];
    for (let n = el; n && n.nodeType === 1 && n !== document.documentElement; n = n.parentElement) {
      if (n.id) {
        parts.unshift("#" + CSS.escape(n.id));
        break;
      }
      if (n === document.body) {
        parts.unshift("body");
        break;
      }
      let index = 1;
      for (let s = n.previousElementSibling; s; s = s.previousElementSibling) if (s.tagName === n.tagName) index++;
      parts.unshift(n.tagName.toLowerCase() + ":nth-of-type(" + index + ")");
    }
    return parts.join(" > ");
  };
  const specOf = (el) => el.closest("[data-spec]")?.getAttribute("data-spec") || "";
  const excerpt = (text, max = 240) => {
    const t = (text || "").replace(/\s+/g, " ").trim();
    return t.length > max ? t.slice(0, max) + "..." : t;
  };
  const anchorFor = (el, quote) => ({
    selector: selectorFor(el),
    spec: specOf(el),
    tag: el.tagName.toLowerCase(),
    quote: excerpt(quote || el.innerText || el.textContent),
  });

  // -- dom helpers ----------------------------------------------------------------------------------------------

  const h = (tag, props = {}, ...kids) => {
    const el = document.createElement(tag);
    for (const [k, v] of Object.entries(props)) {
      if (k === "class") el.className = v;
      else if (k.startsWith("on")) el.addEventListener(k.slice(2), v);
      else if (v !== false && v != null) el.setAttribute(k, v === true ? "" : v);
    }
    for (const kid of kids.flat()) if (kid != null) el.append(kid);
    return el;
  };

  const host = h("div", { id: "__review-root" });
  const root = host.attachShadow({ mode: "open" });
  root.append(
    h("style", {}, `
      :host { all: initial; }
      * { box-sizing: border-box; }
      .panel, .pill, .card, .selbtn, .hover {
        --bg: #ffffff; --fg: #1c1b19; --muted: #6b675f; --line: #dcd8cf; --accent: #b4540a; --accent-fg: #ffffff;
        --soft: #f6f3ec; --ok: #1f7a4d;
        font: 13px/1.45 ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif; color: var(--fg);
      }
      @media (prefers-color-scheme: dark) {
        .panel, .pill, .card, .selbtn, .hover {
          --bg: #1f1d1a; --fg: #ece8df; --muted: #a29d92; --line: #3a3732; --accent: #e08a3c; --accent-fg: #1a1209;
          --soft: #2a2723; --ok: #5fc08c;
        }
      }
      .panel { position: fixed; top: 0; right: 0; bottom: 0; width: 340px; z-index: 2147483000; background: var(--bg);
        border-left: 1px solid var(--line); display: flex; flex-direction: column; }
      .head { display: flex; align-items: center; gap: 8px; padding: 10px 12px; border-bottom: 1px solid var(--line); }
      .title { font-weight: 600; flex: 1; }
      .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--muted); }
      .dot.on { background: var(--ok); }
      .status { color: var(--muted); font-size: 12px; }
      button { font: inherit; color: var(--fg); background: var(--soft); border: 1px solid var(--line); border-radius: 6px;
        padding: 5px 10px; cursor: pointer; }
      button:hover:not(:disabled) { border-color: var(--accent); }
      button:disabled { opacity: .5; cursor: not-allowed; }
      button.primary { background: var(--accent); color: var(--accent-fg); border-color: var(--accent); font-weight: 600; }
      button.toggle[aria-pressed="true"] { background: var(--accent); color: var(--accent-fg); border-color: var(--accent); }
      .scroll { flex: 1; overflow-y: auto; padding: 10px 12px; display: flex; flex-direction: column; gap: 10px; }
      .empty { color: var(--muted); }
      .msg { border: 1px solid var(--line); border-radius: 8px; padding: 8px 10px; background: var(--soft); }
      .msg.agent { background: var(--bg); border-left: 3px solid var(--accent); }
      .who { font-size: 11px; color: var(--muted); text-transform: uppercase; letter-spacing: .04em; margin-bottom: 3px; }
      .note { margin-top: 6px; padding-top: 6px; border-top: 1px dashed var(--line); }
      .quote { color: var(--muted); font-style: italic; word-break: break-word; }
      .where { font: 11px ui-monospace, Menlo, monospace; color: var(--muted); word-break: break-all; }
      .queue { border-top: 1px solid var(--line); padding: 8px 12px; max-height: 32%; overflow-y: auto; }
      .qitem { display: flex; gap: 8px; align-items: flex-start; padding: 4px 0; }
      .qn { flex: none; width: 18px; height: 18px; border-radius: 50%; background: var(--accent); color: var(--accent-fg);
        font-size: 11px; display: grid; place-items: center; }
      .qbody { flex: 1; min-width: 0; }
      .x { border: 0; background: none; padding: 0 4px; color: var(--muted); }
      .composer { border-top: 1px solid var(--line); padding: 10px 12px; display: flex; flex-direction: column; gap: 8px; }
      textarea { width: 100%; font: inherit; color: var(--fg); background: var(--bg); border: 1px solid var(--line);
        border-radius: 6px; padding: 6px 8px; resize: vertical; min-height: 56px; }
      textarea:focus { outline: 2px solid var(--accent); outline-offset: 0; border-color: transparent; }
      .row { display: flex; gap: 8px; }
      .row > * { flex: 1; }
      .hint { color: var(--muted); font-size: 11px; }
      .pill { position: fixed; right: 16px; bottom: 16px; z-index: 2147483000; background: var(--accent); color: var(--accent-fg);
        border: 0; border-radius: 999px; padding: 8px 14px; font-weight: 600; box-shadow: 0 2px 10px rgba(0,0,0,.25); }
      .card { position: fixed; z-index: 2147483100; width: 300px; background: var(--bg); border: 1px solid var(--accent);
        border-radius: 8px; padding: 10px; box-shadow: 0 6px 24px rgba(0,0,0,.28); display: flex; flex-direction: column; gap: 8px; }
      .selbtn { position: fixed; z-index: 2147483100; background: var(--accent); color: var(--accent-fg); border: 0; font-weight: 600;
        box-shadow: 0 2px 8px rgba(0,0,0,.3); }
      .hover { position: fixed; z-index: 2147482900; pointer-events: none; border: 2px solid var(--accent);
        background: color-mix(in srgb, var(--accent) 12%, transparent); border-radius: 3px; display: none; }
      @media (max-width: 899px) {
        .panel { top: auto; width: 100%; height: 55vh; border-left: 0; border-top: 1px solid var(--line); }
      }
    `),
  );
  const hover = h("div", { class: "hover" });
  root.append(hover);
  const view = h("div");
  root.append(view);

  const pageStyle = h("style", {}, `[${MARK}] { outline: 2px solid #b4540a !important; outline-offset: 2px; }`);

  // -- annotation flow ------------------------------------------------------------------------------------------

  let card = null;
  let selBtn = null;

  const closeCard = () => {
    card?.remove();
    card = null;
  };
  const closeSelBtn = () => {
    selBtn?.remove();
    selBtn = null;
  };

  const openCard = (el, rect, quote) => {
    closeCard();
    closeSelBtn();
    const anchor = anchorFor(el, quote);
    const ta = h("textarea", { placeholder: "What should change here?", rows: "3" });
    const queue = () => {
      const note = ta.value.trim();
      if (!note) return;
      state.queue.push({ ...anchor, note });
      markQueued();
      closeCard();
      render();
      persist();
    };
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) queue();
      if (e.key === "Escape") closeCard();
    });
    card = h(
      "div",
      { class: "card" },
      h("div", { class: "where" }, anchor.spec ? "#" + anchor.spec : anchor.selector),
      anchor.quote ? h("div", { class: "quote" }, '"' + excerpt(anchor.quote, 120) + '"') : null,
      ta,
      h("div", { class: "row" }, h("button", { onclick: closeCard }, "Cancel"), h("button", { class: "primary", onclick: queue }, "Queue note")),
      h("div", { class: "hint" }, "Cmd/Ctrl+Enter queues, Esc cancels"),
    );
    const left = Math.min(Math.max(8, rect.left), innerWidth - 316 - (state.open && innerWidth >= 900 ? 340 : 0));
    const top = Math.min(rect.bottom + 8, innerHeight - 220);
    card.style.left = left + "px";
    card.style.top = Math.max(8, top) + "px";
    root.append(card);
    ta.focus();
  };

  const markQueued = () => {
    document.querySelectorAll("[" + MARK + "]").forEach((el) => el.removeAttribute(MARK));
    state.queue.forEach((item, i) => {
      try {
        document.querySelector(item.selector)?.setAttribute(MARK, String(i + 1));
      } catch {
        /* selector no longer valid after the spec changed */
      }
    });
  };

  const inPanel = (e) => e.composedPath().includes(host);
  // Pick mode swallows page clicks; it is only on while the panel is open, so a hidden panel leaves the page usable.
  const picking = () => state.open && state.annotate;
  const togglePick = () => { state.annotate = !state.annotate; hover.style.display = "none"; render(); persist(); };

  document.addEventListener(
    "click",
    (e) => {
      if (!picking() || inPanel(e)) return;
      if (!(e.target instanceof Element)) return;
      if (getSelection() && !getSelection().isCollapsed) return; // a text selection is handled by the Comment button
      e.preventDefault();
      e.stopPropagation();
      openCard(e.target, e.target.getBoundingClientRect(), "");
    },
    true,
  );

  document.addEventListener("mousemove", (e) => {
    if (!picking() || inPanel(e) || card || !(e.target instanceof Element)) {
      hover.style.display = "none";
      return;
    }
    const r = e.target.getBoundingClientRect();
    Object.assign(hover.style, { display: "block", left: r.left + "px", top: r.top + "px", width: r.width + "px", height: r.height + "px" });
  });
  document.addEventListener("mouseleave", () => (hover.style.display = "none"));

  document.addEventListener("mouseup", (e) => {
    if (inPanel(e)) return;
    setTimeout(() => {
      const sel = getSelection();
      closeSelBtn();
      if (!sel || sel.isCollapsed || !sel.toString().trim()) return;
      const range = sel.getRangeAt(0);
      const common = range.commonAncestorContainer;
      const el = common.nodeType === 1 ? common : common.parentElement;
      if (!el || host.contains(el)) return;
      const rect = range.getBoundingClientRect();
      const quote = sel.toString();
      selBtn = h("button", { class: "selbtn", onmousedown: (ev) => ev.preventDefault(), onclick: () => openCard(el, rect, quote) }, "Comment");
      selBtn.style.left = Math.max(8, rect.left) + "px";
      selBtn.style.top = Math.max(8, rect.top - 34) + "px";
      root.append(selBtn);
    }, 0);
  });

  document.addEventListener("keydown", (e) => {
    if (e.altKey && e.code === "KeyA") {
      e.preventDefault();
      togglePick();
    }
    if (e.key === "Escape") {
      closeCard();
      closeSelBtn();
    }
  });

  // -- panel ----------------------------------------------------------------------------------------------------

  const send = async (approve) => {
    const message = state.draft.trim();
    await api("feedback", { items: state.queue, message, approve });
    state.queue = [];
    state.draft = "";
    markQueued();
    persist();
    await refresh();
  };

  const renderMessage = (m) =>
    h(
      "div",
      { class: "msg " + m.role },
      h("div", { class: "who" }, m.role === "agent" ? "Agent" : "You" + (m.delivered ? "  (seen by agent)" : "  (waiting)")),
      m.text ? h("div", {}, m.text) : null,
      (m.items || []).map((item) =>
        h(
          "div",
          { class: "note" },
          h("div", { class: "where" }, (item.spec ? "#" + item.spec + "  " : "") + item.selector),
          item.quote ? h("div", { class: "quote" }, '"' + excerpt(item.quote, 100) + '"') : null,
          h("div", {}, item.note),
        ),
      ),
      m.approve ? h("div", { class: "note" }, "Approved") : null,
    );

  function render() {
    const active = root.activeElement;
    const keepFocus = active && active.dataset ? active.dataset.keep : null;
    const caret = active && "selectionStart" in active ? active.selectionStart : null;
    view.replaceChildren();
    if (!state.open) {
      view.append(h("button", { class: "pill", onclick: () => { state.open = true; adjustPage(); render(); persist(); } }, "Review" + (state.queue.length ? " (" + state.queue.length + ")" : "")));
      return;
    }
    const draft = h("textarea", { "data-keep": "draft", placeholder: "General message to the agent (optional)", rows: "2" });
    draft.value = state.draft;
    draft.addEventListener("input", () => {
      state.draft = draft.value;
      persist();
      sendBtn.disabled = !(state.queue.length || state.draft.trim());
      approveBtn.disabled = Boolean(state.queue.length || state.draft.trim());
    });
    const sendBtn = h("button", { class: "primary", onclick: () => send(false) }, "Send to agent" + (state.queue.length ? " (" + state.queue.length + ")" : ""));
    const approveBtn = h("button", { onclick: () => send(true), title: "Send queued notes first; approve once the queue is empty" }, state.approved ? "Approved" : "Approve spec");
    sendBtn.disabled = !(state.queue.length || state.draft.trim());
    approveBtn.disabled = Boolean(state.queue.length || state.draft.trim()) || state.approved;

    view.append(
      h(
        "div",
        { class: "panel" },
        h(
          "div",
          { class: "head" },
          h("span", { class: "title" }, "Spec review"),
          h("span", { class: "dot" + (state.listening ? " on" : "") }),
          h("span", { class: "status" }, state.listening ? "agent listening" : "agent not listening"),
        ),
        h(
          "div",
          { class: "head" },
          h("button", { class: "toggle", "aria-pressed": String(state.annotate), title: "Alt+A", onclick: togglePick }, "Pick elements: " + (state.annotate ? "ON" : "OFF")),
          h("span", { class: "hint", style: "flex:1" }, state.annotate ? "Hover and click to comment" : "Page is interactive; select text to comment"),
          h("button", { onclick: () => { state.open = false; adjustPage(); render(); persist(); } }, "Hide"),
        ),
        h(
          "div",
          { class: "scroll" },
          state.messages.length ? state.messages.map(renderMessage) : h("div", { class: "empty" }, "No messages yet. Click an element or select text to leave a note, then send."),
        ),
        state.queue.length
          ? h(
              "div",
              { class: "queue" },
              state.queue.map((item, i) =>
                h(
                  "div",
                  { class: "qitem" },
                  h("span", { class: "qn" }, String(i + 1)),
                  h("div", { class: "qbody" }, h("div", { class: "where" }, (item.spec ? "#" + item.spec : item.selector)), h("div", {}, item.note)),
                  h("button", { class: "x", title: "Remove", onclick: () => { state.queue.splice(i, 1); markQueued(); render(); persist(); } }, "x"),
                ),
              ),
            )
          : null,
        h("div", { class: "composer" }, draft, h("div", { class: "row" }, sendBtn, approveBtn)),
      ),
    );
    const list = view.querySelector(".scroll");
    list.scrollTop = list.scrollHeight;
    if (keepFocus === "draft") {
      draft.focus();
      if (caret != null) draft.setSelectionRange(caret, caret);
    }
  }

  function adjustPage() {
    document.documentElement.style.paddingRight = state.open && innerWidth >= 900 ? "340px" : "";
  }

  // -- sync with the server -------------------------------------------------------------------------------------

  async function refresh() {
    let snap;
    try {
      snap = await api("state");
    } catch {
      state.listening = false;
      return;
    }
    if (state.mtime !== null && snap.mtime !== state.mtime) {
      // The agent saved a new version of the spec: reload, keeping queue, draft and scroll via sessionStorage.
      persist();
      location.reload();
      return;
    }
    state.mtime = snap.mtime;
    const changed = JSON.stringify([snap.messages, snap.listening, snap.approved]) !== JSON.stringify([state.messages, state.listening, state.approved]);
    state.messages = snap.messages;
    state.listening = snap.listening;
    state.approved = snap.approved;
    if (changed && !(root.activeElement && root.activeElement.tagName === "TEXTAREA" && card)) render();
  }

  document.head.append(pageStyle);
  document.body.append(host);
  adjustPage();
  addEventListener("resize", adjustPage);
  if (saved.scroll) scrollTo(0, saved.scroll);
  markQueued();
  render();
  refresh();
  setInterval(refresh, 1000);
})();
