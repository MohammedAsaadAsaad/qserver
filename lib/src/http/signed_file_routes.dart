import '../container/quds_env.dart';
import '../storage/local_storage_disk.dart';
import '../storage/signed_url.dart';
import '../storage/storage.dart';
import 'enums.dart';
import 'quds_response.dart';
import 'static_files.dart';
import '../routing/router.dart';

/// Opt-in `GET /quds/files` for HMAC temporary URLs. Off unless
/// `QUDS_SIGNED_FILES=true`.
class SignedFileRoutes {
  static void register(QudsRouter router) {
    final enabled = env<bool>('QUDS_SIGNED_FILES', false) ?? false;
    if (!enabled) return;
    if (router.hasRoute(HttpMethod.get, '/quds/files')) return;

    router.get('/quds/files', (request) async {
      final path = request.query('path') ?? '';
      final expires = request.query('expires') ?? '';
      final sig = request.query('sig') ?? '';
      if (!SignedUrl.valid(path: path, expires: expires, sig: sig)) {
        return QudsResponse.error('Forbidden', status: 403);
      }
      if (!await Storage.exists(path)) {
        return QudsResponse.error('Not found', status: 404);
      }
      final disk = Storage.disk;
      if (disk is LocalStorageDisk) {
        return StaticFiles.serve(Storage.rootPath, path);
      }
      final public = Storage.url(path);
      if (public != null) {
        return QudsResponse(
          statusCode: 302,
          headers: {'Location': public},
        );
      }
      return QudsResponse.error('Not found', status: 404);
    });
  }
}
