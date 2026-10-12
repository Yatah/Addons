using System;
using System.IO;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Drawing.Drawing2D;

// Pixel buffer in float RGBA (0..1, straight alpha): all the compositing work is
// done on these, Bitmaps only for load / save / resampling.
public class Img {
	public int W, H;
	public float[] R, G, B, A;
	public Img(int w, int h) { W = w; H = h; R = new float[w * h]; G = new float[w * h]; B = new float[w * h]; A = new float[w * h]; }
	public Img Clone() { var o = new Img(W, H); Array.Copy(R, o.R, R.Length); Array.Copy(G, o.G, G.Length); Array.Copy(B, o.B, B.Length); Array.Copy(A, o.A, A.Length); return o; }
	public int I(int x, int y) { return y * W + x; }

	public static Img FromBitmap(Bitmap bm) {
		var o = new Img(bm.Width, bm.Height);
		var d = bm.LockBits(new Rectangle(0, 0, bm.Width, bm.Height), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var px = new byte[bm.Width * bm.Height * 4];
		System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length);
		bm.UnlockBits(d);
		for (int i = 0; i < o.R.Length; i++) { o.B[i] = px[i * 4] / 255f; o.G[i] = px[i * 4 + 1] / 255f; o.R[i] = px[i * 4 + 2] / 255f; o.A[i] = px[i * 4 + 3] / 255f; }
		return o;
	}
	public Bitmap ToBitmap() {
		var bm = new Bitmap(W, H, PixelFormat.Format32bppArgb);
		var d = bm.LockBits(new Rectangle(0, 0, W, H), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
		var px = new byte[W * H * 4];
		for (int i = 0; i < R.Length; i++) { px[i * 4] = C(B[i]); px[i * 4 + 1] = C(G[i]); px[i * 4 + 2] = C(R[i]); px[i * 4 + 3] = C(A[i]); }
		System.Runtime.InteropServices.Marshal.Copy(px, 0, d.Scan0, px.Length);
		bm.UnlockBits(d);
		return bm;
	}
	static byte C(float v) { v = v * 255f + 0.5f; return (byte)(v < 0 ? 0 : v > 255 ? 255 : v); }
	public static Img Load(string p) {
		if (p.EndsWith(".tga", StringComparison.OrdinalIgnoreCase)) return FromBitmap(Tga.Load(p));
		using (var bm = new Bitmap(p)) return FromBitmap(bm);
	}
	public void SavePng(string p) { using (var bm = ToBitmap()) bm.Save(p, ImageFormat.Png); }
	public void SaveTga(string p) { using (var bm = ToBitmap()) Tga.Save(bm, p); }
	// preview on a colour (to judge the matte)
	public void SavePreview(string p, int r, int g, int b) {
		var o = new Img(W, H);
		for (int i = 0; i < R.Length; i++) { float a = A[i]; o.R[i] = R[i] * a + r / 255f * (1 - a); o.G[i] = G[i] * a + g / 255f * (1 - a); o.B[i] = B[i] * a + b / 255f * (1 - a); o.A[i] = 1; }
		o.SavePng(p);
	}

	public Img Crop(int x, int y, int w, int h) {
		var o = new Img(w, h);
		for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) {
			int sx = x + i, sy = y + j; if (sx < 0 || sy < 0 || sx >= W || sy >= H) continue;
			int s = I(sx, sy), t = o.I(i, j); o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s]; o.A[t] = A[s];
		}
		return o;
	}

	// resampling through GDI+ on premultiplied data (no dark fringes)
	public Img Resize(int w, int h) {
		var pre = Clone();
		for (int i = 0; i < R.Length; i++) { pre.R[i] *= A[i]; pre.G[i] *= A[i]; pre.B[i] *= A[i]; }
		Bitmap src = new Bitmap(W, H, PixelFormat.Format64bppArgb);
		// encode premultiplied rgb as plain 32 bit colour + alpha channel separately
		using (var cb = pre.RgbBitmap()) using (var ab = pre.AlphaBitmap())
		using (var cr = ResizeBm(cb, w, h)) using (var ar = ResizeBm(ab, w, h)) {
			var o = FromBitmap(cr); var oa = FromBitmap(ar);
			for (int i = 0; i < o.R.Length; i++) {
				float a = oa.R[i]; o.A[i] = a;
				if (a > 0.002f) { o.R[i] = Math.Min(1, o.R[i] / a); o.G[i] = Math.Min(1, o.G[i] / a); o.B[i] = Math.Min(1, o.B[i] / a); }
				else { o.R[i] = o.G[i] = o.B[i] = 0; }
			}
			src.Dispose();
			return o;
		}
	}
	Bitmap RgbBitmap() { var o = Clone(); for (int i = 0; i < A.Length; i++) o.A[i] = 1; return o.ToBitmap(); }
	Bitmap AlphaBitmap() { var o = new Img(W, H); for (int i = 0; i < A.Length; i++) { o.R[i] = o.G[i] = o.B[i] = A[i]; o.A[i] = 1; } return o.ToBitmap(); }
	static Bitmap ResizeBm(Bitmap b, int w, int h) {
		var o = new Bitmap(w, h, PixelFormat.Format32bppArgb);
		using (var g = Graphics.FromImage(o)) {
			g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
			g.CompositingMode = CompositingMode.SourceCopy;
			using (var ia = new ImageAttributes()) { ia.SetWrapMode(WrapMode.TileFlipXY); g.DrawImage(b, new Rectangle(0, 0, w, h), 0, 0, b.Width, b.Height, GraphicsUnit.Pixel, ia); }
		}
		return o;
	}
	public Img Scale(double f) { return Resize(Math.Max(1, (int)Math.Round(W * f)), Math.Max(1, (int)Math.Round(H * f))); }

	// unsharp mask on the colour (3x3 gaussian)
	public void Sharpen(float amount) {
		var bl = Clone(); bl.Blur(1);
		for (int i = 0; i < R.Length; i++) {
			R[i] = Cl(R[i] + (R[i] - bl.R[i]) * amount); G[i] = Cl(G[i] + (G[i] - bl.G[i]) * amount); B[i] = Cl(B[i] + (B[i] - bl.B[i]) * amount);
		}
	}
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	// box blur passes (approx gaussian), all channels
	public void Blur(int radius) {
		for (int pass = 0; pass < 2; pass++) { BlurDir(radius, true); BlurDir(radius, false); }
	}
	void BlurDir(int r, bool horiz) {
		var ch = new float[][] { R, G, B, A };
		foreach (var c in ch) {
			var t = new float[c.Length];
			for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
				float s = 0; int n = 0;
				for (int k = -r; k <= r; k++) {
					int xx = horiz ? x + k : x, yy = horiz ? y : y + k;
					if (xx < 0) xx = 0; if (yy < 0) yy = 0; if (xx >= W) xx = W - 1; if (yy >= H) yy = H - 1;
					s += c[yy * W + xx]; n++;
				}
				t[y * W + x] = s / n;
			}
			Array.Copy(t, c, t.Length);
		}
	}

	// Matte: pixels close to one of the background colours become transparent,
	// only when connected to the crop border through background-like pixels
	// (dark details inside the object stay). t0: fully bg under, t1: fully fg over.
	// checker squares: neutral greys in [NeutralLo, NeutralHi] count as background
	public static float NeutralLo = 2, NeutralHi = 0, NeutralSat = 0.07f;
	public void Matte(float[][] bgs, float t0, float t1, bool[] keep) {
		var dist = new float[W * H];
		for (int i = 0; i < dist.Length; i++) {
			float best = 99;
			foreach (var c in bgs) { float dr = R[i] - c[0], dg = G[i] - c[1], db = B[i] - c[2]; float d = (float)Math.Sqrt(dr * dr + dg * dg + db * db); if (d < best) best = d; }
			float h, s, v; ToHsv(R[i], G[i], B[i], out h, out s, out v);
			if (s < NeutralSat && v >= NeutralLo && v <= NeutralHi) best = Math.Min(best, t0);
			dist[i] = best;
		}
		var bg = new bool[W * H];
		var q = new Queue<int>();
		for (int x = 0; x < W; x++) { Seed(q, bg, dist, x, 0, t1, keep); Seed(q, bg, dist, x, H - 1, t1, keep); }
		for (int y = 0; y < H; y++) { Seed(q, bg, dist, 0, y, t1, keep); Seed(q, bg, dist, W - 1, y, t1, keep); }
		while (q.Count > 0) {
			int i = q.Dequeue(); int x = i % W, y = i / W;
			if (x > 0) Seed(q, bg, dist, x - 1, y, t1, keep); if (x < W - 1) Seed(q, bg, dist, x + 1, y, t1, keep);
			if (y > 0) Seed(q, bg, dist, x, y - 1, t1, keep); if (y < H - 1) Seed(q, bg, dist, x, y + 1, t1, keep);
		}
		for (int i = 0; i < dist.Length; i++) {
			if (!bg[i]) continue;
			float a = (dist[i] - t0) / (t1 - t0); if (a < 0) a = 0; if (a > 1) a = 1;
			A[i] = Math.Min(A[i], a);
		}
	}
	void Seed(Queue<int> q, bool[] bg, float[] dist, int x, int y, float t1, bool[] keep) {
		int i = y * W + x; if (bg[i] || dist[i] >= t1 || (keep != null && keep[i])) return; bg[i] = true; q.Enqueue(i);
	}
	// Matte for the sheet: background = the blue slate (hue ~210, blue > green)
	// or the neutral checker squares; foreground keeps anything warm, teal or
	// saturated, or clearly brighter / darker than the local background. Flood
	// from the crop border, soft edge, then the edge colours are pulled from the
	// foreground (no slate halo).
	public void Matte2(float slateTol, float checkLo, float checkHi, bool[] keep) {
		var bgLike = new float[W * H]; // 0 = sure background .. 1 = sure foreground
		for (int i = 0; i < bgLike.Length; i++) {
			float r = R[i], g = G[i], b = B[i];
			float h, s, v; ToHsv(r, g, b, out h, out s, out v);
			float f = 1;
			// slate: blue dominant, dark, low saturation
			bool bluish = b >= g - 0.004f && b >= r && g >= r - 0.006f;
			if (bluish && v < 0.26f && s < 0.42f) {
				float dv = Math.Abs(v - 0.17f);
				f = Math.Min(f, Math.Max(0, (dv - slateTol) / slateTol));
			}
			// checker: neutral grey in the checker range
			if (s < 0.07f && v >= checkLo && v <= checkHi) f = Math.Min(f, 0.0f);
			// very dark neutral (the slate's own shadow round the pieces)
			if (s < 0.25f && v < 0.085f && bluish) f = 0;
			bgLike[i] = f;
		}
		var bg = new bool[W * H]; var q = new Queue<int>();
		Action<int, int> seed = (x, y) => { int i = y * W + x; if (bg[i] || bgLike[i] > 0.5f || (keep != null && keep[i])) return; bg[i] = true; q.Enqueue(i); };
		for (int x = 0; x < W; x++) { seed(x, 0); seed(x, H - 1); }
		for (int y = 0; y < H; y++) { seed(0, y); seed(W - 1, y); }
		while (q.Count > 0) { int i = q.Dequeue(); int x = i % W, y = i / W;
			if (x > 0) seed(x - 1, y); if (x < W - 1) seed(x + 1, y); if (y > 0) seed(x, y - 1); if (y < H - 1) seed(x, y + 1); }
		for (int i = 0; i < A.Length; i++) if (bg[i]) A[i] = Math.Min(A[i], bgLike[i]);
		// soft edge: 1 px blur of the alpha, only where it lowers it next to the background
		var a2 = (float[])A.Clone();
		for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++) {
			int i = y * W + x; if (A[i] <= 0) continue;
			float m = (A[i] * 4 + A[i - 1] + A[i + 1] + A[i - W] + A[i + W]) / 8;
			a2[i] = Math.Min(A[i], m);
		}
		A = a2;
		// edge colours from the most opaque neighbour
		var r0 = (float[])R.Clone(); var g0 = (float[])G.Clone(); var b0 = (float[])B.Clone();
		for (int y = 1; y < H - 1; y++) for (int x = 1; x < W - 1; x++) {
			int i = y * W + x; if (A[i] <= 0 || A[i] >= 0.95f) continue;
			int best = i; float ba = A[i];
			for (int k = -2; k <= 2; k++) for (int l = -2; l <= 2; l++) {
				int xx = x + l, yy = y + k; if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
				int j = yy * W + xx; if (A[j] > ba) { ba = A[j]; best = j; }
			}
			R[i] = r0[best]; G[i] = g0[best]; B[i] = b0[best];
		}
	}
	// painted shadows on the background: dark neutral pixels (below yFrom) with
	// no bright opaque pixel within `radius` become transparent
	public void RemoveDarkFar(int yFrom, float vDark, float vBright, int radius, float satMax) {
		var bright = new bool[W * H];
		for (int i = 0; i < A.Length; i++) { float v = Math.Max(R[i], Math.Max(G[i], B[i])); bright[i] = A[i] > 0.5f && v > vBright; }
		var kill = new List<int>();
		for (int y = Math.Max(0, yFrom); y < H; y++) for (int x = 0; x < W; x++) {
			int i = y * W + x; if (A[i] <= 0) continue;
			float h, s, v; ToHsv(R[i], G[i], B[i], out h, out s, out v);
			if (v >= vDark || s > satMax) continue;
			bool near = false;
			for (int k = -radius; k <= radius && !near; k++) for (int l = -radius; l <= radius && !near; l++) {
				int xx = x + l, yy = y + k; if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue;
				if (bright[yy * W + xx]) near = true;
			}
			if (!near) kill.Add(i);
		}
		foreach (int i in kill) A[i] = 0;
	}
	// Chroma key on a magenta background: key = how magenta a pixel is
	// (min(R, B) - G, with R ~ B), flood from the border through keyed pixels,
	// soft edge, magenta spill removed from the edge colours.
	public void KeyMagenta(float k0, float k1) {
		var key = new float[W * H];
		for (int i = 0; i < key.Length; i++) {
			float m = Math.Min(R[i], B[i]) - G[i];
			float bal = 1 - Math.Min(1, Math.Abs(R[i] - B[i]) * 2.5f);
			key[i] = m * bal; // ~0.9 on the background
		}
		var bg = new bool[W * H]; var q = new Queue<int>();
		Action<int, int> seed = (x, y) => { int i = y * W + x; if (bg[i] || key[i] < k0) return; bg[i] = true; q.Enqueue(i); };
		// (every keyed pixel: enclosed holes of frames too)
		// (big keyed areas only: a glowing purple eye core stays)
		{
			var lab = new int[W * H]; int id = 0; var qq = new Queue<int>(); var comp = new List<int>();
			for (int s = 0; s < key.Length; s++) {
				if (lab[s] != 0 || key[s] < k0) continue;
				id++; comp.Clear(); qq.Enqueue(s); lab[s] = id;
				while (qq.Count > 0) {
					int i = qq.Dequeue(); comp.Add(i); int x = i % W, y = i / W;
					if (x > 0 && lab[i - 1] == 0 && key[i - 1] >= k0) { lab[i - 1] = id; qq.Enqueue(i - 1); }
					if (x < W - 1 && lab[i + 1] == 0 && key[i + 1] >= k0) { lab[i + 1] = id; qq.Enqueue(i + 1); }
					if (y > 0 && lab[i - W] == 0 && key[i - W] >= k0) { lab[i - W] = id; qq.Enqueue(i - W); }
					if (y < H - 1 && lab[i + W] == 0 && key[i + W] >= k0) { lab[i + W] = id; qq.Enqueue(i + W); }
				}
				if (comp.Count >= 4000) foreach (int i in comp) bg[i] = true;
			}
		}
		for (int x = 0; x < W; x++) { seed(x, 0); seed(x, H - 1); }
		for (int y = 0; y < H; y++) { seed(0, y); seed(W - 1, y); }
		while (q.Count > 0) { int i = q.Dequeue(); int x = i % W, y = i / W;
			if (x > 0) seed(x - 1, y); if (x < W - 1) seed(x + 1, y); if (y > 0) seed(x, y - 1); if (y < H - 1) seed(x, y + 1); }
		// alpha: background 0, its neighbours by their key (anti aliasing)
		var near = new bool[W * H];
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			int i = y * W + x; if (!bg[i]) continue;
			for (int k = -2; k <= 2; k++) for (int l = -2; l <= 2; l++) {
				int xx = x + l, yy = y + k; if (xx >= 0 && yy >= 0 && xx < W && yy < H) near[yy * W + xx] = true;
			}
		}
		for (int i = 0; i < key.Length; i++) {
			if (bg[i]) { A[i] = 0; continue; }
			if (!near[i]) continue;
			float a = 1 - Math.Max(0, Math.Min(1, (key[i] - k0 * 0.25f) / (k1 - k0 * 0.25f)));
			A[i] = Math.Min(A[i], a);
			// despill: pull the magenta excess out of the colour
			float ex = Math.Min(R[i], B[i]) - G[i];
			if (ex > 0) { float s = ex * (1 - a * 0.5f); R[i] -= s; B[i] -= s; }
		}
	}
	// bounding box of the opaque pixels (alpha > t): x, y, w, h
	public int[] Bounds(float t) {
		int x0 = W, y0 = H, x1 = -1, y1 = -1;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) if (A[y * W + x] > t) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
		return x1 < 0 ? new[] { 0, 0, W, H } : new[] { x0, y0, x1 - x0 + 1, y1 - y0 + 1 };
	}
	// drop the alpha islands smaller than `minArea` pixels (matte leftovers)
	public void RemoveIslands(int minArea, float thr) {
		var lab = new int[W * H]; int id = 0; var q = new Queue<int>(); var comp = new List<int>();
		for (int s = 0; s < lab.Length; s++) {
			if (lab[s] != 0 || A[s] <= thr) continue;
			id++; comp.Clear(); q.Enqueue(s); lab[s] = id;
			while (q.Count > 0) {
				int i = q.Dequeue(); comp.Add(i); int x = i % W, y = i / W;
				for (int k = 0; k < 8; k++) {
					int xx = x + (k == 0 || k == 4 || k == 5 ? 1 : k == 1 || k == 6 || k == 7 ? -1 : 0);
					int yy = y + (k == 2 || k == 4 || k == 6 ? 1 : k == 3 || k == 5 || k == 7 ? -1 : 0);
					if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue; int j = yy * W + xx;
					if (lab[j] == 0 && A[j] > thr) { lab[j] = id; q.Enqueue(j); }
				}
			}
			if (comp.Count < minArea) foreach (int i in comp) A[i] = 0;
		}
		// faint pixels not attached to a kept island
		for (int i = 0; i < A.Length; i++) {
			if (A[i] > thr || A[i] == 0) continue;
			int x = i % W, y = i / W; bool near = false;
			for (int k = -2; k <= 2 && !near; k++) for (int l = -2; l <= 2 && !near; l++) {
				int xx = x + k, yy = y + l; if (xx < 0 || yy < 0 || xx >= W || yy >= H) continue; if (A[yy * W + xx] > thr) near = true;
			}
			if (!near) A[i] = 0;
		}
	}
	// erode the alpha a little (removes the background halo), then feather
	public void CleanEdges(float shrink) {
		var a = (float[])A.Clone();
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			float m = a[y * W + x];
			for (int k = 0; k < 4; k++) {
				int xx = x + (k == 0 ? 1 : k == 1 ? -1 : 0), yy = y + (k == 2 ? 1 : k == 3 ? -1 : 0);
				if (xx < 0 || yy < 0 || xx >= W || yy >= H) { m = Math.Min(m, 0); continue; }
				m = Math.Min(m, a[yy * W + xx]);
			}
			A[y * W + x] = a[y * W + x] * (1 - shrink) + m * shrink;
		}
	}
	public void Levels(float gain, float bias) { for (int i = 0; i < R.Length; i++) { R[i] = Cl(R[i] * gain + bias); G[i] = Cl(G[i] * gain + bias); B[i] = Cl(B[i] * gain + bias); } }
	public void Saturate(float s) {
		for (int i = 0; i < R.Length; i++) { float l = R[i] * 0.3f + G[i] * 0.59f + B[i] * 0.11f; R[i] = Cl(l + (R[i] - l) * s); G[i] = Cl(l + (G[i] - l) * s); B[i] = Cl(l + (B[i] - l) * s); }
	}

	// hue remap: pixels whose hue is within [h0,h1] (degrees) and saturation > smin
	// get hue hNew (weight fades with saturation); satMul / valMul on them
	public void HueRemap(float h0, float h1, float hNew, float smin, float satMul, float valMul) {
		for (int i = 0; i < R.Length; i++) {
			float h, s, v; ToHsv(R[i], G[i], B[i], out h, out s, out v);
			if (h < h0 || h > h1 || s < smin) continue;
			float w = Math.Min(1, (s - smin) / 0.15f);
			float r, g, b; FromHsv(hNew, Math.Min(1, s * satMul), Math.Min(1, v * valMul), out r, out g, out b);
			R[i] = R[i] * (1 - w) + r * w; G[i] = G[i] * (1 - w) + g * w; B[i] = B[i] * (1 - w) + b * w;
		}
	}
	public static void ToHsv(float r, float g, float b, out float h, out float s, out float v) {
		float mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b)), d = mx - mn; v = mx; s = mx > 0 ? d / mx : 0;
		if (d < 1e-5f) { h = 0; return; }
		if (mx == r) h = 60 * (((g - b) / d) % 6); else if (mx == g) h = 60 * ((b - r) / d + 2); else h = 60 * ((r - g) / d + 4);
		if (h < 0) h += 360;
	}
	public static void FromHsv(float h, float s, float v, out float r, out float g, out float b) {
		float c = v * s, x = c * (1 - Math.Abs((h / 60) % 2 - 1)), m = v - c;
		if (h < 60) { r = c; g = x; b = 0; } else if (h < 120) { r = x; g = c; b = 0; } else if (h < 180) { r = 0; g = c; b = x; }
		else if (h < 240) { r = 0; g = x; b = c; } else if (h < 300) { r = x; g = 0; b = c; } else { r = c; g = 0; b = x; }
		r += m; g += m; b += m;
	}

	// seamless horizontal tile: the last `ov` columns cross-fade into the first ones
	public Img SeamlessH(int ov) {
		int w = W - ov; var o = new Img(w, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < w; x++) {
			int s = I(x, y), t = o.I(x, y);
			float f = x < ov ? (float)x / ov : 1; // blend the start with the tail
			int s2 = I(x + w, y);
			if (x < ov) { o.R[t] = R[s] * f + R[s2] * (1 - f); o.G[t] = G[s] * f + G[s2] * (1 - f); o.B[t] = B[s] * f + B[s2] * (1 - f); o.A[t] = A[s] * f + A[s2] * (1 - f); }
			else { o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s]; o.A[t] = A[s]; }
		}
		return o;
	}
	public Img SeamlessV(int ov) { return Rot().SeamlessH(ov).Rot().Rot().Rot(); }
	// 90 degrees clockwise
	public Img Rot() {
		var o = new Img(H, W);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) { int s = I(x, y), t = o.I(H - 1 - y, x); o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s]; o.A[t] = A[s]; }
		return o;
	}
	public Img FlipH() {
		var o = new Img(W, H);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) { int s = I(x, y), t = o.I(W - 1 - x, y); o.R[t] = R[s]; o.G[t] = G[s]; o.B[t] = B[s]; o.A[t] = A[s]; }
		return o;
	}

	// alpha "over" compositing of src at (x, y), optional opacity
	public void Draw(Img s, int x, int y, float op) {
		for (int j = 0; j < s.H; j++) {
			int ty = y + j; if (ty < 0 || ty >= H) continue;
			for (int i = 0; i < s.W; i++) {
				int tx = x + i; if (tx < 0 || tx >= W) continue;
				int si = s.I(i, j), ti = I(tx, ty);
				float sa = s.A[si] * op; if (sa <= 0) continue;
				float da = A[ti], oa = sa + da * (1 - sa);
				R[ti] = (s.R[si] * sa + R[ti] * da * (1 - sa)) / oa; G[ti] = (s.G[si] * sa + G[ti] * da * (1 - sa)) / oa; B[ti] = (s.B[si] * sa + B[ti] * da * (1 - sa)) / oa;
				A[ti] = oa;
			}
		}
	}
	// soft drop shadow of the piece itself, returns a bigger image (pad on each side)
	public Img WithShadow(int dx, int dy, int blur, float op, int pad) {
		var o = new Img(W + pad * 2, H + pad * 2);
		var sh = new Img(W + pad * 2, H + pad * 2);
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			int tx = x + pad + dx, ty = y + pad + dy; if (tx < 0 || ty < 0 || tx >= sh.W || ty >= sh.H) continue;
			sh.A[sh.I(tx, ty)] = A[I(x, y)] * op;
		}
		if (blur > 0) sh.Blur(blur);
		o.Draw(sh, 0, 0, 1);
		o.Draw(this, pad, pad, 1);
		return o;
	}
	// fill a rectangle by repeating a tile (texture space of the target)
	public void FillTile(Img t, int x0, int y0, int w, int h, int ox, int oy) {
		for (int y = y0; y < y0 + h; y++) { if (y < 0 || y >= H) continue;
			for (int x = x0; x < x0 + w; x++) { if (x < 0 || x >= W) continue;
				int tx = ((x - ox) % t.W + t.W) % t.W, ty = ((y - oy) % t.H + t.H) % t.H;
				int s = t.I(tx, ty), d = I(x, y); R[d] = t.R[s]; G[d] = t.G[s]; B[d] = t.B[s]; A[d] = t.A[s];
			}
		}
	}
	public void Clear(int x0, int y0, int w, int h) {
		for (int y = y0; y < y0 + h; y++) for (int x = x0; x < x0 + w; x++) { if (x < 0 || y < 0 || x >= W || y >= H) continue; int d = I(x, y); R[d] = G[d] = B[d] = A[d] = 0; }
	}
	// darken a rectangle (inset / shadow), soft edges of `soft` px
	public void Shade(int x0, int y0, int w, int h, float amount, int soft) {
		for (int y = y0 - soft; y < y0 + h + soft; y++) { if (y < 0 || y >= H) continue;
			for (int x = x0 - soft; x < x0 + w + soft; x++) { if (x < 0 || x >= W) continue;
				float fx = Math.Min(1, Math.Min((float)(x - (x0 - soft)) / Math.Max(1, soft), (float)((x0 + w + soft) - x) / Math.Max(1, soft)));
				float fy = Math.Min(1, Math.Min((float)(y - (y0 - soft)) / Math.Max(1, soft), (float)((y0 + h + soft) - y) / Math.Max(1, soft)));
				float f = 1 - amount * Math.Max(0, Math.Min(fx, fy)); int d = I(x, y); R[d] *= f; G[d] *= f; B[d] *= f;
			}
		}
	}
	// steel rim along a rounded rectangle (x0,y0)-(x1,y1), radius r: dark outer
	// line, bright bevel, steel body, dark inner line, inner shadow; inside and
	// outside stay transparent (the frame of a bar / icon)
	public void SteelRim(float x0, float y0, float x1, float y1, float r, float width) {
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			float px = x + 0.5f, py = y + 0.5f;
			// signed distance to the rounded rectangle outline (> 0 inside)
			float d;
			bool inX = px >= x0 + r && px <= x1 - r, inY = py >= y0 + r && py <= y1 - r;
			if (inX || inY) d = Math.Min(Math.Min(px - x0, x1 - px), Math.Min(py - y0, y1 - py));
			else {
				float cx = px < x0 + r ? x0 + r : x1 - r, cy = py < y0 + r ? y0 + r : y1 - r;
				float dx = px - cx, dy = py - cy;
				d = r - (float)Math.Sqrt(dx * dx + dy * dy);
			}
			float t = d / width; // 0 at the outline, 1 at the inner edge of the rim
			float cr, cg, cb, a;
			if (d < -1) continue;
			if (d < 0) { cr = 0.02f; cg = 0.025f; cb = 0.03f; a = 1 + d; }
			else if (t < 0.18f) { cr = 0.05f; cg = 0.055f; cb = 0.065f; a = 1; }
			else if (t < 0.40f) { cr = 0.58f; cg = 0.60f; cb = 0.62f; a = 1; }
			else if (t < 0.78f) { float k = (t - 0.4f) / 0.38f; cr = 0.36f - 0.12f * k; cg = 0.38f - 0.12f * k; cb = 0.41f - 0.12f * k; a = 1; }
			else if (t < 1.0f) { cr = 0.03f; cg = 0.035f; cb = 0.04f; a = 1; }
			else { float k = (d - width) / (width * 1.6f); if (k >= 1) continue; cr = 0; cg = 0; cb = 0.01f; a = 0.55f * (1 - k) * (1 - k); }
			int i = I(x, y); R[i] = cr; G[i] = cg; B[i] = cb; A[i] = Math.Max(0, Math.Min(1, a));
		}
	}
	// nine slice: stretch the centre and the edges of `s` (corner sizes c) into w x h
	public static Img Nine(Img s, int c, int w, int h) {
		var o = new Img(w, h);
		int[] sx = { 0, c, s.W - c, s.W }, sy = { 0, c, s.H - c, s.H };
		int[] dx = { 0, c, w - c, w }, dy = { 0, c, h - c, h };
		for (int j = 0; j < 3; j++) for (int i = 0; i < 3; i++) {
			int sw = sx[i + 1] - sx[i], sh = sy[j + 1] - sy[j], dw = dx[i + 1] - dx[i], dh = dy[j + 1] - dy[j];
			if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) continue;
			var part = s.Crop(sx[i], sy[j], sw, sh);
			if (sw != dw || sh != dh) part = part.Resize(dw, dh);
			o.Draw(part, dx[i], dy[j], 1);
		}
		return o;
	}
}

