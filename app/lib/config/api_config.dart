class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.6.8';
  static const appBuild = 20;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'https://granmap.168.119.244.43.sslip.io/api',
  );
}
