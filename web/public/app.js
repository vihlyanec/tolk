import {parseQuick} from './smart.js';
import {dayAndTime} from './model.js';
import * as Pomodoro from './pomodoro.js';
import {Client, api} from './sync.js';
const client = new Client();
const root = document.querySelector('#app');
const editor = document.querySelector('#editor');
let view = 'all', projectID = '', selectedDay = '', search = '', session = {}, noticeTimer;
let showCompleted = false;
const paths = {
  flag: '<path d="M5 21V3m0 0c4-3 8 3 14 0v10c-6 3-10-3-14 0"/>',
  timer: '<circle cx="12" cy="13" r="8"/><path d="M9 2h6m-3 0v3m0 4v5l3 2m4-12 2 2"/>',
  today: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.5 1.5m11 11L19 19M5 19l1.5-1.5m11-11L19 5"/>',
  inbox: '<path d="M4 4h16l2 12v4H2v-4L4 4Z"/><path d="M2 15h6l2 3h4l2-3h6"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 11h18m-13 5h2m4 0h2"/>',
  projects: '<path d="M3 7V5a2 2 0 0 1 2-2h5l3 3h6a2 2 0 0 1 2 2v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"/>',
  account: '<circle cx="12" cy="8" r="4"/><path d="M4 21v-2a8 8 0 0 1 16 0v2"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  chevron: '<path d="m9 5 7 7-7 7"/>',
  back: '<path d="m14 5-7 7 7 7"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  search: '<circle cx="10" cy="10" r="6"/><path d="m15 15 5 5"/>',
  cloud: '<path d="M6 18a5 5 0 0 1-1-10 7 7 0 0 1 13-1 5.5 5.5 0 0 1 0 11M9 13l3-3 3 3m-3-3v11"/>',
  menu: '<path d="M5 6h14M5 12h14M5 18h14"/>',
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  tasks: '<rect x="4" y="4" width="16" height="16" rx="3"/><path d="m8 12 3 3 5-7"/>',
  all: '<path d="M9 5h12M9 12h12M9 19h12m-18-14h1m-1 7h1m-1 7h1"/>',
  settings: '<path d="m12 2 8 5v10l-8 5-8-5V7Z"/><circle cx="12" cy="12" r="3"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
  close: '<path d="m6 6 12 12M6 18 18 6"/>',
  trash: '<path d="M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7m4-7v7"/>',
  filter: '<path d="M3 5h18M3 12h11M3 19h7m5-6h7m-3-3v6"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.65" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${name === 'calendar' ? '<rect x="4" y="5" width="16" height="16" rx="3"/><path d="M8 3v4m8-4v4"/><text x="12" y="17.5" text-anchor="middle" font-size="9" font-weight="600" stroke="none" fill="currentColor">' + Number(today().slice(-2)) + '</text>' : paths[name] || paths.projects}</svg>`;
const escape = text => String(text ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const settings = () => client.records('settings')[0]?.data || {};
const today = () => new Intl.DateTimeFormat('en-CA', {timeZone: settings().timeZone || 'Europe/Moscow', year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());
const dateLabel = date => new Date(date + 'T12:00:00').toLocaleDateString('ru-RU', {day:'numeric', month:'long'});
const projects = () => client.records('project').filter(r => !r.data.deleted && !r.data.archived);
const tags = () => client.records('tag').filter(r => !r.data.deleted);
const hiddenProject=id=>client.records('project').some(p=>p.id===id&&(p.data.deleted||p.data.archived));
const tagFamily=(id,seen=new Set())=>{if(seen.has(id))return seen;seen.add(id);tags().filter(t=>(t.data.parentID||'').toLowerCase()===id.toLowerCase()).forEach(t=>tagFamily(t.id,seen));return seen;};
const notesView = () => view === 'notes' || (view === 'projects' && projects().find(r=>r.id===projectID)?.data.itemKind === 'note');
const projectName = id => projects().find(p => p.id === id)?.data.title || 'Входящие';
function notify(message) {
  const notice = document.querySelector('#notice');
  notice.textContent = message; notice.hidden = false;
  clearTimeout(noticeTimer); noticeTimer = setTimeout(() => {notice.hidden = true;}, 5000);
}
function guarded(action) { return async event => {try {await action(event);} catch (error) {notify(error.message);}}; }
function applyTheme() {
  const theme = settings().theme || 'dark';
  document.documentElement.dataset.theme = theme;
  const dark = theme === 'dark' || (theme === 'system' && matchMedia('(prefers-color-scheme: dark)').matches);
  document.querySelector('meta[name=theme-color]').content = dark ? '#1e1e1e' : '#ffffff';
}
function renderLogin() {
  root.innerHTML = `<main class="login"><div class="login-brand"><img src="/brand.png" width="52" height="52" alt=""><span>Толк</span></div>
    <h1>${session.canSetup ? 'Ваше пространство' : 'С возвращением'}</h1>
    <p>${session.canSetup ? 'Создайте личный аккаунт для задач и настроек.' : 'Войдите, чтобы открыть свои задачи.'}</p>
    <form id="login-form"><label>Имя аккаунта<input name="name" autocomplete="username" required maxlength="80" autocapitalize="none"></label>
    <label>Пароль<input name="password" type="password" autocomplete="${session.canSetup ? 'new-password' : 'current-password'}" required ${session.canSetup ? 'minlength="12"' : ''} maxlength="256"></label>
    ${session.activationRequired ? '<label>Код активации<input name="setupCode" type="password" autocomplete="off" required maxlength="128"></label>' : ''}
    ${session.canSetup ? '<p class="hint">Не меньше 12 символов. Сохраните пароль: восстановление доступа ещё не подключено.</p>' : ''}
    <p id="login-error" class="error" role="alert"></p><button class="primary" type="submit">${session.canSetup ? 'Создать аккаунт' : 'Войти'}</button></form>
    <p class="local-note">Ваши задачи на Mac и iPhone.<br>Mac подключается в настройках приложения → Аккаунт.</p></main>`;
  document.querySelector('#login-form').onsubmit = async event => {
    event.preventDefault();
    const form = event.target, button = form.querySelector('button'); button.disabled = true;
    try {
      const result = await api(session.canSetup ? 'setup' : 'login', Object.fromEntries(new FormData(form)));
      await client.setAccount(result.account); await client.sync();
    } catch (error) { document.querySelector('#login-error').textContent = error.message; }
    finally {button.disabled = false;}
  };
}
function navigate(next, id = '') {
  view = next; projectID = id; search = '';
  document.querySelector('#drawer')?.close();
  render();
  window.scrollTo({top:0, behavior:'instant'});
  if (view === 'search') document.querySelector('#search')?.focus();
}
function openMenu() {
  const drawer = document.querySelector('#drawer');
  const active = client.records('task').filter(r => !r.data.deleted && !r.data.completed);
  const rows = [
    ['today','Сегодня','calendar',active.filter(r => r.data.date && r.data.date <= today()).length],
    ['inbox','Входящие','inbox',active.filter(r => !r.data.projectID).length],
    ['all','Все задачи','all',active.length],
    ['projects','Проекты','projects',projects().length],
    ['notes','Заметки','projects',client.records('task').filter(r=>!r.data.deleted&&r.data.itemKind==='note').length],
    ['tags','Метки','filter',tags().length],
  ];
  const name = client.account.name;
  const initials = name.trim().split(/\s+/).slice(0,2).map(part => part[0]).join('').toLocaleUpperCase();
  drawer.innerHTML = `<div class="drawer-layout"><header class="drawer-profile"><button class="profile" data-view="account"><span class="avatar">${escape(initials)}</span><strong>${escape(name)}</strong></button><div class="profile-tools"><button aria-label="Состояние синхронизации" id="drawer-sync">${icon('bell')}${client.state.conflicts.length ? '<i></i>' : ''}</button><button aria-label="Настройки" data-view="account">${icon('settings')}</button></div></header>
    <button class="drawer-shortcut" data-view="projects"><span>${icon('projects')}</span>Проекты</button>
    <nav class="drawer-links" aria-label="Списки задач">${rows.map(([id,label,symbol,count]) => `<button data-view="${id}" ${view === id && !projectID ? 'aria-current="page"' : ''}><span class="drawer-symbol">${icon(symbol)}</span><span>${label}</span><small>${count || ''}</small></button>`).join('')}
    ${projects().map(project => `<button data-project="${project.id}" ${projectID === project.id ? 'aria-current="page"' : ''}><span class="drawer-symbol project-folder">${icon('projects')}</span><span>${escape(project.data.title)}</span><small>${active.filter(r => r.data.projectID === project.id).length || ''}</small></button>`).join('')}
    <button id="drawer-trash"><span class="drawer-symbol">${icon('trash')}</span><span>Корзина</span><small>${client.records('task').filter(r => r.data.deleted).length || ''}</small></button></nav>
    <footer class="drawer-footer"><button class="round-button" aria-label="Новый проект" id="drawer-add">${icon('plus')}</button><button class="round-button" aria-label="Закрыть меню" id="drawer-close">${icon('close')}</button><button class="round-button" aria-label="Настройки списка" id="drawer-options">${icon('filter')}</button></footer></div>`;
  drawer.querySelectorAll('[data-view]').forEach(button => button.onclick = () => navigate(button.dataset.view));
  drawer.querySelectorAll('[data-project]').forEach(button => button.onclick = () => navigate('projects',button.dataset.project));
  drawer.querySelector('#drawer-close').onclick = () => drawer.close();
  drawer.querySelector('#drawer-add').onclick = () => {drawer.close(); editProject();};
  drawer.querySelector('#drawer-sync').onclick = () => {drawer.close(); openActivity();};
  drawer.querySelector('#drawer-options').onclick = () => {drawer.close(); openListOptions();};
  drawer.querySelector('#drawer-trash').onclick = () => {navigate('account'); document.querySelector('#trash-section')?.scrollIntoView();};
  drawer.onclick = event => {if(event.target === drawer && event.offsetX >= drawer.clientWidth) drawer.close();};
  if (!drawer.open) drawer.showModal();
}
function openActivity() {
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Закрыть</button><h2 id="editor-title">Синхронизация</h2><button type="submit" class="text-button">Обновить</button></header><div class="editor-content"><p>${escape(client.status || 'Подключаемся…')}</p><p class="hint">${client.state.pending.length ? 'Ожидают отправки: ' + client.state.pending.length : 'Очередь отправки пуста.'}</p><p class="hint">${client.state.lastSync ? 'Последнее обновление: ' + escape(new Date(client.state.lastSync).toLocaleString('ru-RU')) : 'Первое обновление ещё не выполнено.'}</p><p class="hint">Фоновые напоминания включаются в настройках на каждом устройстве.</p><p role="alert" class="error"></p></div></form>`, () => client.sync());
}
function openListOptions() {
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Отмена</button><h2 id="editor-title">Вид списка</h2><button type="submit" class="text-button">Готово</button></header><div class="editor-content"><label class="check-setting"><input name="completed" type="checkbox" ${showCompleted ? 'checked' : ''}>Показывать выполненные</label><p class="hint">Настройка сохраняется в аккаунте и применяется на Mac и iPhone.</p><button type="button" class="secondary" id="options-search">Найти задачу</button><button type="button" class="secondary" id="options-sync">Синхронизировать</button><p role="alert" class="error"></p></div></form>`, async form => {showCompleted = form.has('completed');await client.mutate('settings',client.account.id,{showCompleted});render();});
  editor.querySelector('#options-search').onclick = () => {editor.close(); navigate('search');};
  editor.querySelector('#options-sync').onclick = () => {editor.close(); void client.sync();};
}
function render() {
  applyTheme();
  showCompleted=settings().showCompleted ?? false;
  if (!client.account) {
    document.querySelector('#drawer')?.close();
    if (editor.open) editor.close();
    return renderLogin();
  }
  const list = client.records('task').filter(r => !r.data.deleted && (notesView() ? r.data.itemKind === 'note' : r.data.itemKind !== 'note') && !hiddenProject(r.data.projectID));
  const titles = {today:'Сегодня', inbox:'Входящие', all:'Все задачи', search:'Поиск', calendar:'Календарь', projects:'Проекты', account:'Настройки', focus:'Помодоро',notes:'Заметки',tags:'Метки',tag:'Метка'};
  const title = projectID && view === 'projects' ? projectName(projectID) : view === 'tag' ? tags().find(r=>r.id===projectID)?.data.title || 'Метка' : titles[view];
  const problem = client.state.pending.length || client.state.conflicts.length || client.authRequired || client.status.startsWith('Без связи');
  const dock = [['all','Задачи','tasks'],['calendar','Календарь','calendar'],['notes','Заметки','projects'],['focus','Помодоро','timer'],['account','Настройки','settings']];
  root.innerHTML = `<div class="shell ${view==='calendar'?'calendar-shell':''}"><aside class="native-rail"><img src="/brand.png" width="32" height="32" alt="Толк">${dock.map(([id,label,symbol])=>`<button data-view="${id}" aria-label="${label}" ${view===id?'aria-current="page"':''}>${icon(symbol)}</button>`).join('')}</aside>
    <aside class="native-sidebar"><label class="sidebar-search">${icon('search')}<input id="sidebar-search" type="search" placeholder="Поиск задач и заметок" aria-label="Поиск задач и заметок"></label><nav aria-label="Списки">${[['all','Все','all'],['inbox','Входящие','inbox'],['today','Сегодня','today']].map(([id,label,symbol])=>`<button data-view="${id}" ${view===id?'aria-current="page"':''}>${icon(symbol)}<span>${label}</span><small>${client.records('task').filter(r=>!r.data.deleted&&!r.data.completed&&r.data.itemKind!=='note'&&(id==='inbox'?!r.data.projectID:id==='today'?r.data.date&&r.data.date<=today():true)).length}</small></button>`).join('')}</nav><div class="sidebar-heading">Проекты<button id="sidebar-add-project" aria-label="Добавить проект">${icon('plus')}</button></div><nav>${projects().map(p=>`<button data-project="${p.id}" ${projectID===p.id?'aria-current="page"':''}><i class="project-dot" data-color="${escape(p.data.color)}"></i><span>${escape(p.data.title)}</span></button>`).join('')}</nav><div class="sidebar-heading">Метки<button id="sidebar-add-tag" aria-label="Добавить метку">${icon('plus')}</button></div><nav>${tags().map(t=>`<button data-tag="${t.id}"><span class="tag-hash">#</span><span>${escape(t.data.title)}</span></button>`).join('')}</nav><footer><button data-view="account">${icon('cloud')}<span>${escape(client.account.name)}</span></button><button id="desktop-menu" aria-label="Открыть меню">${icon('more')}</button></footer></aside>
    <main class="workspace"><header class="page-header"><div class="toolbar"><button id="open-menu" class="round-button" aria-label="Открыть меню">${icon('menu')}</button><button id="list-options" class="round-button" aria-label="Действия со списком">${icon('more')}</button></div><h1>${escape(title)}</h1></header>
    <section ${view === 'focus' || !focusSession() ? 'hidden' : ''} class="focus-bar" aria-label="Таймер Помодоро"><button id="open-focus" aria-label="Открыть Помодоро">${icon('timer')}<span id="focus-summary">Помодоро</span></button><button id="focus-toggle" hidden></button></section>
    <div class="sync-line ${problem ? 'has-status' : ''}" role="status"><span class="sync-dot ${client.state.pending.length ? 'pending' : ''}"></span><span>${escape(client.status || 'Подключаемся…')}${client.state.pending.length ? ' · в очереди: ' + client.state.pending.length : ''}</span></div>
    ${client.authRequired ? '<button class="text-button" id="reauth">Войти снова, сохранив очередь</button>' : ''}<div id="content"></div></main>
    <nav class="navigation" aria-label="Разделы">${dock.map(([id,label,symbol]) => `<button data-view="${id}" aria-label="${label}" ${view === id || (id === 'inbox' && ['projects','all'].includes(view)) ? 'aria-current="page"' : ''}>${icon(symbol)}<span>${label}</span></button>`).join('')}</nav>
    ${!['account','focus'].includes(view) ? `<button class="add-button" id="add" aria-label="${view === 'projects' && !projectID ? 'Новый проект' : 'Новая задача'}">${icon('plus')}<span>${view === 'projects' && !projectID ? 'Проект' : notesView() ? 'Заметка' : 'Задача'}</span></button>` : ''}</div>`;
  const content = document.querySelector('#content');
  if (view === 'tags') renderTags(content);
  else if (view === 'focus') renderFocus(content);
  else if (view === 'account') renderAccount(content);
  else if (view === 'projects' && !projectID) renderProjects(content, list);
  else renderTasks(content, list);
  root.querySelectorAll('[data-view]').forEach(button => button.onclick = () => navigate(button.dataset.view));
  document.querySelector('#open-focus').onclick = openFocus;
  document.querySelector('#focus-toggle').onclick = guarded(toggleFocus);
  updateFocus();
  document.querySelector('#open-menu').onclick = openMenu;
  document.querySelector('#desktop-menu').onclick = openMenu;
  root.querySelectorAll('[data-project]').forEach(b=>b.onclick=()=>navigate('projects',b.dataset.project));
  root.querySelectorAll('[data-tag]').forEach(b=>b.onclick=()=>navigate('tag',b.dataset.tag));
  root.querySelectorAll('[data-color]').forEach(el=>{if(/^[0-9a-f]{6}$/i.test(el.dataset.color))el.style.backgroundColor='#'+el.dataset.color;});
  document.querySelector('#sidebar-add-project').onclick=editProject;
  document.querySelector('#sidebar-add-tag').onclick=editTag;
  document.querySelector('#sidebar-search').oninput=e=>{search=e.target.value;view='search';renderTasks(document.querySelector('#content'),client.records('task').filter(r=>!r.data.deleted));};

  document.querySelector('#list-options').onclick = openListOptions;
  document.querySelector('#reauth')?.addEventListener('click', () => {
    openEditor(`<form><header class="editor-header"><button class="text-button" type="button" data-cancel>Отмена</button><h2 id="editor-title">Войти снова</h2><button class="text-button" type="submit">Войти</button></header><div class="editor-content"><p>${escape(client.account.name)}</p><label>Пароль<input name="password" type="password" autocomplete="current-password" required maxlength="256" autofocus></label><p class="error" role="alert"></p></div></form>`, async form => {
      const result = await api('login', {name:client.account.name, password:form.get('password')});
      if (result.account.id !== client.account.id) throw new Error('Нужен вход в исходный аккаунт.');
      await client.sync();
    });
  });
  applyTagColors();
  document.querySelector('#add')?.addEventListener('click', () => view === 'projects' && !projectID ? editProject() : editTask());
}
function renderTasks(content, all) {
  if(view==='calendar') {
    if(matchMedia('(min-width:1100px)').matches){renderCalendar(content,all);return;}
    all=all.concat(calendarEvents());
  }
  const day = selectedDay || today();
  let list = all.filter(r => view === 'today' ? r.data.date && r.data.date <= today() && (!r.data.completed || r.data.date === today())
    : view === 'inbox' ? !r.data.projectID : view === 'calendar' ? r.data.date === day : view === 'projects' ? r.data.projectID === projectID : view === 'tag' ? (r.data.tagIDs || []).some(id=>tagFamily(projectID).has(id.toLowerCase())) : true);
  if (!showCompleted) list = list.filter(r => !r.data.completed);
  if (search) list = list.filter(r => (r.data.title + ' ' + (r.data.body || '')).toLocaleLowerCase().includes(search.toLocaleLowerCase()));
  list.sort((a, b) => Number(!!a.data.completed) - Number(!!b.data.completed) || (a.data.date || '9999').localeCompare(b.data.date || '9999') || (a.data.time || '').localeCompare(b.data.time || '') || ((a.data.order ?? 100000) - (b.data.order ?? 100000)));
  content.innerHTML = `${view === 'calendar' ? `<label class="day-picker">День<input id="calendar-day" type="date" value="${day}"></label>` : ''}
    ${view === 'search' ? `<label class="search">${icon('search')}<input id="search" type="search" placeholder="Найти задачу" aria-label="Найти задачу" value="${escape(search)}"></label>` : ''}
    ${!['search','calendar'].includes(view)?`<form id="inline-add" class="inline-capture">${icon('plus')}<input name="title" placeholder="${notesView()?'Добавить заметку…':'Добавить задачу…  12 дек в 10'}" aria-label="Быстрое добавление" required maxlength="500"><button aria-label="Добавить" type="submit">${icon('check')}</button></form>`:''}<div id="tasks" class="task-group">${list.length ? groupedRows(list) : `<div class="empty">${icon(search ? 'search' : view === 'calendar' ? 'calendar' : 'tasks')}<h3>${search ? 'Ничего не нашлось' : view === 'today' ? 'На сегодня всё спокойно' : 'Здесь пока нет задач'}</h3><p>${search ? 'Попробуйте другое слово.' : 'Нажмите плюс, чтобы записать первую.'}</p>${!search ? '<button class="text-button" id="empty-add">Добавить задачу</button>' : ''}</div>`}</div>`;
  document.querySelector('#inline-add')?.addEventListener('submit',guarded(async e=>{e.preventDefault();const input=e.target.elements.title;const title=input.value.trim();if(!title)return;const parsed=notesView()?{title,schedule:{kind:'none'},priority:0,duration:30,tagIDs:[],projectID:'',warnings:[]}:parseQuick(title,{projects:projects(),tags:tags(),zone:settings().timeZone||'Europe/Moscow'});if(!parsed.title)throw new Error('Введите название задачи.');const warnings=parsed.warnings;delete parsed.warnings;if(!parsed.projectID && view==='projects')parsed.projectID=projectID;if(parsed.schedule.kind==='none'&&view==='today')parsed.schedule={kind:'day',day:today()};await client.mutate('task',crypto.randomUUID(),{...parsed,itemKind:notesView()?'note':'task',completed:false,deleted:false});if(warnings.length)notify(warnings.join('. '));input.value='';render();document.querySelector('#inline-add input')?.focus();}));
  document.querySelector('#empty-add')?.addEventListener('click', () => editTask());
  content.querySelectorAll('[data-task]').forEach(b => b.onclick = () => {const record=all.find(r=>r.id===b.dataset.task);record.kind==='event'?openEvent(record):editTask(record);});
  content.querySelectorAll('[data-complete]').forEach(b => b.onclick = guarded(async () => {
    const task = all.find(r => r.id === b.dataset.complete);
    await client.mutate('task', task.id, {completed: !task.data.completed});
  }));
  document.querySelector('#calendar-day')?.addEventListener('change', e => {selectedDay = e.target.value; render();});
  const field = document.querySelector('#search');
  if (field) field.oninput = event => {
    search = event.target.value;
    const position = event.target.selectionStart;
    render(); const next = document.querySelector('#search'); next.focus();
    next.setSelectionRange(position, position);
  };
}
function taskDate(task) {
  if (!task.date) return '';
  const current = today();
  const day = new Date(task.date + 'T12:00:00');
  let label = task.date === current ? 'Сегодня' : day.getFullYear() !== new Date(current + 'T12:00:00').getFullYear()
    ? day.toLocaleDateString('ru-RU') : day.toLocaleDateString('ru-RU',{day:'numeric',month:'short'});
  return label + (task.time ? ', ' + task.time : '');
}
function taskRow(record) {
  const task = record.data;
  const late = !task.completed && task.date && task.date < today();
  return `<article class="task-row ${task.completed ? 'completed' : ''}"><button ${task.itemKind==='note'||record.kind==='event'?'hidden':''} class="complete priority-${task.priority || 0}" data-complete="${record.id}" aria-label="${task.completed ? 'Вернуть в работу' : 'Выполнить'}: ${escape(task.title)}" aria-pressed="${!!task.completed}">${task.completed ? icon('check') : ''}</button>
    <button class="task-body" data-task="${record.id}"><span class="task-title">${escape(task.title)}</span>${task.projectID && view !== 'projects' ? `<span class="project-label">${escape(projectName(task.projectID))}</span>` : ''}${task.priority?`<span class="priority-chip priority-${task.priority}">${icon('flag')}${['','Высокий','Средний','Низкий'][task.priority]}</span>`:''}${(task.tagIDs||[]).map(id=>tags().find(t=>t.id===id.toLowerCase())).filter(Boolean).map(t=>`<span class="tag-chip" data-tag-color="${escape(t.data.color)}">#${escape(t.data.title)}</span>`).join('')}${task.body ? `<span class="body-preview">${escape(task.body.replace(/\s+/g,' '))}</span>` : ''}${task.date ? `<span class="task-date ${late ? 'overdue' : ''}">${escape(taskDate(task))}</span>` : ''}</button></article>`;
}
function renderProjects(content, tasks) {
  const list = projects();
  content.innerHTML = `<div class="project-list">${list.length ? list.map(record => `<button class="project-row" data-project="${record.id}"><span class="project-icon">${icon('projects')}</span><span>${escape(record.data.title)}<small>${tasks.filter(t => t.data.projectID === record.id && !t.data.completed).length} в работе</small></span>${icon('chevron')}</button>`).join('') : '<div class="empty"><h3>Начните с одного проекта</h3><p>Для работы, дома или того, что давно хочется сделать.</p><button id="empty-project" class="text-button">Создать проект</button></div>'}</div>`;
  content.querySelectorAll('[data-project]').forEach(b => b.onclick = () => navigate('projects',b.dataset.project));
  document.querySelector('#empty-project')?.addEventListener('click', editProject);
}
function conflictView(conflict) {
  const op = conflict.operation;
  const local = Object.assign({}, op.patch, ...client.state.pending.filter(p => p.kind === op.kind && p.entityID === op.entityID).map(p => p.patch));
  const names = {title:'Название', body:'Описание', date:'Дата', time:'Время', completed:'Выполнение', deleted:'Удаление', projectID:'Проект', priority:'Приоритет', theme:'Оформление', timeZone:'Часовой пояс', startHour:'Начало дня', endHour:'Конец дня', pushEnabled:'Напоминания', focusSession:'Сеанс Помодоро'};
  const display = (field, value) => {
    if (value === undefined || value === null || value === '') return 'Не задано';
    if (field === 'focusSession') { const timer = Pomodoro.decode(value); return timer ? `Помодоро: ${timer.title} · ${timer.phase === 'focus' ? 'фокус' : 'перерыв'}` : 'Нет сеанса'; }
    if (field === 'projectID') return projectName(value);
    if (field === 'completed') return value ? 'Выполнена' : 'В работе';
    if (field === 'deleted') return value ? 'Удалена' : 'Сохранена';
    if (field === 'priority') return ['Без приоритета','Высокий','Средний','Низкий'][value];
    if (field === 'theme') return {system:'Как на устройстве',dark:'Тёмное',light:'Светлое'}[value];
    if (field === 'date') return dateLabel(value);
    return String(value);
  };
  return `<div class="conflict"><h3>${escape(conflict.remote.data.title || 'Настройки')}</h3>${Object.keys(local).map(field => `<div class="version-field"><strong>${escape(names[field] || field)}</strong><div class="version-pair"><div><small>На сервере</small><p>${escape(display(field, conflict.remote.data[field]))}</p></div><div><small>На устройстве</small><p>${escape(display(field, local[field]))}</p></div></div></div>`).join('')}<div class="button-pair"><button class="secondary" data-resolve="${op.id}" data-local="true">Моя версия</button><button class="secondary" data-resolve="${op.id}" data-local="false">С сервера</button></div></div>`;
}
function renderAccount(content) {
  const prefs = settings();
  const baseline = client.records('settings')[0] || {version:0, data:{}};
  const trash = client.records('task').filter(r => r.data.deleted);
  content.innerHTML = `${client.state.serverReset?'<section class="settings-section"><h2>Сервер восстановлен</h2><p>Локальные изменения сохранены. Сверьте версии перед отправкой.</p><button id="recover-server" class="secondary">Сверить версии</button></section>':''}<section class="settings-section"><h2>Ваши настройки</h2><form id="preferences">
    <label class="setting-row">Оформление<select name="theme"><option value="system">Как на устройстве</option><option value="light">Светлое</option><option value="dark">Тёмное</option></select></label>
    <label class="setting-row">Часовой пояс<input name="timeZone" value="${escape(prefs.timeZone || 'Europe/Moscow')}" required></label>
    <div class="setting-hours"><label>Начало дня<input name="startHour" type="number" min="0" max="23" value="${prefs.startHour ?? 7}"></label><label>Конец дня<input name="endHour" type="number" min="1" max="24" value="${prefs.endHour ?? 23}"></label></div>
    <button class="secondary" type="submit">Сохранить настройки</button></form><p class="hint">Сохраняются в аккаунте и доступны на Mac и iPhone.</p></section>
    <section class="settings-section"><h2>Подключения и уведомления</h2>
    <div class="integration"><strong>TickTick</strong><span>${prefs.integrations?.tickTick?.configured?'Подключён через Mac. Изменения отправляются, когда Mac в сети.':'Подключается в настройках Толка на Mac'}</span>${prefs.integrations?.tickTick?.configured?`<label class="check-setting"><input id="tick-enabled" type="checkbox" ${prefs.integrations.tickTick.options?.enabled?'checked':''}>Синхронизировать через Mac</label>`:''}</div>
    <div class="integration"><strong>Apple Календарь</strong><span>${prefs.integrations?.appleCalendar?.configured?'События обновляются через Mac':'Подключается на Mac с разрешением macOS'}</span>${(prefs.integrations?.appleCalendar?.calendars||[]).map(c=>`<label class="check-setting"><input type="checkbox" data-apple-calendar="${escape(c.id)}" ${(prefs.integrations.appleCalendar.selected||[]).includes(c.id)?'checked':''}>${escape(c.name)}</label>`).join('')}</div>
    <div class="integration"><strong>Push-уведомления</strong><span id="push-status">На iPhone установите Толк на экран «Домой», затем разрешите уведомления.</span><label class="check-setting"><input id="push-on-time" type="checkbox" ${(prefs.defaultTimedReminderOffsets||[]).includes(0)?'checked':''}>Напоминать в назначенное время задачи</label><button class="secondary" id="enable-push">Включить на этом устройстве</button><button class="text-button" id="disable-push">Отключить на этом устройстве</button></div>
    <p class="hint">Доступ к TickTick и Apple Календарю обслуживает ваш Mac. Их ключи остаются на устройстве.</p></section>
    ${client.state.conflicts.length ? `<section class="settings-section"><h2>Выберите версию</h2><p>Одна запись изменена на разных устройствах. Выбор применяется ко всем ожидающим правкам этой записи.</p>${client.state.conflicts.map(conflictView).join('')}</section>` : ''}
    <section class="settings-section" id="trash-section"><h2>Корзина</h2>${trash.length ? trash.map(task => `<div class="trash-row"><span>${escape(task.data.title)}</span><button class="text-button" data-restore="${task.id}">Восстановить</button></div>`).join('') : '<p class="hint">Удалённых задач пока нет. Здесь их можно будет восстановить.</p>'}</section>
    <section class="settings-section"><h2>Об этой версии</h2><p class="hint">Общие задачи, заметки, проекты и настройки. Подключите этот аккаунт в приложении на Mac: Настройки → Аккаунт.</p>
    <button class="secondary" id="retry-sync">Синхронизировать сейчас</button><button class="text-button" id="logout">Выйти из аккаунта</button></section>`;
  document.querySelector('#recover-server')?.addEventListener('click',guarded(()=>client.recoverServer()));
  document.querySelector('[name=theme]').value = prefs.theme || 'dark';
  document.querySelector('#preferences').onsubmit = guarded(async event => {
    event.preventDefault(); const data = Object.fromEntries(new FormData(event.target));
    data.startHour = Number(data.startHour); data.endHour = Number(data.endHour);
    if (data.startHour >= data.endHour) throw new Error('Конец дня должен быть позже начала.');
    const changes = Object.fromEntries(Object.entries(data).filter(([key,value]) => baseline.data[key] !== value));
    if (Object.keys(changes).length) await client.mutate('settings', client.account.id, changes, baseline);
    notify('Настройки сохранены на устройстве');
  });
  document.querySelector('#tick-enabled')?.addEventListener('change',guarded(async e=>{const connections=structuredClone(prefs.integrations);connections.tickTick.options.enabled=e.target.checked;await client.mutate('settings',client.account.id,{integrations:connections},baseline);}));
  content.querySelectorAll('[data-apple-calendar]').forEach(b=>b.onchange=guarded(async()=>{const connections=structuredClone(prefs.integrations);connections.appleCalendar.selected=Array.from(content.querySelectorAll('[data-apple-calendar]:checked')).map(el=>el.dataset.appleCalendar);await client.mutate('settings',client.account.id,{integrations:connections},baseline);}));
  document.querySelector('#push-on-time').onchange=guarded(async e=>{const offsets=(prefs.defaultTimedReminderOffsets||[]).filter(v=>v!==0);if(e.target.checked)offsets.push(0);await client.mutate('settings',client.account.id,{defaultTimedReminderOffsets:offsets},baseline);});
  document.querySelector('#enable-push').onclick=guarded(enablePush);
  document.querySelector('#disable-push').onclick=guarded(disablePush);
  document.querySelector('#retry-sync').onclick = () => client.sync();
  void showDevices(content).catch(()=>{});

  document.querySelector('#logout').onclick = guarded(async () => {await client.logout(); render();});
  content.querySelectorAll('[data-resolve]').forEach(b => b.onclick = guarded(() => client.resolve(b.dataset.resolve, b.dataset.local === 'true')));
  content.querySelectorAll('[data-restore]').forEach(b => b.onclick = guarded(async () => {
    await client.mutate('task', b.dataset.restore, {deleted:false}); notify('Задача восстановлена');
  }));
}
function openEditor(html, onSave) {
  editor.innerHTML = html;
  if (!editor.open) editor.showModal();
  editor.querySelector('[data-cancel]').onclick = () => editor.close();
  editor.querySelector('form').onsubmit = async event => {
    event.preventDefault(); const button = event.target.querySelector('[type=submit]'); button.disabled = true;
    try {await onSave(new FormData(event.target)); if (editor.querySelector('form') === event.target) editor.close();}
    catch (error) {editor.querySelector('[role=alert]').textContent = error.message;}
    finally {button.disabled = false;}
  };
}
function editProject() {
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Отмена</button><h2 id="editor-title">Новый проект</h2><button type="submit" class="text-button">Создать</button></header><div class="editor-content"><label>Название<input name="title" placeholder="Например, Дом" maxlength="500" required autofocus></label><p role="alert" class="error"></p></div></form>`, async form => {
    await client.mutate('project', crypto.randomUUID(), {title: form.get('title').trim(), color:'598BFF', deleted:false});
  });
}
function editTask(record) {
  let beginFocus = false;
  const data = record?.data || {date: view === 'today' ? today() : view === 'calendar' ? selectedDay || today() : '', projectID};
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Отмена</button><h2 id="editor-title">${record ? 'Задача' : 'Новая задача'}</h2><button type="submit" class="text-button">Сохранить</button></header>
    <div class="editor-content"><label class="sr-only" for="task-title">Название</label><textarea id="task-title" class="title-input" name="title" rows="2" placeholder="Что нужно сделать?" maxlength="16000" required autofocus>${escape(data.title || '')}</textarea>
    <label>Описание<textarea name="body" rows="5" placeholder="Детали, мысли, ссылки…" maxlength="5000000">${escape(data.body || '')}</textarea></label>
    <div class="date-time"><label>Дата<input type="date" name="date" value="${escape(data.date || '')}"></label><label>Время<input type="time" name="time" value="${escape(data.time || '')}"></label></div>
    <label>Проект<select name="projectID"><option value="">Входящие</option>${projects().map(p => `<option value="${p.id}" ${p.id === data.projectID ? 'selected' : ''}>${escape(p.data.title)}</option>`).join('')}</select></label>
    <label>Приоритет<select name="priority">${['Без приоритета','Высокий','Средний','Низкий'].map((p,i) => `<option value="${i}" ${i === (data.priority || 0) ? 'selected' : ''}>${p}</option>`).join('')}</select></label>
    <div class="date-time"><label>Длительность, мин<input name="duration" type="number" min="1" max="10080" value="${data.duration||30}" required></label><label>Повтор<select name="recurrence">${[['none','Не повторять'],['daily','Каждый день'],['weekdays','По будням'],['weekly','Каждую неделю'],['monthly','Каждый месяц'],['intervalDays','Через несколько дней']].map(([id,title])=>`<option value="${id}" ${id===(data.recurrence||'none')?'selected':''}>${title}</option>`).join('')}</select></label></div>
    <div class="date-time"><label>Интервал повтора, дней<input name="repeatEveryDays" type="number" min="1" max="3650" value="${data.repeatEveryDays||3}"></label><label>Напоминание<select name="customReminder"><option value="keep">${Array.isArray(data.timedReminderOffsets)?data.timedReminderOffsets.length?data.timedReminderOffsets.map(n=>n===0?'В момент задачи':`За ${n} мин`).join(', '):'Без напоминания':'Как в настройках'}</option><option value="default">Как в настройках</option><option value="none">Не напоминать</option><option value="0">В момент задачи</option><option value="5">За 5 минут</option><option value="15">За 15 минут</option><option value="30">За 30 минут</option></select></label></div>
    <label>Раздел<input name="section" value="${escape(data.section||'Без раздела')}" maxlength="500"></label>
    ${tags().length?`<fieldset class="tag-options"><legend>Метки</legend>${tags().map(t=>`<label><input type="checkbox" name="tags" value="${t.id}" ${(data.tagIDs||[]).some(id=>id.toLowerCase()===t.id.toLowerCase())?'checked':''}>${escape(t.data.title)}</label>`).join('')}</fieldset>`:''}
    <label>Чек-лист · по одному пункту на строке<textarea name="checklist" rows="3">${escape((data.checklist||[]).map(c=>c.title).join('\n'))}</textarea></label>
    <p class="error" role="alert"></p>${record && !data.completed ? '<button id="task-focus" type="button" class="secondary">Сохранить и начать фокус</button>' : ''}${record ? '<button id="delete-task" type="button" class="delete-button">Удалить задачу</button>' : ''}</div></form>`, async form => {
    const patch = Object.fromEntries(form); patch.title = patch.title.trim(); patch.priority = Number(patch.priority);
    if (!patch.title) throw new Error('Введите название задачи.');
    if (patch.time && !patch.date) throw new Error('Выберите дату для задачи со временем.');
    if(patch.recurrence==='intervalDays')patch.repeatEveryDays=Number(patch.repeatEveryDays);else delete patch.repeatEveryDays;
    if(patch.customReminder!=='keep'){patch.timedReminderOffsets=patch.customReminder==='default'?null:patch.customReminder==='none'?[]:[Number(patch.customReminder)];if(patch.customReminder==='default')patch.reminderMinutes=null;}delete patch.customReminder;
    patch.duration=Number(form.get('duration'));patch.itemKind=data.itemKind || (notesView()?'note':'task');patch.tagIDs=form.getAll('tags');delete patch.tags;patch.checklist=(form.get('checklist')||'').split('\n').filter(t=>t.trim()).map((t,i)=>({...data.checklist?.[i],id:data.checklist?.[i]?.id || crypto.randomUUID(),title:t.trim(),done:data.checklist?.[i]?.done||false}));
    if (record) {
      for (const field of Object.keys(patch)) if (JSON.stringify(data[field] ?? (field === 'priority' ? 0 : '')) === JSON.stringify(patch[field])) delete patch[field];
    } else Object.assign(patch, {completed:false, deleted:false});
    if (Object.keys(patch).length) await client.mutate('task', record?.id || crypto.randomUUID(), patch, record);
    if (beginFocus) await startFocus(client.records('task').find(r => r.id === record.id));
  });
  document.querySelector('#task-focus')?.addEventListener('click', () => {beginFocus = true; editor.querySelector('form').requestSubmit();});
  document.querySelector('#delete-task')?.addEventListener('click', guarded(async () => {
    await client.mutate('task', record.id, {deleted:true}, record); editor.close(); notify('Задача в корзине. Восстановить можно через меню.');
  }));
}
const focusRecord = () => client.records('settings').find(r => r.id === client.account?.id);
const focusSession = () => Pomodoro.decode(focusRecord()?.data.focusSession);
let focusSaving = false, focusAudio, observedDeadline, previousFocusSeconds;
function prepareFocusSound() {
  try {
    const Audio = window.AudioContext || window.webkitAudioContext;
    if (Audio) {focusAudio ||= new Audio(); void focusAudio.resume().catch(() => {});}
  } catch { /* The countdown remains available if audio is disabled. */ }
}
function focusFinishedSound() {
  if (!focusAudio || focusAudio.state !== 'running') return;
  const tone = focusAudio.createOscillator(), gain = focusAudio.createGain();
  tone.frequency.value = 660; tone.connect(gain); gain.connect(focusAudio.destination);
  gain.gain.setValueAtTime(.12,focusAudio.currentTime);
  gain.gain.exponentialRampToValueAtTime(.001,focusAudio.currentTime + .7);
  tone.start(); tone.stop(focusAudio.currentTime + .7);
}
async function saveFocus(value, baseline = focusRecord()) {
  if (focusSaving) return;
  focusSaving = true;
  try {await client.mutate('settings', client.account.id, {focusSession:value ? JSON.stringify(value) : ''}, baseline);}
  finally {focusSaving = false; updateFocus();}
}
async function startFocus(record) {
  prepareFocusSound();
  const current = focusSession();
  if (current?.taskID === record.id) return openFocus();
  if (current && !confirm('Завершить текущий сеанс и начать фокус по другой задаче?')) return;
  await saveFocus(Pomodoro.start(record.id, record.data.title)); openFocus();
}
async function toggleFocus() {
  prepareFocusSound();
  const baseline = focusRecord(), value = Pomodoro.decode(baseline?.data.focusSession);
  if (!value) return openFocus();
  if (!Pomodoro.seconds(value)) return openFocus();
  if (value.deadline !== null) return pauseFocus();
  await saveFocus(Pomodoro.transition(value, 'resume'), baseline);
}
function updateFocus() {
  const summary = document.querySelector('#focus-summary'), toggle = document.querySelector('#focus-toggle');
  const value = client.account ? focusSession() : null;
  const left = value ? Pomodoro.seconds(value) : null;
  if (value?.deadline && value.deadline === observedDeadline && previousFocusSeconds > 0 && left === 0) {focusFinishedSound(); notify(value.phase === 'focus' ? 'Фокус завершён. Можно начать перерыв.' : 'Перерыв завершён. Можно вернуться к задаче.');}
  observedDeadline = value?.deadline; previousFocusSeconds = left;
  if (summary) summary.textContent = value ? `${value.phase === 'focus' ? 'Фокус' : 'Перерыв'} · ${Pomodoro.clock(Pomodoro.seconds(value))}${value.deadline === null && Pomodoro.seconds(value) ? ' · пауза' : ''}` : 'Помодоро · выбрать задачу';
  if (toggle) {
    toggle.hidden = !value; toggle.disabled = focusSaving;
    toggle.textContent = value && !Pomodoro.seconds(value) ? 'Готово' : value?.deadline === null ? 'Продолжить' : 'Пауза';
  }
  const panel = document.querySelector('#focus-panel');
  if (!panel) return;
  const time = panel.querySelector('#focus-clock'), action = panel.querySelector('#focus-action');
  if (value && time && action) {
    time.textContent = Pomodoro.clock(Pomodoro.seconds(value));
    panel.querySelector('#focus-phase').textContent = value.phase === 'focus' ? 'Фокус' : value.phase === 'longBreak' ? 'Длинный перерыв' : 'Перерыв';
    panel.querySelector('#focus-count').textContent = String(value.completed);
    panel.querySelector('#focus-task-name').textContent = client.records('task').find(r => r.id === value.taskID)?.data.title || value.title;
    const inline = panel.querySelector('#focus-note-inline');
    if (inline) {inline.textContent = value.resumeNote || ''; inline.parentElement.hidden = !value.resumeNote;}
    panel.querySelector('#focus-resume-note').textContent = value.resumeNote || 'При паузе можно записать следующий шаг. Это необязательно.';
    action.textContent = !Pomodoro.seconds(value) ? value.phase === 'focus' ? 'Начать перерыв' : 'Начать фокус' : value.deadline === null ? 'Продолжить' : 'Пауза';
    action.disabled = focusSaving;
  }
}
function openFocus() {
  prepareFocusSound();
  if (editor.open) editor.close();
  navigate('focus');
}
async function pauseFocus() {
  const baseline = focusRecord(), current = Pomodoro.decode(baseline?.data.focusSession);
  if (!current || current.deadline === null || !Pomodoro.seconds(current)) return;
  await saveFocus(Pomodoro.transition(current,'pause'),baseline);
  const pausedRecord = focusRecord(), paused = Pomodoro.decode(pausedRecord?.data.focusSession);
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Пропустить</button><h2 id="editor-title">С чего продолжить?</h2><button type="submit" class="text-button">Сохранить</button></header><div class="editor-content"><p>Таймер на паузе. Оставьте себе следующий шаг — или пропустите.</p><label>Заметка, необязательно<textarea name="resumeNote" rows="5" maxlength="2000" placeholder="Например, начать с третьего пункта" autofocus>${escape(paused?.resumeNote || '')}</textarea></label><p class="error" role="alert"></p></div></form>`, async form => {
    if (focusRecord()?.data.focusSession !== pausedRecord?.data.focusSession) throw new Error('Сеанс изменился на другом устройстве. Закройте окно и проверьте таймер.');
    await saveFocus({...paused,resumeNote:form.get('resumeNote').trim()},pausedRecord);
  });
}
function renderFocus(content) {
  const value = focusSession();
  content.innerHTML = `<section id="focus-panel" class="focus-workspace"><div class="focus-main"><p id="focus-phase">Фокус</p><h2 id="focus-task-name">${escape(value?.title || 'Выберите задачу для фокуса')}</h2><details class="focus-inline-note" ${value?.resumeNote ? '' : 'hidden'} ${value?.deadline === null ? 'open' : ''}><summary>С чего продолжить</summary><p id="focus-note-inline">${escape(value?.resumeNote || '')}</p></details><div class="focus-dial"><div id="focus-clock" class="focus-clock" role="timer" aria-label="Осталось времени">25:00</div></div>
    ${value ? '<button id="focus-action" class="primary" type="button">Пауза</button><button id="focus-stop" class="text-button" type="button">Завершить сеанс</button>' : ''}
    <label class="focus-select">${value ? 'Сменить задачу' : 'Начать фокус по задаче'}<select id="focus-task-picker"><option value="">Выберите задачу</option>${client.records('task').filter(r => !r.data.deleted && !r.data.completed && r.data.itemKind !== 'note').map(r => `<option value="${r.id}">${escape(r.data.title)}</option>`).join('')}</select></label>
    <p class="hint">25 минут фокуса · 5 минут отдыха.<br>После четырёх подходов — 15 минут отдыха.</p></div>
    <aside class="focus-overview"><h2>Обзор сеанса</h2><div class="focus-stat"><span>Завершено подходов</span><strong id="focus-count">0</strong></div><h3>С чего продолжить</h3><p id="focus-resume-note" class="resume-note">${escape(value?.resumeNote || 'При паузе можно записать следующий шаг. Это необязательно.')}</p><p class="hint">Сеанс сохраняется в аккаунте. Для фоновых уведомлений включите их в настройках на этом устройстве.</p></aside></section>`;
  content.querySelector('#focus-action')?.addEventListener('click',guarded(async () => {
    prepareFocusSound();
    const baseline = focusRecord(), current = Pomodoro.decode(baseline?.data.focusSession);
    if (!current || focusSaving) return;
    if (current.deadline !== null && Pomodoro.seconds(current)) return pauseFocus();
    await saveFocus(Pomodoro.transition(current, !Pomodoro.seconds(current) ? 'next' : 'resume'),baseline);
  }));
  content.querySelector('#focus-stop')?.addEventListener('click',guarded(() => saveFocus(null)));
  content.querySelector('#focus-task-picker').onchange = guarded(event => {
    const record = client.records('task').find(r => r.id === event.target.value);
    if (record) return startFocus(record);
  });
}
setInterval(updateFocus, 1000);
client.addEventListener('change', () => {
  updateFocus();
  // Preserve unsaved settings and search focus while background sync updates the header.
  if (root.contains(document.activeElement) && document.activeElement.matches('input, select, textarea')) {
    const status = document.querySelector('.sync-line span:last-child');
    if (status) status.textContent = client.status;
    return;
  }
  render();
});
addEventListener('online', () => client.sync());
addEventListener('focus', () => client.sync());
document.addEventListener('visibilitychange', () => {if (!document.hidden) void client.sync();});
setInterval(() => {if (!document.hidden) void client.sync();}, 15000);
try {
  session = await client.initialize(); render(); await client.sync();
  const requestedTask=new URL(location.href).searchParams.get('task');
  if(requestedTask){const task=client.records('task').find(r=>r.id===requestedTask);if(task)editTask(task);}
  if(new URL(location.href).searchParams.has('focus') && client.account)navigate('focus');
} catch (error) {
  root.innerHTML = `<main class="login"><h1>Не удалось открыть Толк</h1><p>${escape(error.message)}</p><button id="reload" class="primary">Попробовать ещё раз</button></main>`;
  document.querySelector('#reload').onclick = () => location.reload();
}
if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(() => notify('Не удалось подготовить приложение к работе без сети.'));

