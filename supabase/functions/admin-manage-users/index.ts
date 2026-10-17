import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...cors, 'Content-Type': 'application/json' },
});

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405);
  const url = Deno.env.get('SUPABASE_URL');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const authorization = request.headers.get('Authorization');
  if (!url || !anonKey || !serviceKey || !authorization?.startsWith('Bearer ')) {
    return json({ error: 'Missing configuration or bearer token' }, 401);
  }
  try {
    const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } } });
    const { data: { user }, error: authError } = await caller.auth.getUser();
    if (authError || !user) return json({ error: 'Sign in again to continue' }, 401);
    const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from('profiles')
      .select('role,active').eq('user_id', user.id).maybeSingle();
    if (profileError || profile?.role !== 'admin' || !profile.active) return json({ error: 'Forbidden' }, 403);
    const body = await request.json();
    if (body.action === 'create_shop') {
      const name = String(body.name ?? '').trim();
      if (!name) return json({ error: 'Shop name is required' }, 400);
      const { data, error } = await admin.from('shops').insert({ name }).select('id,name').single();
      if (error) return json({ error: error.message }, 400);
      return json({ shop: data });
    }
    if (body.action === 'create_user') {
      const email = String(body.email ?? '').trim();
      const password = String(body.password ?? '');
      const displayName = String(body.display_name ?? '').trim();
      const shopId = String(body.shop_id ?? '');
      if (!email || password.length < 8 || !displayName || !shopId) return json({ error: 'Email, display name, shop, and a password of at least 8 characters are required' }, 400);
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email, password, email_confirm: true, user_metadata: { display_name: displayName },
      });
      if (createError || !created.user) return json({ error: createError?.message ?? 'Could not create user' }, 400);
      const { error: insertError } = await admin.from('profiles').insert({
        user_id: created.user.id, role: 'shop', shop_id: shopId, display_name: displayName, active: true,
      });
      if (insertError) {
        await admin.auth.admin.deleteUser(created.user.id);
        return json({ error: insertError.message }, 400);
      }
      return json({ user_id: created.user.id, email });
    }
    if (body.action === 'reset_password') {
      const userId = String(body.user_id ?? '');
      const password = String(body.password ?? '');
      if (!userId || password.length < 8) return json({ error: 'User ID and a password of at least 8 characters are required' }, 400);
      const { error } = await admin.auth.admin.updateUserById(userId, { password });
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }
    if (body.action === 'set_active') {
      const userId = String(body.user_id ?? '');
      if (!userId || typeof body.active !== 'boolean') return json({ error: 'User ID and active state are required' }, 400);
      const { error } = await admin.from('profiles').update({ active: body.active }).eq('user_id', userId);
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }
    return json({ error: 'Unknown action' }, 400);
  } catch (error) {
    console.error('admin-manage-users failed', error);
    return json({ error: 'Unexpected error. Retry or contact the administrator.' }, 500);
  }
});