public static class Noise {
	// periodic value noise (period p cells), smooth interpolation
	static float Hash(int x, int y, int seed) { unchecked { int h = x * 374761393 + y * 668265263 + seed * 144269; h = (h ^ (h >> 13)) * 1274126177; return ((h ^ (h >> 16)) & 0xffff) / 65535f; } }
	public static float Value(float x, float y, int p, int seed) {
		int x0 = (int)Math.Floor(x), y0 = (int)Math.Floor(y); float fx = x - x0, fy = y - y0;
		fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
		int a = ((x0 % p) + p) % p, b = ((y0 % p) + p) % p, a1 = (a + 1) % p, b1 = (b + 1) % p;
		float v00 = Hash(a, b, seed), v10 = Hash(a1, b, seed), v01 = Hash(a, b1, seed), v11 = Hash(a1, b1, seed);
		return (v00 * (1 - fx) + v10 * fx) * (1 - fy) + (v01 * (1 - fx) + v11 * fx) * fy;
	}
	// seamless slate (size s): fbm + faint ridged veins, mean colour r g b
	public static Img Slate(int s, float r, float g, float b, float contrast, float veins) {
		var o = new Img(s, s);
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float f = 0, amp = 0.5f, tot = 0;
			for (int oc = 0; oc < 5; oc++) { int p = 4 << oc; f += Value(x * p / (float)s, y * p / (float)s, p, 7 + oc) * amp; tot += amp; amp *= 0.5f; }
			f /= tot;
			float ridge = 1 - Math.Abs(Value(x * 6f / s, y * 6f / s, 6, 91) * 2 - 1);
			float ridge2 = 1 - Math.Abs(Value(x * 11f / s, y * 11f / s, 11, 57) * 2 - 1);
			float vein = ((float)Math.Pow(Math.Max(0, ridge), 16) + (float)Math.Pow(Math.Max(0, ridge2), 20) * 0.6f) * veins;
			float k = 1 + (f - 0.5f) * contrast - vein;
			int i = o.I(x, y); o.R[i] = r * k; o.G[i] = g * k; o.B[i] = b * k; o.A[i] = 1;
		}
		return o;
	}
}

