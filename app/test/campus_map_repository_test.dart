import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granmap/data/campus_map_repository.dart';
import 'package:granmap/services/granmap_api.dart';
import 'package:granmap/services/local_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => SharedPreferencesAsyncPlatform.instance = null);
  late String bundled;
  late Map<String, dynamic> legacy;
  setUpAll(() async {
    bundled = await File('assets/maps/gran_tiete_floorplan_v12.json')
        .readAsString();
    legacy = {
      'version': 'upper-floorplan-v11',
      'checksum':
          'c950c72596f5b62989a248ed11d9b0734f1ef68fb7ae5b0c3462731e293f5c88',
      'schema_version': 1,
      'map_data': jsonDecode(
        await File('assets/maps/gran_tiete_upper_floorplan_v11.json')
            .readAsString(),
      ),
    };
  });

  CampusMapRepository repository(_Api api, _Store store) => CampusMapRepository(
    api: api,
    store: store,
    assets: _Assets(bundled),
    storageTimeout: const Duration(milliseconds: 20),
    requestTimeout: const Duration(milliseconds: 20),
  );

  test(
    'seed antigo intocado usa planta atualizada e conserva bloqueios',
    () async {
      final result = await repository(
        _Api(
          publication: () async => MapPublicationFetch(data: legacy),
          closures: [
            {'edge_id': 'upper_spine_5__upper_spine_6'},
            {'edge_id': 'ground_services_north__ground_services_mid'},
            {'edge_id': 'ground_c1_end__ground_spiral_ramp_landing'},
          ],
        ),
        _Store(),
      ).loadCampus();
      expect(result.campus.building.version, '0.12-floorplan-v12');
      expect(result.source, CampusMapSource.bundled);
      expect(
        result.blockedEdgeIds,
        containsAll([
          'upper_gallery_turn__upper_gallery_step',
          'ground_services_north_approach__ground_services_mid_approach',
          'ground_ramp_access_corner__ground_spiral_ramp_landing',
        ]),
      );
      expect(result.warning, isNull);
    },
  );

  test('publicação institucional alterada mantém prioridade', () async {
    final official = {...legacy, 'checksum': 'edited-by-admin'};
    final result = await repository(
      _Api(publication: () async => MapPublicationFetch(data: official)),
      _Store(),
    ).loadCampus();
    expect(result.campus.building.version, '0.11-upper-floorplan-v11');
    expect(result.source, CampusMapSource.online);
  });

  test('cache seed com resposta304 usa planta atualizada', () async {
    final result = await repository(
      _Api(
        publication: () async => const MapPublicationFetch(notModified: true),
      ),
      _Store(cached: legacy),
    ).loadCampus();
    expect(result.campus.building.version, '0.12-floorplan-v12');
    expect(result.warning, isNull);
  });

  test(
    'cache seed offline conserva os bloqueios salvos na planta nova',
    () async {
      final result = await repository(
        _Api(publication: () => Future.error(StateError('offline'))),
        _Store(
          cached: legacy,
          closures: [
            {'edge_id': 'ground_c1_start__ground_c1_first'},
          ],
        ),
      ).loadCampus();
      expect(result.campus.building.version, '0.12-floorplan-v12');
      expect(
        result.blockedEdgeIds,
        contains('ground_c1_start__ground_c1_first'),
      );
      expect(result.warning, contains('sem conexão'));
    },
  );

  test('storage ou rede travados não deixam abertura infinita', () async {
    final result = await repository(
      _Api(publication: () => Completer<MapPublicationFetch>().future),
      _Store(read: () => Completer<Map<String, dynamic>?>().future),
    ).loadCampus();
    expect(result.campus.building.version, '0.12-floorplan-v12');
    expect(result.source, CampusMapSource.bundled);
  });

  test('falha ao gravar cache não descarta mapa válido recebido', () async {
    final official = {
      ...legacy,
      'version': 'official-revision',
      'checksum': 'new',
    };
    final result = await repository(
      _Api(publication: () async => MapPublicationFetch(data: official)),
      _Store(save: () => Future.error(StateError('disk unavailable'))),
    ).loadCampus();
    expect(result.version, 'official-revision');
    expect(result.source, CampusMapSource.online);
    await Future<void>.delayed(const Duration(milliseconds: 25));
  });
}

class _Assets extends CachingAssetBundle {
  final String value;
  _Assets(this.value);
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
}

class _Api extends GranMapApi {
  final Future<MapPublicationFetch> Function() publication;
  final List<Map<String, dynamic>> closures;
  _Api({required this.publication, this.closures = const []});
  @override
  Future<MapPublicationFetch> fetchCurrentMapConditional({String? etag}) =>
      publication();
  @override
  Future<List<Map<String, dynamic>>> fetchRouteClosures() async => closures;
}

class _Store extends LocalStore {
  final Map<String, dynamic>? cached;
  final List<Map<String, dynamic>> closures;
  final Future<Map<String, dynamic>?> Function()? read;
  final Future<void> Function()? save;
  _Store({this.cached, this.closures = const [], this.read, this.save});
  @override
  Future<Map<String, dynamic>?> readPublishedMap() =>
      read?.call() ?? Future.value(cached);
  @override
  Future<List<Map<String, dynamic>>> readRouteClosures() async => closures;
  @override
  Future<void> savePublishedMap(Map<String, dynamic> publication) =>
      save?.call() ?? Future.value();
  @override
  Future<void> saveRouteClosures(List<Map<String, dynamic>> closures) async {}
}
