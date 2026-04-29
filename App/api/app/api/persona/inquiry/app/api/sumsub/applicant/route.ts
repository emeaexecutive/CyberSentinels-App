import { NextResponse } from 'next/server'
import { pool } from '@/lib/db'
import { retrieveSumsubApplicantStatus, scoreSumsubApplicant } from '@/lib/sumsub'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const applicantId = String(body.applicant_id || '')
    const entityId = String(body.entity_id || applicantId)

    if (!applicantId) {
      return NextResponse.json(
        { success: false, error: 'applicant_id is required' },
        { status: 400 }
      )
    }

    const sumsubResult = await retrieveSumsubApplicantStatus(applicantId)
     if (!sumsubResult.success) {
      return NextResponse.json(
        { success: false, error: 'Sumsub lookup failed', details: sumsubResult.data },
        { status: 400 }
      )
    }

    const signal = scoreSumsubApplicant(sumsubResult.data)

    await pool.query(
      `INSERT INTO trust_signals (provider, signal_type, entity_type, entity_id, score, status, raw_response)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        signal.provider,
        signal.signalType,
        'human',
        entityId,
        signal.score,
        signal.status,
        JSON.stringify(sumsubResult.data)
      ]
    )

    await pool.query(
      `INSERT INTO audit_logs (event_type, entity_type, entity_id, details)
       VALUES ($1, $2, $3, $4)`,
      [
        'sumsub_liveness_signal_received',
        'human',
        entityId,
        JSON.stringify(signal)
      ]
    )

    return NextResponse.json({ success: true, signal })
  } catch (error) {
    console.error('Sumsub applicant error:', error)

    return NextResponse.json(
      { success: false, error: 'Sumsub applicant processing failed' },
      { status: 500 }
    )
  }
}
