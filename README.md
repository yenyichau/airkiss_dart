# airkiss_dart[nullsafety]

[![pub package](https://img.shields.io/pub/v/airkiss.svg)](https://pub.dev/packages/airkiss_dart)

A dart wechat airkiss lib to config IOT device from [sintrb](https://github.com/sintrb).
[View on GitHub origin](https://github.com/sintrb/dart-airkiss/)
## Usage
To use this plugin, add `airkiss_dart` as a dependency in your [pubspec.yaml](https://flutter.io/platform-plugins/) file.
```yaml
dependencies:
  airkiss_dart: ^1.0.1
```


### Example

``` dart
import 'package:airkiss_dart/airkiss_dart.dart';


import 'package:airkiss_dart/airkiss_dart.dart';

void test(String ssid, String pwd) async {
  print('config ssid:$ssid, pwd:$pwd');
  AirkissConfig ac = AirkissConfig();
  var res = await ac.config(ssid, pwd);
  if (res != null) {
    print('result: $res');
  }
  else {
    print(
        'config failed!!! please ensure phone/pc connected to Wi—Fi[$ssid] with 2.4GHz Channel(NOT 5GHz Channel)');
  }
}

void main() {
  test("SSID", "PASSWORD");
}
```

