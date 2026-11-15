'use strict';

const $ = (id) => document.getElementById(id);

const GATES = [
  { key: 'secrets', name: 'Secrets', tool: 'Gitleaks', rule: 'Any committed credential fails the build.' },
  { key: 'sonar', name: 'Code quality', tool: 'SonarQube', rule: 'Quality Gate must pass: no new bugs or vulnerabilities, coverage ≥ 80% on new code.' },
  { key: 'iac', name: 'Infrastructure', tool: 'tfsec · Checkov', rule: 'HIGH / CRITICAL Terraform & K8s misconfigs fail the build.' },
  { key: 'trivy', name: 'Container', tool: 'Trivy', rule: 'Any fixable CRITICAL CVE in the image fails the build.' },
  { key: 'zap', name: 'Runtime', tool: 'OWASP ZAP', rule: 'Baseline scan of the running app; any FAIL rule breaks the build.' },
  { key: 'deploy', name: 'Deploy', tool: 'Kubernetes', rule: 'Rolling update; auto-rollback if the rollout is unhealthy.' },
];

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function api(path, opts) {
  const res = await fetch(path, { headers: { 'content-type': 'application/json' }, ...opts });
  if (res.status === 204) return null;
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || `HTTP ${res.status}`);
  return body;
}

function timeAgo(iso) {
  const s = Math.max(1, Math.round((Date.now() - new Date(iso)) / 1000));
  if (s < 60) return `${s}s ago`;
  if (s < 3600) return `${Math.round(s / 60)}m ago`;
  if (s < 86400) return `${Math.round(s / 3600)}h ago`;
  return `${Math.round(s / 86400)}d ago`;
}

/* ---------- build info ---------- */
async function loadInfo() {
  const info = await api('/api/info');
  $('build').textContent = `#${info.build}`;
  $('version').textContent = info.version;
  $('commit').textContent = String(info.commit).slice(0, 12);
  $('image').textContent = info.image;
  $('image').title = info.image;
  $('pod').textContent = info.pod;
  $('deployed').textContent = info.deployedAt ? `${new Date(info.deployedAt).toLocaleString()} · ${timeAgo(info.deployedAt)}` : 'not deployed by pipeline';
  const pill = $('env-pill');
  pill.textContent = `ENV ${info.environment}`;
  pill.classList.toggle('prod', info.environment === 'production');
}

/* ---------- gates + findings ---------- */
function gateResult(key, s) {
  if (!s || s.source === 'none') return { text: key === 'deploy' ? 'running' : 'run in pipeline', warn: false };
  switch (key) {
    case 'secrets': return { text: `${s.gitleaks?.leaks ?? 0} leaks` };
    case 'sonar': return { text: `gate ${String(s.sonar?.qualityGate || 'OK').toLowerCase()}` };
    case 'iac': return { text: `${s.iac?.failedHighCritical ?? 0} high/crit` };
    case 'trivy': {
      const t = s.trivy || {};
      return { text: `${t.CRITICAL || 0} crit · ${t.HIGH || 0} high`, warn: (t.HIGH || 0) > 0 };
    }
    case 'zap': {
      const z = s.zap || {};
      return { text: `${z.high || 0} high · ${z.medium || 0} med`, warn: (z.medium || 0) > 0 };
    }
    case 'deploy': return { text: 'rolled out' };
    default: return { text: '—' };
  }
}

function renderGates(summary) {
  const track = $('track');
  track.innerHTML = GATES.map((g, i) => {
    const r = gateResult(g.key, summary);
    return `<li class="gate${r.warn ? ' warn' : ''}" data-i="${i}">
      <span class="lamp">${r.warn ? '!' : '✓'}</span>
      <div class="gate-card">
        <h3>${esc(g.name)}</h3>
        <span class="tool">${esc(g.tool)}</span>
        <p class="rule">${esc(g.rule)}</p>
        <div class="result">${esc(r.text)}</div>
      </div>
    </li>`;
  }).join('');
  // light the checkpoints one by one
  [...track.children].forEach((el, i) => setTimeout(() => el.classList.add('lit'), 180 + i * 220));
}

function renderBars(el, rows) {
  const max = Math.max(1, ...rows.map((r) => r.n));
  el.innerHTML = rows.map((r) => `<li class="sev-${r.sev}"><span class="name">${r.label}</span><span class="rail"><span class="fill"></span></span><span class="n">${r.n}</span></li>`).join('');
  requestAnimationFrame(() => {
    [...el.querySelectorAll('.fill')].forEach((f, i) => { f.style.width = `${(rows[i].n / max) * 100}%`; });
  });
}

async function loadScans() {
  const s = await api('/api/scans').catch(() => null);
  const real = s && s.source !== 'none';
  $('scan-source').textContent = real ? `source: build #${s.build ?? '—'}` : 'source: local (no pipeline data)';
  renderGates(s);
  const t = (real && s.trivy) || {};
  const z = (real && s.zap) || {};
  renderBars($('trivy-bars'), [
    { sev: 'critical', label: 'critical', n: t.CRITICAL || 0 },
    { sev: 'high', label: 'high', n: t.HIGH || 0 },
    { sev: 'medium', label: 'medium', n: t.MEDIUM || 0 },
    { sev: 'low', label: 'low', n: t.LOW || 0 },
  ]);
  renderBars($('zap-bars'), [
    { sev: 'high', label: 'high', n: z.high || 0 },
    { sev: 'medium', label: 'medium', n: z.medium || 0 },
    { sev: 'low', label: 'low', n: z.low || 0 },
    { sev: 'info', label: 'info', n: z.info || 0 },
  ]);
}

/* ---------- release log ---------- */
async function loadLog() {
  const items = await api('/api/releases');
  $('log-count').textContent = items.length;
  $('log').innerHTML = items.map((i) => `<li>
      <span class="tag ${esc(i.severity)}">${esc(i.severity)}</span>
      <span class="t">${esc(i.title)}<span class="when">${timeAgo(i.createdAt)}</span></span>
      <button class="del" data-id="${esc(i.id)}" aria-label="Delete entry">✕</button>
    </li>`).join('') || '<li><span></span><span class="t muted">No entries yet.</span></li>';
}

$('log-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const form = e.currentTarget;
  const data = Object.fromEntries(new FormData(form));
  $('form-error').textContent = '';
  try {
    await api('/api/releases', { method: 'POST', body: JSON.stringify(data) });
    form.reset();
    await loadLog();
  } catch (err) {
    $('form-error').textContent = `✕ ${err.message}`;
  }
});

$('log').addEventListener('click', async (e) => {
  const btn = e.target.closest('.del');
  if (!btn) return;
  await api(`/api/releases/${encodeURIComponent(btn.dataset.id)}`, { method: 'DELETE' }).catch(() => {});
  loadLog();
});

/* ---------- health + clock ---------- */
async function ping() {
  const h = $('health');
  const t0 = performance.now();
  try {
    const res = await fetch('/healthz', { cache: 'no-store' });
    if (!res.ok) throw new Error();
    h.className = 'health ok';
    $('health-text').textContent = `healthy · ${Math.round(performance.now() - t0)}ms`;
  } catch {
    h.className = 'health down';
    $('health-text').textContent = 'unreachable';
  }
}

function tick() { $('clock').textContent = new Date().toLocaleTimeString([], { hour12: false }); }

tick(); setInterval(tick, 1000);
ping(); setInterval(ping, 10000);
loadInfo().catch(() => {});
loadScans();
loadLog().catch(() => {});