// Painted (procedural) pieces of the undead skin: lit cylinders of bone and
// patinated metal, periodic along their length.
public static class Paint {
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static float Mix(float a, float b, float t) { return a + (b - a) * t; }
	// colour (r, g, b, a) over the pixel i
	static void Over(Img o, int i, float r, float g, float b, float a) {
		if (a <= 0) return;
		float da = o.A[i], oa = a + da * (1 - a);
		o.R[i] = (r * a + o.R[i] * da * (1 - a)) / oa; o.G[i] = (g * a + o.G[i] * da * (1 - a)) / oa; o.B[i] = (b * a + o.B[i] * da * (1 - a)) / oa;
		o.A[i] = oa;
	}
	// lit cylinder profile: t in [-1, 1] across (-1 = lit side); returns the light
	static float Light(float t) {
		float nz = (float)Math.Sqrt(Math.Max(0, 1 - t * t));
		// light from the lit side, slightly towards the viewer
		float diff = Math.Max(0, -t * 0.62f + nz * 0.78f);
		return diff;
	}
	// horizontal bone rod: w x h, radius r (px), centred at cy, lit from the top,
	// periodic along x (period w). Shadow under it on the background.
	public static Img BoneRod(int w, int h, float r, float cy, int seed) { return BoneRod(w, h, r, cy, seed, 0); }
	// rail > 0: a dark iron rail of that height behind the lower half of the bone
	public static Img BoneRod(int w, int h, float r, float cy, int seed, float rail) {
		var o = new Img(w, h);
		if (rail > 0) {
			float top = cy + r * 0.05f, bot = top + rail;
			for (int x = 0; x < w; x++) for (int y = 0; y < h; y++) {
				float py = y + 0.5f; int i = o.I(x, y);
				if (py < top - 0.5f) continue;
				if (py > bot + 0.5f) {
					float sh = py - bot; if (sh < rail * 0.9f) { float k = 1 - sh / (rail * 0.9f); o.R[i] = 0; o.G[i] = 0; o.B[i] = 0.01f; o.A[i] = 0.6f * k * k; }
					continue;
				}
				float v = (py - top) / rail; float n = (Noise.Value(x * 0.08f, y * 0.4f, Math.Max(1, (int)(w * 0.08f)), seed + 40) - 0.5f) * 0.06f;
				float c = v < 0.12f ? 0.36f : v > 0.85f ? 0.03f : 0.12f - v * 0.05f + n;
				o.R[i] = c * 0.95f; o.G[i] = c; o.B[i] = c * 1.08f; o.A[i] = Cl(Math.Min(py - (top - 0.5f), bot + 0.5f - py));
			}
		}
		// colours from the asset sheet bone
		float[] dark = { 0.13f, 0.11f, 0.085f }, mid = { 0.55f, 0.50f, 0.39f }, lite = { 0.88f, 0.84f, 0.70f };
		int per = Math.Max(1, w / 48);
		// knuckles: a few bumps along the length (periodic positions)
		var rnd = new Random(seed); int nk = Math.Max(1, w / 90); var kx = new float[nk]; var ka = new float[nk];
		for (int k = 0; k < nk; k++) { kx[k] = (k + 0.2f + (float)rnd.NextDouble() * 0.6f) * w / nk; ka[k] = 0.10f + (float)rnd.NextDouble() * 0.12f; }
		for (int x = 0; x < w; x++) {
			// organic width, knuckles, a slow bend
			float fx = x / (float)w;
			float rr = r * (0.92f + 0.14f * Noise.Value(fx * per, 0.5f, per, seed));
			for (int k = 0; k < nk; k++) { float dx = Math.Abs(x - kx[k]); dx = Math.Min(dx, w - dx); rr += r * ka[k] * (float)Math.Exp(-dx * dx / (r * r * 0.5f)); }
			float bend = (Noise.Value(fx * per, 3.5f, per, seed + 3) - 0.5f) * r * 0.12f;
			float c = cy + bend;
			// colour drift along the bone: yellowed / greyed patches
			float tint = Noise.Value(fx * per * 2, 7.5f, per * 2, seed + 21);
			for (int y = 0; y < h; y++) {
				float d = (y + 0.5f) - c;
				float t = d / rr;
				int i = o.I(x, y);
				// shadow under the rod (over what is there: the rail, the background)
				float sh = d - rr * 0.35f;
				if (d > 0 && sh > 0 && sh < rr * 1.3f) { float k = 1 - sh / (rr * 1.3f); Over(o, i, 0, 0, 0.01f, 0.5f * k * k); }
				if (Math.Abs(t) > 1) {
					float edge = rr + 0.8f - Math.Abs(d);
					if (edge <= 0) continue;
					// anti-aliased dark silhouette
					Over(o, i, dark[0] * 0.5f, dark[1] * 0.5f, dark[2] * 0.5f, Cl(edge));
					continue;
				}
				float l = Light(t);
				// grain along the bone, fine speckles, a few darker streaks / pits
				float grain = (Noise.Value(fx * per * 9, y * 0.35f, per * 9, seed + 7) - 0.5f) * 0.20f
					+ (Noise.Value(fx * per * 30, y * 1.3f, per * 30, seed + 11) - 0.5f) * 0.10f;
				float streak = (float)Math.Pow(Math.Max(0, Noise.Value(fx * per * 4, y * 0.12f + 5, per * 4, seed + 13) - 0.60f) * 2.5f, 2) * 0.45f;
				float k2 = Cl(l * (1 + grain) - streak);
				float cr = k2 < 0.55f ? Mix(dark[0], mid[0], k2 / 0.55f) : Mix(mid[0], lite[0], (k2 - 0.55f) / 0.45f);
				float cg = k2 < 0.55f ? Mix(dark[1], mid[1], k2 / 0.55f) : Mix(mid[1], lite[1], (k2 - 0.55f) / 0.45f);
				float cb = k2 < 0.55f ? Mix(dark[2], mid[2], k2 / 0.55f) : Mix(mid[2], lite[2], (k2 - 0.55f) / 0.45f);
				// yellowed (warm) or greyed (cold) patches
				float warm = (tint - 0.5f) * 0.9f;
				cr *= 1 + warm * 0.10f; cg *= 1 + warm * 0.02f; cb *= 1 - warm * 0.16f;
				// specular on the lit side, occlusion at the silhouette
				float spec = (float)Math.Exp(-Math.Pow((t + 0.45f) / 0.13f, 2)) * 0.26f;
				float ao = 1 - (float)Math.Pow(Math.Abs(t), 5) * 0.7f;
				cr = Cl((cr + spec) * ao); cg = Cl((cg + spec * 0.95f) * ao); cb = Cl((cb + spec * 0.8f) * ao);
				Over(o, i, cr, cg, cb, Cl(rr + 0.5f - Math.Abs(d)));
			}
		}
		return o;
	}
	// patinated metal band around a rod: bw wide, radius r, centred cy (vertical band
	// on a horizontal rod), two rivets
	public static Img Band(int bw, int h, float r, float cy) {
		var o = new Img(bw, h);
		float[] dark = { 0.03f, 0.07f, 0.07f }, mid = { 0.17f, 0.34f, 0.31f }, lite = { 0.52f, 0.70f, 0.64f };
		for (int x = 0; x < bw; x++) for (int y = 0; y < h; y++) {
			float d = (y + 0.5f) - cy, t = d / r; int i = o.I(x, y);
			float ex = Math.Min(x + 0.5f, bw - x - 0.5f); // distance to the band edges
			if (Math.Abs(t) > 1) {
				float edge = r + 0.8f - Math.Abs(d); if (edge <= 0) continue;
				o.R[i] = 0.01f; o.G[i] = 0.02f; o.B[i] = 0.02f; o.A[i] = Cl(edge); continue;
			}
			float l = Light(t);
			float noise = (Noise.Value(x * 0.5f, y * 0.5f, 64, 29) - 0.5f) * 0.25f;
			float k = Cl(l * (1 + noise));
			float cr = k < 0.5f ? Mix(dark[0], mid[0], k / 0.5f) : Mix(mid[0], lite[0], (k - 0.5f) / 0.5f);
			float cg = k < 0.5f ? Mix(dark[1], mid[1], k / 0.5f) : Mix(mid[1], lite[1], (k - 0.5f) / 0.5f);
			float cb = k < 0.5f ? Mix(dark[2], mid[2], k / 0.5f) : Mix(mid[2], lite[2], (k - 0.5f) / 0.5f);
			// bevelled edges (raised rims) and occlusion
			float bev = ex < 1.2f ? 0.35f : ex < 2.6f ? 1.25f : 1f;
			float ao = 1 - (float)Math.Pow(Math.Abs(t), 6) * 0.6f;
			cr *= bev * ao; cg *= bev * ao; cb *= bev * ao;
			// rivets
			foreach (float ry in new float[] { -0.45f, 0.45f }) {
				float rx = bw / 2f, ryy = cy + ry * r, rd = (float)Math.Sqrt(Math.Pow(x + 0.5f - rx, 2) + Math.Pow(y + 0.5f - ryy, 2));
				float rrad = Math.Max(1.2f, bw * 0.13f);
				if (rd < rrad) { float hl = 1 - rd / rrad; float up = (y + 0.5f - ryy) < 0 ? 1.3f : 0.7f; cr = Mix(cr, 0.75f * up, hl * 0.8f); cg = Mix(cg, 0.80f * up, hl * 0.8f); cb = Mix(cb, 0.74f * up, hl * 0.8f); }
			}
			o.R[i] = Cl(cr); o.G[i] = Cl(cg); o.B[i] = Cl(cb); o.A[i] = Cl(r + 0.5f - Math.Abs(d));
		}
		return o;
	}
	// alpha mask: union of ellipses (cx, cy, rx, ry), feather f
	public static void EllipseMask(Img im, float[][] ellipses, float f) {
		for (int y = 0; y < im.H; y++) for (int x = 0; x < im.W; x++) {
			float best = -99;
			foreach (var e in ellipses) {
				float dx = (x + 0.5f - e[0]) / e[2], dy = (y + 0.5f - e[1]) / e[3];
				float dd = (1 - (float)Math.Sqrt(dx * dx + dy * dy)) * Math.Min(e[2], e[3]);
				if (dd > best) best = dd;
			}
			float a = Cl(best / f + 0.5f);
			int i = im.I(x, y); im.A[i] *= a;
		}
	}
}

