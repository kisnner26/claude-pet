(() => {
  if (window.__claudePetWebScout) return;
  window.__claudePetWebScout = true;

  const ROOT_ID = "claude-pet-scout-layer";
  const MAX_ISSUES = 24;
  const state = { agent: "claude", mode: "", issues: [], index: 0, range: null };
  let frame = 0;

  const visible = element => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 2 && rect.height > 2 && rect.bottom > 0 && rect.right > 0 &&
      rect.top < innerHeight && rect.left < innerWidth && style.display !== "none" &&
      style.visibility !== "hidden" && Number(style.opacity) !== 0;
  };

  function accessibleName(element) {
    const labelledBy = element.getAttribute("aria-labelledby")?.split(/\s+/)
      .map(id => document.getElementById(id)?.textContent?.trim()).filter(Boolean).join(" ");
    const labels = [...(element.labels || [])].map(label => label.textContent?.trim()).filter(Boolean).join(" ");
    return element.getAttribute("aria-label")?.trim() || labelledBy || labels ||
      element.getAttribute("alt")?.trim() || element.getAttribute("title")?.trim() ||
      (["button", "submit", "reset"].includes(element.type) ? element.value?.trim() : "") ||
      element.textContent?.trim() || "";
  }

  function rgba(value) {
    const parts = value.match(/[\d.]+/g)?.map(Number);
    if (!parts || parts.length < 3) return null;
    return { r: parts[0], g: parts[1], b: parts[2], a: parts[3] ?? 1 };
  }

  function luminance(color) {
    const channel = value => {
      const normalized = value / 255;
      return normalized <= .03928 ? normalized / 12.92 : ((normalized + .055) / 1.055) ** 2.4;
    };
    return .2126 * channel(color.r) + .7152 * channel(color.g) + .0722 * channel(color.b);
  }

  function contrastRatio(element) {
    const foreground = rgba(getComputedStyle(element).color);
    let parent = element;
    let background = null;
    while (parent && !background) {
      const candidate = rgba(getComputedStyle(parent).backgroundColor);
      if (candidate?.a > .96) background = candidate;
      parent = parent.parentElement;
    }
    if (!foreground || !background) return null;
    const values = [luminance(foreground), luminance(background)].sort((a, b) => b - a);
    return (values[0] + .05) / (values[1] + .05);
  }

  function auditPage() {
    const results = [];
    const registered = new WeakMap();
    const add = (element, code, label, tone = "warning") => {
      if (!visible(element) || registered.get(element)?.has(code)) return;
      const codes = registered.get(element) || new Set();
      codes.add(code);
      registered.set(element, codes);
      results.push({ element, code, label, tone });
    };

    const controls = document.querySelectorAll('button, a[href], input:not([type="hidden"]), select, textarea, [role="button"], [role="link"]');
    controls.forEach(element => {
      if (!accessibleName(element)) add(element, "name", "control sin nombre accesible", "error");
      const rect = element.getBoundingClientRect();
      if (rect.width < 44 || rect.height < 44) add(element, "target", "objetivo táctil menor de 44 px");
    });

    document.querySelectorAll("img").forEach(image => {
      if (!image.hasAttribute("alt")) add(image, "alt", "imagen sin atributo alt", "error");
    });

    const ids = new Map();
    document.querySelectorAll("[id]").forEach(element => {
      if (!element.id) return;
      if (ids.has(element.id)) add(element, "duplicate-id", `id duplicado: ${element.id}`, "error");
      else ids.set(element.id, element);
    });

    [...document.querySelectorAll("body *")].slice(0, 2500).forEach(element => {
      if (element.closest(`#${ROOT_ID}`) || !visible(element)) return;
      const rect = element.getBoundingClientRect();
      if (rect.right > innerWidth + 2 || rect.left < -2) add(element, "overflow", "contenido fuera del viewport");
    });

    [...document.querySelectorAll("p, span, label, button, a, li, h1, h2, h3, h4, h5, h6")].slice(0, 1200).forEach(element => {
      if (!element.textContent?.trim() || !visible(element)) return;
      const ratio = contrastRatio(element);
      if (ratio == null) return;
      const style = getComputedStyle(element);
      const size = parseFloat(style.fontSize);
      const weight = Number(style.fontWeight) || (style.fontWeight === "bold" ? 700 : 400);
      const large = size >= 24 || (size >= 18.66 && weight >= 700);
      if (ratio < (large ? 3 : 4.5)) add(element, "contrast", `contraste ${ratio.toFixed(1)}:1; mínimo ${large ? "3" : "4.5"}:1`);
    });

    return results
      .sort((a, b) => Number(b.tone === "error") - Number(a.tone === "error"))
      .slice(0, MAX_ISSUES);
  }

  function clear() {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    document.getElementById(ROOT_ID)?.remove();
    state.mode = "";
    state.issues = [];
    state.index = 0;
    state.range = null;
  }

  function ensureRoot() {
    let root = document.getElementById(ROOT_ID);
    if (root) return root;
    root = document.createElement("div");
    root.id = ROOT_ID;
    root.innerHTML = `
      <div class="claude-pet-scout" aria-hidden="true"><span class="claude-pet-scout-eyes"></span></div>
      <div class="claude-pet-drawing" aria-hidden="true"></div>
      <div class="claude-pet-toolbar" role="group" aria-label="controles de web scout">
        <button type="button" data-nav="previous" aria-label="problema anterior">‹</button>
        <span data-status role="status" aria-live="polite"></span>
        <button type="button" data-nav="next" aria-label="problema siguiente">›</button>
        <button type="button" data-nav="clear" aria-label="quitar marcas">×</button>
      </div>`;
    root.addEventListener("click", event => {
      const action = event.target.closest("button[data-nav]")?.dataset.nav;
      if (action === "clear") clear();
      else if (action === "previous") navigate(-1);
      else if (action === "next") navigate(1);
    });
    document.documentElement.append(root);
    return root;
  }

  function makeMark(container, rect, tone, active = true) {
    if (!rect || rect.width < 1 || rect.height < 1 || rect.bottom < 0 || rect.top > innerHeight) return;
    const left = Math.max(2, rect.left - 3);
    const mark = document.createElement("div");
    mark.className = "claude-pet-mark";
    mark.dataset.tone = tone;
    mark.dataset.active = String(active);
    mark.style.cssText = `left:${left}px;top:${Math.max(2, rect.top - 3)}px;width:${Math.max(2, Math.min(innerWidth - left - 2, rect.width + 6))}px;height:${Math.max(2, rect.height + 6)}px`;
    container.append(mark);
  }

  function connect(container, rect, label, tone) {
    if (!rect || rect.width < 1 || rect.height < 1) return;
    const pet = { x: innerWidth - 50, y: innerHeight - 43 };
    const target = { x: Math.max(4, Math.min(innerWidth - 4, rect.left + rect.width / 2)), y: Math.max(4, Math.min(innerHeight - 4, rect.top + rect.height / 2)) };
    const dx = target.x - pet.x;
    const dy = target.y - pet.y;
    const leg = document.createElement("div");
    leg.className = "claude-pet-leg";
    leg.style.cssText = `left:${pet.x}px;top:${pet.y}px;width:${Math.hypot(dx, dy)}px;transform:rotate(${Math.atan2(dy, dx)}rad)`;
    const note = document.createElement("div");
    note.className = "claude-pet-label";
    note.dataset.tone = tone;
    note.textContent = label;
    note.style.cssText = `left:${Math.max(6, Math.min(innerWidth - 274, rect.left))}px;top:${Math.max(6, Math.min(innerHeight - 42, rect.bottom + 7))}px`;
    container.append(leg, note);
  }

  function render() {
    if (!state.mode) return;
    const root = ensureRoot();
    root.dataset.agent = state.agent;
    const drawing = root.querySelector(".claude-pet-drawing");
    const status = root.querySelector("[data-status]");
    const previous = root.querySelector('[data-nav="previous"]');
    const next = root.querySelector('[data-nav="next"]');
    drawing.replaceChildren();

    if (state.mode === "evidence") {
      const rects = [...state.range.getClientRects()].filter(rect => rect.width > 2 && rect.height > 2).slice(0, 8);
      rects.forEach(rect => makeMark(drawing, rect, "info"));
      connect(drawing, rects[0], "evidencia seleccionada", "info");
      status.textContent = `${rects.length} fragmentos`;
      previous.disabled = true;
      next.disabled = true;
      return;
    }

    const current = state.issues[state.index];
    state.issues.forEach((issue, index) => makeMark(drawing, issue.element.getBoundingClientRect(), issue.tone, index === state.index));
    if (current) {
      const rect = current.element.getBoundingClientRect();
      connect(drawing, rect, current.label, current.tone);
      status.textContent = `${state.index + 1} / ${state.issues.length} · ${current.code}`;
    } else {
      status.textContent = "sin problemas básicos visibles";
    }
    previous.disabled = state.issues.length < 2;
    next.disabled = state.issues.length < 2;
  }

  function scheduleRender() {
    if (!state.mode || frame) return;
    frame = requestAnimationFrame(() => { frame = 0; render(); });
  }

  function navigate(offset) {
    if (state.issues.length < 2) return;
    state.index = (state.index + offset + state.issues.length) % state.issues.length;
    const rect = state.issues[state.index].element.getBoundingClientRect();
    if (rect.bottom < 0 || rect.top > innerHeight) state.issues[state.index].element.scrollIntoView({ block: "center" });
    render();
  }

  function evidence(agent) {
    const selection = getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return { message: "selecciona un texto primero." };
    const range = selection.getRangeAt(0).cloneRange();
    clear();
    state.agent = agent === "codex" ? "codex" : "claude";
    state.mode = "evidence";
    state.range = range;
    render();
    const count = [...range.getClientRects()].filter(rect => rect.width > 2 && rect.height > 2).length;
    return { message: `${Math.min(count, 8)} fragmentos marcados.` };
  }

  function audit(agent) {
    clear();
    state.agent = agent === "codex" ? "codex" : "claude";
    state.mode = "audit";
    state.issues = auditPage();
    render();
    return { message: state.issues.length ? `${state.issues.length} problemas visibles.` : "sin problemas básicos visibles." };
  }

  addEventListener("scroll", scheduleRender, { capture: true, passive: true });
  addEventListener("resize", scheduleRender, { passive: true });
  addEventListener("keydown", event => {
    if (!state.mode || event.target.matches?.("input, textarea, select, [contenteditable]")) return;
    if (event.key === "Escape") clear();
    else if (event.key === "ArrowLeft") navigate(-1);
    else if (event.key === "ArrowRight") navigate(1);
  });

  chrome.runtime.onMessage.addListener((message, _sender, reply) => {
    if (message?.type !== "claude-pet") return;
    if (message.command === "ping") reply({ message: "listo." });
    else if (message.command === "clear") { clear(); reply({ message: "marcas eliminadas." }); }
    else if (message.command === "evidence") reply(evidence(message.agent));
    else if (message.command === "audit") reply(audit(message.agent));
  });
})();
