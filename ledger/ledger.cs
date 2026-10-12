// The Goblin Ledger: the textures of its three themes, made from noise and
// lit height fields (kit.cs: Img, Noise, HField). Tileable materials repeat
// without seams (periodic noise); metal pieces are lit from the top left.
// (the using clauses are those of kit.cs: this file is compiled after it)

public static class LedgerArt {
	static float Cl(float v) { return v < 0 ? 0 : v > 1 ? 1 : v; }
	static float SS(float a, float b, float x) { float t = Cl((x - a) / (b - a)); return t * t * (3 - 2 * t); }
	static float Mix(float a, float b, float t) { return a + (b - a) * t; }

	// periodic fbm on an s x s image: base period p cells, oct octaves
	public static float Fbm(float x, float y, int s, int p, int oct, int seed) {
		float f = 0, amp = 0.5f, tot = 0;
		for (int o = 0; o < oct; o++) { int q = p << o; f += Noise.Value(x * q / s, y * q / s, q, seed + o * 31) * amp; tot += amp; amp *= 0.5f; }
		return f / tot;
	}
	// periodic noise stretched: px cells along x, py along y
	static float Streak(float x, float y, int s, int px, int py, int seed) { return Noise.Value(x * px / s, y * py / s, Math.Max(px, py), seed); }

	static void Put(Img o, int x, int y, float r, float g, float b, float a) { int i = o.I(x, y); o.R[i] = Cl(r); o.G[i] = Cl(g); o.B[i] = Cl(b); o.A[i] = Cl(a); }

	// ---- tileable materials, s x s ------------------------------------------------

