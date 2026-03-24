class CharacterPosition {
  final double x;
  final double y;
  final String action; // run, sit, jump, yawn, excited

  const CharacterPosition({
    required this.x,
    required this.y,
    required this.action,
  });

  factory CharacterPosition.fromJson(Map<String, dynamic> json) =>
      CharacterPosition(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        action: json['action'] as String,
      );
}

class InteractiveHotspot {
  final double x, y, width, height;
  final String soundEffect;
  final String animationType;
  final String hintText;

  const InteractiveHotspot({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.soundEffect,
    required this.animationType,
    required this.hintText,
  });

  factory InteractiveHotspot.fromJson(Map<String, dynamic> json) =>
      InteractiveHotspot(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        soundEffect: json['soundEffect'] as String,
        animationType: json['animationType'] as String,
        hintText: json['hintText'] as String,
      );
}

class KeywordHighlight {
  final String word;
  final double x, y, width, height;
  final String color;
  /// Milliseconds into the EN audio track at which to trigger this highlight.
  final int positionMs;

  const KeywordHighlight({
    required this.word,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.color = '#FFD93D',
    this.positionMs = 0,
  });

  factory KeywordHighlight.fromJson(Map<String, dynamic> json) =>
      KeywordHighlight(
        word: json['word'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        color: json['color'] as String? ?? '#FFD93D',
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      );
}

class BookPage {
  final String imageAsset;
  final String narrativeCN;
  final String narrativeEN;
  final List<String> keywords;
  final List<String> keywordsCN;
  final List<InteractiveHotspot> hotspots;
  final List<KeywordHighlight> highlights;
  final CharacterPosition characterPos;
  final String? audioCN;
  final String? audioEN;
  final String? videoAsset;
  final String teacherExpression;

  const BookPage({
    required this.imageAsset,
    required this.narrativeCN,
    required this.narrativeEN,
    required this.keywords,
    this.keywordsCN = const [],
    required this.hotspots,
    this.highlights = const [],
    required this.characterPos,
    this.audioCN,
    this.audioEN,
    this.videoAsset,
    this.teacherExpression = 'normal',
  });

  factory BookPage.fromJson(Map<String, dynamic> json) => BookPage(
        imageAsset: json['imageAsset'] as String,
        narrativeCN: json['narrativeCN'] as String,
        narrativeEN: json['narrativeEN'] as String,
        keywords: List<String>.from(json['keywords'] as List),
        keywordsCN: json['keywordsCN'] != null
            ? List<String>.from(json['keywordsCN'] as List)
            : [],
        hotspots: (json['hotspots'] as List? ?? [])
            .map((h) => InteractiveHotspot.fromJson(h as Map<String, dynamic>))
            .toList(),
        highlights: (json['highlights'] as List? ?? [])
            .map((h) => KeywordHighlight.fromJson(h as Map<String, dynamic>))
            .toList(),
        characterPos: CharacterPosition.fromJson(
            json['characterPos'] as Map<String, dynamic>),
        audioCN: json['audioCN'] as String?,
        audioEN: json['audioEN'] as String?,
        videoAsset: json['videoAsset'] as String?,
        teacherExpression: json['teacherExpression'] as String? ?? 'normal',
      );
}