// Procedural sculpted pieces (height field + lighting), rendered supersampled.
public static class Sculpt {
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static float SS(float a, float b, float x) { float t = Cl((x - a) / (b - a)); return t * t * (3 - 2 * t); }
	static float SMax(float a, float b, float k) { float h = Cl(0.5f + 0.5f * (b - a) / k); return a * (1 - h) + b * h + k * h * (1 - h); }
	static float G(float x, float y, float cx, float cy, float s) { float dx = x - cx, dy = y - cy; return (float)Math.Exp(-(dx * dx + dy * dy) / (2 * s * s)); }
	static float Dome(float u, float v, float cx, float cy, float rx, float ry, float amp) {
		float dx = (u - cx) / rx, dy = (v - cy) / ry; float e = dx * dx + dy * dy; return e < 1 ? amp * (float)Math.Sqrt(1 - e) : -0.3f * (e - 1);
	}
	// rotated ellipse value (< 1 inside)
	static float Ell(float u, float v, float cx, float cy, float rx, float ry, float ang) {
		float c = (float)Math.Cos(ang), s = (float)Math.Sin(ang); float dx = u - cx, dy = v - cy;
		float a = (dx * c + dy * s) / rx, b = (-dx * s + dy * c) / ry; return a * a + b * b;
	}

