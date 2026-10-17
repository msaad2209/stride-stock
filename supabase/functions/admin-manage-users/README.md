# admin-manage-users

This Supabase Edge Function handles admin-only shop creation and shop-user account tasks. It verifies the caller's Supabase access token, then checks that the caller has an active `admin` row in `public.profiles` before it uses the built-in `SUPABASE_SERVICE_ROLE_KEY` secret. The service key exists only inside the Supabase Function runtime and must never be copied into the browser app, GitHub, or this repository.

## Deploy

Install the free Supabase CLI from the official Supabase instructions, open a terminal in the repository folder, then run:

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy admin-manage-users
```

The function uses the standard `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` environment secrets provided by Supabase Functions. Do not paste the service-role key into a command, a source file, or the Vite environment.

## Supported actions

- `create_shop`: body `{ "action": "create_shop", "name": "Another shop" }`
- `create_user`: body `{ "action": "create_user", "email": "shop@example.invalid", "password": "temporary-password", "display_name": "Shop staff", "shop_id": "SHOP_UUID" }`. Email confirmation is completed automatically.
- `reset_password`: body `{ "action": "reset_password", "user_id": "AUTH_USER_UUID", "password": "new-temporary-password" }`
- `set_active`: body `{ "action": "set_active", "user_id": "AUTH_USER_UUID", "active": false }`

The frontend invokes these actions from **Admin**. The function returns HTTP 403 for accounts without an active admin profile. Account creation removes the new Auth user if its corresponding profile cannot be written, to avoid an orphaned login.

## Manual fallback

Without the CLI, an administrator can create Auth users in **Supabase Dashboard → Authentication → Users → Add user**, enable email confirmation for that user, then add a matching `profiles` row in the SQL Editor with `role='shop'`, `shop_id`, and `display_name`. Password reset is available from the Auth user menu. Set `profiles.active=false` to deactivate access, or `true` to restore it. Create shops in the table editor; the migration trigger adds the standard categories automatically.
