class MattermostConfig {
  final String baseUrl;
  final String team;
  final String channel;
  final String botName;
  final String botToken;
  final String opencodeBotName;
  final String opencodeToken;

  const MattermostConfig({
    required this.baseUrl,
    required this.team,
    required this.channel,
    required this.botName,
    required this.botToken,
    required this.opencodeBotName,
    required this.opencodeToken,
  });

  String get channelUrl => '$baseUrl/$team/channels/$channel';
}
