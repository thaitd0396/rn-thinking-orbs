package com.rnthinkingorbs

import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin
import kotlin.math.sqrt

internal object ThinkingOrbsSpin {
  const val IDLE_PERIOD = 4.6f
  val IDLE_SPEED = (2f * Math.PI.toFloat()) / IDLE_PERIOD
}

/**
 * View-space trackball: the front of the sphere follows the finger.
 * Screen axes are +X right, +Y down, +Z toward the camera.
 * The rotation axis stays parallel to the phone face (`z = 0`).
 */
internal class ThinkingOrbsTrackball {
  private var qw = 1f
  private var qx = 0f
  private var qy = 0f
  private var qz = 0f

  fun roll(dxRadians: Float, dyRadians: Float) {
    val angle = hypot(dxRadians, dyRadians)
    if (angle < 1e-8f) {
      return
    }
    val ax = -dyRadians / angle
    val ay = dxRadians / angle
    val half = angle * 0.5f
    val dw = cos(half)
    val s = sin(half)
    val dxq = ax * s
    val dyq = ay * s
    val nw = dw * qw - dxq * qx - dyq * qy
    val nx = dw * qx + dxq * qw + dyq * qz
    val ny = dw * qy - dxq * qz + dyq * qw
    val nz = dw * qz + dxq * qy - dyq * qx
    val len = sqrt(nw * nw + nx * nx + ny * ny + nz * nz)
    if (len < 1e-8f) {
      return
    }
    qw = nw / len
    qx = nx / len
    qy = ny / len
    qz = nz / len
  }

  /** Row-major 3x3, `p' = M p`. */
  fun matrixRows(): FloatArray {
    val xx = qx * qx
    val yy = qy * qy
    val zz = qz * qz
    val xy = qx * qy
    val xz = qx * qz
    val yz = qy * qz
    val wx = qw * qx
    val wy = qw * qy
    val wz = qw * qz
    return floatArrayOf(
      1f - 2f * (yy + zz),
      2f * (xy - wz),
      2f * (xz + wy),
      2f * (xy + wz),
      1f - 2f * (xx + zz),
      2f * (yz - wx),
      2f * (xz - wy),
      2f * (yz + wx),
      1f - 2f * (xx + yy),
    )
  }
}
