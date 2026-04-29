# CYBER SENTINELS — Multi-Provider Security API Layer

Create these files in your `CyberSentinels-App` repo.

This adds:

* Persona identity verification signal
* Sumsub liveness / ID verification signal
* Fingerprint device intelligence signal
* unified Cyber Sentinels trust score
* audit logging for every provider result

Persona API supports identity verification, risk assessment and compliance workflows. Sumsub supports applicant verification and liveness / face match checks. Fingerprint Server API is server-side only and used for visitor/event intelligence.

---

# 1. Update `.env.example`

```env
# Database
DATABASE_URL=postgresql://username:password@host:5432/cybersentinels

# World ID
WORLD_RP_ID=cybersentinels
WORLD_SIGNING_KEY=your_signing_key_here
NEXT_PUBLIC_WORLD_APP_ID=app_staging_xxxxx

# Persona
PERSONA_API_KEY=persona_api_key_here
PERSONA_TEMPLATE_ID=itmpl_xxxxx

# Sumsub
SUMSUB_APP_TOKEN=sumsub_app_token_here
SUMSUB_SECRET_KEY=sumsub_secret_key_here
SUMSUB_BASE_URL=https://api.sumsub.com
SUMSUB_LEVEL_NAME=basic-kyc-level

# Fingerprint
FINGERPRINT_SERVER_API_KEY=fingerprint_server_api_key_here
FINGERPRINT_REGION=eu

# App
NEXT_PUBLIC_APP_URL=http://localhost:3000
NODE_ENV=development
```

---

# 2. Update `db/schema.sql`

Add these tables below your existing tables.

```sql
CREATE TABLE IF NOT EXISTS trust_signals (
  id SERIAL PRIMARY KEY,
  provider VARCHAR(100) NOT NULL,
  signal_type VARCHAR(100) NOT NULL,
  entity_type VARCHAR(100),
  entity_id VARCHAR(255),
  score INTEGER DEFAULT 0,
  status VARCHAR(50) DEFAULT 'pending',
  raw_response JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS trust_decisions (
  id SERIAL PRIMARY KEY,
  entity_type VARCHAR(100) NOT NULL,
  entity_id VARCHAR(255) NOT NULL,
  final_score INTEGER NOT NULL,
  decision VARCHAR(50) NOT NULL,
  reasons JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);
```

---

# 3. Create `lib/trust-score.ts`

```ts
export type TrustSignal = {
  provider: 'world_id' | 'persona' | 'sumsub' | 'fingerprint' | 'internal'
  signalType: string
  score: number
  status: 'passed' | 'failed' | 'review' | 'pending'
  reason?: string
}

export function calculateCompositeTrustScore(signals: TrustSignal[]) {
  if (!signals.length) {
    return {
      finalScore: 0,
      decision: 'review' as const,
      reasons: ['No trust signals received']
    }
  }

  const weightedSignals = signals.map((signal) => {
    const weight = getProviderWeight(signal.provider)
    const statusPenalty = getStatusPenalty(signal.status)

    return {
      ...signal,
      weightedScore: Math.max(0, signal.score * weight - statusPenalty)
    }
  })

  const totalWeight = signals.reduce((sum, signal) => sum + getProviderWeight(signal.provider), 0)
  const totalScore = weightedSignals.reduce((sum, signal) => sum + signal.weightedScore, 0)
  const finalScore = Math.round(Math.min(100, totalScore / totalWeight))

  const failedCritical = signals.some(
    (signal) =>
      signal.status === 'failed' &&
      ['world_id', 'persona', 'sumsub'].includes(signal.provider)
  )

  let decision: 'approved' | 'review' | 'blocked'

  if (failedCritical || finalScore < 45) {
    decision = 'blocked'
  } else if (finalScore < 75 || signals.some((signal) => signal.status === 'review')) {
    decision = 'review'
  } else {
    decision = 'approved'
  }

  const reasons = weightedSignals.map((signal) =>
    `${signal.provider}:${signal.signalType}:${signal.status}:${signal.score}`
  )

  return {
    finalScore,
    decision,
    reasons
  }
}

function getProviderWeight(provider: TrustSignal['provider']) {
  switch (provider) {
    case 'world_id':
      return 1.2
    case 'persona':
      return 1.4
    case 'sumsub':
      return 1.4
    case 'fingerprint':
      return 0.9
    case 'internal':
      return 1
    default:
      return 1
  }
}

function getStatusPenalty(status: TrustSignal['status']) {
  switch (status) {
    case 'failed':
      return 45
    case 'review':
      return 20
    case 'pending':
      return 10
    case 'passed':
    default:
      return 0
  }
}
```

