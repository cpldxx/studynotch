// The home page's moving parts.
//   1. The highlighter stroke behind the headline.
//   2. The mood stage: seven faces of the mascot.
//   3. The screen: a MacBook display with the notch island, a textbook page and the mascot sitting on
//      the top bezel. Pick a sentence and the right-click menu, the question popup and a prepared
//      answer follow; press the notch and the mascot jumps into the island. Seven tour steps drive
//      the same screen.
// Everything here is canned. The real app sends the question to the Claude the user connected.
(function () {
  'use strict';

  var Mascot = window.Mascot;
  // The faint light behind the mascot and the cards: the state's colour (DESIGN.md "Glow").
  var GLOW = { focus: '#7CE38B', drift: '#FFB25E', thinking: '#C9A6FF', proud: '#7CE38B' };
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  function $(id) { return document.getElementById(id); }
  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  // ----- 1. The headline rests fully highlighted; the stroke is drawn only when the page really renders.
  var mark = $('headline-mark');
  if (mark && window.requestAnimationFrame && !still.matches) {
    requestAnimationFrame(function () {
      mark.classList.add('hl-wait');
      requestAnimationFrame(function () {
        requestAnimationFrame(function () {
          mark.classList.add('hl-go');
          mark.classList.remove('hl-wait');
        });
      });
    });
  }
  if (!Mascot) return;


  // ----- 2. The mood stage.
  (function () {
    var pet = $('mood-pet'), stage = $('mood-stage'), when = $('mood-when');
    if (!pet || !stage) return;
    var lines = ['Drag me, I spin!', 'Boing!', 'My eyes change colour'], said = 0;
    var m = Mascot.mount(pet, { smile: false, onPat: function () { m.say(lines[said++ % lines.length]); } });
    var buttons = Array.prototype.slice.call(document.querySelectorAll('.mood'));
    buttons.forEach(function (b) {
      b.addEventListener('click', function () {
        var mood = b.getAttribute('data-mood');
        buttons.forEach(function (o) { o.setAttribute('aria-pressed', o === b ? 'true' : 'false'); });
        m.setMood(mood);
        stage.style.setProperty('--glow', GLOW[mood] || '#fff');
        stage.style.setProperty('--glow-a', GLOW[mood] ? '.45' : '.14');
        if (when) when.textContent = b.getAttribute('data-when');
      });
    });
  })();

  // The mascot waits at the end of the page and is glad when the pointer reaches "Get started".
  (function () {
    var pet = $('end-pet');
    if (!pet) return;
    var m = Mascot.mount(pet, { onPat: function () { m.say('Let\'s study together'); } });
    var cta = document.querySelector('.end .btn-primary'), over = false, focused = false;
    if (!cta) return;
    function glad() { m.setMood(over || focused ? 'happy' : 'rest'); }
    cta.addEventListener('pointerenter', function () { over = true; glad(); });
    cta.addEventListener('pointerleave', function () { over = false; glad(); });
    cta.addEventListener('focus', function () { focused = true; glad(); });
    cta.addEventListener('blur', function () { focused = false; glad(); });
  })();

  // ----- 3. The screen.
  var demoEl = $('demo'), mac = $('mac'), island = $('island'), layer = $('demo-layer'), roverEl = $('rover'), sayEl = $('say');
  if (!demoEl || !mac || !island || !layer || !roverEl) return;

  var sentences = Array.prototype.slice.call(document.querySelectorAll('.sentence'));
  var timer = null;

  var firstPresets = [
    { id: 'dontget', label: 'I don\'t get this' },
    { id: 'easier', label: 'Simpler' },
    { id: 'example', label: 'Example' },
    { id: 'summary', label: 'One-line summary' }
  ];

  var answers = {
    s1: {
      source: 'Lecture 9.pdf p.4',
      dontget: 'Being differentiable at (a,b) means f is well approximated by its tangent plane near (a,b). The tangent plane has no breaks, so as you approach that point, the values of f approach f(a,b) as well. That is exactly continuity.',
      easier: 'If you can lay a flat board snugly against the surface (differentiable), there can be no hole or step there (continuous). Fitting the board is the stricter of the two conditions.',
      example: 'f(x,y) = x² + y² is differentiable at (1,2). Its tangent plane is z = 5 + 2(x−1) + 4(y−2), and as you approach (1,2), the values of f approach 5.',
      summary: 'Differentiable always implies continuous. The reverse does not hold.'
    },
    s2: {
      source: 'Lecture 9.pdf p.5',
      dontget: 'Partial derivatives only look in two directions: along the x-axis and along the y-axis. A function can behave in both of those and still change value when you approach along a diagonal. Then the partials exist but the function is not continuous.',
      easier: 'Picture ground that is flat if you only walk north–south or east–west, but has a cliff along the diagonal path.',
      example: 'f(x,y) = xy/(x²+y²), f(0,0) = 0. On both axes it is always 0, so both partial derivatives are 0. But along y = x its value is 1/2, so it is not continuous at (0,0).',
      summary: 'Having partial derivatives guarantees neither continuity nor differentiability.'
    }
  };

  function icon(path, size) {
    var span = el('span', 'glyph');
    span.setAttribute('aria-hidden', 'true');
    span.innerHTML = '<svg viewBox="0 0 16 16" width="' + size + '" height="' + size + '"><path d="' + path + '" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>';
    return span;
  }
  var PEN = 'M3 13l1-3.5 7-7 2.5 2.5-7 7L3 13zM9.5 4l2.5 2.5M2 15h12';
  var CROSS = 'M4 4l8 8M12 4l-8 8';
  var UP = 'M8 13V3M4 7l4-4 4 4';

  var courses = [
    { name: 'MATH 237', files: '3 files' },
    { name: 'ACTSCI 221', files: 'No files yet' },
    { name: 'General', files: 'Timer only' }
  ];

  // What the screen is showing. `session` is null outside a session.
  var demo = { session: null, focus: 0, minutes: 50, tab: 'home', sound: true, thinking: false, card: null, cheer: false };
  var hovering = false, closeTimer = null, peekTimer = null, cheerTimer = null;
  var viewId = '', layerKind = null;

  function startSession(prepared) {
    var total = (prepared ? 50 : demo.minutes) * 60;
    demo.session = { course: prepared ? 0 : demo.focus, rest: false, total: total, left: prepared ? 32 * 60 + 10 : total, asked: prepared ? 1 : 0 };
    if (prepared) demo.focus = 0;
  }
  function ensureSession() {
    if (!demo.session) startSession(true);
    demo.session.rest = false;
  }
  function two(n) { return n < 10 ? '0' + n : '' + n; }
  function clock() { var s = demo.session; return s.rest ? '4:59' : Math.floor(s.left / 60) + ':' + two(s.left % 60); }
  function minsLeft() { return Math.ceil(demo.session.left / 60) + 'm'; }
  function sessionLine() {
    var s = demo.session, spent = Math.floor((s.total - s.left) / 60);
    if (s.rest) return 'On a break';
    return (spent ? 'Focused ' + spent + ' min' : 'Just started') + (s.asked ? ' · ' + s.asked + (s.asked === 1 ? ' question' : ' questions') : '');
  }
  // The session clock runs, as it does in the app. The folded notch shows minutes only.
  setInterval(function () {
    var s = demo.session;
    if (!s || s.rest || s.left <= 60 || document.hidden) return;
    s.left -= 1;
    Array.prototype.forEach.call(island.querySelectorAll('[data-live]'), function (n) {
      var kind = n.getAttribute('data-live');
      var text = kind === 'clock' ? clock() : kind === 'mins' ? minsLeft() : sessionLine();
      if (n.textContent !== text) n.textContent = text;
    });
  }, 1000);
  function live(node, kind) { node.setAttribute('data-live', kind); return node; }

  // ----- The island.
  var content = el('div');
  content.id = 'isl-content';
  var under = el('div', 'under');
  var count = el('div', 'isl-count');
  island.appendChild(content);
  island.appendChild(count);
  mac.appendChild(under);

  // Put new content in the island. When the view is the same one (a pill, a minute button, the sound
  // toggle), it must not fade in again, and the control that was pressed keeps the keyboard focus.
  function render(id, node) {
    var same = id === viewId, at = -1, active = document.activeElement;
    if (island.contains(active)) at = Array.prototype.indexOf.call(content.querySelectorAll('button'), active);
    // The three tabs, sound and close are the first five buttons of every open view.
    var keep = same || (at >= 0 && at < 5 && viewId.indexOf('open/') === 0 && id.indexOf('open/') === 0);
    viewId = id;
    content.innerHTML = '';
    if (same) node.classList.add('still');
    content.appendChild(node);
    if (at >= 0) {
      var buttons = content.querySelectorAll('button');
      (buttons[keep ? at : 0] || buttons[0]).focus({ preventScroll: true });
    }
  }

  function ring(white) {
    var s = demo.session, done = Math.max(0.03, (s.total - s.left) / s.total) * 31.4;
    return '<svg class="isl-ring" viewBox="0 0 12 12" aria-hidden="true"><circle cx="6" cy="6" r="5" fill="none" stroke="rgba(255,255,255,.18)" stroke-width="2"/>' +
      '<circle cx="6" cy="6" r="5" fill="none" stroke="' + (white ? '#8E939C' : '#fff') + '" stroke-width="2" stroke-linecap="round" stroke-dasharray="' + done.toFixed(1) + ' 31.4" transform="rotate(-90 6 6)"/></svg>';
  }

  // Folded. With a session: the mascot in the left ear, the minutes in the right. Without one the
  // island is just the notch, and it shows its ears only while the pointer is on it.
  function fold(thinking) {
    stopClose();
    clearTimeout(peekTimer);
    demo.thinking = !!thinking;
    demo.card = null;
    var peek = !demo.session && hovering;
    // Shrinking from the open card uses the close curve; growing ears on hover uses the open spring.
    island.classList.toggle('is-folding', island.getAttribute('data-state') === 'open');
    var state = demo.session || peek ? 'compact' : 'idle';
    island.setAttribute('data-state', state);
    var bar = el('button', 'isl-compact');
    bar.type = 'button';
    bar.setAttribute('aria-label', demo.session ? 'Open the notch island. ' + courses[demo.session.course].name + ', ' + sessionLine() : 'Open the notch island');
    if (demo.session) {
      var ear = el('span', 'isl-ear');
      ear.innerHTML = ring(demo.session.rest);
      ear.appendChild(demo.session.rest ? el('span', null, 'Break') : live(el('span', null, minsLeft()), 'mins'));
      bar.appendChild(ear);
    } else if (peek) {
      var today = el('span', 'isl-ear', 'Today 42m');
      today.style.color = '#8E939C';
      bar.appendChild(today);
    }
    bar.addEventListener('click', function () { open('home'); });
    render(state + (demo.session ? '/session' : ''), bar);
    sync();
  }

  function head() {
    var h = el('div', 'isl-head');
    var tabs = el('div', 'isl-tabs');
    [['home', 'Home', 'M2.5 7.5L8 3l5.5 4.5V13H10V9.5H6V13H2.5z'],
     ['record', 'Record', 'M3 13V9M8 13V4M13 13V7'],
     ['add', 'Add courses and files', 'M8 3v10M3 8h10']].forEach(function (t) {
      var on = !demo.card && demo.tab === t[0];
      var b = el('button', 'isl-tab' + (on ? ' on' : ''));
      b.type = 'button';
      b.setAttribute('aria-label', t[1]);
      b.setAttribute('aria-pressed', on ? 'true' : 'false');
      b.innerHTML = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="' + t[2] + '" fill="' + (t[0] === 'home' ? 'currentColor' : 'none') + '" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>';
      b.addEventListener('click', function () { open(t[0]); });
      tabs.appendChild(b);
    });
    h.appendChild(tabs);
    var icons = el('div', 'isl-icons');
    var sound = el('button', 'isl-icon');
    sound.type = 'button';
    sound.setAttribute('aria-label', demo.sound ? 'Mute sounds' : 'Turn sounds on');
    sound.innerHTML = '<svg viewBox="0 0 16 16" width="15" height="15" aria-hidden="true"><path d="M2.5 6h2.5L8.5 3v10L5 10H2.5z" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round"/>' +
      (demo.sound ? '<path d="M11 5.5q1.5 2.5 0 5M12.8 4q2.6 4 0 8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>' : '<path d="M11 6l3.5 4M14.5 6L11 10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>') + '</svg>';
    sound.addEventListener('click', function () { demo.sound = !demo.sound; if (!demo.card) open(demo.tab); });
    var close = el('button', 'isl-icon');
    close.type = 'button';
    close.setAttribute('aria-label', 'Close');
    close.appendChild(icon(CROSS, 12));
    close.addEventListener('click', function () { fold(false); });
    icons.appendChild(sound);
    icons.appendChild(close);
    h.appendChild(icons);
    return h;
  }

  function btn(label, primary, onClick) {
    var b = el('button', 'isl-btn' + (primary ? ' primary' : ''), label);
    b.type = 'button';
    b.addEventListener('click', function (e) { e.stopPropagation(); onClick(); });
    return b;
  }
  // A card, with a faint light rising from below in the state's colour: the app's one spoonful of colour.
  function card(wash) {
    var c = el('div', 'isl-card');
    if (wash) c.style.setProperty('--wash', wash);
    return c;
  }
  function title(name, sub) {
    var t = el('div', 'isl-title');
    t.appendChild(el('b', null, name));
    t.appendChild(sub && sub.nodeType ? sub : el('span', null, sub));
    return t;
  }
  function note(text) {
    var t = el('div', 'isl-title');
    t.appendChild(el('span', null, text));
    return t;
  }

  function homeBody(body) {
    var s = demo.session, c = courses[demo.focus];
    var running = !!s && demo.focus === s.course;
    var left = card(running ? (s.rest ? 'rgba(255,255,255,.1)' : 'rgba(124,227,139,.32)') : null);
    var text = el('div', 'isl-text');
    text.appendChild(title(c.name, running ? live(el('span', null, sessionLine()), 'line') : c.files));
    var row = el('div', 'isl-row');
    row.appendChild(running && !s.rest ? live(el('span', 'isl-clock', clock()), 'clock') : el('span', 'isl-clock', running ? clock() : demo.minutes + ':00'));
    var main = el('div', 'isl-btns');
    var more = el('div', 'isl-btns');
    if (running && s.rest) {
      main.appendChild(btn('Resume', true, function () { s.rest = false; open('home'); aside('Back to it!'); }));
      more.appendChild(btn('End', false, end));
    } else if (running) {
      main.appendChild(btn('Ask', true, function () { fold(false); flashSentences(); }));
      more.appendChild(btn('5-min break', false, function () { s.rest = true; fold(false); }));
      more.appendChild(btn('End', false, end));
    } else if (s) {
      main.appendChild(btn('Switch to this course', true, function () { s.course = demo.focus; s.rest = false; open('home'); aside('Switched!'); }));
      more.appendChild(note(courses[s.course].name + ' session in progress'));
    } else {
      main.appendChild(btn('Start', true, function () { startSession(false); fold(false); setStep(1); }));
      [25, 50, 90].forEach(function (m) {
        var b = btn(m + ' min', false, function () { demo.minutes = m; open('home'); });
        b.setAttribute('aria-pressed', demo.minutes === m ? 'true' : 'false');
        if (demo.minutes === m) b.classList.add('on');
        more.appendChild(b);
      });
    }
    row.appendChild(main);
    text.appendChild(row);
    text.appendChild(more);
    left.appendChild(text);
    body.appendChild(left);

    var right = card();
    var pills = el('div', 'isl-pills');
    courses.forEach(function (course, i) {
      var ticking = s && i === s.course && !s.rest;
      var p = el('button', 'isl-pill' + (i === demo.focus ? ' on' : '') + (ticking ? ' live' : ''));
      p.type = 'button';
      p.setAttribute('aria-pressed', i === demo.focus ? 'true' : 'false');
      p.setAttribute('aria-label', course.name);
      p.appendChild(ticking ? live(el('span', null, clock()), 'clock') : el('span', null, course.name));
      p.addEventListener('click', function () { demo.focus = i; open('home'); });
      pills.appendChild(p);
    });
    var add = el('button', 'isl-pill add', '+ Course');
    add.type = 'button';
    add.addEventListener('click', function () { open('add'); });
    pills.appendChild(add);
    right.appendChild(pills);
    body.appendChild(right);
  }

  function recordBody(body) {
    var left = card('rgba(255,255,255,.12)');
    var text = el('div', 'isl-text');
    text.appendChild(title('Today', 'Example data'));
    text.appendChild(el('div', 'isl-clock', '42 min'));
    text.appendChild(note('1 session · 2 questions'));
    left.appendChild(text);
    body.appendChild(left);
    var right = card();
    var bars = el('div', 'isl-bars');
    var cap = el('div', 'isl-bars-cap', 'Last 7 days');
    right.appendChild(cap);
    [['Th', 35], ['Fr', 80], ['Sa', 0], ['Su', 50], ['Mo', 95], ['Tu', 20], ['We', 42]].forEach(function (d, i) {
      var col = el('div', i === 6 ? 'today' : '');
      var bar = el('span');
      bar.style.height = Math.max(3, Math.round(52 * d[1] / 95)) + 'px';
      bar.style.animationDelay = (i * 35) + 'ms';
      col.appendChild(bar);
      col.appendChild(document.createTextNode(d[0]));
      col.addEventListener('mouseenter', function () { cap.textContent = d[0] + ' · ' + d[1] + ' min'; });
      col.addEventListener('mouseleave', function () { cap.textContent = 'Last 7 days'; });
      bars.appendChild(col);
    });
    right.appendChild(bars);
    body.appendChild(right);
  }

  function addBody(body) {
    var left = card();
    var text = el('div', 'isl-text');
    text.appendChild(title('New course', 'In the app, type a name and press Return'));
    text.appendChild(note('Link a folder or add PDFs before you press Add.'));
    left.appendChild(text);
    body.appendChild(left);
    var right = card();
    var drop = el('div', 'isl-drop', 'Drop PDFs or a folder here');
    drop.appendChild(el('span', null, 'They join the course when you press Add'));
    right.appendChild(drop);
    body.appendChild(right);
  }

  // Open: the 640px card. `fill` draws the body; `kind` names a card that is not a tab.
  function show(kind, fill, one) {
    clearLayer();
    clearTimeout(peekTimer);
    demo.thinking = false;
    demo.card = kind;
    island.classList.remove('is-folding');
    island.setAttribute('data-state', 'open');
    under.classList.remove('on');
    var wrap = el('div', 'isl-open');
    wrap.appendChild(head());
    var body = el('div', 'isl-body' + (one ? ' one' : ''));
    fill(body);
    wrap.appendChild(body);
    render('open/' + (kind || demo.tab), wrap);
    sync();
  }

  function open(tab) {
    demo.tab = tab || 'home';
    show(null, demo.tab === 'record' ? recordBody : demo.tab === 'add' ? addBody : homeBody, false);
    if (demo.tab === 'home' && !demo.session) setStep(0);
    armClose();
  }

  // The example totals of a finished session. The page says these are examples.
  function end() {
    var name = courses[demo.session ? demo.session.course : 0].name;
    demo.session = null;
    show('summary', function (body) {
      var c = card('rgba(124,227,139,.4)');
      var text = el('div', 'isl-text');
      text.appendChild(title('Session done', name + ' · focused 43 min · drifted 4 min · 2 questions'));
      text.appendChild(note('Stuck on: why partial derivatives don\'t imply continuity'));
      var row = el('div', 'isl-btns');
      row.appendChild(btn('One more', true, function () { startSession(false); fold(false); setStep(1); }));
      row.appendChild(btn('Close', false, function () { fold(false); }));
      text.appendChild(row);
      c.appendChild(text);
      body.appendChild(c);
    }, true);
    setStep(6);
    armClose();
  }

  function nudge() {
    ensureSession();
    show('nudge', function (body) {
      var c = card('rgba(255,178,94,.42)');
      var text = el('div', 'isl-text');
      text.appendChild(title('2 min on youtube.com', courses[demo.session.course].name + ' session · nothing is blocked'));
      var row = el('div', 'isl-btns');
      row.appendChild(btn('Back to work', true, function () { fold(false); setStep(1); }));
      row.appendChild(btn('5-min break', false, function () { demo.session.rest = true; fold(false); setStep(1); }));
      row.appendChild(btn('It\'s for study', false, function () { fold(false); setStep(1); }));
      text.appendChild(row);
      c.appendChild(text);
      body.appendChild(c);
    }, true);
    setStep(5);
    stopClose();
  }

  // Like the app: an open island folds 15 seconds after the pointer leaves it; the bar under it
  // counts the last ten.
  function armClose() {
    stopClose();
    if (hovering) return;
    count.classList.add('run');
    closeTimer = setTimeout(function () { fold(false); }, 15000);
  }
  function stopClose() {
    clearTimeout(closeTimer);
    count.classList.remove('run');
    void count.offsetWidth;
  }

  island.addEventListener('pointerenter', function (e) {
    if (e.pointerType === 'touch') return;
    hovering = true;
    stopClose();
    clearTimeout(peekTimer);
    var state = island.getAttribute('data-state');
    if (state === 'idle') fold(demo.thinking);
    if (state !== 'open') {
      under.innerHTML = '';
      under.appendChild(el('i'));
      under.appendChild(document.createTextNode(demo.session ? courses[demo.session.course].name + ' · ' + sessionLine() : 'Click to open'));
      under.classList.add('on');
    }
  });
  function leftIsland() {
    hovering = false;
    under.classList.remove('on');
    var state = island.getAttribute('data-state');
    if (state === 'open' && demo.card !== 'nudge') armClose();
    if (state === 'compact' && !demo.session) peekTimer = setTimeout(function () { if (island.getAttribute('data-state') === 'compact' && !demo.session) fold(demo.thinking); }, 900);
  }
  island.addEventListener('pointerleave', function (e) {
    if (e.pointerType === 'touch' || (e.relatedTarget && roverEl.contains(e.relatedTarget))) return;
    leftIsland();
  });
  roverEl.addEventListener('pointerleave', function (e) {
    if (e.pointerType !== 'touch' && place === 'card' && hovering && !(e.relatedTarget && island.contains(e.relatedTarget))) leftIsland();
  });
  // Clicks inside the island stay there (its content is redrawn under the pointer).
  island.addEventListener('click', function (e) { e.stopPropagation(); });
  // A click anywhere else on the screen folds it back, as in the app.
  mac.addEventListener('click', function (e) {
    if (island.getAttribute('data-state') === 'open' && !island.contains(e.target)) fold(false);
  });

  // ----- The mascot on the screen. One character with three places: on the top bezel (the perch),
  // in the island's left ear, and in the open card. It follows its place with a spring, so it rides
  // along while the island itself is still changing size.
  var place = 'perch', entered = still.matches, alive = 0, leap = 0, near = entered;
  var spot = { x: { x: 0, v: 0 }, y: { x: 0, v: 0 }, s: { x: 1, v: 0 } };
  var perchLines = ['Drag me, I spin!', 'Click the notch, I\'ll hop in', 'Stuck? Right-click it!'];
  var cardLines = ['Right-click what you don\'t get', 'Nice, keep going', 'I\'ll keep watch here'];
  var patted = 0, hintText = '', sayTimer = null;

  var rover = Mascot.mount(roverEl, {
    onPat: function () {
      if (place === 'perch') aside(perchLines[patted++ % perchLines.length]);
      else if (place === 'card') aside(demo.card === 'summary' ? 'Nice work' : demo.session ? cardLines[patted++ % cardLines.length] : 'Pick a course');
    }
  });

  // The pencilled note above the screen is the mascot's voice. It says what to press next, and it
  // only shows once the mascot has arrived where it is going.
  function speak(text) {
    if (!sayEl) return;
    sayEl.textContent = text || '';
    sayEl.classList.remove('on');
    if (text && near) {
      void sayEl.offsetWidth;
      sayEl.classList.add('on');
    }
  }
  // A line of its own for a moment, then back to the hint.
  function aside(text) {
    speak(text);
    clearTimeout(sayTimer);
    sayTimer = setTimeout(function () { speak(hintText); }, 2600);
  }
  // The hint follows from what the screen shows, so it can never be left over from an earlier step.
  function hintNow() {
    var s = demo.session, open = island.getAttribute('data-state') === 'open';
    if (layerKind === 'menu') return 'Press the black button on top';
    if (layerKind === 'compose') return 'Pick a question, then Send!';
    if (demo.thinking) return 'Writing your answer…';
    if (layerKind === 'answer') return 'Here\'s your answer!';
    if (demo.card === 'nudge') return 'No blocking, just a nudge';
    if (demo.card === 'summary') return 'Nice work!';
    if (open) return s ? (s.rest ? 'Taking a break' : 'I\'ll keep watch here') : 'Pick a course, then Start';
    if (s) return s.rest ? 'Just five minutes' : 'Click a sentence you don\'t get';
    return 'Click an underlined sentence';
  }
  function refreshHint() {
    var text = hintNow();
    if (text === hintText) return;
    hintText = text;
    clearTimeout(sayTimer);
    speak(text);
  }

  // Where it should be now, as an offset from the perch and a scale.
  function aim() {
    if (!entered) return [0, -70, 0.55];
    if (place === 'perch') return [0, 0, 1];
    // Aim at where the island will be when it has finished changing size (345px folded, 640px open,
    // never wider than the screen), so the mascot is never left outside it on the way.
    var w = Math.min(place === 'card' ? 640 : 345, mac.clientWidth - 24);
    var left = mac.offsetLeft + mac.clientLeft + (mac.clientWidth - w) / 2, top = mac.offsetTop + mac.clientTop;
    var h = roverEl.offsetHeight;
    var px = roverEl.offsetLeft + roverEl.offsetWidth / 2, py = roverEl.offsetTop + h / 2;
    if (place === 'ear') return [left + 40 - px, top + 16 - py, 20 / h];
    return [left + 64 - px, top + 97 - py, 54 / h];
  }
  Mascot.onFrame(function (dt) {
    var to = aim(), busy = false, hop = 0;
    if (still.matches) {
      spot.x.x = to[0]; spot.y.x = to[1]; spot.s.x = to[2];
      leap = 0;
    } else {
      if (Mascot.spring(spot.x, to[0], dt, 120, 16, 0.1)) busy = true;
      if (Mascot.spring(spot.y, to[1], dt, 120, 16, 0.1)) busy = true;
      if (Mascot.spring(spot.s, to[2], dt, 120, 17, 0.002)) busy = true;
      // Going somewhere new is a small jump, not a slide: an arc on top of the spring.
      if (leap > 0) { leap = Math.max(0, leap - dt / 0.46); busy = true; }
      hop = -Math.sin(Math.PI * (1 - leap)) * 38 * spot.s.x;
    }
    var s = Math.max(0.05, spot.s.x);
    roverEl.style.transform = 'translate3d(' + spot.x.x.toFixed(2) + 'px,' + (spot.y.x + hop).toFixed(2) + 'px,0) scale(' + s.toFixed(4) + ')';
    roverEl.style.setProperty('--s', s.toFixed(3));
    var here = entered && Math.abs(to[0] - spot.x.x) + Math.abs(to[1] - spot.y.x) < 12 && leap < 0.15;
    if (here && !near) {
      near = true;
      if (!still.matches) rover.land();
      if (sayEl && sayEl.textContent) sayEl.classList.add('on');
    }
    return busy || performance.now() < alive;
  });
  spot.y.x = aim()[1];
  spot.s.x = aim()[2];

  // Bring the mascot's place, face and glow in line with what the screen shows.
  function sync() {
    var state = island.getAttribute('data-state'), s = demo.session;
    var was = place;
    place = state === 'open' ? 'card' : state === 'compact' && s ? 'ear' : 'perch';
    var mood = demo.thinking ? 'thinking' : demo.card === 'nudge' ? 'drift' : demo.card === 'summary' ? 'proud'
      : s ? (s.rest ? 'sleep' : 'focus') : demo.cheer ? 'proud' : 'rest';
    rover.setMood(mood);
    roverEl.style.setProperty('--glow', GLOW[mood] || '#fff');
    roverEl.style.setProperty('--glow-a', place === 'card' ? (GLOW[mood] ? '.45' : '.14') : '0');
    roverEl.classList.toggle('in-island', place !== 'perch');
    roverEl.style.pointerEvents = place === 'ear' ? 'none' : '';
    roverEl.tabIndex = place === 'ear' ? -1 : 0;
    if (was !== place) {
      // The bubble waits until the mascot has landed.
      if (!still.matches) {
        // A new jump may start in the middle of the last one: keep the height it has now.
        spot.y.x -= Math.sin(Math.PI * (1 - leap)) * 38 * spot.s.x;
        near = false;
        leap = 1;
        if (sayEl) sayEl.classList.remove('on');
      }
      alive = performance.now() + 1200;
    }
    refreshHint();
    Mascot.wake();
  }
  window.addEventListener('resize', function () { alive = performance.now() + 300; Mascot.wake(); });

  function flashSentences() {
    sentences.forEach(function (s) { s.classList.add('picked'); });
    setTimeout(function () { sentences.forEach(function (s) { s.classList.remove('picked'); }); }, 700);
  }

  // ----- The layer over the page: the right-click menu, then the question popup.
  function clearLayer() {
    clearTimeout(timer);
    layer.textContent = '';
    layerKind = null;
  }
  // The popup that is about to be replaced: where it was, and whether the keyboard was in it.
  function leaving() {
    var old = layer.firstChild;
    var isPopup = old && old.classList.contains('popup');
    return { top: isPopup ? old.getBoundingClientRect().top : null, at: isPopup ? parseFloat(old.style.top) : null, focus: layer.contains(document.activeElement) };
  }
  // A popup that replaces another one slides from the old place; only its new rows fade in.
  function arrive(card, was) {
    if (was.top != null) {
      card.style.animation = 'none';
      var dy = was.top - card.getBoundingClientRect().top;
      if (!still.matches && card.animate && Math.abs(dy) > 1) card.animate([{ transform: 'translateY(' + dy + 'px)' }, { transform: 'none' }], { duration: 260, easing: 'cubic-bezier(.23,1,.32,1)' });
    }
    if (was.focus) (card.querySelector('.chip:not(:disabled)') || card.querySelector('.x')).focus({ preventScroll: true });
  }
  function fresh(node) { node.classList.add('fresh'); return node; }
  function unpick() { sentences.forEach(function (s) { s.classList.remove('picked'); }); }

  // Back to a quiet screen. The session, if there is one, keeps running.
  function reset() {
    var back = layer.contains(document.activeElement) && document.querySelector('.sentence.picked');
    clearLayer();
    unpick();
    demo.cheer = false;
    fold(false);
    setStep(demo.session ? 1 : -1);
    if (back) back.focus({ preventScroll: true });
  }

  // Place a card of the layer next to the sentence it belongs to, inside the screen.
  //   at:   keep this top (a popup that replaces another stays where the last one was)
  //   menu: the list under the ask button is only a picture, so it may run off the bottom as long
  //         as the button itself stays next to the sentence
  function pin(node, anchor, at, menu) {
    var box = mac.getBoundingClientRect();
    var a = anchor.getBoundingClientRect();
    var left0 = box.left + mac.clientLeft, top0 = box.top + mac.clientTop;
    var boxW = mac.clientWidth, boxH = mac.clientHeight;
    var width = node.offsetWidth, height = node.offsetHeight;
    var left = Math.min(Math.max(12, a.left - left0 + 36), boxW - width - 12);
    var below = a.bottom - top0 + 8;
    var above = a.top - top0 - height - 8;
    var top;
    if (menu) top = below + 48 <= boxH ? below : above;
    else {
      top = at != null ? at : (below + height <= boxH - 8 || above < 40 ? below : above);
      // Never let the card run off the bottom of the screen; on a short screen it may reach up to the notch.
      top = Math.max(Math.min(38, boxH - height - 8), Math.min(top, boxH - height - 10));
    }
    if (top < below - 1) node.style.transformOrigin = 'left bottom';
    node.style.left = Math.round(left) + 'px';
    node.style.top = Math.round(top) + 'px';
  }

  function showMenu(sentence, key) {
    clearLayer();
    var menu = el('div', 'ctx');
    var ask = el('button', 'ctx-ask');
    ask.type = 'button';
    ask.appendChild(icon(PEN, 14));
    var label = el('span', null, demo.session ? 'Ask' : 'Ask StudyNotch');
    label.setAttribute('translate', 'no');
    ask.appendChild(label);
    ask.addEventListener('click', function () { showPopup(sentence, key); });
    menu.appendChild(ask);
    var list = el('div', 'ctx-list');
    list.setAttribute('aria-hidden', 'true');
    ['Look Up', 'Translate', 'Search With Google', 'Copy', 'Share…'].forEach(function (label) {
      list.appendChild(el('div', 'ctx-item', label));
    });
    menu.appendChild(list);
    // Take the keyboard only when it came from the sentence; a tour button keeps it.
    var fromSentence = document.activeElement === sentence;
    layer.appendChild(menu);
    pin(menu, sentence, null, true);
    if (fromSentence) ask.focus({ preventScroll: true });
    layerKind = 'menu';
    refreshHint();
    setStep(2);
  }

  function popupShell(sentence, mood) {
    var card = el('div', 'popup');
    card.setAttribute('role', 'dialog');
    card.setAttribute('aria-label', 'Ask');
    var head = el('div', 'popup-head');
    var title = el('span', 'island-title');
    var face = el('span', 'glyph');
    face.innerHTML = Mascot.flat(mood || 'rest');
    title.appendChild(face);
    title.appendChild(document.createTextNode('Ask'));
    head.appendChild(title);
    head.appendChild(el('span', 'popup-meta', (demo.session ? courses[demo.session.course].name + ' · ' : '') + 'Preview'));
    var ai = el('span', 'popup-ai');
    ai.appendChild(el('i'));
    ai.appendChild(document.createTextNode('Claude'));
    head.appendChild(ai);
    var close = el('button', 'x');
    close.type = 'button';
    close.setAttribute('aria-label', 'Close');
    close.appendChild(icon(CROSS, 11));
    close.addEventListener('click', reset);
    head.appendChild(close);
    card.appendChild(head);
    card.appendChild(el('div', 'island-quote', sentence.textContent.trim()));
    return card;
  }

  function composer(card, title, presets, onSend) {
    var chosen = null;
    card.appendChild(el('div', 'popup-label', title));
    var row = el('div', 'chips');
    var send = el('button', 'chip primary send');
    send.type = 'button';
    send.appendChild(icon(UP, 12));
    send.appendChild(document.createTextNode('Send'));
    send.disabled = true;
    presets.forEach(function (p) {
      var b = el('button', 'chip', p.label);
      b.type = 'button';
      b.setAttribute('aria-pressed', 'false');
      b.addEventListener('click', function () {
        chosen = chosen === p ? null : p;
        Array.prototype.forEach.call(row.children, function (c) {
          var on = chosen && c.textContent === chosen.label;
          c.classList.toggle('selected', !!on);
          c.setAttribute('aria-pressed', on ? 'true' : 'false');
        });
        send.disabled = !chosen;
      });
      row.appendChild(b);
    });
    card.appendChild(row);
    var foot = el('div', 'popup-foot');
    foot.appendChild(el('span', 'popup-note', 'In the app you can also type your own question.'));
    send.addEventListener('click', function () { if (chosen) onSend(chosen); });
    foot.appendChild(send);
    card.appendChild(foot);
  }

  function showPopup(sentence, key) {
    var was = leaving();
    clearLayer();
    var card = popupShell(sentence);
    composer(card, 'What would you like to know?', firstPresets, function (preset) { waiting(sentence, key, preset); });
    layer.appendChild(card);
    pin(card, sentence);
    was.top = null;
    arrive(card, was);
    layerKind = 'compose';
    refreshHint();
    setStep(3);
  }

  function waiting(sentence, key, preset) {
    var was = leaving();
    clearLayer();
    fold(true);
    var card = popupShell(sentence, 'thinking');
    card.appendChild(fresh(el('div', 'popup-bubble', preset.label)));
    var status = fresh(el('div', 'island-status'));
    var dots = el('span', 'dots');
    dots.appendChild(el('i')); dots.appendChild(el('i')); dots.appendChild(el('i'));
    status.appendChild(dots);
    status.appendChild(document.createTextNode(demo.session ? 'Found it in ' + answers[key].source + ', writing…' : 'Writing…'));
    card.appendChild(status);
    layer.appendChild(card);
    pin(card, sentence, was.at);
    arrive(card, was);
    layerKind = 'wait';
    refreshHint();
    setStep(4);
    timer = setTimeout(function () { answer(sentence, key, preset); }, 1100);
  }

  function answer(sentence, key, preset) {
    var was = leaving();
    clearLayer();
    var data = answers[key], inSession = !!demo.session;
    if (inSession) demo.session.asked += 1;
    demo.cheer = true;
    clearTimeout(cheerTimer);
    cheerTimer = setTimeout(function () { demo.cheer = false; sync(); }, 2600);
    fold(false);
    var card = popupShell(sentence, 'happy');
    card.appendChild(el('div', 'popup-bubble', preset.label));
    card.appendChild(fresh(el('div', 'island-answer', data[preset.id])));
    card.appendChild(fresh(el('div', 'island-source', inSession ? 'Source: ' + data.source : 'In a session it also finds the page in your course material.')));
    var rest = firstPresets.filter(function (p) { return p.id !== preset.id; });
    composer(card, 'Where are you still stuck?', rest, function (next) { waiting(sentence, key, next); });
    layer.appendChild(card);
    pin(card, sentence, was.at);
    arrive(card, was);
    layerKind = 'answer';
    refreshHint();
    if (place === 'perch') rover.pat();
    setStep(4);
  }

  function pick(sentence) {
    unpick();
    sentence.classList.add('picked');
    fold(false);
    showMenu(sentence, sentence.getAttribute('data-key'));
  }
  sentences.forEach(function (sentence) {
    sentence.addEventListener('click', function (event) { event.preventDefault(); pick(sentence); });
    // It is a link in the markup so the sentence can wrap; Space should press it like a button.
    sentence.addEventListener('keydown', function (event) {
      if (event.key === ' ' || event.key === 'Spacebar') { event.preventDefault(); pick(sentence); }
    });
  });
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && layer.firstChild) reset();
  });

  // ----- The tour: seven steps of one study hour. Each button puts the screen in that state.
  var tour = $('tour'), tourText = $('tour-text'), tourNext = $('tour-next'), tourName = $('tour-name');
  var steps = tour ? Array.prototype.map.call(tour.querySelectorAll('li'), function (li) {
    return { button: li.querySelector('button'), text: li.querySelector('p').textContent };
  }) : [];
  var intro = tourText ? tourText.textContent : '', step = -1;
  function nameOf(i) { return steps[i].button.textContent.trim(); }

  function setStep(i) {
    if (!tour) return;
    step = i;
    steps.forEach(function (s, n) {
      if (n === i) s.button.setAttribute('aria-current', 'step'); else s.button.removeAttribute('aria-current');
    });
    var text = i < 0 ? intro : steps[i].text;
    if (tourText.textContent !== text) tourText.textContent = text;
    if (tourName) tourName.textContent = i < 0 ? '' : (i + 1) + '. ' + nameOf(i);
    tourNext.textContent = i < 0 ? 'Start from 1' : i === steps.length - 1 ? 'Start over' : 'Next: ' + nameOf(i + 1);
  }

  function go(i) {
    clearLayer();
    unpick();
    demo.cheer = false;
    var first = sentences[0];
    if (i < 0) {
      demo.session = null;
      fold(false);
    } else if (i === 0) {
      demo.session = null;
      demo.focus = 0;
      open('home');
    } else {
      ensureSession();
      if (i === 1) fold(false);
      else if (i === 2) pick(first);
      else if (i === 3) { fold(false); first.classList.add('picked'); showPopup(first, 's1'); }
      else if (i === 4) { first.classList.add('picked'); waiting(first, 's1', firstPresets[0]); }
      else if (i === 5) nudge();
      else if (i === 6) end();
    }
    setStep(i);
    // Bring the screen into view when the notch is out of sight (phones, or after scrolling down).
    var top = mac.getBoundingClientRect().top;
    if (top < 0 || top > window.innerHeight * 0.6) {
      var y = window.scrollY;
      var demoTop = y + demoEl.getBoundingClientRect().top, macTop = y + mac.getBoundingClientRect().top;
      var nextBottom = y + tourNext.getBoundingClientRect().bottom;
      // Show the screen from its top; on a short window give up the band above it before the button.
      var to = Math.min(Math.max(demoTop - 8, nextBottom + 12 - window.innerHeight), macTop - 8);
      window.scrollTo({ top: to, behavior: still.matches ? 'auto' : 'smooth' });
    }
  }

  if (tour) {
    tour.classList.add('is-live');
    steps.forEach(function (s, n) { s.button.addEventListener('click', function () { go(n); }); });
    tourNext.addEventListener('click', function () { go(step >= steps.length - 1 ? -1 : step + 1); });
    tourNext.hidden = false;
  }

  // ----- First paint: the notch alone, the mascot dropping onto the bezel, then its first line.
  fold(false);
  setStep(-1);
  if (still.matches) {
    roverEl.classList.add('is-in');
    speak(hintText);
  } else {
    setTimeout(function () {
      entered = true;
      roverEl.classList.add('is-in');
      alive = performance.now() + 1200;
      Mascot.wake();
    }, 260);
  }
})();
