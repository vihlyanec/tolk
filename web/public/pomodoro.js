// Epoch deadlines survive a suspended Safari tab, sleep and page reload.
export const duration = phase => phase === 'focus' ? 1500 : phase === 'longBreak' ? 900 : 300;
export function start(taskID, title, now = Date.now()) {
  return {taskID, title, phase:'focus', completed:0, remaining:1500, deadline:now + 1500000};
}
export function decode(raw) {
  if (!raw) return null;
  try {
    const value = JSON.parse(raw);
    if (!value || !['focus','shortBreak','longBreak'].includes(value.phase) ||
        typeof value.taskID !== 'string' || typeof value.title !== 'string' ||
        !Number.isInteger(value.completed) || value.completed < 0 ||
        !Number.isFinite(value.remaining) || value.remaining < 0 || value.remaining > 1500 ||
        !(value.deadline === null || Number.isFinite(value.deadline))) return null;
    if (value.resumeNote !== undefined && (typeof value.resumeNote !== 'string' || value.resumeNote.length > 2000)) return null;
    return value;
  } catch {return null;}
}
export const seconds = (session, now = Date.now()) => Math.max(0, Math.ceil(session.deadline === null ? session.remaining : (session.deadline - now) / 1000));
export function transition(session, action, now = Date.now()) {
  const next = {...session};
  if (action === 'pause' && next.deadline !== null) {
    next.remaining = Math.max(0, (next.deadline - now) / 1000); next.deadline = null;
  } else if (action === 'resume' && next.deadline === null && next.remaining > 0) {
    next.deadline = now + next.remaining * 1000;
  } else if (action === 'next' && seconds(next, now) === 0) {
    if (next.phase === 'focus') {next.completed++; next.phase = next.completed % 4 === 0 ? 'longBreak' : 'shortBreak';}
    else next.phase = 'focus';
    next.remaining = duration(next.phase); next.deadline = now + next.remaining * 1000;
  }
  return next;
}
export const clock = value => `${String(Math.floor(value / 60)).padStart(2,'0')}:${String(value % 60).padStart(2,'0')}`;
