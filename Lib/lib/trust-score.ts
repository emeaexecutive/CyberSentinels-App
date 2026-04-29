export type TrustSignal = {
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
