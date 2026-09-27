// The pixel field behind Home and Trail (docs/DESIGN.md → Pixel field), drawn
// by a WebGL shader in this worker on an OffscreenCanvas, so the page's own
// thread does no drawing. The same scene maths is in ios/Curio/PixelField.metal.
// Wrapped in a function: client files share one global scope.
(() => {
  type RGB = [number, number, number];
  interface Colors { dim: RGB; mid: RGB; lit: RGB; crest: RGB; planets: [RGB, RGB, RGB, RGB] }
  type Message =
    | { type: 'init'; canvas: OffscreenCanvas; reduceMotion: boolean }
    | { type: 'size'; width: number; height: number; dpr: number }
    | { type: 'scene'; scene: number; intensity: number }
    | { type: 'colors'; colors: Colors }
    | { type: 'pointer'; x: number; y: number; tap: boolean }
    | { type: 'run'; running: boolean }
    | { type: 'focus'; fill: number; rect: [number, number, number, number] };

  const vertex = 'attribute vec2 p; void main() { gl_Position = vec4(p, 0.0, 1.0); }';
  // One cell = 8 CSS px; each cell is a square "pixel" with a small gap.
  // Scenes: 0 starfield + comet (phones), 1 atom (Trail), 2 solar system (Home),
  // 3 the stamp celebration burst (from the tap point).
  // uRect is the empty space the scene must fit in (left, top, right,
  // bottom); uFill the line background pixels start below (0: a gradient
  // over the whole canvas, as on phones).
  const fragment = `
precision mediump float;
uniform vec2 uSize; uniform float uDpr, uTime, uScene, uIntensity, uFill; uniform vec3 uPointer, uTap; uniform vec4 uRect;
uniform vec3 uDim, uMid, uLit, uCrest, uP1, uP2, uP3, uP4;
float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
vec2 rot(vec2 p, float a) { float c = cos(a), s = sin(a); return vec2(c * p.x - s * p.y, s * p.x + c * p.y); }
float ringDist(vec2 q, vec2 ab) { return abs(length(q / ab) - 1.0) * min(ab.x, ab.y); }
void main() {
  const float C = 8.0;
  vec2 pos = vec2(gl_FragCoord.x, uSize.y * uDpr - gl_FragCoord.y) / uDpr;
  vec2 cell = floor(pos / C), center = (cell + 0.5) * C, local = fract(pos / C) - 0.5;
  if (max(abs(local.x), abs(local.y)) > 0.36) { gl_FragColor = vec4(0.0); return; }
  float y01 = center.y / uSize.y, t = uTime;
  float h1 = hash(cell), h2 = hash(cell + 17.0);
  if (uScene > 2.5) {
    // Scene 3, the stamp celebration: rings and sparkles from the tap point
    // (the stamp), fading over about three seconds; no background pixels.
    float age = uTap.z, dist = length(center - uTap.xy), b = 0.0;
    for (int k = 0; k < 3; k++) {
      float since = age - float(k) * 0.18;
      if (since > 0.0) b = max(b, exp(-pow(dist - since * 260.0, 2.0) / (2.8 * C * C)) * clamp(1.0 - since * 0.7, 0.0, 1.0) * step(0.25, h2));
    }
    float spark = h1 > 0.9 && dist < 26.0 * C ? (0.5 + 0.5 * sin(t * 9.0 + h2 * 40.0)) * clamp(1.0 - age * 0.45, 0.0, 1.0) * smoothstep(26.0 * C, 6.0 * C, dist) : 0.0;
    float burst = max(b, spark);
    if (burst < 0.05) { gl_FragColor = vec4(0.0); return; }
    vec3 bc = burst < 0.3 ? uMid : burst < 0.6 ? uLit : uCrest;
    if (spark >= b) { float k = floor(h2 * 4.0); bc = k < 1.0 ? uP1 : k < 2.0 ? uP2 : k < 3.0 ? uP3 : uP4; }
    gl_FragColor = vec4(bc * uIntensity, uIntensity);
    return;
  }
  // Below the fill line: 0 at the line, 1 at the bottom edge.
  float yy = uFill > 0.5 ? (center.y - uFill) / max(uSize.y - uFill, 1.0) : y01;
  float d = uFill > 0.5 ? smoothstep(0.0, 0.3, yy) * mix(0.2, 1.0, yy * yy) : pow(smoothstep(0.45, 1.0, y01), 2.0);
  float v = h1 < d * 0.9 ? 0.18 + 0.22 * (0.5 + 0.5 * sin(t * 0.8 + h2 * 6.2832)) : 0.0;
  if (h2 > (uScene < 0.5 ? 0.985 : 0.992)) v = max(v, (0.35 + 0.35 * sin(t * 2.3 + h1 * 40.0)) * smoothstep(uFill > 0.5 ? 0.0 : 0.05, uFill > 0.5 ? 0.15 : 0.4, yy));
  float s = 0.0, ci = 0.0, r = (uRect.w - uRect.y) * 0.5;
  vec2 f = vec2(uRect.x + uRect.z, uRect.y + uRect.w) * 0.5;
  if (r < 5.0 * C) {
  } else if (uScene < 0.5) {
    float ph = fract(t / 7.0);
    vec2 head = vec2(mix(-0.1, 1.1, ph) * uSize.x, f.y + (ph - 0.5) * r * 1.2);
    vec2 dir = normalize(vec2(uSize.x * 1.2, r * 1.2)), rel = center - head;
    float along = dot(rel, -dir), perp = abs(dot(rel, vec2(-dir.y, dir.x))), len = 20.0 * C;
    if (along > 0.0 && along < len && perp < C * (0.6 + 1.4 * along / len)) s = 0.85 * (1.0 - along / len);
    s = max(s, exp(-dot(rel, rel) / (2.8 * C * C)));
  } else if (uScene < 1.5) {
    float a = min(r * 1.05, (uRect.z - uRect.x) * 0.3);
    vec2 ab = vec2(a, a * 0.34);
    if (length(center - f) < C * 2.2 * (1.0 + 0.08 * sin(t * 2.0))) { s = 1.0; ci = 3.0; }
    for (int i = 0; i < 3; i++) {
      float fi = float(i), ang = fi * 1.0472;
      if (ringDist(rot(center - f, -ang), ab) < 0.55 * C) s = max(s, 0.42);
      float w = t * (0.9 + 0.25 * fi) + fi * 2.1;
      if (length(center - f - rot(vec2(ab.x * cos(w), ab.y * sin(w)), ang)) < 1.4 * C) { s = 1.0; ci = 1.0; }
    }
  } else {
    // The sun near the left of the space; orbits out to its right edge and
    // within its height (the left halves run off the canvas).
    float sun = min(4.5 * C, r - 2.0 * C);
    vec2 c = vec2(uRect.x + (uRect.z - uRect.x) * 0.06 + sun + 2.0 * C, f.y);
    float dn = length(center - c), reach = uRect.z - c.x - 2.0 * C;
    if (dn < sun) { s = 1.0; ci = 3.0; } else if (dn < sun + 2.0 * C) s = 0.5;
    for (int i = 0; i < 4; i++) {
      float fi = float(i), a = reach * (0.34 + 0.22 * fi);
      vec2 ab = vec2(a, min(a * 0.22, r - 2.0 * C));
      if (ringDist(center - c, ab) < 0.5 * C) s = max(s, 0.4);
      float w = t * (0.5 / (1.0 + 0.6 * fi)) + fi * 1.7;
      if (length(center - c - vec2(ab.x * cos(w), ab.y * sin(w))) < C * (1.3 + 0.35 * fi)) { s = 1.0; ci = fi + 1.0; }
    }
  }
  float age = uPointer.z, pd = length(center - uPointer.xy);
  float hover = exp(-pd * pd / (24.5 * C * C)) * clamp(1.0 - age * 0.6, 0.0, 1.0) * (h1 > 0.3 ? 1.0 : 0.4);
  float tapAge = uTap.z, td = length(center - uTap.xy);
  float ripple = exp(-pow(td - tapAge * 220.0, 2.0) / (2.8 * C * C)) * clamp(1.0 - tapAge * 0.8, 0.0, 1.0) * step(0.2, h2);
  float fx = max(hover, ripple), level = max(max(v, s), fx);
  if (level < 0.05) { gl_FragColor = vec4(0.0); return; }
  vec3 col = level < 0.3 ? uDim : level < 0.55 ? uMid : level < 0.8 ? uLit : uCrest;
  if (ci > 0.5 && s >= max(v, fx)) col = ci < 1.5 ? uP1 : ci < 2.5 ? uP2 : ci < 3.5 ? uP3 : uP4;
  float alpha = uIntensity * (uFill > 0.5 ? smoothstep(-0.02, 0.1, yy) : smoothstep(0.0, 0.3, y01));
  gl_FragColor = vec4(col * alpha, alpha);
}`;

  const scope = self as unknown as { onmessage: ((event: MessageEvent<Message>) => void) | null; requestAnimationFrame?: (callback: () => void) => number };
  let gl: WebGLRenderingContext | null = null;
  let uniforms: Record<string, WebGLUniformLocation | null> = {};
  let size = { width: 0, height: 0, dpr: 1 };
  let scene = 0;
  let intensity = 1;
  let colors: Colors | null = null;
  let pointer = { x: -9999, y: -9999, at: -99999 };
  let tap = { x: -9999, y: -9999, at: -99999 };
  let fill = 0;
  let rect: [number, number, number, number] = [0, 0, 0, 0];
  let running = false;
  let reduceMotion = false;
  let scheduled = false;
  let last = 0;
  const started = performance.now();
  const frameMs = 1000 / 30;

  function compile(type: number, source: string) {
    const shader = gl!.createShader(type)!;
    gl!.shaderSource(shader, source);
    gl!.compileShader(shader);
    return shader;
  }

  function setup(canvas: OffscreenCanvas) {
    gl = canvas.getContext('webgl', { alpha: true, premultipliedAlpha: true, antialias: false }) as WebGLRenderingContext | null;
    if (!gl) return;
    const program = gl.createProgram()!;
    gl.attachShader(program, compile(gl.VERTEX_SHADER, vertex));
    gl.attachShader(program, compile(gl.FRAGMENT_SHADER, fragment));
    gl.linkProgram(program);
    if (!gl.getProgramParameter(program, gl.LINK_STATUS)) { gl = null; return; }
    gl.useProgram(program);
    // One triangle that covers the whole canvas.
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    const location = gl.getAttribLocation(program, 'p');
    gl.enableVertexAttribArray(location);
    gl.vertexAttribPointer(location, 2, gl.FLOAT, false, 0, 0);
    for (const name of ['uSize', 'uDpr', 'uTime', 'uScene', 'uIntensity', 'uFill', 'uPointer', 'uTap', 'uRect', 'uDim', 'uMid', 'uLit', 'uCrest', 'uP1', 'uP2', 'uP3', 'uP4']) {
      uniforms[name] = gl.getUniformLocation(program, name);
    }
  }

  function draw(now: number) {
    if (!gl || !colors || !size.width || !size.height) return;
    const canvas = gl.canvas as OffscreenCanvas;
    const width = Math.round(size.width * size.dpr), height = Math.round(size.height * size.dpr);
    if (canvas.width !== width || canvas.height !== height) { canvas.width = width; canvas.height = height; }
    gl.viewport(0, 0, width, height);
    const time = reduceMotion ? 12 : (now - started) / 1000;
    gl.uniform2f(uniforms.uSize, size.width, size.height);
    gl.uniform1f(uniforms.uDpr, size.dpr);
    gl.uniform1f(uniforms.uTime, time);
    gl.uniform1f(uniforms.uScene, scene);
    gl.uniform1f(uniforms.uIntensity, intensity);
    gl.uniform3f(uniforms.uPointer, pointer.x, pointer.y, reduceMotion ? 99 : (now - pointer.at) / 1000);
    gl.uniform3f(uniforms.uTap, tap.x, tap.y, reduceMotion ? 99 : (now - tap.at) / 1000);
    gl.uniform1f(uniforms.uFill, fill);
    gl.uniform4f(uniforms.uRect, ...rect);
    const set = (name: string, [r, g, b]: RGB) => gl!.uniform3f(uniforms[name], r, g, b);
    set('uDim', colors.dim); set('uMid', colors.mid); set('uLit', colors.lit); set('uCrest', colors.crest);
    colors.planets.forEach((planet, i) => set(`uP${i + 1}`, planet));
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  /** About 30 frames a second while running; one still frame otherwise. */
  function schedule() {
    if (scheduled) return;
    scheduled = true;
    const next = () => {
      scheduled = false;
      const now = performance.now();
      if (now - last >= frameMs - 2) { last = now; draw(now); }
      if (running && !reduceMotion) schedule();
    };
    if (scope.requestAnimationFrame) scope.requestAnimationFrame(next); else setTimeout(next, frameMs);
  }

  scope.onmessage = ({ data }) => {
    switch (data.type) {
      case 'init': reduceMotion = data.reduceMotion; setup(data.canvas); break;
      case 'size': size = { width: data.width, height: data.height, dpr: Math.min(data.dpr, 2) }; break;
      case 'scene': scene = data.scene; intensity = data.intensity; break;
      case 'colors': colors = data.colors; break;
      case 'pointer':
        pointer = { x: data.x, y: data.y, at: performance.now() };
        if (data.tap) tap = { ...pointer };
        break;
      case 'run': running = data.running; break;
      case 'focus': fill = data.fill; rect = data.rect; break;
    }
    // Draw at once for changes while paused (size, theme), and keep going if running.
    last = 0;
    schedule();
  };
})();
