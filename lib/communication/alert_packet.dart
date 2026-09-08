class AlertPacket {
  final String alertId;
  final String eventType;
  final int severity;
  final double riskScore;
  final int issuedAt;
  final int expiresAt;
  final double latitude;
  final double longitude;
  final String instructionEn;
  final String instructionHi;
  final int priority;
  final int ttl;
  final int hopCount;
  final String payloadHash;
  final String signature;
  final String originatorId;
  final String senderPhone;
  final String message;

  AlertPacket({
    required this.alertId,
    this.eventType = "FLASH_FLOOD",
    this.severity = 10,
    this.riskScore = 95.0,
    required this.issuedAt,
    required this.expiresAt,
    required this.latitude,
    required this.longitude,
    this.instructionEn = "Evacuate immediately to higher ground!",
    this.instructionHi = "Turant unchi jagah par jayein!",
    this.priority = 10,
    this.ttl = 5,
    this.hopCount = 0,
    this.payloadHash = "",
    this.signature = "SIG_OFFLINE",
    this.originatorId = "LOCAL_NODE",
    this.senderPhone = "unknown_user",
    this.message = "Emergency SOS Alert Broadcasted via Mesh",
  });

  Map<String, dynamic> toJson() => {
    'alertId': alertId,
    'eventType': eventType,
    'severity': severity,
    'riskScore': riskScore,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'latitude': latitude,
    'longitude': longitude,
    'instructionEn': instructionEn,
    'instructionHi': instructionHi,
    'priority': priority,
    'ttl': ttl,
    'hopCount': hopCount,
    'payloadHash': payloadHash,
    'signature': signature,
    'originatorId': originatorId,
    'phone': senderPhone,
    'message': message,
    'status': 'PENDING',
  };

  factory AlertPacket.fromJson(Map<String, dynamic> json) => AlertPacket(
    alertId: json['alertId'] ?? json['id'] ?? 'ALERT_${DateTime.now().millisecondsSinceEpoch}',
    eventType: json['eventType'] ?? 'EMERGENCY_SOS',
    severity: (json['severity'] as num?)?.toInt() ?? 10,
    riskScore: (json['riskScore'] as num?)?.toDouble() ?? 95.0,
    issuedAt: (json['issuedAt'] as num?)?.toInt() ?? (json['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    expiresAt: (json['expiresAt'] as num?)?.toInt() ?? (DateTime.now().millisecondsSinceEpoch + 3600000),
    latitude: (json['latitude'] as num?)?.toDouble() ?? (json['lat'] as num?)?.toDouble() ?? 0.0,
    longitude: (json['longitude'] as num?)?.toDouble() ?? (json['lng'] as num?)?.toDouble() ?? 0.0,
    instructionEn: json['instructionEn'] ?? 'Evacuate immediately to higher ground!',
    instructionHi: json['instructionHi'] ?? 'Turant unchi jagah par jayein!',
    priority: (json['priority'] as num?)?.toInt() ?? 10,
    ttl: (json['ttl'] as num?)?.toInt() ?? 5,
    hopCount: (json['hopCount'] as num?)?.toInt() ?? 0,
    payloadHash: json['payloadHash'] ?? '',
    signature: json['signature'] ?? 'SIG_OFFLINE',
    originatorId: json['originatorId'] ?? 'LOCAL_NODE',
    senderPhone: json['phone'] ?? 'unknown_user',
    message: json['message'] ?? 'Emergency SOS Alert Broadcasted via Mesh',
  );
}
