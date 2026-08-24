class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.4.1';
  static const appBuild = 10;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
