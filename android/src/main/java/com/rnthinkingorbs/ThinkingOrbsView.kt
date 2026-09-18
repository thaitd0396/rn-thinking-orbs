package com.rnthinkingorbs

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
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
    val box = minOf(width, height).toDouble()
    if (box <= 0) return
    val ox = (width - box) / 2
    val oy = (height - box) / 2
    val seconds =
      if (animated) (System.nanoTime() - startedAtNanos) / 1_000_000_000.0 else 0.0
    val phase = orbPhase(4.6, 1.0, false, 0.0, seconds)
    val dots = orbSheetDots(phase, box, orbSizeDotScale(box))
    for (dot in dots) {
      paint.color = if (dot.accent) accentColor else dotColor
      paint.alpha = (dot.a * 255).toInt().coerceIn(0, 255)
      canvas.drawCircle(
        (ox + dot.x).toFloat(),
        (oy + dot.y).toFloat(),
        dot.r.toFloat(),
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