async function showPairing() {
  const code=new URL(location.href).searchParams.get('pair');if(!code || !client.account)return;
  const info=await api('device/info',{code});
  openEditor(`<form><header class="editor-header"><button type="button" class="text-button" data-cancel>Отмена</button><h2 id="editor-title">Подключить Mac</h2><button type="submit" class="text-button">Подключить</button></header><div class="editor-content"><h3>${escape(info.name)}</h3><p>Разрешить этому Mac синхронизировать задачи, заметки и настройки с аккаунтом «${escape(client.account.name)}»?</p><p class="hint">Подтверждайте только подключение, которое вы начали в своём приложении. Данные обоих устройств будут объединены. Доступ можно отозвать в настройках.</p><p class="error" role="alert"></p></div></form>`,async()=>{await api('device/approve',{code});history.replaceState(null,'','/');notify('Mac подключён. Вернитесь в приложение.');});
}
function editTag() {
  openEditor(`<form><header class="editor-header"><button type="button" data-cancel class="text-button">Отмена</button><h2 id="editor-title">Новая метка</h2><button type="submit" class="text-button">Создать</button></header><div class="editor-content"><label>Название<input name="title" required maxlength="500"></label><p class="error" role="alert"></p></div></form>`,form=>client.mutate('tag',crypto.randomUUID(),{title:form.get('title').trim(),color:'AD94E8',deleted:false,parentID:null}));
}
function renderTags(content) {
 content.innerHTML=`<div class="project-list">${tags().map(t=>`<button class="project-row" data-tag="${t.id}"><span class="tag-hash">#</span><span>${escape(t.data.title)}</span></button>`).join('')}<button id="tag-add" class="text-button">Добавить метку</button></div>`;
 content.querySelector('#tag-add').onclick=editTag;content.querySelectorAll('[data-tag]').forEach(b=>b.onclick=()=>navigate('tag',b.dataset.tag));
}
client.addEventListener('change',()=>{if(new URL(location.href).searchParams.has('pair') && client.account && !editor.open) void showPairing().catch(e=>notify(e.message));});
if(client.account && new URL(location.href).searchParams.has('pair')) await showPairing().catch(e=>notify(e.message));

