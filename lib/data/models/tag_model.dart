class TagModel {
  final int? id;
  final String name;

  const TagModel({this.id, required this.name});

  Map<String, dynamic> toMap() {
    return {if (id != null) 'id': id, 'name': name.trim()};
  }

  factory TagModel.fromMap(Map<String, dynamic> map) {
    return TagModel(id: map['id'] as int?, name: map['name'] as String);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TagModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
