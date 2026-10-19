const status = document.querySelector("#status");

document.addEventListener("click", async (event) => {
  const button = event.target.closest("button[data-command]");
  if (!button) return;
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab?.id) return;
  try {
    const result = await chrome.tabs.sendMessage(tab.id, { type: "claude-pet", command: button.dataset.command });
    status.textContent = result?.message || "listo.";
  } catch {
    status.textContent = "esta página no permite extensiones.";
  }
});
