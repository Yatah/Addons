// Transparent regions enclosed by a frame (not connected to the image border):
// label map + bbox per hole (x0, y0, x1, y1, count).
public static class Holes {
	public static int[] Label(Img s, float t, out System.Collections.Generic.List<int[]> boxes) {
		int W = s.W, H = s.H; var lab = new int[W * H]; boxes = new System.Collections.Generic.List<int[]>();
		var q = new System.Collections.Generic.Queue<int>();
		// exterior = -1
		for (int x = 0; x < W; x++) { Seed(s, t, lab, q, x, 0, -1); Seed(s, t, lab, q, x, H - 1, -1); }
		for (int y = 0; y < H; y++) { Seed(s, t, lab, q, 0, y, -1); Seed(s, t, lab, q, W - 1, y, -1); }
		Flood(s, t, lab, q, -1, null);
		int n = 0;
		for (int i = 0; i < W * H; i++) if (lab[i] == 0 && s.A[i] < t) {
			n++; var b = new int[] { W, H, -1, -1, 0 }; lab[i] = n; q.Enqueue(i); Flood(s, t, lab, q, n, b); boxes.Add(b);
		}
		return lab;
	}
	static void Seed(Img s, float t, int[] lab, System.Collections.Generic.Queue<int> q, int x, int y, int v) { int i = y * s.W + x; if (lab[i] == 0 && s.A[i] < t) { lab[i] = v; q.Enqueue(i); } }
	static void Flood(Img s, float t, int[] lab, System.Collections.Generic.Queue<int> q, int v, int[] b) {
		int W = s.W, H = s.H;
		while (q.Count > 0) {
			int i = q.Dequeue(), x = i % W, y = i / W;
			if (b != null) { if (x < b[0]) b[0] = x; if (y < b[1]) b[1] = y; if (x > b[2]) b[2] = x; if (y > b[3]) b[3] = y; b[4]++; }
			if (x > 0) Seed(s, t, lab, q, x - 1, y, v); if (x < W - 1) Seed(s, t, lab, q, x + 1, y, v);
			if (y > 0) Seed(s, t, lab, q, x, y - 1, v); if (y < H - 1) Seed(s, t, lab, q, x, y + 1, v);
		}
	}
}

// the inside of a frame (everything the outside can't reach through its line): a vertical
// gradient fill, alpha a, nothing outside the line (chamfered corners stay clean)
public static class Inside {
	public static Img Fill(Img frame, float t, float r0, float g0, float b0, float r1, float g1, float b1, float a) {
		System.Collections.Generic.List<int[]> bx; int[] lab = Holes.Label(frame, t, out bx);
		var o = new Img(frame.W, frame.H);
		for (int y = 0; y < frame.H; y++) { float k = (float)y / frame.H;
			for (int x = 0; x < frame.W; x++) { int i = o.I(x, y); if (lab[i] == -1) continue;
				o.R[i] = r0 + (r1 - r0) * k; o.G[i] = g0 + (g1 - g0) * k; o.B[i] = b0 + (b1 - b0) * k; o.A[i] = a; } }
		return o;
	}
}