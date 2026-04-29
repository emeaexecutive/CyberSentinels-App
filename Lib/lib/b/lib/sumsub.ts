export async function retrievePersonaInquiry(inquiryId: string) {
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
