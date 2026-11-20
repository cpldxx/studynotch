// Three mascot candidates, each drawn twice: a large master (256 box) and a separate 20 px master (20 box).
// Every state is a set of numbers on one drawing. Colours come from DESIGN.md only; shade is Ink at low opacity.
(function () {
  const INK = '#14233B', PAPER = '#FFFFFF', HI = '#FFE94A';
  const STATES = ['idle', 'focus', 'writing', 'drift', 'break'];
  const f = n => +n.toFixed(2);
  const pt = p => f(p[0]) + ' ' + f(p[1]);
  const poly = pts => 'M' + pts.map(pt).join(' L') + ' Z';
  const rotAt = (p, deg, c) => { const a = deg * Math.PI / 180, s = Math.sin(a), k = Math.cos(a);
    return [c[0] + p[0] * k - p[1] * s, c[1] + p[0] * s + p[1] * k]; };
  const lerp = (a, b, t) => [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t];

  // A round-ended tube in two tones: the shadow is the whole body, the lit part sits up and to the left.
  const tube = (d, w, inset, shift) => `
    <path d="${d}" fill="none" stroke="${HI}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${d}" fill="none" stroke="${INK}" stroke-opacity=".14" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>
    <path d="${d}" transform="translate(${shift[0]} ${shift[1]})" fill="none" stroke="${HI}" stroke-width="${w - inset}" stroke-linecap="round" stroke-linejoin="round"/>`;
  const disc = (x, y, r, fill, inset, shift) => `
    <circle cx="${f(x)}" cy="${f(y)}" r="${r}" fill="${fill}"/>
    <circle cx="${f(x)}" cy="${f(y)}" r="${r}" fill="${INK}" fill-opacity=".14"/>
    <circle cx="${f(x + shift[0])}" cy="${f(y + shift[1])}" r="${r - inset}" fill="${fill}"/>`;
  // An eye: a capsule whose lid comes down from the top (open 1 → 0), or a closed line.
  const eye = (x, y, w, h, open, look = [0, 0]) => {
    if (open <= 0.05) return `<path d="M${f(x - w * 0.9)} ${f(y + h * 0.1)} Q${f(x)} ${f(y + h * 0.42)} ${f(x + w * 0.9)} ${f(y + h * 0.1)}" fill="none" stroke="${INK}" stroke-width="${f(w * 0.62)}" stroke-linecap="round"/>`;
    const hh = h * open, top = y + h / 2 - hh;
    return `<rect class="eye" x="${f(x - w / 2 + look[0])}" y="${f(top + look[1])}" width="${f(w)}" height="${f(hh)}" rx="${f(Math.min(w / 2, hh / 2))}" fill="${INK}"/>`;
  };
  // Points along an "M … C … [C …]" path, every `step` units of length, with their tangents.
  function along(d, step, skip) {
    const n = d.match(/-?\d+(\.\d+)?/g).map(Number), segs = [];
    let p = [n[0], n[1]];
    for (let i = 2; i + 5 < n.length + 1; i += 6) { const e = [n[i + 4], n[i + 5]]; segs.push([p, [n[i], n[i + 1]], [n[i + 2], n[i + 3]], e]); p = e; }
    const cub = ([a, b, c, e], t) => { const u = 1 - t; return [0, 1].map(k => u * u * u * a[k] + 3 * u * u * t * b[k] + 3 * u * t * t * c[k] + t * t * t * e[k]); };
    const pts = []; for (const sg of segs) for (let k = 0; k <= 240; k++) pts.push(cub(sg, k / 240));
    let len = 0; const cum = [0]; for (let i = 1; i < pts.length; i++) { len += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]); cum.push(len); }
    const out = []; let j = 0;
    for (let L = skip; L < len - skip; L += step) { while (cum[j + 1] < L) j++; const a = pts[j], b = pts[j + 1] || pts[j], l = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1; out.push({ p: a, u: [(b[0] - a[0]) / l, (b[1] - a[1]) / l] }); }
    return out;
  }
  const ground = (cx, rx, y, ry) => `<ellipse cx="${f(cx)}" cy="${y}" rx="${rx}" ry="${ry}" fill="${INK}" fill-opacity=".08"/>`;

  /* 1 · Inch: a highlighter stroke that came alive and inches along your line. */
  const INCH = {
    idle:    { d: 'M62 192 C50 98 202 98 190 192', head: [190, 192], lift: [13, -15], eye: [5, -4], open: 1, look: [2, 0], contacts: [62, 190], feet: [56, 68, 184, 196] },
    focus:   { d: 'M96 192 C40 26 218 26 162 192', head: [162, 192], lift: [12, -7], eye: [5, -2], open: 0.48, look: [2, 1], contacts: [96, 162], feet: [90, 102, 156, 168] },
    writing: { d: 'M44 192 C66 122 168 116 198 192', head: [198, 192], lift: [12, 2], eye: [6, -3], open: 0.8, look: [2, 3], contacts: [44, 204], feet: [38, 50], line: true },
    drift:   { d: 'M118 192 C214 178 58 116 136 74', head: [136, 74], lift: [-13, -9], eye: [-6, -3], open: 1.15, look: [-2, -1], contacts: [118], feet: [112, 124] },
    break:   { d: 'M152 194 C38 202 52 92 128 96 C192 100 196 158 160 166', head: [160, 166], lift: [0, 0], eye: [-1, -7], open: 0, look: [0, 0], contacts: [128] },
  };
  function inchLarge(state) {
    const s = INCH[state];
    let g = '';
    g += s.contacts.map(x => ground(x, 26, 209, 4.5)).join('');
    if (s.line) g += `<path d="M30 214 L222 210" stroke="${HI}" stroke-opacity=".6" stroke-width="14"/>`;
    for (const x of s.feet || []) g += `<ellipse cx="${x}" cy="206" rx="7" ry="4" fill="${HI}"/><ellipse cx="${x}" cy="206" rx="7" ry="4" fill="${INK}" fill-opacity=".28"/>`;
    g += tube(s.d, 32, 8, [-2.5, -3]);
    for (const { p, u } of along(s.d, 19, 24)) {
      const n = [-u[1], u[0]], r = 12.5, a = [p[0] + n[0] * r, p[1] + n[1] * r], b = [p[0] - n[0] * r, p[1] - n[1] * r], c = [p[0] + u[0] * 5, p[1] + u[1] * 5];
      g += `<path d="M${pt(a)} Q${pt(c)} ${pt(b)}" fill="none" stroke="${INK}" stroke-opacity=".1" stroke-width="2.5" stroke-linecap="round"/>`;
    }
    const hd = [s.head[0] + s.lift[0], s.head[1] + s.lift[1]];
    if (s.lift[0] || s.lift[1]) g += tube(`M${pt(s.head)} L${pt(hd)}`, 30, 8, [-2.5, -3]);
    g += disc(hd[0], hd[1], 18, HI, 5, [-2.5, -3]);
    g += eye(hd[0] + s.eye[0], hd[1] + s.eye[1], 6, 11, s.open, s.look);
    return g;
  }
  const INCH_S = {
    idle:    { d: 'M4 16 C3 8.5 17 8.5 16 16', head: [16, 16], eye: [16.4, 14.9], open: 1 },
    focus:   { d: 'M6.5 16 C2.5 3 17.5 3 13.5 16', head: [13.5, 16], eye: [13.9, 14.9], open: 0.5 },
    writing: { d: 'M3 16 C5 10.5 13 10 17 16.25', head: [17, 16.25], eye: [17.5, 15.4], open: 0.8, line: true },
    drift:   { d: 'M9.5 16.5 C17 15 5 10 11 4', head: [11, 4], eye: [10.3, 3.6], open: 1.1 },
    break:   { d: 'M12.5 16.5 C3 17 3.5 7.5 10 8 C15 8.5 15.5 13.5 12.5 13.75', head: [12.5, 13.75], eye: [12.4, 12.9], open: 0 },
  };
  function inchSmall(state) {
    const s = INCH_S[state];
    let g = '';
    if (s.line) g += `<path d="M1 18.25 H19" stroke="${HI}" stroke-opacity=".6" stroke-width="1.5"/>`;
    g += `<path d="${s.d}" fill="none" stroke="${HI}" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/>`;
    g += `<circle cx="${s.head[0]}" cy="${s.head[1]}" r="2" fill="${HI}"/>`;
    g += s.open > 0 ? `<rect x="${s.eye[0] - 0.6}" y="${f(s.eye[1] - 0.9 * s.open)}" width="1.2" height="${f(1.8 * s.open)}" rx=".6" fill="${INK}"/>`
                    : `<path d="M${s.eye[0] - 0.8} ${s.eye[1]} H${s.eye[0] + 0.8}" stroke="${INK}" stroke-width="1" stroke-linecap="round"/>`;
    return g;
  }

  /* 2 · Scroll: a snail whose shell is a rolled page. It leaves a highlighted line behind it. */
  const SNAIL = {
    idle:    { stalks: [[-14, -46], [16, -42]], len: 1, open: 1, look: [2, 0], neck: 0 },
    focus:   { stalks: [[4, -48], [22, -40]], len: 1.12, open: 0.45, look: [3, 0], neck: 6 },
    writing: { stalks: [[10, -38], [28, -30]], len: 1, open: 0.75, look: [2, 3], neck: 4, trail: true },
    drift:   { stalks: [[-30, -36], [26, -44]], len: 0.96, open: 1.15, look: [-2, -2], neck: -4 },
    break:   { stalks: null, len: 0.82, open: 0, neck: -18 },
  };
  // A spiral built from half-circle arcs on two centres: eight arcs, no traced points.
  function spiral(cx, cy, r0, step, n) {
    const A = [cx, cy], B = [cx + step / 2, cy];
    let r = r0, x = cx - r0, d = `M${f(x)} ${cy}`;
    for (let i = 0; i < n && r > step / 2; i++) {
      const c = i % 2 ? B : A, nx = i % 2 ? c[0] - r : c[0] + r;
      d += ` A${f(r)} ${f(r)} 0 0 ${i % 2 ? 1 : 1} ${f(nx)} ${cy}`;
      x = nx; r -= step / 2;
    }
    return d;
  }
  function snailLarge(state) {
    const s = SNAIL[state];
    const head = [190 + s.neck * 0.4, 158 - s.neck], tail = 42 + (1 - s.len) * 120;
    let g = ground(120, 92, 209, 5);
    if (s.trail) g += `<path d="M6 214 L${f(tail + 30)} 211" stroke="${HI}" stroke-opacity=".6" stroke-width="14"/>`;
    // Foot and neck as one body.
    const body = `M${f(tail)} 200 L196 200 L${f(head[0])} ${f(head[1])}`;
    g += tube(body, 22, 7, [-2, -2.5]);
    g += tube(`M181.5 194 L${f(head[0])} ${f(head[1] + 4)}`, 30, 8, [-2.5, -3]);
    if (s.stalks) for (const [dx, dy] of s.stalks) {
      const tip = [head[0] + dx * s.len, head[1] + dy * s.len];
      g += `<path d="M${pt(head)} L${pt(tip)}" stroke="${HI}" stroke-width="8" stroke-linecap="round"/>`;
      g += disc(tip[0], tip[1], 8, HI, 3, [-1.5, -2]);
      g += eye(tip[0] + 1.5, tip[1] + 0.5, 4.5, 8, s.open, s.look);
    }
    // The shell: a rolled page, lit from the top left.
    const sx = 112, sy = 140 - (state === 'break' ? -4 : 0);
    if (state !== 'break') {
      g += `<path d="M100 176 H40 L28 186 V190 H100 Z" fill="${PAPER}" stroke="${INK}" stroke-opacity=".12" stroke-width="1.5" stroke-linejoin="round"/>`;
      g += `<path d="M40 176 V186 H28 Z" fill="${INK}" fill-opacity=".12"/>`;
      g += `<path d="M48 181.5 H66 M48 185.5 H60" stroke="${INK}" stroke-opacity=".2" stroke-width="2" stroke-linecap="round"/>`;
      g += `<path d="M70 181.5 H90" stroke="${HI}" stroke-width="4" stroke-linecap="round"/>`;
    }
    g += disc(sx, sy, 56, PAPER, 5, [-3.5, -4]);
    g += `<path d="${spiral(sx + 3, sy - 3, 44, 16, 5)}" fill="none" stroke="${INK}" stroke-opacity=".16" stroke-width="3.5" stroke-linecap="round"/>`;
    if (state === 'break') g += eye(160, 186, 5, 8, 0);
    return g;
  }
  const SNAIL_S = {
    idle:    { stalks: [[-1.5, -4], [1.75, -3.5]], neck: 0 },
    focus:   { stalks: [[0.5, -4.25], [2.5, -3.25]], neck: 0.5 },
    writing: { stalks: [[1.25, -3.25], [3, -2.25]], neck: 0.5, trail: true },
    drift:   { stalks: [[-3, -3], [2.5, -3.75]], neck: -0.25 },
    break:   { stalks: null, neck: -2 },
  };
  function snailSmall(state) {
    const s = SNAIL_S[state];
    const head = [15.5, 12.5 - s.neck];
    let g = '';
    if (s.trail) g += `<path d="M0.5 18.25 H6" stroke="${HI}" stroke-opacity=".6" stroke-width="1.5"/>`;
    g += `<path d="M3.5 16.5 H15.5 L${head[0]} ${head[1]}" fill="none" stroke="${HI}" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>`;
    g += `<path d="M14.5 16 L${head[0]} ${head[1] + 0.5}" stroke="${HI}" stroke-width="3" stroke-linecap="round"/>`;
    if (s.stalks) for (const [dx, dy] of s.stalks) g += `<path d="M${pt(head)} l${dx} ${dy}" stroke="${HI}" stroke-width="1.25" stroke-linecap="round"/><circle cx="${head[0] + dx}" cy="${head[1] + dy}" r=".95" fill="${HI}"/>`;
    g += `<circle cx="8.75" cy="11.75" r="4.75" fill="${PAPER}"/>`;
    g += `<path d="M7 11.75 A2.25 2.25 0 1 1 9.25 14" fill="none" stroke="${INK}" stroke-opacity=".4" stroke-width="1" stroke-linecap="round"/>`;
    return g;
  }

  /* 3 · Folio: a moth whose wings are two pages of a book. */
  // Wing angles in degrees; positive raises a wing (SVG's y axis points down).
  const MOTH = {
    idle:    { l: 15, r: 15, tilt: 0, open: 1, look: [0, 0] },
    focus:   { l: 58, r: 58, tilt: 0, open: 0.45, look: [0, 1] },
    writing: { l: 6, r: 44, tilt: 0, open: 0.8, look: [2, -2] },
    drift:   { l: -6, r: 36, tilt: -8, open: 1.15, look: [-2, -1] },
    break:   { l: -26, r: -26, tilt: 0, open: 0, look: [0, 0] },
  };
  const FORE = [[0, -30], [-104, -58], [-96, 6], [-46, 44], [0, 40]];
  function page(pts, deg, mirror, pivot, lines, shade) {
    const m = pts.map(p => [mirror ? -p[0] : p[0], p[1]]).map(p => rotAt(p, mirror ? -deg : deg, pivot));
    const h1 = m[0], o1 = m[1], o2 = m[2], lo = m[m.length - 2], h2 = m[m.length - 1];
    let g = `<path d="${poly(m)}" fill="${PAPER}" stroke="${PAPER}" stroke-width="4" stroke-linejoin="round"/>`;
    if (shade) g += `<path d="${poly(m)}" fill="${INK}" fill-opacity="${shade}" stroke="${INK}" stroke-opacity="${shade}" stroke-width="4" stroke-linejoin="round"/>`;
    g += `<path d="${poly([h1, lerp(h1, o1, 0.18), lerp(h2, lo, 0.36), h2])}" fill="${INK}" fill-opacity=".07"/>`;
    g += `<path d="${poly(m)}" fill="none" stroke="${INK}" stroke-opacity=".12" stroke-width="1.5" stroke-linejoin="round"/>`;
    lines.forEach(([v, t1, t2]) => {
      const a = lerp(lerp(h1, h2, v), lerp(o1, o2, v), t1), b = lerp(lerp(h1, h2, v), lerp(o1, o2, v), t2);
      g += `<path d="M${pt(a)} L${pt(b)}" stroke="${INK}" stroke-opacity=".2" stroke-width="3.5" stroke-linecap="round"/>`;
    });
    return g;
  }
  function mothLarge(state) {
    const s = MOTH[state], pv = [128, 122];
    const foreLines = [[0.2, 0.28, 0.86], [0.36, 0.28, 0.86], [0.52, 0.28, 0.86], [0.68, 0.28, 0.6]];
    let g = ground(128, 70, 216, 5);
    g += `<g transform="rotate(${s.tilt} 128 130)">`;
    // Far wings first: the pair that is raised more sits behind.
    g += page(FORE, s.l, false, pv, foreLines, 0) + page(FORE, s.r, true, pv, foreLines, 0.06);
    // Antennae: two small feathers.
    for (const m of [1, -1]) {
      g += `<path d="M${128 - 6 * m} 82 Q${128 - 16 * m} 58 ${128 - 34 * m} 48" fill="none" stroke="${HI}" stroke-width="4.5" stroke-linecap="round"/>`;
      const tip = `M${128 - 34 * m} 48 Q${128 - 50 * m} 46 ${128 - 52 * m} 34 Q${128 - 38 * m} 34 ${128 - 34 * m} 48 Z`;
      g += `<path d="${tip}" fill="${HI}"/>` + (m < 0 ? `<path d="${tip}" fill="${INK}" fill-opacity=".14"/>` : '');
    }
    g += `<ellipse cx="128" cy="154" rx="12" ry="23" fill="${HI}"/><ellipse cx="128" cy="154" rx="12" ry="23" fill="${INK}" fill-opacity=".14"/><ellipse cx="125.5" cy="151.5" rx="8.5" ry="19.5" fill="${HI}"/>`;
    g += `<ellipse cx="128" cy="122" rx="19" ry="21" fill="${HI}"/><ellipse cx="128" cy="122" rx="19" ry="21" fill="${INK}" fill-opacity=".14"/><ellipse cx="125" cy="119" rx="14.5" ry="17" fill="${HI}"/>`;
    g += disc(128, 92, 14, HI, 4, [-2, -2.5]);
    g += eye(122.5, 92, 4.5, 8.5, s.open, s.look) + eye(133.5, 92, 4.5, 8.5, s.open, s.look);
    return g + '</g>';
  }
  const MOTH_S = { idle: [15, 15, 0], focus: [58, 58, 0], writing: [6, 44, 0], drift: [-6, 36, -8], break: [-26, -26, 0] };
  const FORE_S = [[0, -3], [-8.5, -5.25], [-8, 0.75], [-4, 4], [0, 3.5]];
  function mothSmall(state) {
    const [l, r, tilt] = MOTH_S[state], pv = [10, 10];
    const w = (pts, deg, mirror, op) => { const m = pts.map(p => [mirror ? -p[0] : p[0], p[1]]).map(p => rotAt(p, mirror ? -deg : deg, pv));
      return `<path d="${poly(m)}" fill="${PAPER}" stroke="${PAPER}" stroke-width=".5" stroke-linejoin="round"/>` + (op ? `<path d="${poly(m)}" fill="${INK}" fill-opacity="${op}"/>` : ''); };
    let g = `<g transform="rotate(${tilt} 10 11)">`;
    g += w(FORE_S, l, false, 0) + w(FORE_S, r, true, 0.08);
    g += `<path d="M9.4 6 L7.75 2.75 M10.6 6 L12.25 2.75" stroke="${HI}" stroke-width="1" stroke-linecap="round"/>`;
    g += `<ellipse cx="10" cy="11.5" rx="1.75" ry="3.5" fill="${HI}"/><circle cx="10" cy="7" r="1.75" fill="${HI}"/>`;
    return g + '</g>';
  }

  const svg = (inner, box, label) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${box} ${box}" role="img" aria-label="${label}">${inner}</svg>`;
  window.Mascots = {
    STATES,
    list: [
      { id: 'inch', name: 'Inch', large: inchLarge, small: inchSmall },
      { id: 'scroll', name: 'Scroll', large: snailLarge, small: snailSmall },
      { id: 'folio', name: 'Folio', large: mothLarge, small: mothSmall },
    ],
    large: (m, s) => svg(m.large(s), 256, `${m.name}, ${s}`),
    small: (m, s) => svg(m.small(s), 20, `${m.name}, ${s}`),
  };
})();
