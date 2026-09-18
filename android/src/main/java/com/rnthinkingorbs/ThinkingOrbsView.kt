package com.rnthinkingorbs

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.view.Choreographer
import android.view.View

class ThinkingOrbsView(context: Context) : View(context), Choreographer.FrameCallback {
  init {
    setBackgroundColor(Color.TRANSPARENT)
    isClickable = false
    isFocusable = false
  }

  var accentColor: Int = Color.parseColor("#2A67F4")
    set(value) {
      field = value
      invalidate()
    }
  var dotColor: Int = Color.BLACK
    set(value) {
      field = value
      invalidate()
    }
  var animated: Boolean = true
    set(value) {
      field = value
      if (value) start() else stop()
      invalidate()
    }

  private val paint =
    Paint(Paint.ANTI_ALIAS_FLAG).apply {
      style = Paint.Style.FILL
    }
  private val shaderPaint = Paint(Paint.ANTI_ALIAS_FLAG)
  private val agslRenderer =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
      ThinkingOrbsAgslRenderer.createOrNull()
    } else {
      null
    }
  private var startedAtNanos = System.nanoTime()
  private var running = false

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    setWillNotDraw(false)
    importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    if (animated) start()
  }

  override fun onDetachedFromWindow() {
    stop()
    super.onDetachedFromWindow()
  }

  override fun doFrame(frameTimeNanos: Long) {
    invalidate()
    if (running) {
      Choreographer.getInstance().postFrameCallback(this)
    }
  }

  override fun onDraw(canvas: Canvas) {
    super.onDraw(canvas)
    val boxPx = minOf(width, height).toFloat()
    if (boxPx <= 0f) return
    val density = resources.displayMetrics.density
    val box = (boxPx / density).toDouble()
    val originX = ((width - boxPx) / 2f) / density
    val originY = ((height - boxPx) / 2f) / density
    val seconds =
      if (animated) (System.nanoTime() - startedAtNanos) / 1_000_000_000.0 else 0.0
    val phase = orbPhase(4.6, 1.0, false, 0.0, seconds)
    val renderer = agslRenderer
    if (renderer != null && canvas.isHardwareAccelerated) {
      shaderPaint.shader =
        renderer.apply(
          phase = phase.toFloat(),
          size = box.toFloat(),
          fit = thinkingOrbsFit(box).toFloat(),
          dotScale = orbSizeDotScale(box).toFloat(),
          contentsScale = density,
          originX = originX,
          originY = originY,
          accent = accentColor,
          ink = dotColor,
        )
      canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), shaderPaint)
      return
    }
    val ox = originX * density
    val oy = originY * density
    val dots = orbSheetDots(phase, box, orbSizeDotScale(box))
    for (dot in dots) {
      paint.color = if (dot.accent) accentColor else dotColor
      paint.alpha = (dot.a * 255).toInt().coerceIn(0, 255)
      canvas.drawCircle(
        (ox + dot.x * density).toFloat(),
        (oy + dot.y * density).toFloat(),
        (dot.r * density).toFloat(),
        paint,
      )
    }
  }

  private fun start() {
    if (running) return
    running = true
    startedAtNanos = System.nanoTime()
    Choreographer.getInstance().postFrameCallback(this)
  }

  private fun stop() {
    running = false
    Choreographer.getInstance().removeFrameCallback(this)
  }
}
