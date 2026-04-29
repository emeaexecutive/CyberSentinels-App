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
