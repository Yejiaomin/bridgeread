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

class Lesson {
  final String id;
  final String bookTitle;
  final String characterName;
  final String characterAsset;
  final List<BookPage> pages;
  final List<PhonicsWord> phonicsWords;
  final String featuredSentence;

  const Lesson({
    required this.id,
    required this.bookTitle,
    required this.characterName,
    required this.characterAsset,
    required this.pages,
    required this.phonicsWords,
    required this.featuredSentence,
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
      );
}
