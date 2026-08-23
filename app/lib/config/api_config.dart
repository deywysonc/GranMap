class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.3.2';
  static const appBuild = 8;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
