const status = document.querySelector("#status");
const controls = [...document.querySelectorAll("button[data-command]")];

async function send(tabId, message) {
  try {
    await chrome.tabs.sendMessage(tabId, { type: "claude-pet", command: "ping" });
  } catch {
    await chrome.scripting.insertCSS({ target: { tabId }, files: ["content.css"] });
    await chrome.scripting.executeScript({ target: { tabId }, files: ["content.js"] });
  }
  return chrome.tabs.sendMessage(tabId, message);
}

document.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return;
  controls.forEach(control => { control.disabled = true; });
  document.body.setAttribute("aria-busy", "true");
  status.textContent = "preparando scout…";
  try {
    const agent = document.querySelector('input[name="agent"]:checked')?.value || "claude";
    const result = await send(tab.id, { type: "claude-pet", command: button.dataset.command, agent });
    status.textContent = result?.message || "listo.";
  } catch {
    status.textContent = "esta página no permite extensiones.";
  } finally {
    controls.forEach(control => { control.disabled = false; });
    document.body.removeAttribute("aria-busy");
  }
});
