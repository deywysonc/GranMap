class ApiConfig {
  const ApiConfig._();

  static const appVersion = '1.4.0';
  static const appBuild = 9;

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
