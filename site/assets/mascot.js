// The mascot, Squat: a glossy black droplet drawn in 3D by assets/squat.js (WebGL, no libraries).
// It is StudyNotch's own character (DESIGN.md "Mascot"). Works from file://.
//
//   var m = Mascot.mount(button);          fills the button with the mascot
//   m.setMood('thinking'); m.pat(); m.say('Hello');
//   Mascot.flat('rest', '#7CC8FF')          a small still picture (an <img>) with eyes in that colour
//   Mascot.onFrame(fn)                      join the shared frame loop; fn(dt) returns true while moving
//
// Its eyes follow the pointer and its body turns a little toward it. It can be grabbed and spun, and
// hops when pressed. It blinks at random times and draws frames only while something moves. With
// "reduce motion" it holds still and only its face changes.
(function () {
  'use strict';

  var Squat = window.Squat;
  var still = window.matchMedia('(prefers-reduced-motion: reduce)');
  var MOODS = ['rest', 'happy', 'focus', 'drift', 'sleep', 'thinking', 'proud', 'sad', 'angry'];
  var TURN = 0.2;                      // radians (about 11°): the most the body turns toward the pointer
  var CHANGE = 0.4, BLINK = 0.18;      // seconds: a change of expression, a blink

  // ----- One frame loop for every mascot. It sleeps when nothing is moving.
  var jobs = [], raf = 0, last = 0;
  function frame(now) {
    var dt = Math.min(0.034, Math.max(0.001, (now - last) / 1000));
    last = now;
    raf = 0;
    var busy = false;
    for (var i = 0; i < jobs.length; i++) if (jobs[i](dt) === true) busy = true;
    if (busy) raf = requestAnimationFrame(frame);
  }
  function wake() {
    if (raf || document.hidden) return;
    last = performance.now() - 16;
    raf = requestAnimationFrame(frame);
  }
  document.addEventListener('visibilitychange', wake);

  // A damped spring, stepped once per frame. Returns true while it is still moving.
  function spring(s, to, dt, k, c, eps) {
    s.v += ((to - s.x) * k - s.v * c) * dt;
    s.x += s.v * dt;
    if (Math.abs(to - s.x) < eps && Math.abs(s.v) < eps * 8) { s.x = to; s.v = 0; return false; }
    return true;
  }
  function clamp(v, lo, hi) { return v < lo ? lo : v > hi ? hi : v; }
  function ease(k) { return k * k * (3 - 2 * k); }

  // ----- The pointer every mascot turns toward.
  var pointer = null;
  window.addEventListener('pointermove', function (e) { pointer = { x: e.clientX, y: e.clientY }; wake(); }, { passive: true });
  document.documentElement.addEventListener('pointerleave', function () { pointer = null; wake(); });
  window.addEventListener('scroll', wake, { passive: true });
  window.addEventListener('resize', wake);

  // A small still picture, for places too small for a live one (course pills, the popup's title).
  function flat(mood, eyes) {
    return '<img class="mascot-flat" alt="" src="' + Squat.picture(Squat.look(mood, eyes), 64) + '">';
  }

  function build(el) {
    el.innerHTML = '<span class="mascot-glow"></span><span class="mascot-shadow"></span>' +
      '<span class="mascot-rig"><canvas class="mascot-canvas" aria-hidden="true"></canvas></span>';
  }

  function Mascot(el, opts) {
    opts = opts || {};
    var self = this;
    this.el = el;
    this.opts = opts;
    this.mood = MOODS.indexOf(el.getAttribute('data-mood')) >= 0 ? el.getAttribute('data-mood') : 'rest';
    this.flash = null;                       // a mood shown for a moment on top of the real one
    this.hover = false;
    this.seen = true;
    this.t = 0;                              // this mascot's own clock, in seconds
    this.turn = { x: 0, v: 0 };              // radians, toward the pointer
    this.eye = { x: { x: 0, v: 0 }, y: { x: 0, v: 0 } };   // where the eyes look, toward the pointer
    this.spin = { x: 0, v: 0 };              // degrees, from a drag or a pat
    this.spinTo = 0;
    this.drag = null;
    this.dragged = false;
    this.from = null;
    this.changed = -9;
    this.blinkAt = -9;
    this.glance = 0;
    this.glanceFrom = 0;
    this.glanceAt = -9;
    build(el);
    this.canvas = el.querySelector('canvas');
    this.drawn = this.shown();
    this.cur = Squat.look(this.drawn, opts.eyes);
    el.setAttribute('data-mood', this.drawn);

    el.addEventListener('pointerenter', function (e) { if (e.pointerType !== 'touch') { self.hover = true; self.draw(); } });
    el.addEventListener('pointerleave', function () { self.hover = false; self.draw(); });
    el.addEventListener('pointerdown', function (e) {
      if (e.button) return;
      self.drag = { id: e.pointerId, x: e.clientX, t: e.timeStamp, moved: 0, v: 0, held: false };
      try { el.setPointerCapture(e.pointerId); } catch (err) { /* the pointer is already gone */ }
    });
    el.addEventListener('pointermove', function (e) {
      var d = self.drag;
      if (!d || e.pointerId !== d.id || still.matches) return;
      if (e.pointerType === 'mouse' && !(e.buttons & 1)) { release(e); return; }
      var dx = e.clientX - d.x, dt = Math.max(1, e.timeStamp - d.t);
      d.moved += Math.abs(dx);
      if (!d.held && d.moved > 6) {
        d.held = true;
        el.classList.add('is-held');
      }
      if (d.held) {
        var turn = dx * 0.9;
        self.spin.x += turn;
        self.spin.v = 0;
        d.v = d.v * 0.6 + (turn / dt * 1000) * 0.4;
        wake();
      }
      d.x = e.clientX;
      d.t = e.timeStamp;
    });
    function release(e) {
      var d = self.drag;
      if (!d || (e && e.pointerId !== d.id)) return;
      self.drag = null;
      el.classList.remove('is-held');
      if (!d.held) return;
      // Let it coast, then settle facing front: aim at the whole turn nearest to where the fling would end.
      self.dragged = true;
      setTimeout(function () { self.dragged = false; }, 80);
      var v = clamp(d.v, -1400, 1400);
      self.spin.v = v;
      self.spinTo = Math.round((self.spin.x + v * 0.3) / 360) * 360;
      wake();
    }
    el.addEventListener('pointerup', release);
    el.addEventListener('pointercancel', release);
    el.addEventListener('click', function (e) {
      if (self.dragged) { e.preventDefault(); return; }
      self.pat();
      if (opts.onPat) opts.onPat(self);
    });
    el.addEventListener('animationend', function (e) {
      if (e.animationName === 'mascot-hop') el.classList.remove('is-hop');
      if (e.animationName === 'mascot-land') el.classList.remove('is-land');
    });

    if ('IntersectionObserver' in window) {
      new IntersectionObserver(function (entries) {
        self.seen = entries[0].isIntersecting;
        el.classList.toggle('is-seen', self.seen);
        if (self.seen) { wake(); self.blinkSoon(); } else clearTimeout(self.blinkTimer);
      }).observe(el);
    } else {
      el.classList.add('is-seen');
    }
    this.blinkSoon();
    jobs.push(function (dt) { return self.step(dt); });
    this.step(0);
    wake();
  }

  Mascot.prototype.shown = function () {
    if (this.flash) return this.flash;
    if (this.hover && this.opts.smile !== false && this.mood !== 'thinking' && this.mood !== 'proud') return 'happy';
    return this.mood;
  };

  // Start easing toward the face of the mood it should show now. A new eye shape swaps mid-blink.
  Mascot.prototype.draw = function () {
    var mood = this.shown();
    if (mood === this.drawn) return;
    this.drawn = mood;
    this.el.setAttribute('data-mood', mood);
    if (!still.matches) {
      this.from = this.cur;
      this.changed = this.t;
      this.blinkAt = this.t;
    }
    wake();
  };

  Mascot.prototype.setMood = function (mood) {
    if (MOODS.indexOf(mood) < 0 || mood === this.mood) return;
    this.mood = mood;
    this.draw();
  };

  // Every two to six seconds, while it is on screen: a blink, or now and then a glance to one side.
  Mascot.prototype.blinkSoon = function () {
    var self = this;
    clearTimeout(this.blinkTimer);
    if (still.matches) return;
    this.blinkTimer = setTimeout(function () {
      if (!self.seen || document.hidden) return;
      var mood = self.shown();
      if ((mood === 'rest' || mood === 'focus') && Math.random() < 0.45) {
        self.glanceFrom = self.glanceNow();
        self.glance = Math.random() < 0.4 ? 0 : Math.random() * 1.2 - 0.6;
        self.glanceAt = self.t;
        if (Math.random() < 0.5) self.blinkAt = self.t;
      } else {
        self.blinkAt = self.t;
      }
      wake();
      self.blinkSoon();
    }, 2000 + Math.random() * 4000);
  };

  Mascot.prototype.glanceNow = function () {
    return this.glanceFrom + (this.glance - this.glanceFrom) * ease(clamp((this.t - this.glanceAt) / CHANGE, 0, 1));
  };

  // Pressed: a squash, a hop and one full turn, with a smile for a moment.
  Mascot.prototype.pat = function () {
    var self = this, el = this.el;
    if (this.mood !== 'thinking') {
      this.flash = 'happy';
      clearTimeout(this.flashTimer);
      this.flashTimer = setTimeout(function () { self.flash = null; self.draw(); }, 1300);
      this.draw();
    }
    if (still.matches) return;
    el.classList.remove('is-land');
    el.classList.add('is-hop');
    if (this.spinTo - this.spin.x < 180) this.spinTo += 360;
    wake();
  };

  // A small squash when it lands somewhere new.
  Mascot.prototype.land = function () {
    if (still.matches || this.el.classList.contains('is-hop')) return;
    this.el.classList.remove('is-land');
    void this.el.offsetWidth;
    this.el.classList.add('is-land');
  };

  // A short line in a paper bubble above it.
  Mascot.prototype.say = function (text, ms) {
    var old = this.el.querySelector('.mascot-say');
    if (old) old.remove();
    clearTimeout(this.sayTimer);
    if (!text) return;
    var b = document.createElement('span');
    b.className = 'mascot-say';
    b.textContent = text;
    this.el.appendChild(b);
    this.sayTimer = setTimeout(function () { b.remove(); }, ms || 2200);
  };

  Mascot.prototype.step = function (dt) {
    this.t += dt;
    if (!this.seen) return false;
    var mood = this.shown(), goal = Squat.look(mood, this.opts.eyes), busy = false;
    var aim = 0, ex = 0, ey = 0;
    var watching = pointer && !still.matches && !(this.drag && this.drag.held) && this.opts.follow !== false && mood !== 'sleep';
    if (watching) {
      var r = this.el.getBoundingClientRect();
      var reach = Math.max(240, r.height * 2.2);
      var nx = clamp((pointer.x - (r.left + r.width / 2)) / reach, -1, 1);
      var ny = clamp((pointer.y - (r.top + r.height / 2)) / reach, -1, 1);
      // The body turns toward the pointer. The shader's turn is positive to the left as seen from
      // the camera, so it is negated; with the same sign as the eyes, the two cancelled out and
      // the eyes hardly moved. The same numbers as the app (MascotView.aimed).
      aim = -nx * TURN;
      // Ovals look at the pointer; a smile or sleeping eyes stay where they are.
      if (mood !== 'happy' && mood !== 'proud') { ex = nx * 1.25; ey = -ny * 1.5; }
    }
    var l = goal;
    if (still.matches) {
      this.turn.x = aim; this.turn.v = 0;
      this.spin.x = this.spinTo = 0; this.spin.v = 0;
      goal.look[0] += ex; goal.look[1] += ey;
    } else {
      if (spring(this.turn, aim, dt, 80, 14, 0.002)) busy = true;
      if (spring(this.eye.x, ex, dt, 160, 22, 0.004)) busy = true;
      if (spring(this.eye.y, ey, dt, 160, 22, 0.004)) busy = true;
      var held = this.drag && this.drag.held;
      if (!held && spring(this.spin, this.spinTo, dt, 110, 13, 0.06)) busy = true;
      if (held) busy = true;
      // Keep the numbers small after many turns.
      if (!busy && !held && this.spin.x !== 0) { this.spin.x = this.spinTo = 0; }
      goal.look[0] += this.eye.x.x;
      goal.look[1] += this.eye.y.x;
      if ((mood === 'rest' || mood === 'focus') && !watching) {
        goal.look[0] += this.glanceNow();
        if (this.t - this.glanceAt < CHANGE) busy = true;
      }
      if (this.from && this.t - this.changed < CHANGE) {
        l = Squat.mix(this.from, goal, ease((this.t - this.changed) / CHANGE), BLINK / 2 / CHANGE);
        busy = true;
      }
      var u = (this.t - this.blinkAt) / BLINK;
      if (u >= 0 && u < 1) { l.blink = u < 0.5 ? u * 2 : 2 - u * 2; busy = true; }
    }
    this.cur = l;
    // Draw only when something changed; a cheaper frame while moving, a finer one when it stops.
    var size = Math.max(32, Math.round(this.el.clientHeight * Math.min(2, window.devicePixelRatio || 1)));
    var aa = busy ? 1 : 2;
    var key = size + '|' + aa + '|' + (this.turn.x + this.spin.x * Math.PI / 180).toFixed(3) + '|' + JSON.stringify(l);
    if (key !== this.painted) {
      // Both sides: a new canvas is 300 by 150, so checking only the width left a 150px mascot on a
      // 2x screen (300 pixels) with half a canvas, cut through its eyes.
      if (this.canvas.width !== size || this.canvas.height !== size) this.canvas.width = this.canvas.height = size;
      Squat.paint(this.canvas, l, { aa: aa, turn: this.turn.x + this.spin.x * Math.PI / 180 });
      this.painted = key;
    }
    return busy;
  };

  window.Mascot = {
    mount: function (el, opts) { return new Mascot(el, opts); },
    flat: flat,
    onFrame: function (fn) { jobs.push(fn); wake(); },
    wake: wake,
    spring: spring,
    still: still
  };
})();
