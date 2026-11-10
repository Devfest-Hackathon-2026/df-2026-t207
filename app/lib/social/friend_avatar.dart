import 'package:flutter/material.dart';

import '../app/app_palette.dart';
import '../mypage/profile_photo.dart';

class FriendAvatar extends StatelessWidget {
  const FriendAvatar({
    super.key,
    required this.name,
    this.image,
    this.crop,
    this.radius = 20,
  });

  final String name;
  final ImageProvider? image;
  final String? crop;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: image == null
        ? CircleAvatar(
            radius: radius,
            backgroundColor: context.palette.control,
            foregroundColor: context.palette.ink,
            child: Text(name.isEmpty ? '？' : name.characters.first),
          )
        : ClipOval(
            child: SizedBox.square(
              dimension: radius * 2,
              child: CroppedProfileImage.remote(image!, crop),
            ),
          ),
  );
}
