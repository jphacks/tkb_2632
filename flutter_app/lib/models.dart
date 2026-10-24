typedef Json = Map<String, dynamic>;

class Person {
  final String id;
  final String name;
  const Person(this.id, this.name);
  factory Person.fromJson(Json json) =>
      Person(json['id'] as String, json['name'] as String);
}

class PhotoRound {
  final String id;
  final String photographerId;
  final String subjectId;
  final String status;
  final DateTime createdAt;
  final List<String> photos;
  final Json? favorite;
  final Json? answer;
  PhotoRound.fromJson(Json json)
    : id = json['id'] as String,
      photographerId = json['photographerId'] as String,
      subjectId = json['subjectId'] as String,
      status = json['status'] as String,
      createdAt = DateTime.parse(json['createdAt'] as String).toLocal(),
      photos = (json['photos'] as List).map((p) => p['id'] as String).toList(),
      favorite = json['favorite'] as Json?,
      answer = json['answer'] as Json?;
  String? get favoriteId => favorite?['photoId'] as String?;
  List<String> get reasons => List<String>.from(favorite?['reasons'] ?? []);
  String get timeLabel =>
      '${createdAt.month}/${createdAt.day} ${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')}';
}

const reasonTags = ['構図が好き', '表情がいい', '背景が好き', '雰囲気が好き', '自分らしい'];
