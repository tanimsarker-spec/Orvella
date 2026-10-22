/**
 * Parse an HTTP Range header against a known size.
 * No header -> whole file (uncapped, partial=false). Otherwise capped to maxChunk.
 * Returns null for unsatisfiable/invalid ranges.
 */
export function parseRange(header, size, maxChunk) {
  if (!Number.isInteger(size) || size < 1) return null;
  if (!header) return { start: 0, end: size - 1, partial: false };
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header).trim());
  if (!m || (m[1] === '' && m[2] === '')) return null;
  let start;
  let end;
  if (m[1] === '') {
    const n = Number(m[2]);
    if (n === 0) return null;
    start = Math.max(0, size - n);
    end = size - 1;
  } else {
    start = Number(m[1]);
    end = m[2] === '' ? size - 1 : Math.min(Number(m[2]), size - 1);
  }
  if (start >= size || start > end) return null;
  end = Math.min(end, start + maxChunk - 1);
  return { start, end, partial: true };
}
