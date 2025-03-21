// github: https://github.com/sintrb/dart-airkiss

library airkiss_dart;

import 'dart:io'
    show
        RawDatagramSocket,
        InternetAddress,
        Datagram,
        NetworkInterface,
        InternetAddressType;
import 'dart:async';
import 'dart:convert';

class AirkissOption {
  int send_port;
  int receive_port;
  int trycount;
  int timegap;
  int random;
  bool reuse_address;
  bool reuse_port;
  String ipAddress;

  AirkissOption({
    this.send_port = 10001,
    this.receive_port = 10000,
    this.trycount = 50,
    this.timegap = 1000,
    this.random = 0x55,
    this.reuse_address = true,
    this.reuse_port = false,
    required this.ipAddress, // Now required
  });
}

class AirkissUtils {
  static int crc8(List<int> data) {
    int len = data.length;
    int i = 0;
    int crc = 0x00;
    while (len-- > 0) {
      int extract = data[i++];
      for (int j = 8; j != 0; j--) {
        int sum = ((crc & 0xFF) ^ (extract & 0xFF));
        sum = ((sum & 0xFF) & 0x01);
        crc = ((crc & 0xFF) >> 1);
        if (sum != 0) {
          crc = ((crc & 0xFF) ^ 0x8C);
        }
        extract = ((extract & 0xFF) >> 1);
      }
    }
    return (crc & 0x00FF);
  }

  static List<int> leadingPart() {
    List<int> data = [];
    for (int i = 0; i < 50; ++i) {
      data.addAll([1, 2, 3, 4]);
    }
    return data;
  }

  static List<int> magicCode(List<int> ssid, List<int> password) {
    List<int> data = [];
    int length = ssid.length + password.length + 1;
    List<int> magicCode = [0, 0, 0, 0];
    magicCode[0] = 0x00 | (length >> 4 & 0xF);
    if (magicCode[0] == 0) {
      magicCode[0] = 0x08;
    }
    magicCode[1] = 0x10 | (length & 0xF);
    int crc8 = AirkissUtils.crc8(ssid);
    magicCode[2] = 0x20 | (crc8 >> 4 & 0xF);
    magicCode[3] = 0x30 | (crc8 & 0xF);
    for (int i = 0; i < 20; ++i) {
      for (int j = 0; j < 4; ++j) data.add(magicCode[j]);
    }
    return data;
  }

  static List<int> prefixCode(List<int> password) {
    List<int> data = [];
    int length = password.length;
    List<int> prefixCode = [0, 0, 0, 0];
    prefixCode[0] = 0x40 | (length >> 4 & 0xF);
    prefixCode[1] = 0x50 | (length & 0xF);
    int crc8 = AirkissUtils.crc8([length]);
    prefixCode[2] = 0x60 | (crc8 >> 4 & 0xF);
    prefixCode[3] = 0x70 | (crc8 & 0xF);
    for (int j = 0; j < 4; ++j) {
      data.add(prefixCode[j]);
    }
    return data;
  }

  static List<int> sequence(int index, List<int> bytes) {
    List<int> data = [];
    List<int> content = [];
    content.add(index & 0xFF);
    content.addAll(bytes);
    int crc8 = AirkissUtils.crc8(content);
    data.add(0x80 | crc8);
    data.add(0x80 | index);
    for (int b in bytes) {
      data.add(b | 0x100);
    }
    return data;
  }
}

class AirkissEncoder {
  List<List<int>> encode(String ssid, String pwd, {int random = 0x56}) {
    var strEncoder = Utf8Encoder();
    List<int> ssidbts = strEncoder.convert(ssid);
    List<int> pwdbts = strEncoder.convert(pwd);
    return this.encodeWithBytes(ssidbts, pwdbts, random: random);
  }

  List<List<int>> encodeWithBytes(List<int> ssidbts, List<int> pwdbts,
      {int random = 0x56}) {
    List<int> bytes = [];
    bytes.addAll(AirkissUtils.leadingPart());
    bytes.addAll(AirkissUtils.magicCode(ssidbts, pwdbts));
    List<int> data = []
      ..addAll(pwdbts)
      ..add(random)
      ..addAll(ssidbts);
    var min = (a, b) => a > b ? b : a;
    for (int i = 0; i < 1; ++i) {
      bytes.addAll(AirkissUtils.prefixCode(pwdbts));
      for (int j = 0; j < data.length; j += 4) {
        int end = min(j + 4, data.length);
        List<int> content = data.getRange(j, end).toList();
        bytes.addAll(AirkissUtils.sequence(j ~/ 4, content));
      }
    }
    List<List<int>> bytesArray = [];
    bytesArray.add(bytes);
    bytes.forEach((d) {
      List<int> bts = List.generate(d, (i) => 0);
      bytesArray.add(bts);
    });
    return bytesArray;
  }
}

