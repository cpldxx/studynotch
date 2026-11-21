// Squat, drawn in 3D with WebGL: a round body of glossy black with two white painted eyes.
// The shader is the same program as the app's Metal one (Sources/StudyNotch/MascotRenderer.swift);
// change both together. No libraries, works from file://.
//
//   Squat.look('focus')                 the numbers for one expression (a copy)
//   Squat.mix(a, b, t)                  part way from one look to another
//   Squat.paint(canvas, look, opts)     draw into a 2D canvas; opts: { aa: 1|2, turn: radians }
//   Squat.picture(look, px)             a cached PNG data URL, for small places
//   Squat.ok                            false when the browser has no WebGL (a flat stand-in is drawn)
(function () {
  'use strict';

  // The eyes are always white (Island Text). Moods change their shape and place, not their colour.
  var WHITE = [0.961, 0.965, 0.973];
  var EYES = [0.075, 0.132], LONG = [0.07, 0.15];
  function L(eye, o) {
    var l = { eye: eye.slice(), open: 1, shape: 0, look: [0, 0], lean: 0, squash: 1, blink: 0, lid: [2, 0], size: EYES.slice() };
    for (var k in o) l[k] = o[k];
    return l;
  }
  var LOOKS = {
    rest: function () { return L(WHITE, {}); },
    happy: function () { return L(WHITE, { shape: 1, look: [0, 0.2] }); },
    thinking: function () { return L(WHITE, { open: 0.9, look: [0.9, 0.8], lean: -0.06 }); },
    focus: function () { return L(WHITE, { open: 0.42, look: [0, -0.7], squash: 0.97 }); },
    drift: function () { return L(WHITE, { open: 1.15, look: [-1, 0.2], lean: 0.09 }); },
    sleep: function () { return L(WHITE, { shape: 2, look: [0, -0.3], squash: 0.92 }); },
    proud: function () { return L(WHITE, { shape: 1, look: [0, 0.2], squash: 1.04 }); },
    sad: function () { return L(WHITE, { open: 0.95, look: [0, -0.6], squash: 0.95, lid: [0.15, -0.9], size: LONG.slice() }); },
    angry: function () { return L(WHITE, { open: 0.9, lid: [0.2, 1.1], size: LONG.slice() }); }
  };
  function look(mood, eyeHex) {
    var l = (LOOKS[mood] || LOOKS.rest)();
    if (eyeHex) l.eye = [1, 3, 5].map(function (i) { return parseInt(eyeHex.slice(i, i + 2), 16) / 255; });
    return l;
  }
  // Numbers ease across; the eye shape (oval, smile, asleep) swaps once, at `swap`.
  function mix(a, b, t, swap) {
    var k = Math.max(0, Math.min(1, t)), r = {};
    function m(x, y) { return x + (y - x) * k; }
    function m2(x, y) { return [m(x[0], y[0]), m(x[1], y[1])]; }
    r.eye = [m(a.eye[0], b.eye[0]), m(a.eye[1], b.eye[1]), m(a.eye[2], b.eye[2])];
    r.open = m(a.open, b.open); r.look = m2(a.look, b.look); r.lean = m(a.lean, b.lean);
    r.squash = m(a.squash, b.squash); r.lid = m2(a.lid, b.lid); r.size = m2(a.size, b.size);
    r.blink = b.blink;
    r.shape = k >= (swap == null ? 0.3 : swap) ? b.shape : a.shape;
    return r;
  }

  var FS = [
    'precision highp float;',
    'uniform vec2 uRes; uniform float uAA; uniform float uZoom;',
    'uniform vec4 uEye; uniform vec4 uFace; uniform vec4 uBody; uniform vec4 uLid;',
    'const float C = 0.45; const float YAW = 0.42; const float PITCH = 0.22;',
    'float smin(float a, float b, float k) { float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }',
    'float sdEllipsoid(vec3 p, vec3 r) { float k0 = length(p / r); float k1 = length(p / (r * r)); return k0 * (k0 - 1.0) / k1; }',
    'mat2 rot(float a) { float c = cos(a), s = sin(a); return mat2(c, -s, s, c); }',
    'vec3 bodySpace(vec3 p) { p.xz = rot(uBody.w) * p.xz; p.xy = rot(uBody.x) * p.xy; p.y /= uBody.y; return p; }',
    'float body(vec3 p) {',
    '  return sdEllipsoid(p - vec3(0.0, C, 0.0), vec3(0.48, 0.45, 0.46));',
    '}',
    'float map(vec3 p) { return body(bodySpace(p)) * min(uBody.y, 1.0); }',
    'vec2 facePlane(vec3 b) { vec3 F = vec3(sin(YAW), 0.0, cos(YAW)); vec3 right = vec3(F.z, 0.0, -F.x); vec3 o = b - vec3(0.0, C, 0.0); return vec2(dot(o, right), o.y); }',
    'float taperArc(vec2 q, vec2 c, float r, float halfAng, float th, float up) {',
    '  vec2 v = q - c; v.y *= up;',
    '  float a = clamp(atan(v.x, v.y), -halfAng, halfAng);',
    '  vec2 p = r * vec2(sin(a), cos(a));',
    '  float w = th * mix(1.0, 0.16, pow(abs(a) / halfAng, 1.6));',
    '  return length(v - p) - w;',
    '}',
    'float eyeDist(vec2 f) {',
    '  float d = 1e5;',
    '  for (int i = 0; i < 2; i++) {',
    '    float s = i == 0 ? -1.0 : 1.0;',
    '    vec2 c = vec2(s * 0.17 + uFace.y * 0.06, 0.09 + uFace.z * 0.045);',
    '    vec2 q = f - c; float e;',
    '    if (uFace.x < 0.5) {',
    '      vec2 r = vec2(uLid.z, uLid.w * max(uEye.w * (1.0 - uFace.w), 0.06));',
    '      e = (length(q / r) - 1.0) * min(r.x, r.y);',
    '      float xo = s * q.x;',
    '      e = max(e, (q.y - (uLid.x * r.y + uLid.y * xo)) / sqrt(1.0 + uLid.y * uLid.y));',
    '    } else if (uFace.x < 1.5) {',
    '      e = taperArc(q / vec2(1.15, 1.85), vec2(0.0, -0.04), 0.066, 1.22, 0.019, 1.0) * 1.15;',
    '    } else {',
    '      e = taperArc(q, vec2(0.0, 0.058), 0.086, 0.8, 0.021, -1.0);',
    '    }',
    '    d = min(d, e);',
    '  }',
    '  return d;',
    '}',
    'vec3 normalAt(vec3 p) { vec2 e = vec2(0.0006, 0.0); return normalize(vec3(map(p + e.xyy) - map(p - e.xyy), map(p + e.yxy) - map(p - e.yxy), map(p + e.yyx) - map(p - e.yyx))); }',
    'float shadowAt(vec3 ro, vec3 rd) { float res = 1.0, t = 0.02; for (int i = 0; i < 48; i++) { float h = map(ro + rd * t); res = min(res, 5.0 * h / t); t += clamp(h, 0.008, 0.12); if (res < 0.002 || t > 3.0) break; } return clamp(res, 0.0, 1.0); }',
    'float occlusion(vec3 p, vec3 n) { float occ = 0.0, sca = 1.0; for (int i = 0; i < 6; i++) { float h = 0.012 + 0.15 * float(i) / 5.0; occ += (h - map(p + h * n)) * sca; sca *= 0.86; } return clamp(1.0 - 2.2 * occ, 0.0, 1.0); }',
    'vec3 studio(vec3 r) {',
    '  vec3 c = mix(vec3(0.01), vec3(0.02), smoothstep(-0.3, 0.7, r.y));',
    '  c += vec3(5.0, 4.9, 4.7) * smoothstep(0.84, 0.95, dot(r, normalize(vec3(-0.6, 0.7, 0.4))));',
    '  c += vec3(1.6, 1.8, 2.2) * smoothstep(0.90, 0.985, dot(r, normalize(vec3(0.85, 0.35, -0.4))));',
    '  c += vec3(0.6) * smoothstep(0.93, 0.99, dot(r, normalize(vec3(0.2, 0.15, 1.0))));',
    '  return c;',
    '}',
    'vec3 toLin(vec3 c) { return pow(c, vec3(2.2)); }',
    'vec3 aces(vec3 x) { return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), 0.0, 1.0); }',
    'vec4 shade(vec2 frag) {',
    '  vec2 uv = (2.0 * frag - uRes) / uRes.y;',
    '  vec3 target = vec3(0.0, 0.46, 0.0); float dist = 3.5 / uZoom;',
    '  vec3 ro = target + dist * vec3(sin(YAW) * cos(PITCH), sin(PITCH), cos(YAW) * cos(PITCH));',
    '  vec3 fw = normalize(target - ro), rt = normalize(cross(fw, vec3(0, 1, 0))), up = cross(rt, fw);',
    '  vec3 rd = normalize(fw * 3.4 + uv.x * rt + uv.y * up);',
    '  float t = 0.0; bool hit = false;',
    '  for (int i = 0; i < 140; i++) { float h = map(ro + rd * t); if (abs(h) < 0.0004 * t) { hit = true; break; } t += h * 0.8; if (t > 12.0) break; }',
    '  if (!hit) return vec4(0.0);',
    '  vec3 p = ro + rd * t, n = normalAt(p);',
    '  vec3 Ld = normalize(vec3(-0.45, 0.9, 0.5));',
    '  float sh = shadowAt(p + n * 0.003, Ld);',
    '  float occ = occlusion(p, n);',
    '  float fre = pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 4.0);',
    '  vec3 eyeLin = toLin(uEye.rgb);',
    '  vec3 b = bodySpace(p);',
    '  float g = smoothstep(0.0, 1.0, b.y);',
    '  vec3 alb = mix(toLin(vec3(0.035, 0.038, 0.045)), toLin(vec3(0.11, 0.12, 0.14)), g);',
    '  float dif = clamp(dot(n, Ld), 0.0, 1.0) * mix(1.0, sh, 0.85);',
    '  vec3 col = alb * (1.2 * dif + 0.25 * occ);',
    '  vec3 rimL = normalize(vec3(0.8, 0.3, -0.6));',
    '  col += vec3(0.35, 0.42, 0.55) * pow(clamp(1.0 + dot(n, rd), 0.0, 1.0), 2.2) * clamp(dot(n, rimL) + 0.45, 0.0, 1.0) * occ;',
    '  vec3 nb = n; nb.xz = rot(uBody.w) * nb.xz; nb.xy = rot(uBody.x) * nb.xy;',
    '  float front = smoothstep(0.1, 0.4, dot(nb, vec3(sin(YAW), 0.0, cos(YAW))));',
    '  float ed = eyeDist(facePlane(b));',
    '  float edge = max(0.0025, 0.7 * dist / (3.4 * uRes.y));',
    '  float mask = (1.0 - smoothstep(-edge, edge, ed)) * front;',
    '  col += eyeLin * exp(-max(ed, 0.0) * 28.0) * 0.1 * front;',
    '  col += eyeLin * 0.05 * smoothstep(0.35, 0.0, b.y) * occ;',
    '  col = mix(col, eyeLin * 1.15, mask);',
    '  vec3 hal = normalize(Ld - rd);',
    '  col += pow(clamp(dot(n, hal), 0.0, 1.0), 180.0) * 1.4 * sh;',
    '  col = mix(col, studio(reflect(rd, n)) * occ, (0.045 + 0.85 * fre) * (1.0 - mask * 0.7));',
    '  return vec4(pow(aces(col), vec3(1.0 / 2.2)), 1.0);',
    '}',
    'void main() {',
    '  vec4 acc = vec4(0.0);',
    '  if (uAA > 1.5) {',
    '    for (int j = 0; j < 2; j++) for (int i = 0; i < 2; i++) { vec4 c = shade(gl_FragCoord.xy + (vec2(float(i), float(j)) - 0.5) * 0.5); acc += vec4(c.rgb * c.a, c.a); }',
    '    acc /= 4.0;',
    '  } else { vec4 c = shade(gl_FragCoord.xy); acc = vec4(c.rgb * c.a, c.a); }',
    '  gl_FragColor = acc;',
    '}'
  ].join('\n');

  var gl = null, U = {};
  try {
    var c = document.createElement('canvas');
    gl = c.getContext('webgl', { premultipliedAlpha: true, alpha: true, antialias: false, preserveDrawingBuffer: true });
    if (gl) {
      var vs = gl.createShader(gl.VERTEX_SHADER);
      gl.shaderSource(vs, 'attribute vec2 a; void main(){ gl_Position = vec4(a, 0.0, 1.0); }');
      gl.compileShader(vs);
      var fs = gl.createShader(gl.FRAGMENT_SHADER);
      gl.shaderSource(fs, FS);
      gl.compileShader(fs);
      if (!gl.getShaderParameter(fs, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(fs));
      var prog = gl.createProgram();
      gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog); gl.useProgram(prog);
      var buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      var at = gl.getAttribLocation(prog, 'a');
      gl.enableVertexAttribArray(at);
      gl.vertexAttribPointer(at, 2, gl.FLOAT, false, 0, 0);
      ['uRes', 'uAA', 'uZoom', 'uEye', 'uFace', 'uBody', 'uLid'].forEach(function (n) { U[n] = gl.getUniformLocation(prog, n); });
    }
  } catch (err) {
    gl = null;
  }

  // Without WebGL: the same face, flat.
  function flatStandIn(ctx, l, size) {
    ctx.clearRect(0, 0, size, size);
    ctx.fillStyle = '#141518';
    ctx.beginPath(); ctx.ellipse(size * 0.5, size * 0.56, size * 0.42, size * 0.38, 0, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = 'rgb(' + l.eye.map(function (v) { return Math.round(v * 255); }).join(',') + ')';
    [0.36, 0.64].forEach(function (x) {
      ctx.beginPath(); ctx.ellipse(size * x, size * 0.52, size * 0.06, size * 0.1 * Math.max(0.15, l.open * (1 - l.blink)), 0, 0, Math.PI * 2); ctx.fill();
    });
  }

  function paint(canvas, l, opts) {
    opts = opts || {};
    var size = canvas.width;
    if (canvas.height !== size) canvas.height = size;   // it is drawn in a square
    var ctx = canvas.getContext('2d');
    if (!gl) { flatStandIn(ctx, l, size); return; }
    gl.canvas.width = gl.canvas.height = size;
    gl.viewport(0, 0, size, size);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.uniform2f(U.uRes, size, size);
    gl.uniform1f(U.uAA, opts.aa || 2);
    gl.uniform1f(U.uZoom, opts.zoom || 1.9);
    gl.uniform4f(U.uEye, l.eye[0], l.eye[1], l.eye[2], l.open);
    gl.uniform4f(U.uFace, l.shape, l.look[0], l.look[1], l.blink || 0);
    gl.uniform4f(U.uBody, l.lean, l.squash, 0, opts.turn || 0);
    gl.uniform4f(U.uLid, l.lid[0], l.lid[1], l.size[0], l.size[1]);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    ctx.clearRect(0, 0, size, size);
    ctx.drawImage(gl.canvas, 0, 0);
  }

  var pictures = {};
  function picture(l, px) {
    var key = px + JSON.stringify(l);
    if (pictures[key]) return pictures[key];
    var c = document.createElement('canvas');
    c.width = c.height = px;
    paint(c, l, { aa: 2 });
    return (pictures[key] = c.toDataURL('image/png'));
  }

  window.Squat = { look: look, mix: mix, paint: paint, picture: picture, ok: !!gl };
})();
