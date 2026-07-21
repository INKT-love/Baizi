enum ChatBackgroundMode { selectedModel, latestAssistantReply }

class ModelChatAppearance {
  const ModelChatAppearance({
    required this.modelId,
    this.nickname,
    this.avatarPath,
    this.backgroundPath,
  });

  final String modelId;
  final String? nickname;
  final String? avatarPath;
  final String? backgroundPath;

  bool get isEmpty =>
      (nickname?.trim().isEmpty ?? true) &&
      (avatarPath?.trim().isEmpty ?? true) &&
      (backgroundPath?.trim().isEmpty ?? true);

  ModelChatAppearance copyWith({
    String? nickname,
    String? avatarPath,
    String? backgroundPath,
    bool clearNickname = false,
    bool clearAvatar = false,
    bool clearBackground = false,
  }) {
    return ModelChatAppearance(
      modelId: modelId,
      nickname: clearNickname ? null : (nickname ?? this.nickname),
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      backgroundPath: clearBackground
          ? null
          : (backgroundPath ?? this.backgroundPath),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'modelId': modelId,
    'nickname': nickname,
    'avatarPath': avatarPath,
    'backgroundPath': backgroundPath,
  };

  factory ModelChatAppearance.fromJson(Map<String, dynamic> json) {
    return ModelChatAppearance(
      modelId: (json['modelId'] as String? ?? '').trim(),
      nickname: (json['nickname'] as String?)?.trim(),
      avatarPath: (json['avatarPath'] as String?)?.trim(),
      backgroundPath: (json['backgroundPath'] as String?)?.trim(),
    );
  }
}