async function enablePush() {
 if(!('Notification' in window) || !('PushManager' in window)) throw new Error('Добавьте Толк на экран «Домой» и откройте его оттуда. Для iPhone нужна iOS 16.4 или новее.');
 const permission=await Notification.requestPermission();if(permission!=='granted')throw new Error('Разрешите уведомления для Толка в настройках устройства.');
 const result=await api('push/key',{}),registration=await navigator.serviceWorker.ready;
 const bytes=Uint8Array.from(atob(result.key.replace(/-/g,'+').replace(/_/g,'/')+'='.repeat((4-result.key.length%4)%4)),c=>c.charCodeAt(0));
 const subscription=await registration.pushManager.subscribe({userVisibleOnly:true,applicationServerKey:bytes});
 await api('push/subscribe',{subscription:subscription.toJSON()});
 document.querySelector('#push-status').textContent='Уведомления включены на этом устройстве';notify('Фоновые напоминания включены');
}
async function disablePush() {
 const registration=await navigator.serviceWorker.ready;const subscription=await registration.pushManager.getSubscription();
 if(subscription){await api('push/unsubscribe',{endpoint:subscription.endpoint});await subscription.unsubscribe();}
 document.querySelector('#push-status')?.replaceChildren(document.createTextNode('На этом устройстве уведомления отключены'));
}
async function showDevices(content) {
 const result=await api('devices',{});if(!content.isConnected)return;
 const section=document.createElement('section');section.className='settings-section';
 section.innerHTML=`<h2>Подключённые Mac</h2>${result.devices.length?result.devices.map(d=>`<div class="trash-row"><span>${escape(d.name)}<small class="hint">Последний обмен: ${escape(new Date(d.seen*1000).toLocaleString('ru-RU'))}</small></span><button class="text-button" data-revoke="${d.id}">Отключить доступ</button></div>`).join(''):'<p class="hint">Откройте настройки Толка на Mac → Аккаунт → Подключить и объединить данные.</p>'}`;
 section.querySelectorAll('[data-revoke]').forEach(b=>b.onclick=guarded(async()=>{await api('device/revoke',{id:b.dataset.revoke});section.remove();void showDevices(content);}));content.append(section);
}

