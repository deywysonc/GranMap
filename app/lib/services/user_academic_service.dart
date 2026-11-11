import '../models/academic.dart';
import 'app_session.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class UserAcademicService {
  final GranMapApi api;
  final LocalStore store;
  final AppSession session;
  final Duration requestTimeout;
  final Duration storageTimeout;

  UserAcademicService({
    GranMapApi? api,
    LocalStore? store,
    AppSession? session,
    this.requestTimeout = const Duration(seconds: 6),
    this.storageTimeout = const Duration(seconds: 2),
  }) : api = api ?? GranMapApi(),
       store = store ?? LocalStore(),
       session = session ?? AppSession.instance;

  Future<AcademicSnapshot> load() async {
    final token = session.token;
    final user = session.user;

    if (token == null || user == null) {
      return const AcademicSnapshot(
        classes: [],
        source: AcademicDataSource.none,
        message: 'Entre no GranMap para carregar sua grade acadêmica.',
      );
    }

    final scope = session.storageScope;

    try {
      final classes = await api.fetchMySchedule(token).timeout(requestTimeout);
      DateTime? cachedAt;
      try {
        await store.saveCachedSchedule(scope, classes).timeout(storageTimeout);
        cachedAt = DateTime.now();
      } catch (_) {
        // A grade recebida continua utilizável se a cópia local falhar.
      }

      return AcademicSnapshot(
        classes: classes,
        source: AcademicDataSource.online,
        cachedAt: cachedAt,
        message: classes.isEmpty
            ? 'Nenhuma aula cadastrada para seu curso, semestre e turma.'
            : null,
      );
    } catch (_) {
      try {
        final cache = await store
            .readCachedSchedule(scope)
            .timeout(storageTimeout);
        if (cache != null) return cache;
      } catch (_) {
        return const AcademicSnapshot(
          classes: [],
          source: AcademicDataSource.none,
          message:
              'Sua grade e a cópia local estão indisponíveis. Tente novamente.',
        );
      }

      return const AcademicSnapshot(
        classes: [],
        source: AcademicDataSource.none,
        message:
            'Sem conexão e ainda não existe uma grade salva neste aparelho.',
      );
    }
  }

  void dispose() => api.dispose();
}
