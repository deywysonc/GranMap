class ApiConfig {
  const ApiConfig._();

  static const baseUrl = String.fromEnvironment(
    'GRANMAP_API_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );
}
