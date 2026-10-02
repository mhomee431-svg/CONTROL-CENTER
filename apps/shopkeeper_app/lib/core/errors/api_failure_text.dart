import 'package:flutter/widgets.dart';

import '../network/api_client.dart';
import 'app_message_code.dart';

/// Shopkeeper-facing wording for [e], in the active locale.
///
/// Failures thrown through [ApiException.localized] resolve their copy from the
/// ARB catalog. Everything else keeps its own text: a sentence the backend
/// composed is already the user-facing message, and replacing it with a generic
/// phrase would hide the reason the shopkeeper needs to read.
String apiFailureText(BuildContext context, ApiException e) {
  final code = e.messageCode;
  if (code == null) return e.message;
  return appMessageText(context, code);
}