	// skull, front view, size x size (straight alpha), glow colour gr gg gb
	public static Img Skull(int size, float gr, float gg, float gb, int seed) {
		int N = size * 2; // supersampled
		var h = new float[N * N]; var sock = new float[N * N]; var teeth = new float[N * N]; var gapm = new float[N * N]; var crack = new float[N * N];
		float scale = 1.22f; // domain [-1.22, 1.22]: room for the glow
		for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) {
			float u = ((x + 0.5f) / N * 2 - 1) * scale, v = ((y + 0.5f) / N * 2 - 1) * scale + 0.08f;
			float h1 = Dome(u, v, 0, -0.24f, 0.74f, 0.78f, 1.0f);
			float h2 = Dome(u, v, 0, 0.24f, 0.76f, 0.40f, 0.78f);
			float h3 = Dome(u, v, 0, 0.66f, 0.33f, 0.25f, 0.60f);
			float hh = SMax(SMax(h1, h2, 0.14f), h3, 0.12f);
			// cheekbones, temples, cheek hollows (under the cheekbones)
			hh += 0.13f * G(u, v, -0.54f, 0.26f, 0.10f) + 0.13f * G(u, v, 0.54f, 0.26f, 0.10f);
			hh -= 0.20f * G(u, v, -0.70f, 0.02f, 0.12f) + 0.20f * G(u, v, 0.70f, 0.02f, 0.12f);
			hh -= 0.20f * G(u, v, -0.42f, 0.52f, 0.09f) + 0.20f * G(u, v, 0.42f, 0.52f, 0.09f);
			// heavy brow over the eyes, a frontal ridge
			hh += 0.12f * G(u, v, -0.30f, -0.07f, 0.11f) + 0.12f * G(u, v, 0.30f, -0.07f, 0.11f);
			hh += 0.05f * G(u, v, 0, -0.30f, 0.10f);
			// eye sockets: angular (flat top under the brow, inner corner low)
			float s = 0;
			for (int side = -1; side <= 1; side += 2) {
				float e = Ell(u, v, side * 0.295f, 0.15f, 0.215f, 0.165f, side * -0.33f);
				float vTop = 0.03f + 0.30f * (0.30f - Math.Abs(u));
				float cut = SS(-0.02f, 0.02f, v - vTop);
				s = Math.Max(s, (1 - SS(0.72f, 1.0f, e)) * cut);
			}
			hh -= 0.85f * s;
			// nose: inverted heart, deep
			float n1 = Ell(u, v, -0.048f, 0.44f, 0.062f, 0.115f, 0.38f), n2 = Ell(u, v, 0.048f, 0.44f, 0.062f, 0.115f, -0.38f);
			float nose = 1 - SS(0.65f, 1f, Math.Min(n1, n2));
			hh -= 0.55f * nose;
			s = Math.Max(s, nose * 0.95f);
			// teeth: 6 + 6, irregular
			float tm = 0, gm = 0;
			float rowW = 0.25f;
			if (Math.Abs(u) < rowW + 0.03f && v > 0.575f && v < 0.84f) {
				float t = (u + rowW) / (2 * rowW) * 6; int ti = (int)Math.Floor(t); float ft = t - ti;
				float jitter = (Noise.Value(ti * 3.1f, 0.5f, 64, seed + 5) - 0.5f) * 0.03f;
				float edgeFade = 1 - SS(rowW - 0.04f, rowW + 0.03f, Math.Abs(u));
				float gap = 1 - SS(0.02f, 0.2f, Math.Min(ft, 1 - ft));
				float midGap = 1 - SS(0.0f, 0.03f, Math.Abs(v - 0.705f - jitter));
				// rounded tooth tips at the middle line
				float tip = Math.Abs(v - 0.705f) < 0.06f ? SS(0.0f, 0.06f, Math.Abs(v - 0.705f)) : 1;
				gap = Math.Max(gap, (1 - tip) * (1 - (float)Math.Sin(Math.PI * ft)));
				tm = edgeFade * SS(0.575f, 0.60f, v) * (1 - SS(0.81f, 0.84f, v));
				gm = Math.Max(gap, midGap) * tm;
				float bulge = (float)Math.Sin(Math.PI * ft);
				hh += 0.09f * tm * bulge - 0.16f * gm;
			}
			// thin cracks
			float ck = 0;
			float c1 = Math.Abs(v + 0.60f + 0.32f * (u - 0.2f) + 0.035f * (float)Math.Sin(u * 21));
			if (u > 0.08f && u < 0.50f) ck = Math.Max(ck, 1 - SS(0, 0.010f, c1));
			float c3 = Math.Abs(u - 0.33f - 0.4f * (v + 0.62f) + 0.02f * (float)Math.Sin(v * 30));
			if (v > -0.55f && v < -0.36f) ck = Math.Max(ck, 1 - SS(0, 0.008f, c3));
			hh -= 0.04f * ck;
			int i = y * N + x; h[i] = hh; sock[i] = s; teeth[i] = tm; gapm[i] = gm; crack[i] = ck;
		}
		// ambient occlusion: blurred height vs height
		var blur = BlurField(h, N, N / 24);
		var o = new Img(N, N);
		float lx = -0.45f, ly = -0.55f, lz = 0.70f; float ll = (float)Math.Sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
		float hxh = -lx, hyh = -ly, hzh = 1 - lz; // not used directly
		float k = N * 0.85f;
		for (int y = 1; y < N - 1; y++) for (int x = 1; x < N - 1; x++) {
			int i = y * N + x;
			float hh = h[i]; if (hh <= 0) continue;
			float dx = (h[i + 1] - h[i - 1]) * 0.5f * k / 2.4f, dy = (h[i + N] - h[i - N]) * 0.5f * k / 2.4f;
			float nx = -dx, ny = -dy, nz = 1; float nl = (float)Math.Sqrt(nx * nx + ny * ny + nz * nz); nx /= nl; ny /= nl; nz /= nl;
			float diff = Math.Max(0, nx * lx + ny * ly + nz * lz);
			// blinn specular (viewer on z)
			float bx = lx, by = ly, bz = lz + 1; float bl = (float)Math.Sqrt(bx * bx + by * by + bz * bz); bx /= bl; by /= bl; bz /= bl;
			float spec = (float)Math.Pow(Math.Max(0, nx * bx + ny * by + nz * bz), 14) * 0.07f;
			float cav = Math.Max(0, blur[i] - hh);
			float ao = Cl(1 - cav * 3.2f);
			float u = ((x + 0.5f) / N * 2 - 1) * scale, v = ((y + 0.5f) / N * 2 - 1) * scale + 0.08f;
			// aged bone albedo: mottled, grime in the cavities
			float m = Noise.Value(x * 10f / N, y * 10f / N, 10, seed) * 0.55f + Noise.Value(x * 36f / N, y * 36f / N, 36, seed + 1) * 0.3f
				+ Noise.Value(x * 110f / N, y * 110f / N, 110, seed + 2) * 0.15f;
			float ar = 0.66f + (m - 0.5f) * 0.20f, ag = 0.61f + (m - 0.5f) * 0.19f, ab = 0.49f + (m - 0.5f) * 0.15f;
			float grime = Cl(cav * 6f) * 0.65f + SS(0.25f, 0.95f, v) * 0.22f + SS(-0.2f, -0.9f, v) * 0.10f;
			ar -= grime * 0.55f; ag -= grime * 0.58f; ab -= grime * 0.52f;
			// teeth brighter, gaps and cracks dark
			ar += teeth[i] * 0.05f; ag += teeth[i] * 0.05f; ab += teeth[i] * 0.03f;
			float dark = Math.Max(gapm[i] * 0.9f, crack[i] * 0.75f);
			// key light + cool rim from below right
			float rim = Math.Max(0, nx * 0.55f + ny * 0.45f) * 0.18f;
			float light = 0.16f + 0.92f * diff;
			float r = ar * light * ao + spec + rim * 0.55f, g = ag * light * ao + spec * 0.97f + rim * 0.62f, b = ab * light * ao + spec * 0.9f + rim * 0.75f;
			r *= 1 - dark; g *= 1 - dark; b *= 1 - dark;
			// sockets: black depth, the glow small and deep (low in the socket)
			float s = sock[i];
			if (s > 0) {
				float glow = 0;
				for (int side = -1; side <= 1; side += 2) glow = Math.Max(glow, G(u, v, side * 0.285f, 0.18f, 0.08f));
				float cr = 0.008f + gr * glow * 1.6f, cg = 0.008f + gg * glow * 1.6f, cb = 0.012f + gb * glow * 1.6f;
				float core = (float)Math.Pow(glow, 5) * 0.8f; cr += core; cg += core; cb += core;
				r = r * (1 - s) + cr * s; g = g * (1 - s) + cg * s; b = b * (1 - s) + cb * s;
			}
			// glow light on the socket rims and the cheekbones
			float spill = 0;
			for (int side = -1; side <= 1; side += 2) spill = Math.Max(spill, G(u, v, side * 0.29f, 0.20f, 0.17f));
			spill *= 1 - s;
			r += gr * spill * 0.35f; g += gg * spill * 0.35f; b += gb * spill * 0.35f;
			// silhouette edge: anti aliasing
			float a = Cl(hh * N / 14f);
			o.R[i] = Cl(r); o.G[i] = Cl(g); o.B[i] = Cl(b); o.A[i] = a;
		}
		// dark outline (sits on any background)
		var outl = new Img(N, N);
		for (int i = 0; i < o.A.Length; i++) outl.A[i] = o.A[i];
		outl.Blur(Math.Max(1, N / 160));
		var res = new Img(N, N);
		for (int i = 0; i < res.A.Length; i++) { res.R[i] = 0.02f; res.G[i] = 0.02f; res.B[i] = 0.025f; res.A[i] = Math.Min(1, outl.A[i] * 1.6f) * 0.9f; }
		// bloom of the eyes
		var bloom = new Img(N, N);
		for (int y = 0; y < N; y++) for (int x = 0; x < N; x++) {
			float u = ((x + 0.5f) / N * 2 - 1) * scale, v = ((y + 0.5f) / N * 2 - 1) * scale + 0.08f;
			float gl = 0; for (int side = -1; side <= 1; side += 2) gl = Math.Max(gl, G(u, v, side * 0.285f, 0.18f, 0.12f));
			int i = y * N + x; bloom.R[i] = gr; bloom.G[i] = gg; bloom.B[i] = gb; bloom.A[i] = gl * 0.6f;
		}
		res.Draw(o, 0, 0, 1);
		// additive-looking glow: over the skull, mostly visible in and around the sockets
		for (int i = 0; i < res.A.Length; i++) {
			float ga = bloom.A[i];
			res.R[i] = Cl(res.R[i] * res.A[i] + gr * ga) ; res.G[i] = Cl(res.G[i] * res.A[i] + gg * ga); res.B[i] = Cl(res.B[i] * res.A[i] + gb * ga);
			float na = Cl(res.A[i] + ga * (1 - res.A[i]) * 0.9f);
			if (na > 0) { res.R[i] /= Math.Max(na, 1e-4f); res.G[i] /= Math.Max(na, 1e-4f); res.B[i] /= Math.Max(na, 1e-4f); }
			res.R[i] = Cl(res.R[i]); res.G[i] = Cl(res.G[i]); res.B[i] = Cl(res.B[i]);
			res.A[i] = na;
		}
		return res.Resize(size, size);
	}

	static float[] BlurField(float[] f, int n, int r) {
		var a = (float[])f.Clone(); var t = new float[a.Length];
		for (int pass = 0; pass < 2; pass++) {
			for (int y = 0; y < n; y++) { float s = 0; int c = 0; for (int x = -r; x < n + r; x++) { int xa = x + r, xr = x - r - 1; if (xa < n && xa >= 0) { s += a[y * n + xa]; c++; } if (xr >= 0 && xr < n) { s -= a[y * n + xr]; c--; } if (x >= 0 && x < n) t[y * n + x] = s / Math.Max(1, c); } }
			for (int x = 0; x < n; x++) { float s = 0; int c = 0; for (int y = -r; y < n + r; y++) { int ya = y + r, yr = y - r - 1; if (ya < n && ya >= 0) { s += t[ya * n + x]; c++; } if (yr >= 0 && yr < n) { s -= t[yr * n + x]; c--; } if (y >= 0 && y < n) a[y * n + x] = s / Math.Max(1, c); } }
		}
		return a;
	}
}