function calendarEvents() {
 const zone=settings().timeZone||'Europe/Moscow';
 return client.records('event').filter(r=>!r.data.deleted).map(record=>{
  const data=record.data,wall=dayAndTime(data.start,zone);
  return {...record,data:{...data,body:data.notes||'',date:data.allDay?(data.day||wall.date):wall.date,time:data.allDay?'':wall.time,duration:Math.max(1,(data.end-data.start)/60),completed:false,readOnly:true}};
 });
}
function openEvent(record) {
 openEditor(`<form><header class="editor-header"><button type="button" data-cancel class="text-button">Закрыть</button><h2 id="editor-title">Apple Календарь</h2><span></span></header><div class="editor-content"><h3>${escape(record.data.title)}</h3><p>${escape(taskDate(record.data))}</p><p>${escape(record.data.location||'')}</p><p>${escape(record.data.notes||'')}</p><p class="hint">Событие с Mac. Изменяется в Apple Календаре.</p></div></form>`,()=>{});
}
let calendarInbox=false;
function renderCalendar(content,tasks) {
 const chosen=selectedDay||today(),anchor=new Date(chosen+'T12:00:00Z'),offset=(anchor.getUTCDay()+6)%7;
 anchor.setUTCDate(anchor.getUTCDate()-offset);
 const days=Array.from({length:7},(_,i)=>{const d=new Date(anchor);d.setUTCDate(d.getUTCDate()+i);return d.toISOString().slice(0,10);});
 const events=calendarEvents(),scheduled=tasks.concat(events).filter(r=>days.includes(r.data.date));
 const minute=r=>Number((r.data.time||'00:00').slice(0,2))*60+Number((r.data.time||'00:00').slice(3));
 const timed=scheduled.filter(r=>r.data.time);
 const start=Math.min(settings().startHour??7,...timed.map(r=>Math.floor(minute(r)/60)));
 const end=Math.min(24,Math.max(settings().endHour??23,...timed.map(r=>Math.ceil((minute(r)+(r.data.duration||30))/60))));
 const scale=(settings().hourHeight||96)/60,height=(end-start)*60*scale;
 const queue=tasks.filter(r=>!r.data.completed&&!r.data.time&&(!calendarInbox||!r.data.projectID));
 content.innerHTML=`<div class="calendar-controls"><button class="secondary" id="calendar-prev" aria-label="Предыдущая неделя">${icon('back')}</button><button class="secondary" id="calendar-now">Сегодня</button><button class="secondary" id="calendar-next" aria-label="Следующая неделя">${icon('chevron')}</button><span>${escape(dateLabel(days[0]))} – ${escape(dateLabel(days[6]))}</span></div><div class="calendar-layout"><section class="calendar-scroll" aria-label="Неделя"><div class="week-header"><div></div>${days.map(day=>`<div class="day-heading ${day===today()?'current-day':''}"><strong>${escape(new Date(day+'T12:00:00Z').toLocaleDateString('ru-RU',{weekday:'short',day:'numeric',timeZone:'UTC'}))}</strong>${scheduled.filter(r=>r.data.date===day&&!r.data.time).map(r=>`<button data-calendar-task="${r.id}" class="all-day-task">${escape(r.data.title)}</button>`).join('')}</div>`).join('')}</div><div class="week-grid"><div class="time-axis">${Array.from({length:end-start},(_,i)=>`<span data-hour="${i}">${String(start+i).padStart(2,'0')}:00</span>`).join('')}</div>${days.map(day=>`<div class="day-lane" data-day="${day}">${scheduled.filter(r=>r.data.date===day&&r.data.time).map(r=>`<button class="calendar-event ${r.kind==='event'?'external-event':''}" draggable="${r.kind!=='event'}" data-event="${r.id}"><strong>${escape(r.data.title)}</strong><small>${escape(r.data.time)}</small></button>`).join('')}</div>`).join('')}</div></section><aside class="planning-queue" id="calendar-queue"><header><h2>Распределить задачи</h2><button id="queue-add" aria-label="Добавить задачу">${icon('plus')}</button></header><div class="segmented"><button id="queue-all" ${!calendarInbox?'aria-current="true"':''}>Все</button><button id="queue-inbox" ${calendarInbox?'aria-current="true"':''}>Входящие</button></div><p class="hint">Перетащите задачу на время</p>${queue.map(r=>`<button class="queue-task" draggable="true" data-queue-task="${r.id}"><strong>${escape(r.data.title)}</strong><small>${escape(projectName(r.data.projectID))} · ${r.data.duration||30} мин</small></button>`).join('')||'<p class="hint">Перетащите сюда задачу из календаря.</p>'}</aside></div>`;
 content.querySelector('.week-grid').style.height=height+'px';content.querySelectorAll('[data-hour]').forEach(el=>el.style.top=(Number(el.dataset.hour)*60*scale)+'px');
 content.querySelectorAll('.day-lane').forEach(lane=>{
  lane.style.backgroundImage=`repeating-linear-gradient(to bottom,transparent 0,transparent ${60*scale-1}px,var(--line) ${60*scale-1}px,var(--line) ${60*scale}px)`;
  const list=timed.filter(r=>r.data.date===lane.dataset.day).sort((a,b)=>minute(a)-minute(b));
  let group=[],groupEnd=0;
  function place(){if(!group.length)return;const lanes=[];const placements=[];for(const r of group){const index=lanes.findIndex(end=>end<=minute(r));const col=index<0?lanes.length:index;lanes[col]=minute(r)+(r.data.duration||30);placements.push([r,col]);}for(const [r,col]of placements){const button=lane.querySelector(`[data-event="${r.id}"]`);button.style.top=((minute(r)-start*60)*scale)+'px';button.style.height=(Math.max(26,(r.data.duration||30)*scale))+'px';button.style.left=`calc(${col/lanes.length*100}% + 3px)`;button.style.width=`calc(${100/lanes.length}% - 6px)`;}group=[];}
  for(const r of list){if(group.length&&minute(r)>=groupEnd)place();group.push(r);groupEnd=Math.max(groupEnd,minute(r)+(r.data.duration||30));}place();
  lane.ondragover=e=>e.preventDefault();lane.ondrop=guarded(async e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain');const r=tasks.find(r=>r.id===id);if(!r)return;const m=Math.max(0,Math.min(1425,Math.round((start*60+(e.clientY-lane.getBoundingClientRect().top)/scale)/15)*15));await client.mutate('task',id,{date:lane.dataset.day,time:String(Math.floor(m/60)).padStart(2,'0')+':'+String(m%60).padStart(2,'0')},r);render();});
 });
 content.querySelectorAll('[draggable=true]').forEach(b=>b.ondragstart=e=>e.dataTransfer.setData('text/plain',b.dataset.event||b.dataset.queueTask));
 content.querySelectorAll('[data-event],[data-calendar-task],[data-queue-task]').forEach(b=>b.onclick=()=>{const id=b.dataset.event||b.dataset.calendarTask||b.dataset.queueTask;const r=scheduled.concat(tasks).find(r=>r.id===id);if(r)r.kind==='event'?openEvent(r):editTask(r);});
 const queueElement=content.querySelector('#calendar-queue');queueElement.ondragover=e=>e.preventDefault();queueElement.ondrop=guarded(async e=>{e.preventDefault();const id=e.dataTransfer.getData('text/plain'),r=tasks.find(r=>r.id===id);if(!r)return;await client.mutate('task',id,{schedule:{kind:'none'},...(calendarInbox?{projectID:'',section:'Без раздела'}:{})},r);render();});
 content.querySelector('#queue-all').onclick=()=>{calendarInbox=false;render();};content.querySelector('#queue-inbox').onclick=()=>{calendarInbox=true;render();};content.querySelector('#queue-add').onclick=()=>editTask();
 for(const [id,amount]of [['calendar-prev',-7],['calendar-next',7]])content.querySelector('#'+id).onclick=()=>{const d=new Date(chosen+'T12:00:00Z');d.setUTCDate(d.getUTCDate()+amount);selectedDay=d.toISOString().slice(0,10);render();};
 content.querySelector('#calendar-now').onclick=()=>{selectedDay=today();render();};
}

function groupedRows(records) {
 if(['calendar','search','tag','notes'].includes(view))return records.map(taskRow).join('');
 const groups=new Map();for(const r of records){const date=r.data.date;const label=!date?'Без даты':date<today()?'Просрочено':date===today()?'Сегодня':dateLabel(date);if(!groups.has(label))groups.set(label,[]);groups.get(label).push(r);}
 return Array.from(groups,([label,items])=>`<section class="list-group"><h2>${escape(label)}<small>${items.length}</small></h2>${items.map(taskRow).join('')}</section>`).join('');
}
function applyTagColors(){
 const dark=document.documentElement.dataset.theme==='dark'||(document.documentElement.dataset.theme==='system'&&matchMedia('(prefers-color-scheme:dark)').matches);
 const replacements={'598BFF':'4F8CFF','5BC9A2':'28D9AD','AD94E8':'B58AFF','E6A467':'FFAD40','ED8098':'FF66A0','66BDCB':'35CCE8'};
 const luminance=rgb=>rgb.map(v=>v<=.04045?v/12.92:((v+.055)/1.055)**2.4).reduce((sum,n,i)=>sum+n*[.2126,.7152,.0722][i],0);
 document.querySelectorAll('[data-tag-color]').forEach(el=>{
 let hex=(el.dataset.tagColor||'').toUpperCase();hex=replacements[hex]||hex;if(!/^[0-9A-F]{6}$/.test(hex))return;
 const rgb=[0,2,4].map(i=>parseInt(hex.slice(i,i+2),16)/255),background=rgb.map(n=>n*(dark?.20:.12)+(dark?.13:.95)*(dark?.8:.88));let foreground=rgb;
 for(let step=0;step<=20;step++){const a=luminance(foreground),b=luminance(background);if((Math.max(a,b)+.05)/(Math.min(a,b)+.05)>=5.5)break;const mix=(step+1)/21;foreground=rgb.map(n=>n*(1-mix)+(dark?1:0)*mix);}
 el.style.setProperty('--tag-color','#'+hex);el.style.setProperty('--tag-ink','rgb('+foreground.map(n=>Math.round(n*255)).join(',')+')');
 });
}
