typedef FriendRequests = ({
  List<FriendRequest> incoming,
  List<FriendRequest> outgoing,
});

typedef Notifications = ({List<ApiNotice> items, int unread});

class FriendRecord {
  FriendRecord.fromJson(Map<String, dynamic> json)
    : id = json['friendId'] as String,
      name = json['displayName'] as String,
      profileImage = json['profileImage'] as String?,
      profileCrop = json['profileCrop'] as String?,
      today = json['today'] == null
          ? null
          : FriendPost.fromJson(json['today'] as Map<String, dynamic>);

  final String id;
  final String name;
  final String? profileImage;
  final String? profileCrop;
  final FriendPost? today;
}

class FriendPost {
  FriendPost.fromJson(Map<String, dynamic> json)
    : date = json['date'] as String,
      image = json['image'] as String,
      liked = json['liked'] as bool,
      items = [
        for (final item in json['items'] as List)
          FriendPostItem.fromJson(item as Map<String, dynamic>),
      ],
      notes = List<String>.from(json['itemNotes'] as List? ?? const []);

  final String date;
  final String image;
  final bool liked;
  final List<FriendPostItem> items;
  final List<String> notes;
}

class FriendPostItem {
  FriendPostItem.fromJson(Map<String, dynamic> json)
    : slot = json['slot'] as String,
      label = json['label'] as String,
      color = json['color'] as String? ?? '',
      image = json['image'] as String,
      memo = json['memo'] as String? ?? '';

  final String slot;
  final String label;
  final String color;
  final String image;
  final String memo;
}

class FriendRequest {
  FriendRequest.fromJson(Map<String, dynamic> json)
    : id = json['requestId'] as String,
      name = json['displayName'] as String,
      accepted = json['status'] == 'accepted';

  final String id;
  final String name;
  final bool accepted;
}

class SavedItem {
  SavedItem.fromJson(Map<String, dynamic> json)
    : id = json['saveId'] as String,
      slot = json['slot'] as String,
      label = json['label'] as String,
      color = json['color'] as String? ?? '',
      pattern = json['pattern'] as String?,
      materialGuess = json['materialGuess'] as String?;

  final String id;
  final String slot;
  final String label;
  final String color;
  final String? pattern;
  final String? materialGuess;
}

class ApiNotice {
  ApiNotice.fromJson(Map<String, dynamic> json)
    : id = json['id'] as String,
      type = json['type'] as String,
      text = json['text'] as String,
      read = json['read'] as bool,
      requestId = json['requestId'] as String?,
      jobId = json['jobId'] as String?;

  final String id;
  final String type;
  final String text;
  final bool read;
  final String? requestId;
  final String? jobId;
}