// Height field with albedo, lit like the skull: the forged iron pieces.
public class HField {
	public int W, H; public float[] Ht, A, Ar, Ag, Ab, Sp;
	public HField(int w, int h) { W = w; H = h; int n = w * h; Ht = new float[n]; A = new float[n]; Ar = new float[n]; Ag = new float[n]; Ab = new float[n]; Sp = new float[n]; }
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	public void Set(int x, int y, float h, float a, float r, float g, float b, float sp) {
		if (x < 0 || y < 0 || x >= W || y >= H) return; int i = y * W + x;
		if (a <= 0) return;
		if (h >= Ht[i] || A[i] <= 0) { Ht[i] = h; Ar[i] = r; Ag[i] = g; Ab[i] = b; Sp[i] = sp; }
		A[i] = Math.Max(A[i], a);
	}
	// k: height to slope scale, wrapX: tileable along x
	public Img Shade(float k, bool wrapX, bool wrapY) {
		var o = new Img(W, H);
		float lx = -0.45f, ly = -0.60f, lz = 0.66f; float ll = (float)Math.Sqrt(lx * lx + ly * ly + lz * lz); lx /= ll; ly /= ll; lz /= ll;
		float bx = lx, by = ly, bz = lz + 1; float bl = (float)Math.Sqrt(bx * bx + by * by + bz * bz); bx /= bl; by /= bl; bz /= bl;
		for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {
			int i = y * W + x; if (A[i] <= 0) continue;
			int xl = x - 1, xr = x + 1, yu = y - 1, yd = y + 1;
			if (wrapX) { xl = (xl + W) % W; xr = xr % W; } else { xl = Math.Max(0, xl); xr = Math.Min(W - 1, xr); }
			if (wrapY) { yu = (yu + H) % H; yd = yd % H; } else { yu = Math.Max(0, yu); yd = Math.Min(H - 1, yd); }
			float hl = A[y * W + xl] > 0 ? Ht[y * W + xl] : Ht[i] - 0.5f, hr = A[y * W + xr] > 0 ? Ht[y * W + xr] : Ht[i] - 0.5f;
			float hu = A[yu * W + x] > 0 ? Ht[yu * W + x] : Ht[i] - 0.5f, hd = A[yd * W + x] > 0 ? Ht[yd * W + x] : Ht[i] - 0.5f;
			float dx = (hr - hl) * 0.5f * k, dy = (hd - hu) * 0.5f * k;
			float nx = -dx, ny = -dy, nz = 1; float nl = (float)Math.Sqrt(nx * nx + ny * ny + nz * nz); nx /= nl; ny /= nl; nz /= nl;
			float diff = Math.Max(0, nx * lx + ny * ly + nz * lz);
			float spec = (float)Math.Pow(Math.Max(0, nx * bx + ny * by + nz * bz), 24) * Sp[i];
			float light = 0.20f + 1.05f * diff;
			o.R[i] = Cl(Ar[i] * light + spec); o.G[i] = Cl(Ag[i] * light + spec); o.B[i] = Cl(Ab[i] * light + spec * 1.05f); o.A[i] = Cl(A[i]);
		}
		return o;
	}
}