---

# 4. Create `lib/persona.ts`

```ts
export async function retrievePersonaInquiry(inquiryId: string) {
  const apiKey = process.env.PERSONA_API_KEY

  if (!apiKey) {
    throw new Error('Missing PERSONA_API_KEY')
  }

  const response = await fetch(`https://withpersona.com/api/v1/inquiries/${inquiryId}`, {
    method: 'GET',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      Accept: 'application/json'
    }
  })

  const data = await response.json()

  if (!response.ok) {
    return {
      success: false,
      status: response.status,
      data
    }
  }

  return {
    success: true,
    status: response.status,
    data
  }
}

export function scorePersonaInquiry(personaResponse: any) {
  const status = personaResponse?.data?.attributes?.status

  if (status === 'completed' || status === 'approved') {
    return {
      provider: 'persona' as const,
      signalType: 'identity_verification',
      score: 88,
      status: 'passed' as const,
      reason: 'Persona inquiry completed or approved'
    }
  }

  if (status === 'failed' || status === 'declined') {
    return {
      provider: 'persona' as const,
      signalType: 'identity_verification',
      score: 20,
      status: 'failed' as const,
      reason: 'Persona inquiry failed or declined'
    }
  }

  return {
    provider: 'persona' as const,
    signalType: 'identity_verification',
    score: 55,
    status: 'review' as const,
    reason: `Persona inquiry status: ${status || 'unknown'}`
  }
}
```

---

# 5. Create `lib/sumsub.ts`

```ts
import crypto from 'crypto'

function createSumsubSignature(method: string, path: string, body = '') {
  const secretKey = process.env.SUMSUB_SECRET_KEY

  if (!secretKey) {
    throw new Error('Missing SUMSUB_SECRET_KEY')
  }

  const timestamp = Math.floor(Date.now() / 1000).toString()
  const signaturePayload = timestamp + method.toUpperCase() + path + body
  const signature = crypto
    .createHmac('sha256', secretKey)
    .update(signaturePayload)
    .digest('hex')

  return { timestamp, signature }
}

export async function retrieveSumsubApplicantStatus(applicantId: string) {
  const appToken = process.env.SUMSUB_APP_TOKEN
  const baseUrl = process.env.SUMSUB_BASE_URL || 'https://api.sumsub.com'

  if (!appToken) {
    throw new Error('Missing SUMSUB_APP_TOKEN')
  }

  const path = `/resources/applicants/${applicantId}/one`
  const { timestamp, signature } = createSumsubSignature('GET', path)

  const response = await fetch(`${baseUrl}${path}`, {
    method: 'GET',
    headers: {
      'X-App-Token': appToken,
      'X-App-Access-Ts': timestamp,
      'X-App-Access-Sig': signature,
      Accept: 'application/json'
    }
  })

  const data = await response.json()

  if (!response.ok) {
    return {
      success: false,
      status: response.status,
      data
    }
  }

  return {
    success: true,
    status: response.status,
    data
  }
}

