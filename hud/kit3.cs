public static class K3 {
	public static void Rect(Img C, int x, int y, int w, int h, float r, float g, float b, float a) {
		for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) { int tx = x + i, ty = y + j; if (tx < 0 || ty < 0 || tx >= C.W || ty >= C.H) continue; int d = C.I(tx, ty);
			float da = C.A[d], na = a + da * (1 - a); if (na <= 0) continue; C.R[d] = (r * a + C.R[d] * da * (1 - a)) / na; C.G[d] = (g * a + C.G[d] * da * (1 - a)) / na; C.B[d] = (b * a + C.B[d] * da * (1 - a)) / na; C.A[d] = na; } }
	// recessed slot: dark well, light bevel bottom-right, dark top-left, thin stone rim
	public static void Slot(Img C, int x, int y, int s) {
		Rect(C, x, y, s, s, 0.62f, 0.60f, 0.56f, 0.9f);            // stone rim
		Rect(C, x + 1, y + 1, s - 2, s - 2, 0.10f, 0.09f, 0.08f, 1);
		Rect(C, x + 2, y + 2, s - 4, s - 4, 0.045f, 0.042f, 0.04f, 1);
		Rect(C, x + 2, y + 2, s - 4, 2, 0f, 0f, 0f, 0.6f); Rect(C, x + 2, y + 2, 2, s - 4, 0f, 0f, 0f, 0.6f);
	}
	// soft drop shadow band (inner shadow of a panel under a rail)
	public static void ShadeY(Img C, int x, int y, int w, int h, bool down) { for (int j = 0; j < h; j++) { float a = 0.55f * (1 - (float)j / h); Rect(C, x, down ? y + j : y + h - 1 - j, w, 1, 0, 0, 0, a); } }
	public static void ShadeX(Img C, int x, int y, int w, int h, bool right) { for (int i = 0; i < w; i++) { float a = 0.45f * (1 - (float)i / w); Rect(C, right ? x + i : x + w - 1 - i, y, 1, h, 0, 0, 0, a); } }
}
public static class Comp1 {
	// keep only the connected component (alpha > t, 8-neighbour) containing the seed; returns its bounding crop
	public static Img Keep(Img m, float t, int sx, int sy) {
		int W = m.W, H = m.H; var mark = new bool[W * H]; var st = new System.Collections.Generic.Stack<int>();
		int s0 = sy * W + sx; if (m.A[s0] <= t) { // nearest opaque pixel to the seed
			int best = -1; double bd = 1e18; for (int i = 0; i < W * H; i++) if (m.A[i] > t) { double dx = i % W - sx, dy = i / W - sy, dd = dx * dx + dy * dy; if (dd < bd) { bd = dd; best = i; } } s0 = best; }
		mark[s0] = true; st.Push(s0); int x0 = W, y0 = H, x1 = 0, y1 = 0;
		while (st.Count > 0) { int p = st.Pop(); int x = p % W, y = p / W; if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y;
			for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) { int nx = x + dx, ny = y + dy; if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue; int q = ny * W + nx; if (!mark[q] && m.A[q] > t) { mark[q] = true; st.Push(q); } } }
		var o = new Img(x1 - x0 + 1, y1 - y0 + 1);
		for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) { int a = y * W + x, b = o.I(x - x0, y - y0); if (mark[a]) { o.R[b] = m.R[a]; o.G[b] = m.G[a]; o.B[b] = m.B[a]; o.A[b] = m.A[a]; } }
		return o;
	}
}
public static class Arch {
	// arch frame from a top-left arch quarter (256 px): the opening = inside the ellipse centred on the bottom-right corner
	// half = scaled quarter width; H = total height (straight jambs below the springing); tint = per-channel gain
	public static Img Build(Img q, float rx, float ry, int half, int H, float gr, float gg, float gb) {
		var m = q.Clone();
		for (int y = 0; y < q.H; y++) for (int x = 0; x < q.W; x++) { float dx = (x - (q.W - 1)) / rx, dy = (y - (q.H - 1)) / ry; if (dx * dx + dy * dy < 1) m.A[m.I(x, y)] = 0; }
		for (int i = 0; i < m.R.Length; i++) { m.R[i] = System.Math.Min(1, m.R[i] * gr); m.G[i] = System.Math.Min(1, m.G[i] * gg); m.B[i] = System.Math.Min(1, m.B[i] * gb); }
		var s = m.Resize(half, half);
		var o = new Img(2 * half, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < half; x++) {
			int sy = y < half ? y : half - 1;   // below the quarter: repeat its last row (jamb)
			int a = s.I(x, sy);
			foreach (int tx in new int[] { x, 2 * half - 1 - x }) { int b = o.I(tx, y); o.R[b] = s.R[a]; o.G[b] = s.G[a]; o.B[b] = s.B[a]; o.A[b] = s.A[a]; }
		}
		return o;
	}
}
public static class Niche {
	// niche of jaCryptBrick01 (x 0..193): opening = ellipse top (centre cx,cy radii rx,ry) + rectangle below cy
	public static Img Cut(Img q, int x0, int w, float cx, float cy, float rx, float ry, float xl, float xr) {
		var o = q.Crop(x0, 0, w, q.H);
		for (int y = 0; y < o.H; y++) for (int x = 0; x < o.W; x++) {
			float gx = x + x0; bool inside;
			if (y >= cy) inside = gx >= xl && gx <= xr;
			else { float dx = (gx - cx) / rx, dy = (y - cy) / ry; inside = dx * dx + dy * dy < 1; }
			if (inside) o.A[o.I(x, y)] = 0;
		}
		return o;
	}
}