public static class Forge {
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static float SS(float a, float b, float x) { float t = Cl((x - a) / (b - a)); return t * t * (3 - 2 * t); }
	// dark iron colour at a point (hammered, slightly cold)
	static void Iron(float x, float y, int per, int seed, out float r, out float g, out float b) {
		float n = Noise.Value(x / 14f, y / 14f, per, seed) * 0.6f + Noise.Value(x / 4f, y / 4f, per * 4, seed + 1) * 0.4f;
		float v = 0.19f + (n - 0.5f) * 0.07f;
		r = v * 0.96f; g = v * 1.0f; b = v * 1.10f;
	}
	static void Bone(float x, float y, int seed, out float r, out float g, out float b) {
		float n = Noise.Value(x / 28f, y / 14f, 64, seed) * 0.75f + Noise.Value(x / 6f, y / 6f, 256, seed + 1) * 0.25f;
		r = 0.63f + (n - 0.5f) * 0.14f; g = 0.58f + (n - 0.5f) * 0.13f; b = 0.46f + (n - 0.5f) * 0.10f;
	}
	// bevelled plate profile across a band: flat top with rounded bevels (t in 0..1)
	static float Bevel(float t, float bev) { return Math.Min(1, Math.Min(SS(0, bev, t), SS(0, bev, 1 - t))); }
	static void Rivet(HField f, float cx, float cy, float rad, float baseH) {
		for (int y = (int)(cy - rad - 1); y <= (int)(cy + rad + 1); y++) for (int x = (int)(cx - rad - 1); x <= (int)(cx + rad + 1); x++) {
			float dx = x + 0.5f - cx, dy = y + 0.5f - cy, d = (float)Math.Sqrt(dx * dx + dy * dy) / rad;
			if (d > 1.1f) continue;
			float h = baseH + 0.9f * (float)Math.Sqrt(Math.Max(0, 1 - d * d)); float a = Cl((1.1f - d) / 0.1f);
			f.Set(((x % f.W) + f.W) % f.W, y, h, a, 0.30f, 0.31f, 0.33f, 0.55f);
		}
	}

	// Top trim, w x 96 px, tiles along x: a forged iron beam (y 34..70) with a
	// bone rod lying on it (centre y 30, radius 10), rivets every 128 px, shadow under.
	public static Img Trim(int w, int seed) {
		var f = new HField(w, 96);
		int per = Math.Max(1, w / 14);
		for (int y = 34; y <= 70; y++) for (int x = 0; x < w; x++) {
			float t = (y - 34) / 36f; float h = 0.9f * Bevel(t, 0.18f);
			float hammer = (Noise.Value(x / 9f, y / 9f, Math.Max(1, w / 9), seed + 3) - 0.5f) * 0.10f;
			float r, g, b; Iron(x, y, per, seed, out r, out g, out b);
			// worn bright edges
			float wear = (1 - Bevel(t, 0.10f)) * 0.10f; r += wear; g += wear; b += wear;
			// a groove along the beam
			float groove = 1 - SS(0, 1.6f, Math.Abs(y - 58f));
			f.Set(x, y, h + hammer - groove * 0.35f, 1, r - groove * 0.06f, g - groove * 0.06f, b - groove * 0.06f, 0.35f);
		}
		for (int k = 0; k < w / 128; k++) { Rivet(f, k * 128 + 64, 58, 4.2f, 0.9f); }
		// bone rod on top
		for (int x = 0; x < w; x++) {
			float fx = x / (float)w;
			float rr = 8f * (0.94f + 0.12f * Noise.Value(fx * (w / 40f), 0.5f, Math.Max(1, w / 40), seed + 9));
			float cy = 33 + (Noise.Value(fx * (w / 64f), 3.5f, Math.Max(1, w / 64), seed + 11) - 0.5f) * 1.6f;
			for (int y = (int)(cy - rr - 1); y <= (int)(cy + rr + 1); y++) {
				float d = (y + 0.5f - cy) / rr; if (Math.Abs(d) > 1.05f) continue;
				float h = 1.6f + 3.2f * (float)Math.Sqrt(Math.Max(0, 1 - d * d));
				float r, g, b; Bone(x, y, seed, out r, out g, out b);
				float streak = SS(0.72f, 0.95f, Noise.Value(x / 16f, y / 3f, Math.Max(1, w / 16), seed + 13)) * 0.10f;
				f.Set(x, y, h, Cl((1.05f - Math.Abs(d)) / 0.08f), r - streak, g - streak, b - streak * 0.9f, 0.3f);
			}
		}
		var img = f.Shade(3.2f, true, false);
		// contact shadow under the rod on the beam, drop shadow under the beam
		var o = new Img(w, 96);
		for (int y = 60; y < 90; y++) for (int x = 0; x < w; x++) { float k = 1 - (y - 66) / 22f; if (k <= 0 || y < 66) continue; int i = o.I(x, y); o.A[i] = 0.6f * k * k; o.B[i] = 0.01f; }
		o.Draw(img, 0, 0, 1);
		for (int y = 34; y < 46; y++) for (int x = 0; x < w; x++) { int i = o.I(x, y); float s = 0.35f * (1 - (y - 34) / 12f); o.R[i] *= 1 - s; o.G[i] *= 1 - s; o.B[i] *= 1 - s; }
		// the rod over its own contact shadow: redraw the rod pixels (y < 42) from img
		for (int y = 0; y < 42; y++) for (int x = 0; x < w; x++) { int i = o.I(x, y); if (img.A[i] > 0 && y < 30 + 11) { if (f.Ht[i] >= 1.6f) { o.R[i] = img.R[i]; o.G[i] = img.G[i]; o.B[i] = img.B[i]; o.A[i] = img.A[i]; } } }
		return o;
	}

	// Vertical divider, 64 x h, tiles along y: iron bar (x 20..44) with a bone
	// inlay down its middle, rivets every 128 px.
	public static Img Divider(int h, int seed) {
		var f = new HField(64, h);
		int per = Math.Max(1, h / 14);
		for (int y = 0; y < h; y++) for (int x = 20; x <= 44; x++) {
			float t = (x - 20) / 24f; float hh = 0.9f * Bevel(t, 0.2f);
			float r, g, b; Iron(x, y, per, seed, out r, out g, out b);
			float wear = (1 - Bevel(t, 0.12f)) * 0.10f; r += wear; g += wear; b += wear;
			f.Set(x, y, hh, 1, r, g, b, 0.35f);
		}
		for (int y = 0; y < h; y++) for (int x = 28; x <= 36; x++) {
			float d = (x + 0.5f - 32) / 4.5f; if (Math.Abs(d) > 1) continue;
			float r, g, b; Bone(y, x, seed, out r, out g, out b);
			f.Set(x, y, 1.1f + 0.6f * (float)Math.Sqrt(1 - d * d), 1, r * 0.92f, g * 0.92f, b * 0.92f, 0.25f);
		}
		for (int k = 0; k < h / 128; k++) Rivet(f, 32, k * 128 + 64, 5.5f, 1.2f);
		var img = f.Shade(3.2f, false, true);
		var o = new Img(64, h);
		for (int y = 0; y < h; y++) for (int x = 44; x < 60; x++) { int i = o.I(x, y); float k = 1 - (x - 44) / 16f; o.A[i] = 0.55f * k * k; o.B[i] = 0.01f; }
		o.Draw(img, 0, 0, 1);
		return o;
	}

	// Ring (portrait / minimap window) drawn onto an image: iron torus from rIn
	// to rOut with a thin bone ring inside and rivets; inside transparent is not
	// touched (the caller cuts the hole)
	public static void Ring(Img dst, float cx, float cy, float rIn, float rOut, int rivets, int seed) {
		int x0 = (int)(cx - rOut - 12), x1 = (int)(cx + rOut + 12), y0 = (int)(cy - rOut - 12), y1 = (int)(cy + rOut + 12);
		var f = new HField(x1 - x0, y1 - y0);
		float boneOut = rIn + (rOut - rIn) * 0.30f;
		for (int y = 0; y < f.H; y++) for (int x = 0; x < f.W; x++) {
			float dx = x + x0 + 0.5f - cx, dy = y + y0 + 0.5f - cy, d = (float)Math.Sqrt(dx * dx + dy * dy);
			if (d < rIn - 1 || d > rOut + 1) continue;
			float a = Cl(Math.Min(d - rIn + 1, rOut + 1 - d));
			if (d < boneOut) {
				float t = (d - rIn) / (boneOut - rIn); float hh = 1.2f + 0.9f * (float)Math.Sin(Math.PI * Cl(t));
				float ang = (float)Math.Atan2(dy, dx); float r, g, b; Bone(ang * 90, d, seed, out r, out g, out b);
				f.Set(x, y, hh, a, r, g, b, 0.3f);
			} else {
				float t = (d - boneOut) / (rOut - boneOut); float hh = 1.0f * (float)Math.Sin(Math.PI * Cl(t) * 0.5f + 0.5f) ;
				hh = 0.4f + 0.9f * Math.Min(SS(0, 0.35f, t), SS(0, 0.25f, 1 - t));
				float r, g, b; Iron(x + x0, y + y0, 64, seed, out r, out g, out b);
				float wear = (1 - Math.Min(SS(0, 0.2f, t), SS(0, 0.2f, 1 - t))) * 0.09f;
				f.Set(x, y, hh, a, r + wear, g + wear, b + wear, 0.35f);
			}
		}
		for (int k = 0; k < rivets; k++) {
			double ang = Math.PI * 2 * k / rivets + Math.PI / rivets;
			float rm = (boneOut + rOut) / 2;
			Rivet(f, (float)(cx - x0 + Math.Cos(ang) * rm), (float)(cy - y0 + Math.Sin(ang) * rm), (rOut - boneOut) * 0.28f, 1.1f);
		}
		var img = f.Shade(3.0f, false, false);
		// outer drop shadow, inner shadow onto the window edge
		var sh = new Img(f.W, f.H);
		for (int y = 0; y < f.H; y++) for (int x = 0; x < f.W; x++) {
			float dx = x + x0 + 0.5f - cx - 2, dy = y + y0 + 0.5f - cy - 3, d = (float)Math.Sqrt(dx * dx + dy * dy);
			float k = d > rOut ? 1 - (d - rOut) / 9f : 0; if (k <= 0) continue; int i = sh.I(x, y); sh.A[i] = 0.6f * k * k; sh.B[i] = 0.01f;
		}
		dst.Draw(sh, x0, y0, 1);
		dst.Draw(img, x0, y0, 1);
	}

