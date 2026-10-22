# Reyaa Boutique — Supabase setup for Sai

This package is a normal Next.js project exported for your GitHub repository. The design, storefront routes, customer portal, admin portal, Billplz integration and promotion tools are included. External services are not connected by the ZIP itself.

## 1. Create a separate Supabase project

1. Open https://supabase.com/dashboard and sign in.
2. Click **New project** and choose your organization (for example, `sarishi10's Org`).
3. Name it **Reyaa Boutique**.
4. Generate a strong database password and save it in your password manager. This is the database password, not the store admin password.
5. Choose **Singapore / Southeast Asia** if available for your account, close to Malaysian customers.
6. Check the plan and any displayed cost before creating the project. Free-plan availability depends on your account/project limits.
7. Wait for the project to finish provisioning. Keep it separate from SR-ORDER and other clients.

## 2. Create tables, permissions and image storage

1. In the NEW empty Reyaa project, open **SQL Editor → New query**.
2. On your computer, open `db/SETUP-ALL.sql` from this ZIP in a text editor.
3. Copy the complete contents into SQL Editor and click **Run**.
4. Run this setup once only. It creates the schema inside one transaction. Do not run it against a project containing store data.
5. Run `db/VERIFY-SETUP.sql` in a new query. It should list nine public store tables, each with `rls_enabled = true`, and the public `store-images` bucket. The tables are store_settings, products, product_variants, orders, order_items, subscribers, campaigns, campaign_deliveries and signup_limits.
6. Open the project's **Security Advisor**, review any findings, and keep RLS enabled. Orders and subscriptions must never get an unrestricted public-read policy.

The image bucket is public because product photos are public. Uploads are performed only by the authenticated admin backend. Never upload private client documents to this bucket.

If setup reports an error, keep the full error text and line number. Stop before rerunning individual pieces; the combined transaction should roll back rather than leave half a schema.

## 3. Get the project URL and API keys

Find the **Project URL** in the project **Connect** panel / API settings. In **Settings → API Keys**, locate or create the publishable and secret keys.

You need:

| Website environment variable | Value from Supabase |
| --- | --- |
| `SUPABASE_URL` | Project URL, such as `https://YOUR_PROJECT_REF.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | Publishable key (`sb_publishable_...`) |
| `SUPABASE_SECRET_KEY` | Secret key (`sb_secret_...`) |

Use the modern publishable and secret keys with this implementation. The database password is not used for these values. Keep the secret key out of GitHub, screenshots, frontend JavaScript and chat.

## 4. Enable customer accounts

1. Open **Authentication → Sign In / Providers → Email** (the dashboard label may vary).
2. Enable email/password signups and keep **Confirm email** enabled.
3. Open **Authentication → URL Configuration**.
4. Set **Site URL** to the HTTPS address where you deploy the Next.js website. A temporary hosting address is fine before buying the domain.
5. Add that exact address plus `/account` to **Redirect URLs**, for example `https://YOUR-TEMPORARY-HOST/account`.
6. When the final domain is ready, update these values and the website's `PUBLIC_SITE_URL` together.
7. Use the default Supabase confirmation/reset email templates initially. The account page handles the returned token fragment. If you later switch to custom token-hash/PKCE templates, the matching callback implementation must be added first.

Do not put the GitHub repository URL in these fields. A repository URL is not the running website.

## 5. Connect a production email sender

Customer signup confirmations and password resets need working email delivery. Configure **Authentication → Emails → SMTP Settings** with a provider's verified sender and SMTP credentials. Supabase's built-in trial sender has restrictions and is not sufficient for a public store launch.

The promotion/newsletter code uses **Resend** separately:

- Verify a sending domain with Resend and set its required DNS records.
- Put `RESEND_API_KEY` and `EMAIL_FROM` into the website host's environment settings.
- `EMAIL_FROM` should use a verified sender, for example `Reyaa Boutique <updates@YOUR-DOMAIN>`.
- The same email provider can also supply SMTP for Supabase Auth; these are two separate configuration steps.
- Keep email link tracking disabled for Supabase authentication emails so confirmation/reset links are not rewritten.

Until the sending domain is available, complete the database first and keep public signup/promotion delivery pending. No promotional campaign is sent automatically by setup.

## 6. GitHub → Cloudflare Workers (browser only)

No local Node.js installation is needed. Cloudflare installs dependencies and builds remotely.

