import {
  listWatchedCompanies, createWatchedCompany,
  updateWatchedCompany, deleteWatchedCompany,
} from '../../db.js'
import { readBody, json } from '../http-helpers.js'
import type { RouteContext } from './types.js'

export async function tryHandleCompanies(ctx: RouteContext): Promise<boolean> {
  const { req, res, path, method, url } = ctx

  if (path === '/api/companies' && method === 'GET') {
    const activeOnly = url.searchParams.get('active') === 'true'
    json(res, listWatchedCompanies(activeOnly))
    return true
  }

  if (path === '/api/companies' && method === 'POST') {
    const body = await readBody(req)
    const data = JSON.parse(body.toString())
    if (!data.name || typeof data.name !== 'string' || !data.name.trim()) {
      json(res, { error: 'A name mező kötelező' }, 400)
      return true
    }
    try {
      const company = createWatchedCompany({
        name: data.name.trim(),
        type: data.type,
        career_url: data.career_url ?? null,
        active: data.active ?? 1,
      })
      json(res, company, 201)
    } catch (err: any) {
      if (err?.message?.includes('UNIQUE')) {
        json(res, { error: 'Már létezik ilyen nevű cég' }, 409)
      } else {
        throw err
      }
    }
    return true
  }

  const companyMatch = path.match(/^\/api\/companies\/(\d+)$/)
  if (companyMatch && method === 'PUT') {
    const id = parseInt(companyMatch[1], 10)
    const body = await readBody(req)
    const data = JSON.parse(body.toString())
    if (updateWatchedCompany(id, data)) {
      json(res, { ok: true })
    } else {
      json(res, { error: 'Cég nem található' }, 404)
    }
    return true
  }

  if (companyMatch && method === 'DELETE') {
    const id = parseInt(companyMatch[1], 10)
    if (deleteWatchedCompany(id)) {
      json(res, { ok: true })
    } else {
      json(res, { error: 'Cég nem található' }, 404)
    }
    return true
  }

  return false
}