class AirkissResult {
  InternetAddress? deviceAddress; // 设备地址

  String toString() {
    return 'deviceAddress:$deviceAddress';
  }
}

class AirkissSender {
  var cbk;
  RawDatagramSocket? _soc;
  AirkissOption option;
  bool _isCancelled = false; // Cancellation flag

  AirkissSender(this.option);

  void onFinished(cbk) {
    this.cbk = cbk;
  }

  Future<String?> _getBroadcastAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            List<String> parts = addr.address.split('.');
            parts[3] = '255'; // Replace the last octet with 255
            return parts.join('.');
          }
        }
      }
    } catch (e) {
      print("Error getting broadcast address: $e");
    }
    return null;
  }

  void send(List<List<int>> bytesArray) async {
    assert(cbk != null);

    // String? broadcastIp = await _getBroadcastAddress();

    String? broadcastIp = option.ipAddress;

    if (broadcastIp == null) {
      print("Failed to determine broadcast address.");
      return;
    }

    print("broadcastIp: $broadcastIp");

    InternetAddress bcAddr = InternetAddress(broadcastIp);

    RawDatagramSocket.bind(InternetAddress.anyIPv4, option.receive_port,
            reuseAddress: option.reuse_address, reusePort: option.reuse_port)
        .then((soc) {
      _soc = soc;
      _isCancelled = false; // Reset cancellation flag

      soc.listen((e) {
        if (_isCancelled) return;

        Datagram? dg = soc.receive();
        if (dg != null) {
          List<int> rbytes = dg.data.toList();
          if (rbytes.isNotEmpty && rbytes[0] == option.random) {
            // Device is online, configuration complete
            AirkissResult ret = AirkissResult();
            ret.deviceAddress = dg.address;
            cbk(ret);
            stop();
          }
        }
      });

      soc.broadcastEnabled = true;
      int count = option.trycount;
      bool success = false;
      int ix = 0;

      void _send() {
        if (_isCancelled || count <= 0) return; // Stop if cancelled

        var data = bytesArray[ix % bytesArray.length];
        int sended = soc.send(data, bcAddr, option.send_port);
        if (sended != data.length) {
          print("Send fail!");
        }
        ++ix;
        if (ix % bytesArray.length == 0) {
          --count;
        }
        if (count > 0) {
          Future.delayed(Duration(microseconds: option.timegap))
              .then((_) => _send());
        } else if (!success) {
          cbk(null);
          stop();
        }
      }

      _send();
    });
  }

  /// Cancels the sending process
  void cancel() {
    _isCancelled = true;
    stop();
  }

  void stop() {
    _soc?.close();
    _soc = null;
  }
}

class AirkissConfig {
  AirkissOption option;
  AirkissSender? _sender; // Store sender instance

  AirkissConfig({required this.option}) {
    this.option = option;
  }

  Future<AirkissResult?> config(String ssid, String pwd) async {
    var strEncoder = Utf8Encoder();
    List<int> ssidbts = strEncoder.convert(ssid);
    List<int> pwdbts = strEncoder.convert(pwd);
    return configWithBytes(ssidbts, pwdbts);
  }

  Future<AirkissResult?> configWithBytes(
      List<int> ssidbts, List<int> pwdbts) async {
    Completer<AirkissResult?> completer = Completer();
    var bytes = AirkissEncoder()
        .encodeWithBytes(ssidbts, pwdbts, random: option.random);

    _sender = AirkissSender(this.option); // Store sender instance

    bool isCompleted = false;

    _sender!.onFinished((res) {
      if (!isCompleted) {
        isCompleted = true;
        _sender!.stop();
        completer.complete(res);
      }
    });

    _sender!.send(bytes);

    return completer.future;
  }

  /// Cancels the Airkiss process
  void cancel() {
    _sender?.cancel();
  }
}