1. Extract the updated ZIP and upload its CONTENTS to existing `sarishi10/Reyaa-Boutique`, replacing matching files. Keep `package.json`, `pnpm-lock.yaml`, `vite.config.ts`, `wrangler.jsonc`, app/ and public/ at repository root. Include hidden `.gitignore` and `.env.example`; never upload real credentials.
2. Cloudflare Workers & Pages → Create application → Connect GitHub → select that repository and main branch.
3. Project name: `reyaa-boutique`. Build command: `pnpm run build`. Deploy command: `npx wrangler deploy`. Leave root directory blank. Disable preview builds initially. Leave Cloudflare Access protection off for public customers.
4. Under advanced build settings set `NODE_VERSION=22.16.0`. Keep dependency installation enabled (pnpm is selected from the lockfile/packageManager).
5. Deploy. The Vite Cloudflare plugin generates the Worker and asset configuration; Wrangler uses its generated deployment config automatically.
6. Copy the resulting HTTPS workers.dev address. Under this Worker's Settings → Variables and Secrets add runtime values: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`, `PUBLIC_SITE_URL` (the exact HTTPS address), `ADMIN_EMAIL=nisha.nairofficial0728@gmail.com`, `BILLPLZ_MODE=sandbox`. Store the Supabase secret key as an encrypted Secret. Enter credentials directly in Cloudflare; never GitHub or chat.
7. Deploy the runtime settings/redeploy as prompted. Do not place Supabase or Billplz secrets in build variables. Runtime process.env is provided by Workers nodejs_compat.
8. Add `/account` and `/admin/reset` on the running HTTPS origin to Supabase Auth redirect URLs; set Site URL to that origin.

For local development only, use ignored `.dev.vars` for Worker runtime secrets, `pnpm install --frozen-lockfile`, then `pnpm dev`. The hosting workflow above does not require this.

## 7. Create Nisha's administrator login (browser only)

The approved email is **nisha.nairofficial0728@gmail.com**. No working password is included.

1. In Supabase Authentication → Users → Add user → Create new user, use this exact email and a unique temporary password of at least 12 characters. Set the user as email confirmed. Keep the password private.
2. In Supabase SQL Editor run `db/ADMIN-ROLE-LATER.sql` once. This grants the server-controlled admin role and requires a password reset; customer signup cannot grant this role.
3. Ensure the runtime ADMIN_EMAIL and Auth redirects from section 6 are configured, and complete Auth email/SMTP setup from section 5.
4. Open the site's `/admin` page. Temporary login directs Nisha to email reset; alternatively use Forgot password and her approved email.
5. Open the latest recovery email, choose a new password of at least 12 characters, and sign in again. Management is blocked until verified email recovery completes.

Keep Supabase's default recovery template with `{{ .ConfirmationURL }}`. The separate `/admin/reset` route verifies the recovery session and administrator role. Customer portal remains `/account`. The Supabase dashboard login and store administrator login are separate accounts.

The optional `scripts/setup-admin.mjs` command is retained for developers; it is unnecessary for the browser-only workflow.

## 8. Check the connection

- Open `/api/store` on your running website. It should show `connected: true` and initially an empty products array. Do not share URLs containing tokens or secret values.
- After the administrator is created, open **Admin → Connections**: Database should show connected.
- Add one genuine product, upload its photo, configure actual variants/available stock, then check it appears on the storefront.
- Test signup, confirmation, login, password reset, customer/admin separation and image upload on the real deployment.
- Add real business details, shipping rate, returns/privacy/terms and approved payment badges in admin settings.
- Keep **Open checkout** off until the payment and launch tests are complete.

## What remains before public sales

- Working server deployment linked to GitHub and Supabase.
- Create the approved administrator account and complete its first email password reset.
- Real products, prices, stock, policies and delivery charges.
- Email sender/SMTP and promotion email connection.
- Final Exabytes domain plus DNS/TLS and redirect updates.
- Client-owned Billplz account, sandbox/production keys and approved payment methods.
- Real Supabase/Billplz/email end-to-end testing.

After all the other items are finished, domain and Billplz can be the final two external connections. Database creation alone does not complete the remaining items.

## Official references

- Supabase API keys: https://supabase.com/docs/guides/getting-started/api-keys
- Supabase password auth: https://supabase.com/docs/guides/auth/passwords
- Supabase SMTP: https://supabase.com/docs/guides/auth/auth-smtp
- Supabase production checks: https://supabase.com/docs/guides/deployment/going-into-prod
- Next.js deployment: https://nextjs.org/docs/app/getting-started/deploying
