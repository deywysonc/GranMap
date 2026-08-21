const API = import.meta.env.VITE_GRANMAP_API_URL ?? 'http://127.0.0.1:8000'

export class ApiError extends Error {
  status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

function cookieValue(name: string) {
  const prefix = `${encodeURIComponent(name)}=`
  const item = document.cookie
    .split(';')
    .map(value => value.trim())
    .find(value => value.startsWith(prefix))
  return item ? decodeURIComponent(item.slice(prefix.length)) : ''
}

export function hasAdminSession() {
  return sessionStorage.getItem('granmap.admin.session') === 'cookie' ||
    Boolean(cookieValue('granmap_csrf'))
}

export async function request<T>(
  path: string,
  options: RequestInit = {},
  token?: string,
): Promise<T> {
  const response = await fetch(`${API}${path}`, {
    ...options,
    credentials: 'include',
    headers: {
      ...(options.body ? { 'Content-Type': 'application/json' } : {}),
      ...(token && token !== 'cookie' ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.method && options.method !== 'GET' && cookieValue('granmap_csrf')
        ? { 'X-CSRF-Token': cookieValue('granmap_csrf') }
        : {}),
      ...options.headers,
    },
  })
  if (!response.ok) {
    let message = `Erro ${response.status}`
    try {
      const body = await response.json()
      message = typeof body.detail === 'string'
        ? body.detail
        : body.detail?.message ?? message
    } catch {
      // Mantém a mensagem HTTP quando a resposta não for JSON.
    }
    throw new ApiError(message, response.status)
  }
  return response.json()
}

export const getJson = <T,>(path: string, token?: string) =>
  request<T>(path, {}, token)

export const postJson = <T,>(path: string, data: unknown, token?: string) =>
  request<T>(path, { method: 'POST', body: JSON.stringify(data) }, token)

export const putJson = <T,>(path: string, data: unknown, token?: string) =>
  request<T>(path, { method: 'PUT', body: JSON.stringify(data) }, token)

export const deleteJson = <T,>(path: string, token?: string) =>
  request<T>(path, { method: 'DELETE' }, token)
