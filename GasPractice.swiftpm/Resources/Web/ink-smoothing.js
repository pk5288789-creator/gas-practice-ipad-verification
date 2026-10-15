'use strict';
(function installInkSmoothing(root) {
  const MAX_STRENGTH = 100;
  const MAX_SHIFT_RATIO = .25;
  const originalStrokes = new WeakMap();

  function normalizeStrength(value) {
    const number = typeof value === 'number' || typeof value === 'string' ? Number(value) : 0;
    return Number.isFinite(number) ? Math.max(0, Math.min(MAX_STRENGTH, number)) : 0;
  }

  function validStroke(stroke) {
    if (!stroke || !Array.isArray(stroke.points)) return false;
    for (const point of stroke.points) {
      if (!Array.isArray(point) || point.length < 2 ||
          !Number.isFinite(point[0]) || !Number.isFinite(point[1]) ||
          (point.length > 2 && !Number.isFinite(point[2]))) return false;
    }
    return true;
  }

  function smoothPoint(points, index, amount) {
    const point = points[index], result = point.slice();
    if (index === 0 || index === points.length - 1) return result;
    const previous = points[index - 1], next = points[index + 1];
    // A convex three-point filter reduces local wobble without crossing stroke boundaries.
    const dx = previous[0] / 4 + point[0] / 2 + next[0] / 4 - point[0];
    const dy = previous[1] / 4 + point[1] / 2 + next[1] / 4 - point[1];
    const shift = Math.hypot(dx, dy);
    if (!Number.isFinite(shift) || shift === 0) return result;
    const limit = MAX_SHIFT_RATIO * Math.min(
      Math.hypot(point[0] - previous[0], point[1] - previous[1]),
      Math.hypot(next[0] - point[0], next[1] - point[1]));
    const scale = amount * Math.min(1, limit / shift);
    result[0] += dx * scale;
    result[1] += dy * scale;
    return result;
  }

  /**
   * deriveStroke(rawStroke, strength 0..100) -> display stroke, or null for invalid input.
   * Points are [x,y,pressure?]; all pressure, extra point data and stroke metadata survive.
   * Render the WHOLE active raw stroke with this same interface on preview and saved redraw.
   * Neighbor-based smoothing can change the preceding segment when a new point arrives:
   * clear/replay the active layer, rather than painting a separately smoothed two-point tail.
   * Persist only the caller's raw stroke. Zero, erasers and strokes under three points bypass.
   * Output has one point per input and O(n) work; no interpolation or hidden joins are added.
   * Passing a previous display stroke re-derives from its original, preventing accumulation.
   */
  function deriveStroke(stroke, strength) {
    const raw = originalStrokes.get(stroke) || stroke;
    if (!validStroke(raw)) return null;
    const amount = normalizeStrength(strength) / MAX_STRENGTH;
    if (amount === 0 || raw.tool === 'eraser' || raw.points.length < 3) return raw;
    const display = {...raw, points: raw.points.map((_, index) => smoothPoint(raw.points, index, amount))};
    originalStrokes.set(display, raw);
    return display;
  }

  const api = Object.freeze({deriveStroke, normalizeStrength});
  root.InkSmoothing = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(globalThis);
