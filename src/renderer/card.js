/* global dayflow */
// One reminder card. The main process decides what's on it and what each button does.
const $ = (id) => document.getElementById(id);
const id = new URLSearchParams(location.search).get('id');
document.documentElement.dataset.platform = dayflow.platform;

const act = (action) => dayflow.cardAction(id, action);

function button(label, action, kind = '') {
  const b = document.createElement('button');
  b.className = `btn${kind ? ` ${kind}` : ''}`;
  b.type = 'button';
  b.textContent = label;
  b.addEventListener('click', () => act(action));
  return b;
}

(async () => {
  const d = await dayflow.getCard(id);
  if (!d) return;
  const card = $('card');
  card.classList.toggle('meeting', d.meeting);
  card.classList.toggle('soon', d.role === 'prep' || d.role === 'warn');
  $('label').textContent = d.label;
  $('title').textContent = d.title;
  $('title').title = d.title;
  $('sub').textContent = d.sub;
  $('sub').title = $('sub').textContent;
  showMore(d.more);

  const actions = $('actions');
  if (d.snooze.length) actions.append(button('Snooze ▾', 'snooze', 'ghost'));
  if (d.done) { actions.append(button('Got it', 'dismiss'), button('✓ Done', 'done', 'primary')); return; }
  if (d.join === 'join') actions.append(button('Got it', 'dismiss'), button('Join', 'join', 'primary'));
  else if (d.join === 'calendar') actions.append(button('Open in Calendar', 'calendar'), button('Got it', 'dismiss', 'primary'));
  else actions.append(button('Got it', 'dismiss', 'primary'));
})();

$('open').addEventListener('click', () => act('open'));

function showMore(n) {
  $('more').hidden = !n;
  $('more').textContent = `+${n} more`;
}
dayflow.onCardMore(showMore);
dayflow.onCardLeave(() => $('card').classList.add('leave'));

// Done: the card turns into the cheer-up for a moment, then goes.
dayflow.onCardCheer(({ done, total, streak }) => {
  const card = $('card');
  card.classList.add('cheer');
  $('label').textContent = 'Done';
  $('title').textContent = total && done >= total ? `All ${total} done today! 🎉` : ['Nice!', 'Well done!', 'Great job!', 'Keep it up!'][done % 4];
  $('sub').textContent = `${total && done < total ? `${done} of ${total} done today` : 'Every event checked off'}${streak ? ` · ${streak}-day streak 🔥` : ''}`;
  $('actions').innerHTML = '';
  $('more').hidden = true;
});
