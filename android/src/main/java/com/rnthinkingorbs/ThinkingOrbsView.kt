package com.rnthinkingorbs

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.os.Build
import android.view.Choreographer
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.View
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

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
      syncPlayback()
      invalidate()
    }
  var interactive: Boolean = false
    set(value) {
      field = value
      isClickable = value
      syncPlayback()
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
  private var lastFrameNanos = System.nanoTime()
  private var running = false
  private val trackball = ThinkingOrbsTrackball()
  private var velocityX = -ThinkingOrbsSpin.IDLE_SPEED
  private var velocityY = 0f
  private var idleDirX = -1f
  private var idleDirY = 0f
  private var lastTouchX = 0f
  private var lastTouchY = 0f
  private var dragging = false
  private var idleSeconds = 0.0
  private var idleRunningSinceNanos: Long? = null
  private var velocityTracker: VelocityTracker? = null

  override fun onAttachedToWindow() {
    super.onAttachedToWindow()
    setWillNotDraw(false)
    importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    syncPlayback()
  }

  override fun onDetachedFromWindow() {
    stop()
    recycleVelocityTracker()
    super.onDetachedFromWindow()
  }

  override fun onTouchEvent(event: MotionEvent): Boolean {
    if (!interactive) {
      return super.onTouchEvent(event)
    }
    val box = max(min(width, height), 1).toFloat()
    val gain = 1f / box
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        disallowParentIntercept()
        dragging = true
        velocityX = 0f
        velocityY = 0f
        lastTouchX = event.x
        lastTouchY = event.y
        freezeIdle()
        recycleVelocityTracker()
        velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
        invalidate()
        return true
      }
      MotionEvent.ACTION_MOVE -> {
        disallowParentIntercept()
        velocityTracker?.addMovement(event)
        val dx = (event.x - lastTouchX) * gain
        val dy = (event.y - lastTouchY) * gain
        trackball.roll(dx, dy)
        lastTouchX = event.x
        lastTouchY = event.y
        val step = hypot(dx, dy)
        if (step > 1e-8f) {
          idleDirX = dx / step
          idleDirY = dy / step
        }
        invalidate()
        return true
      }
      MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
        velocityTracker?.addMovement(event)
        velocityTracker?.computeCurrentVelocity(1000)
        velocityX = (velocityTracker?.xVelocity ?: 0f) * gain
        velocityY = (velocityTracker?.yVelocity ?: 0f) * gain
        rememberSpinDirection()
        recycleVelocityTracker()
        dragging = false
        parent?.requestDisallowInterceptTouchEvent(false)
        if (animated) {
          resumeIdle()
        }
        syncPlayback()
        return true
      }
    }
    return super.onTouchEvent(event)
  }

  override fun doFrame(frameTimeNanos: Long) {
    val dt = ((frameTimeNanos - lastFrameNanos).coerceAtLeast(0) / 1_000_000_000.0).toFloat()
    lastFrameNanos = frameTimeNanos
    if (!dragging) {
      coastSpin(dt)
    }
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
    val seconds = currentIdleSeconds()
    val phase = orbPhase(ThinkingOrbsSpin.IDLE_PERIOD.toDouble(), 1.0, false, 0.0, seconds)
    val userRotation = trackball.matrixRows()
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
          userRotation = userRotation,
          accent = accentColor,
          ink = dotColor,
        )
      canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), shaderPaint)
      return
    }
    val ox = originX * density
    val oy = originY * density
    val dots =
      orbSheetDots(
        phase,
        box,
        orbSizeDotScale(box),
        userRotation = userRotation,
      )
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

  private fun syncPlayback() {
    if (animated && !dragging) {
      resumeIdle()
    } else {
      freezeIdle()
    }
    if ((animated || interactive) && isAttachedToWindow) {
      start()
    } else {
      stop()
    }
  }

  private fun currentIdleSeconds(): Double {
    val since = idleRunningSinceNanos
    return if (since == null) {
      idleSeconds
    } else {
      idleSeconds + (System.nanoTime() - since) / 1_000_000_000.0
    }
  }

  private fun freezeIdle() {
    idleSeconds = currentIdleSeconds()
    idleRunningSinceNanos = null
  }

  private fun resumeIdle() {
    if (!animated || idleRunningSinceNanos != null) {
      return
    }
    idleSeconds = currentIdleSeconds()
    idleRunningSinceNanos = System.nanoTime()
  }

  private fun disallowParentIntercept() {
    var current = parent
    while (current != null) {
      current.requestDisallowInterceptTouchEvent(true)
      current = current.parent
    }
  }

  private fun start() {
    if (running) return
    running = true
    lastFrameNanos = System.nanoTime()
    Choreographer.getInstance().postFrameCallback(this)
  }

  private fun stop() {
    running = false
    Choreographer.getInstance().removeFrameCallback(this)
  }

  private fun rememberSpinDirection() {
    val speed = hypot(velocityX, velocityY)
    if (speed <= 1e-6f) {
      return
    }
    idleDirX = velocityX / speed
    idleDirY = velocityY / speed
  }

  private fun coastSpin(dt: Float) {
    if (animated) {
      rememberSpinDirection()
      val cruise = ThinkingOrbsSpin.IDLE_SPEED
      val speed = hypot(velocityX, velocityY)
      val next =
        if (speed > cruise) {
          cruise + (speed - cruise) * exp(-3f * dt)
        } else {
          cruise
        }
      velocityX = idleDirX * next
      velocityY = idleDirY * next
    } else {
      val speed = hypot(velocityX, velocityY)
      if (speed < 0.02f) {
        velocityX = 0f
        velocityY = 0f
      } else {
        val scale = exp(-3f * dt)
        velocityX *= scale
        velocityY *= scale
      }
    }
    trackball.roll(velocityX * dt, velocityY * dt)
  }

  private fun recycleVelocityTracker() {
    velocityTracker?.recycle()
    velocityTracker = null
  }
}
