# StrideStock — footwear shop stock and sales

An installable mobile-first web app for footwear shops. It keeps stock, sales, returns, labels and exports online through Supabase. This beta supports one shop and an admin login; the schema includes shop IDs so it can grow later.

## Set up your free Supabase project

1. Go to [supabase.com](https://supabase.com) and create a free project. Choose a strong database password and keep it somewhere safe.
2. In the project, open **SQL Editor**. Paste and run `supabase/migrations/001_init.sql` first. Then paste and run `supabase/seed.sql` to add Shop 1, categories and three sample designs.
3. Open **Authentication → Users → Add user**. Create your admin with an email and password. There is no sign-up screen in the app.
4. In **Project Settings → API**, copy the Project URL and the public `anon` key. Never put the `service_role` key in this app.

## Run it on your computer

1. Install the current Node.js LTS version from [nodejs.org](https://nodejs.org).
2. Open a terminal in this folder and run `npm install`.
3. Copy `.env.example` to `.env.local`. Replace the two example values with the Supabase Project URL and public anon key.
4. Run `npm run dev` and open the local address printed in the terminal. Sign in with the admin account.
5. `npm test` runs the included checks. `npm run build` creates the website in `dist`.

## Put it online with Cloudflare Pages

1. Push this folder to a private GitHub repository. In GitHub repository settings, add secrets `SUPABASE_URL` and `SUPABASE_ANON_KEY` for the weekly keepalive workflow. The anon key is public by design; RLS still protects data.
2. In [Cloudflare Pages](https://pages.cloudflare.com/), choose **Create a project → Connect to Git** and select your repository.
3. Set framework preset to **Vite**, build command to `npm run build`, and build output directory to `dist`.
4. In Pages **Settings → Environment variables**, add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` for production (and preview if desired). Save and redeploy.
5. Open your HTTPS Pages address, sign in and add your shop's real stock. Keep the initial sample products only if useful.

## Install and try it on a phone

Open the HTTPS Pages site in your phone browser and choose **Add to Home Screen** (or **Install app**). In **Add incoming stock**, enter an item, article number, category, color, size range and quantities. Generate and print labels, or choose **Save as PDF** in the print dialog. Open **Sell**, tap **Scan a barcode**, allow camera access and scan a printed label. Change the price if needed and confirm. The fallback SKU field also accepts a USB/Bluetooth keyboard scanner.

Camera tips: use good light, hold the phone 15–25 cm from the label, print labels at least 38 mm wide, and avoid glossy laminate glare. The camera requires HTTPS. If you deny permission, allow it in the browser's site settings and retry.

## Excel and backups

On **Admin & exports**, download Stock and Sales as `.xlsx`, or Items as `.csv`; open the files in Excel. Make a monthly backup and keep a copy somewhere safe. You can also use the Supabase dashboard's table view to export any table to CSV and open it in Excel. Sales history is never overwritten by stock imports.

## Database and access notes

All business tables carry `shop_id`. Row Level Security allows authenticated accounts to access data; create only the intended admin account in Supabase Auth for this beta. For a production multi-user rollout, replace the broad authenticated policies with shop membership checks. The browser only uses the public anon key. Stock quantity changes happen through database RPCs so concurrent sales cannot reduce stock below zero.

The GitHub Actions keepalive runs weekly and makes an authenticated-by-public-key GET to the Supabase REST API. Add the two repository secrets above for it to work.

## Future roadmap (not implemented)

- Multiple users with roles
- Multi-shop switching
- Supplier and purchase tracking
- GST invoices
- Offline mode
