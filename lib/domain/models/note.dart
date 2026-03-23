import 'package:freezed_annotation/freezed_annotation.dart';

part 'note.freezed.dart';
part 'note.g.dart';

@freezed
abstract class Note with _$Note {
  const factory Note({
    required String id,
    required String title,
    required String body,
    String? colorHex,
    String? memberId,
    required DateTime date,
    required DateTime createdAt,
    required DateTime modifiedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}
