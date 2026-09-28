import {scenarios, getScenario} from './showcase-model.mjs';

const byId = id => document.getElementById(id);
const menu = byId('scenario-menu');
const timeline = byId('timeline');
let active = scenarios[0];
let displayed = 0;
let timer;

function setText(id, value) { byId(id).textContent = String(value); }
function stop() {
  if (timer) clearInterval(timer);
  timer = undefined;
  byId('play').disabled = false;
}
function renderSteps() {
  timeline.replaceChildren();
  active.steps.forEach(([label, description], index) => {
    const item = document.createElement('li');
    item.className = index < displayed ? 'step complete' : 'step waiting';
    const marker = document.createElement('span');
    marker.className = 'step-marker';
    marker.textContent = String(index + 1).padStart(2, '0');
    const copy = document.createElement('div');
    const heading = document.createElement('strong');
    heading.textContent = label;
    const detail = document.createElement('p');
    detail.textContent = description;
    copy.append(heading, detail);
    item.append(marker, copy);
    timeline.append(item);
  });
  const done = displayed === active.steps.length;
  setText('state', done ? ({delivered: '已交付', rejected: '已拒绝', dead_lettered: '死信'}[active.outcome]) : '等待模拟');
  byId('state').className = 'state ' + (done ? active.outcome : 'idle');
  setText('accepted', done ? active.accepted : '—');
  setText('attempts', done ? active.attempts : '—');
  setText('effects', done ? active.businessEffects : '—');
  setText('progress', `${displayed} / ${active.steps.length} 步`);
}
function select(id) {
  const selected = getScenario(id);
  if (!selected) return;
  stop();
  active = selected;
  displayed = 0;
  setText('role', selected.role);
  setText('scenario-title', selected.title);
  setText('scenario-description', selected.description);
  for (const button of menu.querySelectorAll('button')) {
    const current = button.dataset.scenario === id;
    button.setAttribute('aria-pressed', String(current));
    button.classList.toggle('selected', current);
  }
  renderSteps();
}

for (const scenario of scenarios) {
  const button = document.createElement('button');
  button.type = 'button';
  button.dataset.scenario = scenario.id;
  button.className = 'scenario-button';
  const role = document.createElement('span');
  role.textContent = scenario.role;
  const title = document.createElement('strong');
  title.textContent = scenario.title;
  button.append(role, title);
  button.addEventListener('click', () => select(scenario.id));
  menu.append(button);
}
byId('play').addEventListener('click', () => {
  stop();
  displayed = 0;
  renderSteps();
  byId('play').disabled = true;
  timer = setInterval(() => {
    displayed++;
    renderSteps();
    if (displayed === active.steps.length) stop();
  }, 650);
});
byId('reset').addEventListener('click', () => { stop(); displayed = 0; renderSteps(); });
select(active.id);
