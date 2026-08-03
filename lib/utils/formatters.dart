/// 通用字节 / 时长 / 速率格式化。
abstract final class Formatters {
  static String bytes(num value) {
    final n = value.toDouble();
    if (n < 1024) return '${n.toStringAsFixed(0)} B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    if (n < 1024 * 1024 * 1024) {
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(n / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String duration(Duration d) {
    if (d.inDays > 0) {
      return '${d.inDays} 天 ${d.inHours.remainder(24)} 时';
    }
    if (d.inHours > 0) {
      return '${d.inHours} 时 ${d.inMinutes.remainder(60)} 分';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes} 分';
    }
    return '${d.inSeconds} 秒';
  }

  static String bitRate(double bytesPerSec) {
    final bits = bytesPerSec * 8;
    if (bits < 1000) return '${bits.toStringAsFixed(0)} bps';
    if (bits < 1e6) return '${(bits / 1e3).toStringAsFixed(1)} Kbps';
    if (bits < 1e9) return '${(bits / 1e6).toStringAsFixed(1)} Mbps';
    return '${(bits / 1e9).toStringAsFixed(1)} Gbps';
  }
}
