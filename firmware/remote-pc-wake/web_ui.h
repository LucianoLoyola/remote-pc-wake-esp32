// Web UI served by the ESP32 at http://<DEVICE_HOSTNAME>.local
// Single self-contained page: talks to /api/state and /api/action.

#pragma once

const char WEB_UI_HTML[] PROGMEM = R"HTML(<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>WakeDesk</title>
<style>
/* WakeDesk brand colors: see docs/brand.md */
:root{--bg:#F4F7FB;--card:#FFFFFF;--text:#0B1426;--muted:#4A5B75;--line:#DCE3EE;--accent:#0E7490;--on-accent:#FFFFFF;--ok:#15803D;--warn:#B45309;--bad:#B91C1C}
@media (prefers-color-scheme:dark){:root{--bg:#0B1426;--card:#13203A;--text:#E6EDF7;--muted:#8FA3BF;--line:#22314F;--accent:#22D3EE;--on-accent:#0B1426;--ok:#22C55E;--warn:#F59E0B;--bad:#EF4444}}
*{box-sizing:border-box}
body{margin:0;font:15px/1.45 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:var(--bg);color:var(--text)}
main{max-width:560px;margin:0 auto;padding:16px}
h1{font-size:18px;margin:4px 0 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:12px}
.status{display:flex;align-items:center;gap:10px;font-size:17px;font-weight:600}
.dot{width:12px;height:12px;border-radius:50%;background:var(--muted);flex:none}
.on .dot{background:var(--ok)}.off .dot{background:var(--bad)}.warn .dot{background:var(--warn)}
.sub{color:var(--muted);font-size:13px;margin-top:6px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:12px}
.label{color:var(--muted);font-size:12px}
.value{font-size:18px;font-weight:600}
.disk{margin-top:12px}
.row{display:flex;justify-content:space-between;font-size:13px}
.bar{height:6px;background:var(--line);border-radius:3px;overflow:hidden;margin-top:4px}
.bar>i{display:block;height:100%;background:var(--accent)}
.actions{display:grid;grid-template-columns:1fr 1fr;gap:8px}
button,select{font:inherit;padding:10px;border-radius:8px;border:1px solid var(--line);background:var(--card);color:var(--text)}
button{cursor:pointer;font-weight:600}
button.primary{background:var(--accent);border-color:var(--accent);color:var(--on-accent);grid-column:1/-1}
button.danger{color:var(--bad)}
button:disabled{opacity:.4;cursor:default}
.when{display:flex;gap:8px;margin-top:8px;align-items:center}
.when select{flex:1}
.hidden{display:none}
#toast{position:fixed;left:50%;bottom:16px;transform:translateX(-50%);background:var(--text);color:var(--bg);padding:10px 14px;border-radius:8px;font-size:14px;opacity:0;transition:opacity .2s;pointer-events:none;max-width:90%}
#toast.show{opacity:1}
footer{color:var(--muted);font-size:12px;text-align:center;margin-top:8px}
</style>
</head>
<body>
<main>
<h1>WakeDesk</h1>

<section class="card">
  <div class="status" id="status"><span class="dot"></span><span id="statusText">Checking…</span></div>
  <div class="sub" id="statusSub"></div>
  <div class="sub hidden" id="pending"></div>
</section>

<section class="card hidden" id="statsCard">
  <div class="grid" id="stats"></div>
  <div id="disks"></div>
  <div class="sub hidden" id="warnings"></div>
</section>

<section class="card">
  <div class="actions">
    <button class="primary" data-action="wake">⚡ Wake PC</button>
    <button data-action="lock">🔒 Lock</button>
    <button data-action="sleep">💤 Sleep</button>
    <button data-action="restart">🔄 Restart</button>
    <button class="danger" data-action="shutdown">⏻ Shut down</button>
  </div>
  <div class="when">
    <span class="label">Restart / shut down</span>
    <select id="delay">
      <option value="0">Now</option>
      <option value="900">In 15 min</option>
      <option value="1800">In 30 min</option>
      <option value="3600">In 1 hour</option>
      <option value="7200">In 2 hours</option>
    </select>
    <button data-action="cancel">Cancel</button>
  </div>
  <div class="sub" id="agentNote"></div>
</section>

<footer id="footer"></footer>
</main>
<div id="toast"></div>

<script>
const $ = id => document.getElementById(id);
let state = null, busy = false;

function duration(s) {
  s = Math.max(0, s | 0);
  const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
  return d ? `${d}d ${h}h` : h ? `${h}h ${m}m` : `${m}m`;
}

function el(tag, cls, text) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (text !== undefined) e.textContent = text;
  return e;
}

function toast(message) {
  const t = $('toast');
  t.textContent = message;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 4000);
}

async function load(refresh) {
  try {
    const r = await fetch('/api/state' + (refresh ? '?refresh=1' : ''), { cache: 'no-store' });
    if (!r.ok) throw new Error();
    state = await r.json();
    render();
  } catch (e) {
    $('status').className = 'status warn';
    $('statusText').textContent = 'ESP32 not reachable';
  }
}

function render() {
  const s = state, a = s.agent;
  const labels = {
    on: ['PC is on', 'on'],
    off: ['PC is off', 'off'],
    agent_down: ['PC is on, agent not responding', 'warn'],
    unknown: ['Checking…', '']
  };
  let [text, cls] = labels[s.pc] || labels.unknown;
  if (s.expectation === 'wake') { text = 'Waking up…'; cls = 'warn'; }
  $('status').className = 'status ' + cls;
  $('statusText').textContent = text;

  let sub = '';
  const user = a && a.user ? a.user.split('\\').pop() : '';  // "PC\user" -> "user"
  if (a) sub = [a.hostname, user, 'up ' + duration(a.uptimeSeconds)].filter(Boolean).join(' · ');
  else if (s.pc === 'agent_down') sub = 'Agent: ' + s.agentError;
  $('statusSub').textContent = sub;

  const p = a && a.pendingAction;
  $('pending').classList.toggle('hidden', !p);
  if (p) $('pending').textContent = `⏰ Scheduled ${p.action} in ${duration(p.secondsRemaining)}`;

  $('statsCard').classList.toggle('hidden', !a);
  if (a) {
    const items = [['CPU', a.cpuPercent + '%'], ['RAM', `${a.memory.usedPercent}% of ${a.memory.totalGB} GB`]];
    if (a.gpu) items.push(['GPU', `${a.gpu.temperatureC} °C · ${a.gpu.utilizationPercent}%`]);
    $('stats').replaceChildren(...items.map(([label, value]) => {
      const box = el('div');
      box.append(el('div', 'label', label), el('div', 'value', value));
      return box;
    }));
    $('disks').replaceChildren(...a.disks.map(d => {
      const box = el('div', 'disk'), row = el('div', 'row'), bar = el('div', 'bar'), fill = el('i');
      row.append(el('span', '', d.drive), el('span', '', `${d.usedPercent}% · ${d.freeGB} GB free`));
      fill.style.width = d.usedPercent + '%';
      bar.append(fill);
      box.append(row, bar);
      return box;
    }));
    $('warnings').classList.toggle('hidden', !a.warnings.length);
    $('warnings').textContent = a.warnings.map(w => '⚠️ ' + w).join('  ');
  }

  document.querySelectorAll('button[data-action]').forEach(b => {
    const isWake = b.dataset.action === 'wake';
    b.disabled = busy || (isWake ? (s.pc === 'on' || s.pc === 'agent_down') : !(s.pc === 'on' && s.agentConfigured));
  });
  $('agentNote').textContent = s.agentConfigured ? '' : 'PC agent not configured: only Wake is available.';
  $('footer').textContent = `ESP32 ${s.esp.version} · up ${duration(s.esp.uptimeSeconds)} · Wi-Fi ${s.esp.rssi} dBm`;
}

const confirmText = {
  shutdown: 'Shut down the PC? Unsaved work will be lost.',
  restart: 'Restart the PC? Unsaved work will be lost.',
  sleep: 'Put the PC to sleep?'
};

document.querySelectorAll('button[data-action]').forEach(b => b.addEventListener('click', async () => {
  const action = b.dataset.action;
  const delay = (action === 'shutdown' || action === 'restart') ? Number($('delay').value) : 0;
  if (confirmText[action] && !confirm(confirmText[action] + (delay ? ` (in ${duration(delay)})` : ''))) return;
  busy = true;
  render();
  try {
    const r = await fetch(`/api/action?name=${action}&delay=${delay}`, {
      method: 'POST',
      headers: { 'X-Requested-By': 'remote-pc-wake' }
    });
    toast((await r.json()).message);
  } catch (e) {
    toast('Request failed');
  }
  busy = false;
  await load(true);
}));

load(true);
setInterval(() => load(false), 10000);
</script>
</body>
</html>
)HTML";
