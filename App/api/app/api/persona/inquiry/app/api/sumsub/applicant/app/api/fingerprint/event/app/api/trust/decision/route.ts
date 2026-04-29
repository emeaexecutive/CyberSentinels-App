import { NextResponse } from 'next/server'
import { pool } from '@/lib/db'
import { calculateCompositeTrustScore, TrustSignal } from '@/lib/trust-score'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const entityType = String(body.entity_type || 'human')
    const entityId = String(body.entity_id || '')

    if (!entityId) {
      return NextResponse.json(
        { success: false, error: 'entity_id is required' },
        { status: 400 }
      )
    }

    const result = await pool.query(
      `SELECT provider, signal_type, score, status
       FROM trust_signals
       WHERE entity_id = $1
       ORDER BY created_at DESC
       LIMIT 20`,
      [entityId]
    )

    const signals: TrustSignal[] = result.rows.map((row) => ({
      provider: row.provider,
      signalType: row.signal_type,
      score: Number(row.score),
      status: row.status
    }))

    const decision = calculateCompositeTrustScore(signals)

    const inserted = await pool.query(
      `INSERT INTO trust_decisions (entity_type, entity_id, final_score, decision, reasons)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, entity_type, entity_id, final_score, decision, reasons, created_at`,
      [
        entityType,
        entityId,
        decision.finalScore,
        decision.decision,
        JSON.stringify(decision.reasons)
      ]
    )

    await pool.query(
      `INSERT INTO audit_logs (event_type, entity_type, entity_id, details)
       VALUES ($1, $2, $3, $4)`,
      [
        'composite_trust_decision_created',
        entityType,
        entityId,
        JSON.stringify(decision)
      ]
    )

    return NextResponse.json({
      success: true,
      decision: inserted.rows[0],
      signals
    })
  } catch (error) {
    console.error('Trust decision error:', error)

    return NextResponse.json(
      { success: false, error: 'Trust decision processing failed' },
      { status: 500 }
        )
  }
}
