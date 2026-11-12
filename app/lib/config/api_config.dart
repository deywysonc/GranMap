class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.6.11';
  static const appBuild = 23;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'http://127.0.0.1:8787/api',
  );
}
