const fallbackStatusUrl = "./data/status.sample.json";
const apiStatusUrl = "/api/status";

const field = (name) => document.querySelector(`[data-field="${name}"]`);

const stateText = {
  active: "Active",
  inactive: "Inactive",
  failed: "Failed",
  blocked: "Blocked",
  ok: "OK",
  warning: "Warning"
};

function setField(name, value) {
  const node = field(name);
  if (node) node.textContent = value;
}

function formatTime(value) {
  if (!value) return "--";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleTimeString("zh-CN", { hour: "2-digit", minute: "2-digit" });
}

function classForState(state) {
  if (state === "active" || state === "ok" || state === true) return "ok";
  if (state === "failed") return "danger";
  if (state === "blocked" || state === "warning" || state === false) return "warning";
  return "neutral";
}

function renderServices(services) {
  const target = document.getElementById("serviceList");
  target.innerHTML = services.map((service) => {
    const tone = classForState(service.state);
    return `
      <div class="service-row">
        <div class="service-meta">
          <span class="dot ${tone}"></span>
          <div>
            <strong>${service.name}</strong>
            <span>${service.scope} · ${service.unit}</span>
          </div>
        </div>
        <div class="service-state">
          <span class="status-pill ${tone}">${stateText[service.state] || service.state}</span>
          <small>${service.detail}</small>
        </div>
      </div>
    `;
  }).join("");
}

function renderSafetyChecks(checks) {
  const target = document.getElementById("safetyChecks");
  target.innerHTML = checks.map((check) => {
    const tone = classForState(check.state);
    return `
      <div class="check-row">
        <span class="dot ${tone}"></span>
        <span>${check.label}</span>
        <strong>${check.value}</strong>
      </div>
    `;
  }).join("");
}

function renderEvents(events) {
  const target = document.getElementById("eventList");
  target.innerHTML = events.map((event) => `
    <div class="event-row">
      <time>${event.time}</time>
      <span>${event.message}</span>
    </div>
  `).join("");
}

function renderStatus(status) {
  setField("lan_url", status.device.lan_url);
  setField("device_name", status.device.name);
  setField("current_stream", status.streams.current);
  setField("signal_percent", `${status.device.network.signal_percent}%`);
  setField("effective_output", status.audio.effective_output);
  setField("default_volume", `${status.audio.default_volume}%`);
  setField("cpu_temp", `${status.device.cpu_temp_c.toFixed(1)}°C`);
  setField("uptime", status.device.uptime);
  setField("hostname", status.device.hostname);
  setField("ip", status.device.ip);
  setField("rootfs", status.device.rootfs);
  setField("disk_used", `${status.device.disk_used_percent}%`);
  setField("mdns", status.device.network.mdns);
  setField("internet", status.device.network.internet);
  setField("safety_summary", status.safety.summary);
  setField("default_sink", status.audio.default_sink);
  setField("downstream", status.audio.safe_sink.downstream);
  setField("output_mode", status.audio.output_mode);
  setField("pipewire_version", status.audio.pipewire_version);
  setField("wireplumber_version", status.audio.wireplumber_version);
  setField("safe_gain", status.audio.safe_sink.current_gain);
  setField("streams_count", `${status.streams.playing} / ${status.streams.total} playing`);
  setField("generated_at", `更新 ${formatTime(status.generated_at)}`);

  const safetyPill = field("safety_level");
  safetyPill.textContent = status.safety.level === "ok" ? "Safe" : "Safety Warning";
  safetyPill.className = `status-pill ${classForState(status.safety.level)}`;

  const ka11Pill = field("ka11_state");
  const ka11Ok = status.audio.ka11_usb && status.audio.ka11_sink;
  ka11Pill.textContent = ka11Ok ? "KA11 seen" : "KA11 missing";
  ka11Pill.className = `status-pill ${classForState(ka11Ok)}`;

  renderServices(status.services);
  renderSafetyChecks(status.safety.checks);
  renderEvents(status.events);
}

async function fetchStatus() {
  try {
    const response = await fetch(apiStatusUrl, { cache: "no-store" });
    if (!response.ok) throw new Error(`API status ${response.status}`);
    return await response.json();
  } catch (_error) {
    const response = await fetch(fallbackStatusUrl, { cache: "no-store" });
    return await response.json();
  }
}

async function refresh() {
  const button = document.getElementById("refreshButton");
  button.classList.add("is-loading");
  try {
    renderStatus(await fetchStatus());
  } finally {
    button.classList.remove("is-loading");
  }
}

document.getElementById("refreshButton").addEventListener("click", refresh);
refresh();
