(() => {
  const LAYER_ID = "claude-pet-scout-layer";
  const MAX_ISSUES = 8;

  function clear() { document.getElementById(LAYER_ID)?.remove(); }

  function layer() {
    clear();
    const root = document.createElement("div");
    root.id = LAYER_ID;
    root.setAttribute("aria-hidden", "true");
    root.innerHTML = '<div class="claude-pet-scout"><span class="claude-pet-scout-eyes"></span></div>';
    document.documentElement.append(root);
    addEventListener("scroll", clear, { once: true, capture: true });
    addEventListener("resize", clear, { once: true });
    return root;
  }

  function connect(root, rect, label, tone = "info") {
    if (!rect || rect.width < 1 || rect.height < 1) return;
    const pet = { x: innerWidth - 50, y: innerHeight - 43 };
    const target = { x: Math.max(4, Math.min(innerWidth - 4, rect.left + rect.width / 2)), y: Math.max(4, Math.min(innerHeight - 4, rect.top + rect.height / 2)) };
    const dx = target.x - pet.x, dy = target.y - pet.y;
    const leg = document.createElement("div");
    leg.className = "claude-pet-leg";
    leg.style.cssText = `left:${pet.x}px;top:${pet.y}px;width:${Math.hypot(dx, dy)}px;transform:rotate(${Math.atan2(dy, dx)}rad)`;
    const mark = document.createElement("div");
    mark.className = "claude-pet-mark";
    mark.dataset.tone = tone;
    mark.style.cssText = `left:${Math.max(2, rect.left - 3)}px;top:${Math.max(2, rect.top - 3)}px;width:${Math.min(innerWidth - rect.left - 2, rect.width + 6)}px;height:${Math.min(innerHeight - rect.top - 2, rect.height + 6)}px`;
    const note = document.createElement("div");
    note.className = "claude-pet-label";
    note.textContent = label;
    note.style.cssText = `left:${Math.max(4, Math.min(innerWidth - 250, rect.left))}px;top:${Math.max(4, Math.min(innerHeight - 34, rect.bottom + 5))}px`;
    root.append(leg, mark, note);
  }

  function evidence() {
    const selection = getSelection();
    if (!selection || selection.isCollapsed || selection.rangeCount === 0) return { message: "selecciona un texto primero." };
    const rects = [...selection.getRangeAt(0).getClientRects()].filter(rect => rect.width > 2 && rect.height > 2).slice(0, 4);
    const root = layer();
    rects.forEach((rect, index) => connect(root, rect, index === 0 ? "evidencia seleccionada" : "", "info"));
    return { message: `${rects.length} fragmentos marcados.` };
  }

  function contrast(rgb) {
    const parts = rgb.match(/[\d.]+/g)?.slice(0, 3).map(Number);
    if (!parts || parts.length < 3) return 1;
    const luminance = parts.map(value => { const s = value / 255; return s <= .03928 ? s / 12.92 : ((s + .055) / 1.055) ** 2.4; });
    return .2126 * luminance[0] + .7152 * luminance[1] + .0722 * luminance[2];
  }

  function issues() {
    const found = [];
    const visible = element => {
      const rect = element.getBoundingClientRect(), style = getComputedStyle(element);
      return rect.width > 4 && rect.height > 4 && rect.bottom > 0 && rect.top < innerHeight && style.visibility !== "hidden" && style.display !== "none";
    };
    document.querySelectorAll("button, a, input, select, textarea, [role=button], img").forEach(element => {
      if (found.length >= MAX_ISSUES || !visible(element)) return;
      const rect = element.getBoundingClientRect();
      const name = element.getAttribute("aria-label") || element.getAttribute("title") || element.textContent?.trim();
      if (["BUTTON", "A", "INPUT", "SELECT", "TEXTAREA"].includes(element.tagName) && !name && element.getAttribute("placeholder") == null) {
        found.push({ rect, label: "control sin nombre accesible", tone: "error" }); return;
      }
      if (element.tagName === "IMG" && !element.hasAttribute("alt")) {
        found.push({ rect, label: "imagen sin atributo alt", tone: "warning" }); return;
      }
      if (rect.width < 24 || rect.height < 24) found.push({ rect, label: "objetivo táctil menor de 24 px", tone: "warning" });
    });
    document.querySelectorAll("p, span, label, button, a").forEach(element => {
      if (found.length >= MAX_ISSUES || !visible(element) || !element.textContent?.trim()) return;
      const style = getComputedStyle(element);
      const ratio = (Math.max(contrast(style.color), contrast(style.backgroundColor)) + .05) / (Math.min(contrast(style.color), contrast(style.backgroundColor)) + .05);
      if (ratio < 2.5 && style.backgroundColor !== "rgba(0, 0, 0, 0)") found.push({ rect: element.getBoundingClientRect(), label: "contraste probablemente insuficiente", tone: "warning" });
    });
    return found;
  }

  function audit() {
    const found = issues();
    const root = layer();
    found.forEach(item => connect(root, item.rect, item.label, item.tone));
    if (!found.length) {
      const note = document.createElement("div"); note.className = "claude-pet-label"; note.textContent = "sin problemas básicos visibles"; note.style.cssText = "right:22px;bottom:74px"; root.append(note);
    }
    return { message: found.length ? `${found.length} problemas visibles.` : "sin problemas básicos visibles." };
  }

  chrome.runtime.onMessage.addListener((message, _sender, reply) => {
    if (message?.type !== "claude-pet") return;
    if (message.command === "clear") { clear(); reply({ message: "marcas eliminadas." }); }
    else if (message.command === "evidence") reply(evidence());
    else if (message.command === "audit") reply(audit());
  });
})();
