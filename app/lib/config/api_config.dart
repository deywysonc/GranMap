class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.6.10';
  static const appBuild = 22;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'https://granmap.168.119.244.43.sslip.io/api',
  );
}
