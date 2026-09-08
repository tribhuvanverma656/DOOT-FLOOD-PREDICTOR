class AlertPayload {
  final String? id;
  final double lat;
  final double lng;
  final String message;
  final double? riskScore;
  final int? timestamp;

  AlertPayload({
    this.id,
    required this.lat,
    required this.lng,
    required this.message,
    this.riskScore,
    this.timestamp,
  });

  factory AlertPayload.emergency({
    required double lat,
    required double lng,
    required String message,
    required double riskScore,
  }) {
    return AlertPayload(
      id: "ALERT_${DateTime.now().millisecondsSinceEpoch}",
      lat: lat,
      lng: lng,
      message: message,
      riskScore: riskScore,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory AlertPayload.fromJson(Map<String, dynamic> json) {
    return AlertPayload(
      id: json['id'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num? ?? json['lon'] as num).toDouble(),
      message: json['message'] as String? ?? json['type'] as String? ?? '',
      riskScore: (json['riskScore'] as num?)?.toDouble() ?? 0.95,
      timestamp: json['timestamp'] is int
          ? json['timestamp']
          : DateTime.tryParse(json['timestamp'] ?? '')?.millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lat': lat,
      'lng': lng,
      'message': message,
      'riskScore': riskScore,
      'timestamp': timestamp,
    };
  }
}