	// Icon slot, size x size: bevelled iron frame (fw px) round a dark recess
	public static Img Slot(int size, float fw, float tr, float tg, float tb, int seed) {
		var f = new HField(size, size);
		for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
			float e = Math.Min(Math.Min(x + 0.5f, size - x - 0.5f), Math.Min(y + 0.5f, size - y - 0.5f));
			float r, g, b; Iron(x, y, 32, seed, out r, out g, out b);
			if (e < fw) {
				float t = e / fw; float hh = 0.9f * Math.Min(SS(0, 0.35f, t), SS(0, 0.4f, 1 - t)) + 0.1f;
				r = r * 1.25f + tr; g = g * 1.25f + tg; b = b * 1.25f + tb;
				f.Set(x, y, hh, 1, r, g, b, 0.4f);
			} else {
				// recess: dark, slightly lighter towards the centre, fine grain
				float c = Math.Min(1, (e - fw) / (size * 0.25f));
				float n = (Noise.Value(x / 3f, y / 3f, Math.Max(1, size / 3), seed + 7) - 0.5f) * 0.02f;
				float v = 0.035f + 0.035f * c + n;
				f.Set(x, y, -0.2f, 1, v * 0.95f, v, v * 1.15f, 0.05f);
			}
		}
		return f.Shade(2.6f, false, false);
	}
}

// Orc art -> undead: wood to aged bone, red cloth / paint to teal patina,
// iron colder, black fills kept (textured later).
public static class Repaint {
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static float SS(float a, float b, float x) { float t = Cl((x - a) / (b - a)); return t * t * (3 - 2 * t); }
	static void Ramp(float l, float[][] stops, out float r, out float g, out float b) {
		// stops: { pos, r, g, b }
		r = stops[0][1]; g = stops[0][2]; b = stops[0][3];
		for (int k = 1; k < stops.Length; k++) {
			if (l <= stops[k][0]) {
				float t = Cl((l - stops[k - 1][0]) / (stops[k][0] - stops[k - 1][0]));
				r = stops[k - 1][1] + (stops[k][1] - stops[k - 1][1]) * t; g = stops[k - 1][2] + (stops[k][2] - stops[k - 1][2]) * t; b = stops[k - 1][3] + (stops[k][3] - stops[k - 1][3]) * t;
				return;
			}
			r = stops[k][1]; g = stops[k][2]; b = stops[k][3];
		}
	}
	static readonly float[][] BONE = {
		new float[] { 0.00f, 0.03f, 0.03f, 0.03f }, new float[] { 0.10f, 0.13f, 0.12f, 0.10f }, new float[] { 0.28f, 0.33f, 0.31f, 0.26f },
		new float[] { 0.48f, 0.52f, 0.49f, 0.41f }, new float[] { 0.70f, 0.68f, 0.65f, 0.55f }, new float[] { 1.00f, 0.85f, 0.83f, 0.74f },
	};
	static readonly float[][] TEAL = {
		new float[] { 0.00f, 0.01f, 0.03f, 0.03f }, new float[] { 0.25f, 0.08f, 0.22f, 0.20f }, new float[] { 0.55f, 0.22f, 0.46f, 0.41f },
		new float[] { 1.00f, 0.62f, 0.86f, 0.78f },
	};
	public static Img Undead(Img src, float boneGain) {
		var o = src.Clone();
		for (int i = 0; i < o.R.Length; i++) {
			if (o.A[i] <= 0) continue;
			float r = src.R[i], g = src.G[i], b = src.B[i];
			float h, s, v; Img.ToHsv(r, g, b, out h, out s, out v);
			float l = 0.30f * r + 0.59f * g + 0.11f * b;
			// iron / neutral: colder, a touch darker
			float nr = r * 0.90f, ng = g * 0.96f, nb = b * 1.06f;
			// red (cloth, ropes, paint) -> teal patina
			float red = (h < 14 || h > 335) ? SS(0.28f, 0.45f, s) * SS(0.12f, 0.2f, v) : 0;
			// warm (wood, leather, tusks) -> bone
			float warm = (h >= 14 && h <= 62) ? SS(0.10f, 0.22f, s) : 0;
			if (red > 0) {
				float tr, tg, tb; Ramp(Cl(l * 2.2f), TEAL, out tr, out tg, out tb);
				nr = nr * (1 - red) + tr * red; ng = ng * (1 - red) + tg * red; nb = nb * (1 - red) + tb * red;
			}
			if (warm > 0) {
				// wood is darker than bone: lift the luminance, keep its grain
				float lb = Cl((float)Math.Pow(Cl(l * boneGain), 0.8f));
				float br, bg, bb; Ramp(lb, BONE, out br, out bg, out bb);
				nr = nr * (1 - warm) + br * warm; ng = ng * (1 - warm) + bg * warm; nb = nb * (1 - warm) + bb * warm;
			}
			o.R[i] = Cl(nr); o.G[i] = Cl(ng); o.B[i] = Cl(nb);
		}
		return o;
	}
	// glowing eye in a dark socket: light added round (cx, cy), core sigma s
	public static void Eye(Img img, float cx, float cy, float s, float cr, float cg, float cb) {
		int r = (int)Math.Ceiling(s * 4);
		for (int y = (int)cy - r; y <= (int)cy + r; y++) for (int x = (int)cx - r; x <= (int)cx + r; x++) {
			if (x < 0 || y < 0 || x >= img.W || y >= img.H) continue;
			int i = img.I(x, y); if (img.A[i] <= 0) continue;
			float dx = x + 0.5f - cx, dy = y + 0.5f - cy, d2 = dx * dx + dy * dy;
			float core = (float)Math.Exp(-d2 / (2 * s * s)), halo = (float)Math.Exp(-d2 / (8 * s * s)) * 0.25f;
			float v = Math.Max(img.R[i], Math.Max(img.G[i], img.B[i]));
			float k = core * (1.1f - Math.Min(1, v * 1.4f)) + halo;
			if (k < 0) k = 0;
			float hot = (float)Math.Pow(core, 4) * 0.5f;
			img.R[i] = Cl(img.R[i] + cr * k + hot); img.G[i] = Cl(img.G[i] + cg * k + hot); img.B[i] = Cl(img.B[i] + cb * k + hot * 0.7f);
		}
	}
	// black fills of the art replaced by the tile (tilePx texture px per tile)
	public static Img Fill(Img art, Img tile, float tilePx, float threshold) {
		var o = art.Clone();
		for (int y = 0; y < art.H; y++) for (int x = 0; x < art.W; x++) {
			int i = art.I(x, y);
			float br = Math.Max(art.R[i], Math.Max(art.G[i], art.B[i]));
			if (art.A[i] > 0.78f && br < threshold) {
				float w = 1 - br / threshold;
				int tx = (int)(x * tile.W / tilePx) % tile.W, ty = (int)((art.H - 1 - y) * tile.H / tilePx) % tile.H;
				int t = tile.I(tx, tile.H - 1 - ty);
				o.R[i] = art.R[i] * (1 - w) + tile.R[t] * w; o.G[i] = art.G[i] * (1 - w) + tile.G[t] * w; o.B[i] = art.B[i] * (1 - w) + tile.B[t] * w;
			}
		}
		return o;
	}
}

public static class Tga {
	public static Bitmap Load(string p) {
		byte[] b = File.ReadAllBytes(p);
		int idLen = b[0], cmType = b[1], type = b[2]; int cmLen = b[5] | (b[6] << 8), cmEnt = b[7];
		int w = b[12] | (b[13] << 8), h = b[14] | (b[15] << 8), bpp = b[16], desc = b[17];
		int pos = 18 + idLen + (cmType == 1 ? cmLen * ((cmEnt + 7) / 8) : 0); int bytes = bpp / 8; int n = w * h; byte[] px = new byte[n * 4];
		bool rle = type >= 9; int i = 0;
		while (i < n) {
			if (rle) { int hdr = b[pos++]; int cnt = (hdr & 0x7F) + 1;
				if ((hdr & 0x80) != 0) { int s = pos; pos += bytes; for (int k = 0; k < cnt && i < n; k++) Set(px, i++, b, s, bytes); }
				else { for (int k = 0; k < cnt && i < n; k++) { Set(px, i++, b, pos, bytes); pos += bytes; } } }
			else { Set(px, i++, b, pos, bytes); pos += bytes; }
		}
		bool top = (desc & 0x20) != 0; Bitmap bm = new Bitmap(w, h, PixelFormat.Format32bppArgb);
		var d = bm.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
		var outp = new byte[w * h * 4];
		for (int y = 0; y < h; y++) { int sy = top ? y : (h - 1 - y); Array.Copy(px, sy * w * 4, outp, y * w * 4, w * 4); }
		System.Runtime.InteropServices.Marshal.Copy(outp, 0, d.Scan0, outp.Length); bm.UnlockBits(d);
		return bm;
	}
	static void Set(byte[] px, int i, byte[] b, int s, int bytes) { int j = i * 4;
		if (bytes >= 3) { px[j] = b[s]; px[j + 1] = b[s + 1]; px[j + 2] = b[s + 2]; px[j + 3] = (byte)(bytes == 4 ? b[s + 3] : 255); } else { px[j] = px[j + 1] = px[j + 2] = b[s]; px[j + 3] = 255; } }
	public static void Save(Bitmap bm, string p) {
		int w = bm.Width, h = bm.Height; byte[] o = new byte[18 + w * h * 4];
		o[2] = 2; o[12] = (byte)(w & 255); o[13] = (byte)(w >> 8); o[14] = (byte)(h & 255); o[15] = (byte)(h >> 8); o[16] = 32; o[17] = 8;
		var d = bm.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
		var px = new byte[w * h * 4]; System.Runtime.InteropServices.Marshal.Copy(d.Scan0, px, 0, px.Length); bm.UnlockBits(d);
		int k = 18; for (int y = h - 1; y >= 0; y--) { Array.Copy(px, y * w * 4, o, k, w * 4); k += w * 4; }
		File.WriteAllBytes(p, o);
	}
}
