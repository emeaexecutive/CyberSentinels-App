import { NextResponse } from 'next/server'
      return NextResponse.json(
        { success: false, error: 'inquiry_id is required' },
        { status: 400 }
      )
    }

    const personaResult = await retrievePersonaInquiry(inquiryId)

    if (!personaResult.success) {
      return NextResponse.json(
        { success: false, error: 'Persona lookup failed', details: personaResult.data },
        { status: 400 }
      )
    }

    const signal = scorePersonaInquiry(personaResult.data)

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
        JSON.stringify(personaResult.data)
      ]
    )

    await pool.query(
      `INSERT INTO audit_logs (event_type, entity_type, entity_id, details)
       VALUES ($1, $2, $3, $4)`,
      [
        'persona_identity_signal_received',
        'human',
        entityId,
        JSON.stringify(signal)
      ]
    )

    return NextResponse.json({ success: true, signal })
  } catch (error) {
    console.error('Persona inquiry error:', error)

    return NextResponse.json(
      { success: false, error: 'Persona inquiry processing failed' },
      { status: 500 }
    )
  }
}
