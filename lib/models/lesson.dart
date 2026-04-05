import 'book_page.dart';

class PhonicsWord {
  final String word;
  final List<String> phonemes;
  final String imageAsset;

  const PhonicsWord({
    required this.word,
    required this.phonemes,
    required this.imageAsset,
  });

  factory PhonicsWord.fromJson(Map<String, dynamic> json) => PhonicsWord(
        word: json['word'] as String,
        phonemes: List<String>.from(json['phonemes'] as List),
        imageAsset: json['imageAsset'] as String,
      );
}

class RecordingSentence {
  final String text;
  final String audio;
  final String side; // "left" or "right"

  const RecordingSentence({required this.text, required this.audio, required this.side});

  factory RecordingSentence.fromJson(Map<String, dynamic> json) => RecordingSentence(
        text: json['text'] as String,
        audio: json['audio'] as String,
        side: json['side'] as String,
      );
}

class RecordingPage {
  final String imageAsset;
  final List<RecordingSentence> sentences;

  const RecordingPage({required this.imageAsset, required this.sentences});

  factory RecordingPage.fromJson(Map<String, dynamic> json) {
    // Support both old format (leftSentence/rightSentence) and new (sentences array)
    if (json.containsKey('sentences')) {
      return RecordingPage(
        imageAsset: json['imageAsset'] as String,
        sentences: (json['sentences'] as List)
            .map((s) => RecordingSentence.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
    }
    // Legacy: convert old format
    return RecordingPage(
      imageAsset: json['imageAsset'] as String,
      sentences: [
        RecordingSentence(text: json['leftSentence'] as String, audio: json['leftAudio'] as String, side: 'left'),
        RecordingSentence(text: json['rightSentence'] as String, audio: json['rightAudio'] as String, side: 'right'),
      ],
    );
  }
}

class Lesson {
  final String id;
  final String bookTitle;
  final String characterName;
  final String characterAsset;
  final List<BookPage> pages;
  final List<PhonicsWord> phonicsWords;
  final String featuredSentence;
  final String originalAudio;
  final RecordingPage? recordingPage;

  const Lesson({
    required this.id,
    required this.bookTitle,
    required this.characterName,
    required this.characterAsset,
    required this.pages,
    required this.phonicsWords,
    required this.featuredSentence,
    this.originalAudio = '',
    this.recordingPage,
  });

  factory Lesson.fromJson(Map<String, dynamic> json) => Lesson(
        id: json['id'] as String,
        bookTitle: json['bookTitle'] as String,
        characterName: json['characterName'] as String,
        characterAsset: json['characterAsset'] as String,
        pages: (json['pages'] as List)
            .map((p) => BookPage.fromJson(p as Map<String, dynamic>))
            .toList(),
        phonicsWords: (json['phonicsWords'] as List)
            .map((w) => PhonicsWord.fromJson(w as Map<String, dynamic>))
            .toList(),
        featuredSentence: json['featuredSentence'] as String,
        originalAudio: (json['originalAudio'] as String?) ?? '',
        recordingPage: json['recordingPage'] != null
            ? RecordingPage.fromJson(json['recordingPage'] as Map<String, dynamic>)
            : null,
      );
}