export function scoreSumsubApplicant(sumsubResponse: any) {
  const reviewAnswer = sumsubResponse?.review?.reviewResult?.reviewAnswer
  const reviewStatus = sumsubResponse?.review?.reviewStatus

  if (reviewAnswer === 'GREEN') {
    return {
      provider: 'sumsub' as const,
      signalType: 'liveness_id_verification',
      score: 90,
      status: 'passed' as const,
      reason: 'Sumsub applicant review returned GREEN'
    }
  }

  if (reviewAnswer === 'RED') {
    return {
      provider: 'sumsub' as const,
      signalType: 'liveness_id_verification',
      score: 15,
      status: 'failed' as const,
      reason: 'Sumsub applicant review returned RED'
    }
  }

  return {
    provider: 'sumsub' as const,
    signalType: 'liveness_id_verification',
    score: 55,
    status: 'review' as const,
    reason: `Sumsub review status: ${reviewStatus || 'unknown'}`
  }
}
```

---

# 6. Create `lib/fingerprint.ts`

```ts
export async function retrieveFingerprintEvent(requestId: string) {
  const apiKey = process.env.FINGERPRINT_SERVER_API_KEY

  if (!apiKey) {
    throw new Error('Missing FINGERPRINT_SERVER_API_KEY')
  }

  const region = process.env.FINGERPRINT_REGION || 'eu'
  const baseUrl = region === 'us'
    ? 'https://api.fpjs.io'
    : 'https://eu.api.fpjs.io'

  const response = await fetch(`${baseUrl}/events/${requestId}`, {
    method: 'GET',
    headers: {
      'Auth-API-Key': apiKey,
      Accept: 'application/json'
    }
  })

  const data = await response.json()

  if (!response.ok) {
    return {
      success: false,
      status: response.status,
      data
    }
  }

  return {
    success: true,
    status: response.status,
    data
  }
}

export function scoreFingerprintEvent(fingerprintResponse: any) {
  const confidenceScore = fingerprintResponse?.products?.identification?.data?.confidence?.score
  const botResult = fingerprintResponse?.products?.botd?.data?.bot?.result
  const vpnResult = fingerprintResponse?.products?.vpn?.data?.result

  let score = 70
  const reasons: string[] = []

  if (typeof confidenceScore === 'number') {
    score = Math.round(confidenceScore * 100)
    reasons.push(`confidence:${confidenceScore}`)
  }

  if (botResult === 'bad') {
    score -= 35
    reasons.push('bot_detected')
  }

  if (vpnResult === true) {
    score -= 15
    reasons.push('vpn_detected')
  }

  score = Math.max(0, Math.min(100, score))

  return {
    provider: 'fingerprint' as const,
    signalType: 'device_intelligence',
    score,
    status: score >= 75 ? 'passed' as const : score >= 45 ? 'review' as const : 'failed' as const,
    reason: reasons.join(', ') || 'Fingerprint device intelligence assessed'
  }
}
```

---

# 7. Create `app/api/persona/inquiry/route.ts`

```ts
import { NextResponse } from 'next/server'
import { pool } from '@/lib/db'
import { retrievePersonaInquiry, scorePersonaInquiry } from '@/lib/persona'

export async function POST(request: Request) {
  try {
    const body = await request.json()
    const inquiryId = String(body.inquiry_id || '')
    const entityId = String(body.entity_id || inquiryId)

    if (!inquiryId) {
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
```

---

# 8. Create `app/api/sumsub/applicant/route.ts`

```ts
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
```

---

# 9. Create `app/api/fingerprint/event/route.ts`

```ts
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
```

---

# 10. Create `app/api/trust/decision/route.ts`

```ts
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
```

---

# 11. API routes added

```text
POST /api/persona/inquiry
POST /api/sumsub/applicant
POST /api/fingerprint/event
POST /api/trust/decision
```

---

# 12. Strategic architecture

Cyber Sentinels should treat each provider like a signal, not the source of truth.

```text
World ID      = proof-of-human / uniqueness
Persona       = ID verification / risk workflow
Sumsub        = liveness / ID / anti-spoofing checks
Fingerprint   = device and session intelligence
Cyber Sentinels = trust score + audit log + decision engine + trust graph
```

This makes the product stronger and more defensible because you are not reselling one API.

You are orchestrating trust.
