import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/task.dart';

class RemoteException implements Exception {
  RemoteException(this.message, {this.permanent = false});

  final String message;

  /// True for 4xx answers: retrying the same request will not help.
  final bool permanent;

  @override
  String toString() => message;
}

class PushResult {
  const PushResult({required this.conflict, required this.task});

  /// True when the server holds a newer version (HTTP 409); [task] is then
  /// the server's copy. Otherwise [task] is what the server stored.
  final bool conflict;
  final Task task;
}

class PullResult {
  const PullResult(this.seq, this.tasks);
  final int seq;
  final List<Task> tasks;
}

class RemoteApi {
  RemoteApi(this.baseUrl);

  String baseUrl;
  static const _timeout = Duration(seconds: 8);

  Future<PushResult> push(Task t, {required String opId}) async {
    final res = await _send(() => http
        .put(
          Uri.parse('$baseUrl/tasks/${t.id}'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({...t.toJson(), 'baseVersion': t.version, 'opId': opId}),
        )
        .timeout(_timeout));

    if (res.statusCode == 200 || res.statusCode == 201 || res.statusCode == 409) {
      final task = Task.fromJson(
          (jsonDecode(res.body) as Map<String, dynamic>)['task'] as Map<String, dynamic>);
      return PushResult(conflict: res.statusCode == 409, task: task);
    }
    throw _statusError(res);
  }

  Future<PullResult> pull(int since) async {
    final res = await _send(
        () => http.get(Uri.parse('$baseUrl/tasks?since=$since')).timeout(_timeout));
    if (res.statusCode != 200) throw _statusError(res);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PullResult(
      (body['seq'] as num).toInt(),
      (body['tasks'] as List)
          .map((j) => Task.fromJson(j as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call();
    } on TimeoutException {
      throw RemoteException('Server did not answer in time');
    } on FormatException catch (e) {
      throw RemoteException('Bad server reply: ${e.message}');
    } catch (_) {
      throw RemoteException('Cannot reach server at $baseUrl');
    }
  }

  RemoteException _statusError(http.Response res) => RemoteException(
        'Server returned ${res.statusCode}',
        permanent: res.statusCode >= 400 && res.statusCode < 500,
      );
}
