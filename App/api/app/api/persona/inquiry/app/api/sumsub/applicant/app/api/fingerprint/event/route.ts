import { NextResponse } from 'next/server'
import { pool } from '@/lib/db'
import { retrieveFingerprintEvent, scoreFingerprintEvent } from '@/lib/fingerprint'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const requestId = String(body.request_id || '')
    const entityId = String(body.entity_id || requestId)

    if (!requestId) {
      return NextResponse.json(
        { success: false, error: 'request_id is required' },
        { status: 400 }
      )
    }

    const fingerprintResult = await retrieveFingerprintEvent(requestId)

    if (!fingerprintResult.success) {
      return NextResponse.json(
        { success: false, error: 'Fingerprint lookup failed', details: fingerprintResult.data },
        { status: 400 }
         )
    }

    const signal = scoreFingerprintEvent(fingerprintResult.data)

    await pool.query(
      `INSERT INTO trust_signals (provider, signal_type, entity_type, entity_id, score, status, raw_response)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        signal.provider,
        signal.signalType,
        'session',
        entityId,
        signal.score,
        signal.status,
        JSON.stringify(fingerprintResult.data)
      ]
    )

    await pool.query(
      `INSERT INTO audit_logs (event_type, entity_type, entity_id, details)
       VALUES ($1, $2, $3, $4)`,
      [
        'fingerprint_device_signal_received',
        'session',
        entityId,
        JSON.stringify(signal)
      ]
    )

    return NextResponse.json({ success: true, signal })
  } catch (error) {
    console.error('Fingerprint event error:', error)

    return NextResponse.json(
      { success: false, error: 'Fingerprint event processing failed' },
      { status: 500 }
    )
  }
}
