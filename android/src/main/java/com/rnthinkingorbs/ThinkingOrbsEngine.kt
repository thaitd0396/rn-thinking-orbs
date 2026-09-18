package com.rnthinkingorbs

internal data class OrbDot(
  val x: Double,
  val y: Double,
  val r: Double,
  val a: Double,
  val accent: Boolean,
)

internal data class OrbKnobs(
  val n: Double = 1.0,
  val sp: Double = 1.0,
  val pv: Double = 1.0,
  val dz: Double = 1.0,
  val df: Double = 1.0,
  val yw: Double = 0.0,
  val pc: Double = 0.0,
  val sn: Double = 0.0,
  val op: Double = 1.0,
)

private const val TAU = Math.PI * 2
private const val ORB_DOT = 1.0
private const val ORB_ACCENT = 2.0

internal fun orbPhase(
  period: Double,
  speed: Double,
  reverse: Boolean,
  startAt: Double,
  seconds: Double,
): Double {
  val span = period / maxOf(0.0001, speed)
  var u = ((seconds % span) / span)
  if (u < 0) u += 1
  if (reverse) u = 1 - u
  u = (u + startAt) % 1
  return if (u < 0) u + 1 else u
}

internal fun orbSizeDotScale(size: Double): Double {
  if (size <= 46) return 0.4
  if (size <= 190) return 0.4 + ((size - 46) / 144) * 0.6
  if (size <= 340) return 1 + ((size - 190) / 150) * 0.55
  return 1.55
}

internal fun thinkingOrbsFit(size: Double): Double = orbFitCached(size, OrbKnobs())

internal fun orbSheetDots(
  phase: Double,
  size: Double,
  dotScale: Double,
  knobs: OrbKnobs = OrbKnobs(),
  userRotation: FloatArray = IDENTITY_ROTATION,
): List<OrbDot> {
  val fit = orbFitCached(size, knobs)
  val half = size / 2
  val out = ArrayList<OrbDot>(160)
  val sink =
    OrbSink(dotScale, knobs, phase) { x, y, r, a, col ->
      val fx = half + (x - half) * fit
      val fy = half + (y - half) * fit
      val fr = r * (0.55 + 0.45 * fit)
      val fa = a * knobs.op
      if (fr <= 0.05 || fa <= 0.004) return@OrbSink
      out.add(OrbDot(fx, fy, fr, minOf(1.0, fa), col == ORB_ACCENT))
    }
  drawStripes(phase, size, sink, userRotation)
  return out
}

private class OrbSink(
  val ds: Double,
  knobs: OrbKnobs,
  var t: Double,
  private val emit: (Double, Double, Double, Double, Double) -> Unit,
) {
  val n = knobs.n
  val sp = knobs.sp
  val pv = knobs.pv
  val dz = knobs.dz
  val df = knobs.df
  val yw = knobs.yw
  val pc = knobs.pc
  val sn = knobs.sn

  fun d(x: Double, y: Double, r: Double, a: Double, col: Double) {
    emit(x, y, r, a, col)
  }
}

private fun cl(u: Double) = u.coerceIn(0.0, 1.0)

private fun nc(count: Double, n: Double): Int {
  val v = kotlin.math.round(count * n).toInt()
  return if (v < 1) 1 else v
}

internal val IDENTITY_ROTATION =
  floatArrayOf(
    1f, 0f, 0f,
    0f, 1f, 0f,
    0f, 0f, 1f,
  )

private fun rot(p: DoubleArray, ay: Double, ax: Double): DoubleArray {
  val ca = kotlin.math.cos(ay)
  val sa = kotlin.math.sin(ay)
  val x = p[0] * ca - p[2] * sa
  var z = p[0] * sa + p[2] * ca
  val cb = kotlin.math.cos(ax)
  val sb = kotlin.math.sin(ax)
  val y = p[1] * cb - z * sb
  z = p[1] * sb + z * cb
  return doubleArrayOf(x, y, z, p.getOrElse(3) { Double.NaN }, p.getOrElse(4) { Double.NaN }, p.getOrElse(5) { Double.NaN })
}

private fun mulRows(p: DoubleArray, m: FloatArray): DoubleArray {
  val x = p[0] * m[0] + p[1] * m[1] + p[2] * m[2]
  val y = p[0] * m[3] + p[1] * m[4] + p[2] * m[5]
  val z = p[0] * m[6] + p[1] * m[7] + p[2] * m[8]
  return doubleArrayOf(x, y, z, p.getOrElse(3) { Double.NaN }, p.getOrElse(4) { Double.NaN }, p.getOrElse(5) { Double.NaN })
}

