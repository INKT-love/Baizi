import '../../../core/config/baizi_gateway.dart';
import '../../../core/providers/assistant_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/api/chat_api_service.dart';

enum GenerationErrorRecovery {
  none,
  invalidApiKey,
  forbiddenApiKey,
  chooseModel,
}

GenerationErrorRecovery classifyGenerationError(Object error) {
  if (error is ChatApiHttpException) {
    if (error.statusCode == 401) {
      return GenerationErrorRecovery.invalidApiKey;
    }
    if (error.statusCode == 403) {
      return GenerationErrorRecovery.forbiddenApiKey;
    }
    if (_isStaleModelHttpError(error)) {
      return GenerationErrorRecovery.chooseModel;
    }
    return GenerationErrorRecovery.none;
  }
  if (error is BaiziGatewayException) {
    return switch (error.type) {
      BaiziGatewayFailureType.missingApiKey =>
        GenerationErrorRecovery.invalidApiKey,
      BaiziGatewayFailureType.modelUnavailable =>
        GenerationErrorRecovery.chooseModel,
    };
  }
  if (error == 'no_model') return GenerationErrorRecovery.chooseModel;
  return GenerationErrorRecovery.none;
}

bool _isStaleModelHttpError(ChatApiHttpException error) {
  if (error.statusCode == 404) return true;

  final body = error.responseBody.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  if (body.contains('model_not_found') ||
      body.contains('model-not-found') ||
      body.contains('model_not_available')) {
    return true;
  }
  return RegExp(
    r'\bmodel\b.{0,160}\b(not found|does not exist|not available|unavailable)\b|'
    r'\b(no such|unknown) model\b',
  ).hasMatch(body);
}

String? recoveryModelSelectionInitialId(
  SettingsProvider settings,
  AssistantProvider assistants,
) {
  return assistants.currentAssistant?.chatModelId ?? settings.currentModelId;
}

Future<void> applyRecoveryModelSelection({
  required SettingsProvider settings,
  required AssistantProvider assistants,
  required String modelId,
}) async {
  final assistant = assistants.currentAssistant;
  if (assistant?.chatModelId != null) {
    await assistants.updateAssistant(
      assistant!.copyWith(
        chatModelProvider: BaiziGateway.providerId,
        chatModelId: modelId,
      ),
    );
    return;
  }
  await settings.setCurrentModel(BaiziGateway.providerId, modelId);
}
