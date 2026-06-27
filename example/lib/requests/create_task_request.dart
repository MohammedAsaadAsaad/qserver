import 'package:qserver/qserver.dart';

class CreateTaskRequest extends QudsFormRequest {
  CreateTaskRequest(super.request);

  @override
  Future<bool> authorize() async {
    // In a real app, you might check if the user has permission to create tasks
    return true;
  }

  @override
  Map<String, QudsValidator> rules() {
    return {
      'title': IsRequired().isString().min(3).max(50),
      'description': IsString().max(255),
    };
  }
}