private fun view(p: DoubleArray, k: OrbSink): DoubleArray {
  val ay = k.yw + TAU * k.sn * k.t
  return rot(p, ay, k.pc)
}

private fun fib(i: Int, n: Int): DoubleArray {
  val y = 1 - (i.toDouble() / (n - 1)) * 2
  val r = kotlin.math.sqrt(maxOf(0.0, 1 - y * y))
  val th = i * 2.399963
  return doubleArrayOf(kotlin.math.cos(th) * r, y, kotlin.math.sin(th) * r)
}

private fun sph(p: DoubleArray): DoubleArray {
  val pol = kotlin.math.acos(p[1].coerceIn(-1.0, 1.0))
  val az = kotlin.math.atan2(p[2], p[0])
  return doubleArrayOf(pol, az)
}

private fun project(pts: List<DoubleArray>, size: Double, k: OrbSink, rf: Double) {
  val cx = size / 2
  val cy = size / 2
  val radius = size * rf * k.sp
  val f = 3.5 * k.pv
  val out =
    pts.map { p0 ->
      val p = view(p0, k)
      val z = p[2]
      val per = f / (f - z)
      val d = cl((z + 1.1) / 2.2)
      val scale = if (p[3].isNaN()) 1.0 else p[3]
      val fade = if (p[4].isNaN()) 1.0 else p[4]
      val col = if (p[5].isNaN() || p[5] == 0.0) ORB_DOT else p[5]
      doubleArrayOf(
        cx + p[0] * radius * per,
        cy + p[1] * radius * per,
        k.ds * (0.4 + 1.6 * k.dz * d) * per * scale,
        (0.07 + 0.93 * Math.pow(d, 1.55 * k.df)) * fade,
        col,
        z,
      )
    }
      .sortedBy { it[5] }
  for (o in out) {
    k.d(o[0], o[1], o[2], o[3], o[4])
  }
}

private fun drawStripes(
  t: Double,
  size: Double,
  k: OrbSink,
  userRotation: FloatArray = IDENTITY_ROTATION,
) {
  val n = nc(160.0, k.n)
  val pts = ArrayList<DoubleArray>(n)
  for (i in 0 until n) {
    val p = fib(i, n)
    val s = sph(p)
    val a = kotlin.math.sin(4 * s[1] + 6 * s[0] - TAU * 2 * t)
    val b = kotlin.math.sin(4 * s[1] - 6 * s[0] + TAU * 2 * t)
    val w = cl((a * b + 1) / 2)
    val spun =
      doubleArrayOf(p[0], p[1], p[2], 0.5 + 1.3 * w, 0.2 + 0.8 * w, if (w > 0.9) ORB_ACCENT else ORB_DOT)
    pts.add(mulRows(spun, userRotation))
  }
  project(pts, size, k, 0.3)
}

private val orbFitCache = LinkedHashMap<String, Double>(16, 0.75f, true)

private fun orbFitCached(size: Double, knobs: OrbKnobs): Double {
  val key = "$size@${knobs.n}@${knobs.sp}@${knobs.pv}@${knobs.dz}@${knobs.df}@${knobs.yw}@${knobs.pc}@${knobs.sn}@${knobs.op}"
  synchronized(orbFitCache) {
    orbFitCache[key]?.let { return it }
  }
  val fit = orbFit(size, knobs)
  synchronized(orbFitCache) {
    orbFitCache[key] = fit
    if (orbFitCache.size > 32) {
      val oldest = orbFitCache.keys.first()
      orbFitCache.remove(oldest)
    }
  }
  return fit
}

private fun orbFit(size: Double, knobs: OrbKnobs): Double {
  val half = size / 2
  var ext = 0.0
  val probe =
    OrbSink(1.0, knobs, 0.0) { x, y, r, a, _ ->
      if (a <= 0.05 || r <= 0.15) return@OrbSink
      ext = maxOf(ext, kotlin.math.abs(x - half) + r * 0.5, kotlin.math.abs(y - half) + r * 0.5)
    }
  for (step in 0 until 20) {
    probe.t = step / 20.0
    drawStripes(step / 20.0, size, probe)
  }
  return if (ext > 1) maxOf(0.55, minOf(1.7, (size * 0.415) / ext)) else 1.0
}
