/// Centralized user-friendly Chinese error formatter translating raw transport, TLS,
/// DNS, HTTP status, and malformed HTML/JSON responses into actionable explanations.
///
/// Single Source of Truth in `core/utils/` usable by `core/`, `state/`, `widgets/`, and `screens/`.
class VedroErrorFormatter {
  static String friendly(Object error) => format(error);

  static String format(Object error) {
    final raw = error
        .toString()
        .replaceFirst('VedroCoreException: ', '')
        .replaceFirst('Exception: ', '')
        .trim();
    if (raw.isEmpty) return '操作失败，请稍后重试';
    final lower = raw.toLowerCase();

    if (lower.contains('unauthorized') ||
        lower.contains('http 401') ||
        lower.contains('status 401') ||
        lower.contains('invalid username') ||
        lower.contains('invalid password')) {
      return '用户名或密码不正确，或登录凭证已失效';
    }
    if (lower.contains('http 403') || lower.contains('status 403') || lower.contains('forbidden')) {
      return '服务器拒绝访问（403），请检查账号权限或是否被限制';
    }
    if (lower.contains('http 404') || lower.contains('status 404') || lower.contains('not found')) {
      return '接口或资源不存在（404），请确认服务器地址与路径（如 /emby）';
    }
    if (lower.contains('http 429') ||
        lower.contains('status 429') ||
        lower.contains('too many requests')) {
      return '请求过于频繁（429），请稍后再试';
    }
    if (lower.contains('http 502') || lower.contains('http 503') || lower.contains('http 504')) {
      return '服务器网关异常或维护中（502/503/504），请稍后重试';
    }
    if (lower.contains('certificate') ||
        lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('handshake') ||
        lower.contains('invalidpeer') ||
        lower.contains('unknownissuer')) {
      return 'HTTPS 证书校验失败：若使用自签名证书，请在「网络与代理」中开启允许自签名证书';
    }
    if (lower.contains('dns') ||
        lower.contains('failed to lookup') ||
        lower.contains('nodename nor servname') ||
        lower.contains('name or service not known') ||
        lower.contains('no such host')) {
      return '域名解析失败，请检查服务器地址拼写或网络连接';
    }
    if (lower.contains('connection refused') ||
        lower.contains('os error 111') ||
        lower.contains('econnrefused')) {
      return '连接被拒绝，请确认服务器已运行且端口正确';
    }
    if (lower.contains('timed out') || lower.contains('timeout') || lower.contains('deadline')) {
      return '连接超时，请检查网络状况、防火墙或代理设置';
    }
    if (lower.contains('expected value at line 1') ||
        lower.contains('<!doctype') ||
        lower.contains('<html') ||
        lower.contains('formatexception')) {
      return '服务器返回了非预期页面（可能被反向代理拦截或地址有误）';
    }
    return raw;
  }
}
