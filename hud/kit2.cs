public static class K2 {
	public static void Blit(Img C, Img s, int sx, int sy, int sw, int sh, int x, int y) {
		for (int j = 0; j < sh; j++) { int ty = y + j; if (ty < 0 || ty >= C.H) continue;
			for (int i = 0; i < sw; i++) { int tx = x + i; if (tx < 0 || tx >= C.W) continue;
				int si = s.I(sx + i, sy + j), d = C.I(tx, ty); float a = s.A[si]; if (a <= 0) continue;
				float da = C.A[d], na = a + da * (1 - a);
				C.R[d] = (s.R[si] * a + C.R[d] * da * (1 - a)) / na; C.G[d] = (s.G[si] * a + C.G[d] * da * (1 - a)) / na; C.B[d] = (s.B[si] * a + C.B[d] * da * (1 - a)) / na; C.A[d] = na; } }
	}
	public static void Put(Img C, Img s, int x, int y) { Blit(C, s, 0, 0, s.W, s.H, x, y); }
	// tile s over a rect (opaque fill)
	public static void Tile(Img C, Img s, int x, int y, int w, int h) { for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) { int tx = x + i, ty = y + j; if (tx < 0 || ty < 0 || tx >= C.W || ty >= C.H) continue; int u = i % (2 * s.W), v = j % (2 * s.H); if (u >= s.W) u = 2 * s.W - 1 - u; if (v >= s.H) v = 2 * s.H - 1 - v; int si = s.I(u, v), d = C.I(tx, ty); C.R[d] = s.R[si]; C.G[d] = s.G[si]; C.B[d] = s.B[si]; C.A[d] = 1; } }
	// horizontal 3-slice: left cap cw, right cap cw, middle stretched (s already cropped to its content)
	public static void Three(Img C, Img s, int cw, int x, int y, int w) {
		Blit(C, s, 0, 0, cw, s.H, x, y); Blit(C, s, s.W - cw, 0, cw, s.H, x + w - cw, y);
		var mid = s.Crop(cw, 0, s.W - 2 * cw, s.H).Resize(System.Math.Max(1, w - 2 * cw), s.H); Put(C, mid, x + cw, y);
	}
	// nine-slice, margin m, corners kept
	public static void Nine(Img C, Img s, int m, int x, int y, int w, int h) {
		int cw = s.W - 2 * m, ch = s.H - 2 * m;
		Blit(C, s, 0, 0, m, m, x, y); Blit(C, s, s.W - m, 0, m, m, x + w - m, y); Blit(C, s, 0, s.H - m, m, m, x, y + h - m); Blit(C, s, s.W - m, s.H - m, m, m, x + w - m, y + h - m);
		Put(C, s.Crop(m, 0, cw, m).Resize(w - 2 * m, m), x + m, y); Put(C, s.Crop(m, s.H - m, cw, m).Resize(w - 2 * m, m), x + m, y + h - m);
		Put(C, s.Crop(0, m, m, ch).Resize(m, h - 2 * m), x, y + m); Put(C, s.Crop(s.W - m, m, m, ch).Resize(m, h - 2 * m), x + w - m, y + m);
	}
	public static void Fill(Img C, int x, int y, int w, int h, float r, float g, float b) { for (int j = 0; j < h; j++) { float k = 1.15f - 0.35f * j / System.Math.Max(1, h - 1); for (int i = 0; i < w; i++) { int d = C.I(x + i, y + j); C.R[d] = System.Math.Min(1, r * k); C.G[d] = System.Math.Min(1, g * k); C.B[d] = System.Math.Min(1, b * k); C.A[d] = 1; } } }
	public static void Clear(Img im, int x0, int y0, int x1, int y1) { for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) im.A[im.I(x, y)] = 0; }
}
