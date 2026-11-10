import 'dart:io';

import 'package:flutter/painting.dart';

final previewOutfit = _image('olive');
final previewJacket = _image('jacket');
final previewSweatshirt = _image('sweatshirt');

MemoryImage _image(String name) => MemoryImage(
  File('test/fixtures/friend_preview/$name.png').readAsBytesSync(),
);
