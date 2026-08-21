// @vitest-environment jsdom

import { afterEach, describe, expect, it, vi } from 'vitest'
import { hasAdminSession, postJson } from './api'

describe('cliente seguro do GranMap Admin', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    sessionStorage.clear()
    document.cookie = 'granmap_csrf=; Max-Age=0; path=/'
  })

  it('envia cookie e cabeçalho CSRF nas mutações', async () => {
    document.cookie = 'granmap_csrf=csrf-test; path=/'
    const fetchMock = vi.fn().mockResolvedValue(new Response(
      JSON.stringify({ saved: true }),
      { status: 200, headers: { 'Content-Type': 'application/json' } },
    ))
    vi.stubGlobal('fetch', fetchMock)

    await postJson('/courses', { name: 'Computação' }, 'cookie')

    expect(fetchMock).toHaveBeenCalledOnce()
    const options = fetchMock.mock.calls[0][1] as RequestInit
    expect(options.credentials).toBe('include')
    expect(options.headers).toMatchObject({ 'X-CSRF-Token': 'csrf-test' })
  })

  it('não trata uma resposta 401 como sucesso', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response(
      JSON.stringify({ detail: 'Sessão inválida.' }),
      { status: 401, headers: { 'Content-Type': 'application/json' } },
    )))
    await expect(postJson('/courses', {}, 'cookie')).rejects.toMatchObject({
      status: 401,
    })
  })

  it('reconhece apenas o marcador local de uma sessão por cookie', () => {
    expect(hasAdminSession()).toBe(false)
    sessionStorage.setItem('granmap.admin.session', 'cookie')
    expect(hasAdminSession()).toBe(true)
  })
})
