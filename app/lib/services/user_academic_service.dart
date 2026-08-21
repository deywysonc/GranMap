import '../models/academic.dart';
import 'app_session.dart';
import 'granmap_api.dart';
import 'local_store.dart';

class UserAcademicService {
  final GranMapApi api;
  final LocalStore store;

  UserAcademicService({GranMapApi? api, LocalStore? store})
    : api = api ?? GranMapApi(),
      store = store ?? LocalStore();

  Future<AcademicSnapshot> load() async {
    final session = AppSession.instance;
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
      final classes = await api.fetchMySchedule(token);
      await store.saveCachedSchedule(scope, classes);

      return AcademicSnapshot(
        classes: classes,
        source: AcademicDataSource.online,
        cachedAt: DateTime.now(),
        message: classes.isEmpty
            ? 'Nenhuma aula cadastrada para seu curso, semestre e turma.'
            : null,
      );
    } catch (_) {
      final cache = await store.readCachedSchedule(scope);
      if (cache != null) return cache;

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
