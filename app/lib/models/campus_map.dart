class BuildingInfo {
  final String id;
  final String name;
  final String version;

  const BuildingInfo({
    required this.id,
    required this.name,
    required this.version,
  });

  factory BuildingInfo.fromJson(Map<String, dynamic> json) {
    return BuildingInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String,
    );
  }
}

class MapMetadata {
  final String roomCatalogStatus;
  final String geometryStatus;
  final String distanceStatus;
  final String coordinateSystem;
  final String distanceUnit;
  final String importantNote;
  final String mapMode;
  final String surveyStatus;

  const MapMetadata({
    this.roomCatalogStatus = 'unknown',
    this.geometryStatus = 'unknown',
    this.distanceStatus = 'unknown',
    this.coordinateSystem = 'unknown',
    this.distanceUnit = 'unknown',
    this.importantNote = '',
    this.mapMode = 'unknown',
    this.surveyStatus = 'unknown',
  });

  bool get hasValidatedMetricGeometry =>
      geometryStatus == 'validated' &&
      distanceStatus == 'validated' &&
      distanceUnit == 'meters';

  factory MapMetadata.fromJson(Map<String, dynamic> json) {
    return MapMetadata(
      roomCatalogStatus: (json['roomCatalogStatus'] ?? 'unknown') as String,
      geometryStatus: (json['geometryStatus'] ?? 'unknown') as String,
      distanceStatus: (json['distanceStatus'] ?? 'unknown') as String,
      coordinateSystem: (json['coordinateSystem'] ?? 'unknown') as String,
      distanceUnit: (json['distanceUnit'] ?? 'unknown') as String,
      importantNote: (json['importantNote'] ?? '') as String,
      mapMode: (json['mapMode'] ?? 'unknown') as String,
      surveyStatus: (json['surveyStatus'] ?? 'unknown') as String,
    );
  }
}

class CampusZone {
  final String id;
  final String name;
  final String type;
  final int floor;
  final double x;
  final double y;
  final double width;
  final double height;
  final String verification;
  final List<String> evidenceCaptureIds;

  const CampusZone({
    required this.id,
    required this.name,
    required this.type,
    required this.floor,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.verification = 'unverified',
    this.evidenceCaptureIds = const [],
  });

  factory CampusZone.fromJson(Map<String, dynamic> json) {
    return CampusZone(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      floor: json['floor'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      width: (json['width'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      verification: (json['verification'] ?? 'unverified') as String,
      evidenceCaptureIds:
          (json['evidenceCaptureIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
    );
  }
}

class CampusFloor {
  final String id;
  final String name;
  final int level;
  final double elevation;

  const CampusFloor({
    required this.id,
    required this.name,
    required this.level,
    required this.elevation,
  });

  factory CampusFloor.fromJson(Map<String, dynamic> json) {
    return CampusFloor(
      id: json['id'] as String,
      name: json['name'] as String,
      level: json['level'] as int,
      elevation: (json['elevation'] as num).toDouble(),
    );
  }
}

class CampusPoi {
  final String id;
  final String name;
  final String type;
  final String sector;
  final int floor;
  final double x;
  final double y;
  final double z;
  final String navigationNode;
  final double displayX;
  final double displayY;
  final String verification;
  final List<String> evidenceCaptureIds;

  const CampusPoi({
    required this.id,
    required this.name,
    required this.type,
    this.sector = '',
    required this.floor,
    required this.x,
    required this.y,
    required this.z,
    required this.navigationNode,
    double? displayX,
    double? displayY,
    this.verification = 'unverified',
    this.evidenceCaptureIds = const [],
  }) : displayX = displayX ?? x,
       displayY = displayY ?? y;

  factory CampusPoi.fromJson(Map<String, dynamic> json) {
    return CampusPoi(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      sector: (json['sector'] ?? '') as String,
      floor: json['floor'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      navigationNode: json['navigationNode'] as String,
      displayX: (json['displayX'] as num?)?.toDouble(),
      displayY: (json['displayY'] as num?)?.toDouble(),
      verification: (json['verification'] ?? 'unverified') as String,
      evidenceCaptureIds:
          (json['evidenceCaptureIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
    );
  }
}

class NavigationNode {
  final String id;
  final int floor;
  final double x;
  final double y;
  final double z;
  final String type;
  final double displayX;
  final double displayY;

  const NavigationNode({
    required this.id,
    required this.floor,
    required this.x,
    required this.y,
    required this.z,
    required this.type,
    double? displayX,
    double? displayY,
  }) : displayX = displayX ?? x,
       displayY = displayY ?? y;

  factory NavigationNode.fromJson(Map<String, dynamic> json) {
    return NavigationNode(
      id: json['id'] as String,
      floor: json['floor'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num).toDouble(),
      type: json['type'] as String,
      displayX: (json['displayX'] as num?)?.toDouble(),
      displayY: (json['displayY'] as num?)?.toDouble(),
    );
  }
}

class NavigationEdge {
  final String from;
  final String to;
  final double distance;
  final String type;
  final bool accessible;
  final String verification;
  final List<String> evidenceCaptureIds;

  const NavigationEdge({
    required this.from,
    required this.to,
    required this.distance,
    required this.type,
    required this.accessible,
    this.verification = 'unverified',
    this.evidenceCaptureIds = const [],
  });

  factory NavigationEdge.fromJson(Map<String, dynamic> json) {
    return NavigationEdge(
      from: json['from'] as String,
      to: json['to'] as String,
      distance: (json['distance'] as num).toDouble(),
      type: json['type'] as String,
      accessible: json['accessible'] as bool,
      verification: (json['verification'] ?? 'unverified') as String,
      evidenceCaptureIds:
          (json['evidenceCaptureIds'] as List<dynamic>? ?? const [])
              .map((item) => item.toString())
              .toList(growable: false),
    );
  }
}

class CampusMap {
  final BuildingInfo building;
  final MapMetadata metadata;
  final List<CampusFloor> floors;
  final List<CampusZone> zones;
  final List<CampusPoi> pois;
  final List<NavigationNode> nodes;
  final List<NavigationEdge> edges;

  const CampusMap({
    required this.building,
    this.metadata = const MapMetadata(),
    required this.floors,
    this.zones = const [],
    required this.pois,
    required this.nodes,
    required this.edges,
  });

  NavigationNode? nodeById(String id) {
    for (final node in nodes) {
      if (node.id == id) return node;
    }
    return null;
  }

  CampusPoi? poiById(String id) {
    for (final poi in pois) {
      if (poi.id == id) return poi;
    }
    return null;
  }

  factory CampusMap.fromJson(Map<String, dynamic> json) {
    return CampusMap(
      building: BuildingInfo.fromJson(json['building'] as Map<String, dynamic>),
      metadata: MapMetadata.fromJson(
        (json['metadata'] as Map<String, dynamic>?) ?? const {},
      ),
      floors: (json['floors'] as List<dynamic>)
          .map((item) => CampusFloor.fromJson(item as Map<String, dynamic>))
          .toList(),
      zones: (json['zones'] as List<dynamic>? ?? const [])
          .map((item) => CampusZone.fromJson(item as Map<String, dynamic>))
          .toList(),
      pois: (json['pois'] as List<dynamic>)
          .map((item) => CampusPoi.fromJson(item as Map<String, dynamic>))
          .toList(),
      nodes: (json['nodes'] as List<dynamic>)
          .map((item) => NavigationNode.fromJson(item as Map<String, dynamic>))
          .toList(),
      edges: (json['edges'] as List<dynamic>)
          .map((item) => NavigationEdge.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}