	// parchment: blotches between a light and a darker tone, grain, fibres
	public static Img Parchment(int s, float lr, float lg, float lb, float dr, float dg, float db, int seed) {
		var o = new Img(s, s);
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float blot = SS(0.35f, 0.78f, Fbm(x, y, s, 3, 4, seed));
			float grain = (Fbm(x, y, s, 48, 2, seed + 5) - 0.5f) * 0.06f;
			float fibre = (Noise.Value(x * 64f / s, y * 6f / s, 64, seed + 9) - 0.5f) * 0.035f;
			float t = blot * 0.55f;
			float k = 1 + grain + fibre;
			Put(o, x, y, Mix(lr, dr, t) * k, Mix(lg, dg, t) * k, Mix(lb, db, t) * k, 1);
		}
		return o;
	}

	// leather: a pebbled grain lit from the top left, creases, slow tone changes
	public static Img Leather(int s, float r, float g, float b, int seed) {
		var o = new Img(s, s);
		var h = new float[s * s];
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float pebble = Fbm(x, y, s, 40, 2, seed);
			float crease = 1 - Math.Abs(Noise.Value(x * 10f / s, y * 10f / s, 10, seed + 3) * 2 - 1);
			h[y * s + x] = pebble - (float)Math.Pow(crease, 24) * 0.18f;
		}
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float dx = h[y * s + (x + 1) % s] - h[y * s + (x + s - 1) % s];
			float dy = h[((y + 1) % s) * s + x] - h[((y + s - 1) % s) * s + x];
			float light = 1 + (-dx * 0.5f - dy * 0.7f) * 2.2f;
			float tone = 1 + (Fbm(x, y, s, 3, 3, seed + 7) - 0.5f) * 0.22f;
			float k = light * tone;
			Put(o, x, y, r * k, g * k, b * k, 1);
		}
		return o;
	}

	// dark riveted plate metal: brushed streaks, mottled patina (tinted pr pg pb in the low parts)
	public static Img Plate(int s, float r, float g, float b, float pr, float pg, float pb, int seed) {
		var o = new Img(s, s);
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float brush = (Streak(x, y, s, 2, 96, seed) - 0.5f) * 0.10f + (Streak(x, y, s, 8, 256, seed + 1) - 0.5f) * 0.05f;
			float mott = Fbm(x, y, s, 4, 4, seed + 2);
			float pat = SS(0.55f, 0.8f, mott) * 0.35f;
			float k = 1 + brush + (mott - 0.5f) * 0.12f;
			Put(o, x, y, Mix(r, pr, pat) * k, Mix(g, pg, pat) * k, Mix(b, pb, pat) * k, 1);
		}
		// faint scratches (wrapped)
		var rnd = new Random(seed);
		for (int n = 0; n < 26; n++) {
			float x0 = rnd.Next(s), y0 = rnd.Next(s), ang = (float)(rnd.NextDouble() * Math.PI), len = 12 + rnd.Next(40);
			for (int t = 0; t < len; t++) {
				int x = ((int)(x0 + Math.Cos(ang) * t) % s + s) % s, y = ((int)(y0 + Math.Sin(ang) * t) % s + s) % s; int i = o.I(x, y);
				o.R[i] = Cl(o.R[i] + 0.035f); o.G[i] = Cl(o.G[i] + 0.035f); o.B[i] = Cl(o.B[i] + 0.035f);
			}
		}
		return o;
	}

	// ---- metal pieces ---------------------------------------------------------------

	static void MetalColour(float x, float y, float r, float g, float b, int seed, out float or_, out float og, out float ob) {
		float n = Noise.Value(x / 9f, y / 9f, 64, seed) * 0.6f + Noise.Value(x / 2.5f, y / 2.5f, 256, seed + 1) * 0.4f;
		float k = 1 + (n - 0.5f) * 0.18f;
		or_ = r * k; og = g * k; ob = b * k;
	}
	static float Bevel(float t, float bev) { return Math.Min(1, Math.Min(SS(0, bev, t), SS(0, bev, 1 - t))); }

	static void Rivet(HField f, float cx, float cy, float rad, float baseH, float r, float g, float b, bool wrapX) {
		for (int y = (int)(cy - rad - 1); y <= (int)(cy + rad + 1); y++) for (int x = (int)(cx - rad - 1); x <= (int)(cx + rad + 1); x++) {
			float dx = x + 0.5f - cx, dy = y + 0.5f - cy, d = (float)Math.Sqrt(dx * dx + dy * dy) / rad;
			if (d > 1.1f) continue;
			float h = baseH + 0.9f * (float)Math.Sqrt(Math.Max(0, 1 - d * d)); float a = Cl((1.1f - d) / 0.1f);
			int xx = wrapX ? ((x % f.W) + f.W) % f.W : x;
			f.Set(xx, y, h, a, r * 1.1f, g * 1.1f, b * 1.1f, 0.7f);
		}
	}

	// a band h px high, tileable along x: bevelled metal; style 0 engraved line
	// (brass), 1 rivets every 64 px (copper), 2 thin with a fine groove (gold)
	public static Img Band(int w, int h, float r, float g, float b, int style, int seed) {
		var f = new HField(w, h);
		float y0 = style == 2 ? h * 0.22f : h * 0.12f, y1 = style == 2 ? h * 0.78f : h * 0.88f;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			if (y + 0.5f < y0 || y + 0.5f > y1) continue;
			float t = (y + 0.5f - y0) / (y1 - y0);
			float hh = 0.9f * Bevel(t, 0.22f);
			float cr, cg, cb; MetalColour(x, y, r, g, b, seed, out cr, out cg, out cb);
			float groove = style != 1 ? 1 - SS(0, 1.2f, Math.Abs(y + 0.5f - h / 2f)) : 0;
			float wear = (1 - Bevel(t, 0.12f)) * 0.12f;
			f.Set(x, y, hh - groove * 0.4f, 1, cr + wear - groove * 0.08f, cg + wear - groove * 0.08f, cb + wear - groove * 0.06f, 0.55f);
		}
		if (style == 1) for (int k = 0; k < w / 64; k++) Rivet(f, k * 64 + 32, h / 2f, h * 0.17f, 0.9f, r, g, b, true);
		var img = f.Shade(3.0f, true, false);
		// soft shadow under the band
		var o = new Img(w, h);
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { float d = y + 0.5f - y1; if (d > 0 && d < 4) { int i = o.I(x, y); o.A[i] = 0.45f * (1 - d / 4); } }
		o.Draw(img, 0, 0, 1);
		return o;
	}

	// a corner protector, s x s, top left: an L of metal (arm px wide) with a
	// rounded inner corner; rivets; style 2: a filigree curl
	public static Img Corner(int s, int arm, float r, float g, float b, int style, int seed) {
		var f = new HField(s, s);
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float px = x + 0.5f, py = y + 0.5f;
			bool inArm = px < arm || py < arm;
			// rounded outer end of each arm, a quarter circle at the inner corner
			float endFade = Math.Min(s - 2 - px, s - 2 - py);
			if (!inArm || endFade < 0) continue;
			float e = Math.Min(Math.Min(px, py), Math.Max(arm - Math.Min(px, py), 0));
			float t = Cl(Math.Min(Math.Min(px, py) / arm, 1));
			float edgeDist = Math.Min(Math.Min(px, py), Math.Min(arm - (px < arm ? px : 0), arm - (py < arm ? py : 0)));
			float hh = 0.6f + 0.5f * SS(0, 5, Math.Min(Math.Min(px, py), Math.Min(s - px, s - py))) * SS(0, 5, Math.Max(arm - px, arm - py));
			float cr, cg, cb; MetalColour(x, y, r, g, b, seed, out cr, out cg, out cb);
			f.Set(x, y, hh, Cl(endFade / 1.5f), cr, cg, cb, 0.6f);
		}
		Rivet(f, arm * 0.5f, arm * 0.5f, arm * 0.2f, 1.1f, r, g, b, false);
		if (style >= 1) { Rivet(f, s - arm * 0.6f, arm * 0.5f, arm * 0.14f, 1.0f, r, g, b, false); Rivet(f, arm * 0.5f, s - arm * 0.6f, arm * 0.14f, 1.0f, r, g, b, false); }
		if (style == 2) {
			// a raised lozenge in the inner corner
			float cx = arm + 7, cy = arm + 7;
			for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
				float d = Math.Abs(x + 0.5f - cx) + Math.Abs(y + 0.5f - cy);
				if (d < 6) f.Set(x, y, 1.0f - d * 0.08f, Cl(6 - d), r, g, b, 0.7f);
			}
		}
		return f.Shade(3.0f, false, false);
	}

	// the spine between the pages, w x h, tileable along y; style 0 stitched
	// leather (r g b), 1 a metal hinge, 2 leather with two gold lines
	public static Img Spine(int w, int h, float r, float g, float b, float mr, float mg, float mb, int style, int seed) {
		var o = new Img(w, h);
		float c = w / 2f;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			float d = Math.Abs(x + 0.5f - c) / c;
			// the gutter: a soft dark fall towards the middle on both sides
			float shade = 0.55f * (1 - SS(0, 1, d));
			Put(o, x, y, 0, 0, 0.01f, shade);
		}
		if (style == 1) {
			var f = new HField(w, h);
			for (int y = 0; y < h; y++) for (int x = (int)(c - 9); x <= (int)(c + 9); x++) {
				float t = (x + 0.5f - (c - 9)) / 18f; float knuckle = (y % 64) < 2 || (y % 64) > 61 ? 0.3f : 1;
				float cr, cg, cb; MetalColour(x, y, mr, mg, mb, seed, out cr, out cg, out cb);
				f.Set(x, y, 1.2f * (float)Math.Sin(Math.PI * Cl(t)) * knuckle, 1, cr * knuckle, cg * knuckle, cb * knuckle, 0.6f);
			}
			o.Draw(f.Shade(3.0f, false, true), 0, 0, 1);
		} else {
			for (int y = 0; y < h; y++) for (int x = (int)(c - 6); x <= (int)(c + 6); x++) {
				float t = Math.Abs(x + 0.5f - c) / 6f; float k = 0.75f + 0.25f * (1 - t);
				Put(o, x, y, r * k, g * k, b * k, 1);
			}
			if (style == 0) {
				for (int y = 0; y < h; y++) if ((y % 12) < 7) foreach (int sx in new[] { (int)(c - 4), (int)(c + 4) }) Put(o, sx, y, 0.86f, 0.78f, 0.6f, 1);
			} else {
				for (int y = 0; y < h; y++) foreach (int sx in new[] { (int)(c - 5), (int)(c + 5) }) Put(o, sx, y, mr, mg, mb, 1);
			}
		}
		return o;
	}

	// a bookmark tab (w x h): a ribbon pointing right with a swallow tail; style
	// 0 cloth with a brass eyelet, 1 a riveted copper tag, 2 cloth with a gold edge
	public static Img Tab(int w, int h, float r, float g, float b, float mr, float mg, float mb, int style, int seed) {
		var o = new Img(w, h);
		float top = 4, bot = h - 4, notch = 14;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			float px = x + 0.5f, py = y + 0.5f;
			if (py < top || py > bot) continue;
			float mid = (top + bot) / 2, rel = Math.Abs(py - mid) / ((bot - top) / 2);
			float right = style == 1 ? w - 6 : w - notch * (1 - rel);
			if (px > right) continue;
			float edge = Math.Min(Math.Min(py - top, bot - py), right - px);
			float k;
			if (style == 1) {
				float n = Streak(x, y, 128, 2, 48, seed) - 0.5f;
				k = 1 + n * 0.12f + (edge < 2 ? 0.18f : 0);
			} else {
				float weave = ((x + y) % 3 == 0 ? 0.04f : 0) - ((x - y + 300) % 4 == 0 ? 0.03f : 0);
				k = 1 + weave + (Fbm(x, y, 128, 4, 2, seed) - 0.5f) * 0.12f - (edge < 2.5f ? 0.18f : 0);
			}
			Put(o, x, y, r * k, g * k, b * k, 1);
			if (style == 2 && edge >= 2 && edge < 3.5f) Put(o, x, y, mr, mg, mb, 1);
		}
		if (style == 0 || style == 1) {
			float cx = 12, cy = h / 2f;
			for (int y = 0; y < h; y++) for (int x = 0; x < 26; x++) {
				float d = (float)Math.Sqrt((x + 0.5f - cx) * (x + 0.5f - cx) + (y + 0.5f - cy) * (y + 0.5f - cy));
				if (d < 5) { float k = 0.8f + 0.4f * (1 - d / 5); Put(o, x, y, mr * k, mg * k, mb * k, 1); }
				if (style == 0 && d < 2.2f) Put(o, x, y, 0.08f, 0.06f, 0.04f, 1);
			}
		}
		// shadow under it
		var s = new Img(w, h);
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { int i = o.I(x, Math.Max(0, y - 2)); if (o.A[i] > 0.5f && o.A[o.I(x, y)] < 0.5f) { s.A[s.I(x, y)] = 0.4f; } }
		s.Draw(o, 0, 0, 1);
		return s;
	}

	// a button (w x h, 3-slice: caps of h / 2): rounded plate of colour (r g b)
	// with a rim (mr mg mb); style 1: two rivets near the ends
	public static Img Button(int w, int h, float r, float g, float b, float mr, float mg, float mb, int style, int seed) {
		var f = new HField(w, h);
		float rad = h * 0.32f;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			float px = x + 0.5f, py = y + 0.5f;
			float qx = Math.Max(Math.Max(rad + 1 - px, px - (w - 1 - rad)), 0), qy = Math.Max(Math.Max(rad + 1 - py, py - (h - 1 - rad)), 0);
			float out_ = (float)Math.Sqrt(qx * qx + qy * qy) - rad;
			if (out_ > 0.8f) continue;
			float a = Cl(0.8f - out_);
			float inner = -out_; // depth inside the edge
			bool rim = inner < 2.2f;
			float cr, cg, cb;
			if (rim) MetalColour(x, y, mr, mg, mb, seed, out cr, out cg, out cb);
			else { float n = (Fbm(x, y, 128, 16, 2, seed) - 0.5f) * 0.10f; cr = r * (1 + n); cg = g * (1 + n); cb = b * (1 + n); }
			float hh = rim ? 0.9f : 0.5f + 0.25f * (1 - Math.Abs(py - h / 2f) / (h / 2f));
			f.Set(x, y, hh, a, cr, cg, cb, rim ? 0.6f : 0.15f);
		}
		if (style == 1) { Rivet(f, 9, h / 2f, 2.6f, 0.9f, mr, mg, mb, false); Rivet(f, w - 10, h / 2f, 2.6f, 0.9f, mr, mg, mb, false); }
		return f.Shade(2.4f, false, false);
	}

	// a coin (s x s): raised rim, an inner ring and a "G" (the goblin mint)
	public static Img Coin(int s, float r, float g, float b, int seed) {
		var f = new HField(s, s);
		float c = s / 2f, R = s / 2f - 2;
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) {
			float d = (float)Math.Sqrt((x + 0.5f - c) * (x + 0.5f - c) + (y + 0.5f - c) * (y + 0.5f - c));
			if (d > R + 0.8f) continue;
			float hh = d > R - 3 ? 1.0f : (Math.Abs(d - R * 0.62f) < 1.2f ? 0.8f : 0.55f);
			float cr, cg, cb; MetalColour(x, y, r, g, b, seed, out cr, out cg, out cb);
			f.Set(x, y, hh, Cl(R + 0.8f - d), cr, cg, cb, 0.7f);
		}
		var img = f.Shade(2.8f, false, false);
		// the G, embossed: drawn with GDI on a mask, lighter
		using (var bm = new Bitmap(s, s)) using (var gr = Graphics.FromImage(bm)) {
			gr.SmoothingMode = SmoothingMode.AntiAlias; gr.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAlias;
			using (var font = new Font("Times New Roman", s * 0.42f, FontStyle.Bold, GraphicsUnit.Pixel)) using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
				gr.DrawString("G", font, Brushes.White, new RectangleF(0, 1, s, s), sf);
			var m = Img.FromBitmap(bm);
			for (int i = 0; i < img.A.Length; i++) if (m.A[i] > 0.1f) { float k = 1 + 0.35f * m.A[i]; img.R[i] = Cl(img.R[i] * k); img.G[i] = Cl(img.G[i] * k); img.B[i] = Cl(img.B[i] * k); }
		}
		return img;
	}

	// a neutral rivet (s x s), tinted by the game
	public static Img RivetImg(int s) {
		var f = new HField(s, s);
		Rivet(f, s / 2f, s / 2f, s / 2f - 1.5f, 0, 0.8f, 0.8f, 0.8f, false);
		return f.Shade(2.6f, false, false);
	}

	// a stamp, white (tinted by the game): double rounded frame, the text, a
	// slight tilt, ink with gaps
	public static Img Stamp(int w, int h, string text, int seed) {
		var bm = new Bitmap(w, h);
		using (var gr = Graphics.FromImage(bm)) {
			gr.SmoothingMode = SmoothingMode.AntiAlias; gr.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
			gr.TranslateTransform(w / 2f, h / 2f); gr.RotateTransform(-5); gr.TranslateTransform(-w / 2f, -h / 2f);
			using (var pen = new Pen(Color.White, 4)) gr.DrawRectangle(pen, 10, 12, w - 20, h - 24);
			using (var pen = new Pen(Color.White, 1.5f)) gr.DrawRectangle(pen, 16, 18, w - 32, h - 36);
			float size = h * 0.36f;
			using (var font = new Font("Georgia", size, FontStyle.Bold, GraphicsUnit.Pixel)) {
				var sz = gr.MeasureString(text, font);
				float k = Math.Min(1, (w - 44) / sz.Width);
				using (var f2 = new Font("Georgia", size * k, FontStyle.Bold, GraphicsUnit.Pixel)) using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center })
					gr.DrawString(text, f2, Brushes.White, new RectangleF(0, 2, w, h), sf);
			}
		}
		var o = Img.FromBitmap(bm); bm.Dispose();
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			int i = o.I(x, y);
			float n = Noise.Value(x / 3f, y / 3f, 256, seed) * 0.6f + Noise.Value(x / 11f, y / 11f, 64, seed + 1) * 0.4f;
			o.A[i] *= n < 0.30f ? 0.25f : (n < 0.38f ? 0.7f : 1);
			o.R[i] = 1; o.G[i] = 1; o.B[i] = 1;
		}
		return o;
	}

	// a flourish (w x h, white): a line thinning to its ends, a lozenge in the middle
	public static Img Flourish(int w, int h) {
		var o = new Img(w, h);
		float c = h / 2f;
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) {
			float t = Math.Abs(x + 0.5f - w / 2f) / (w / 2f);
			float thick = 1.6f * (1 - t * t);
			float a = Cl(thick - Math.Abs(y + 0.5f - c) + 0.5f);
			float dx = Math.Abs(x + 0.5f - w / 2f), dy = Math.Abs(y + 0.5f - c);
			if (dx / 9f + dy / 6f < 1) a = Math.Max(a, Cl((1 - (dx / 9f + dy / 6f)) * 6));
			foreach (float side in new[] { -1f, 1f }) { float ex = w / 2f + side * 18, d = (float)Math.Sqrt((x + 0.5f - ex) * (x + 0.5f - ex) + dy * dy); if (d < 2.2f) a = Math.Max(a, Cl(2.2f - d)); }
			int i = o.I(x, y); o.R[i] = 1; o.G[i] = 1; o.B[i] = 1; o.A[i] = a;
		}
		return o;
	}

	// a dot (s x s, white, anti-aliased)
	public static Img Dot(int s) {
		var o = new Img(s, s); float c = s / 2f, R = s / 2f - 1;
		for (int y = 0; y < s; y++) for (int x = 0; x < s; x++) { float d = (float)Math.Sqrt((x + 0.5f - c) * (x + 0.5f - c) + (y + 0.5f - c) * (y + 0.5f - c)); int i = o.I(x, y); o.R[i] = 1; o.G[i] = 1; o.B[i] = 1; o.A[i] = Cl(R - d + 0.5f); }
		return o;
	}

	// a soft vertical gradient (s x s white, alpha from a0 at the top to a1 at the bottom)
	public static Img Fade(int w, int h, float a0, float a1) {
		var o = new Img(w, h);
		for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) { int i = o.I(x, y); o.R[i] = 1; o.G[i] = 1; o.B[i] = 1; o.A[i] = Mix(a0, a1, (y + 0.5f) / h); }
		return o;
	}
}
