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

## 6. Upload the project to GitHub and connect server hosting

1. Extract `Reyaa-Boutique-GitHub.zip`.
2. Create a **private** GitHub repository named `reyaa-boutique`.
3. Upload the contents INSIDE the extracted folder, so `package.json`, `app/`, `db/` and `README.md` sit at the repository root.
4. Include `.gitignore` and `.env.example`. If your file explorer hides them, enable hidden-file display. Never upload a real `.env.local` file.
5. Connect this repository to a host that runs Next.js server routes, or continue using a compatible existing server deployment. GitHub Pages only serves static files and cannot run this project's payment callbacks, authenticated APIs or admin operations.
6. Use Node.js 22.13+ and the package manager version in `package.json`.
7. Install: `corepack pnpm install --frozen-lockfile`.
8. Build: `corepack pnpm build`.
9. For a Node host, start: `corepack pnpm start` (set the host's `PORT` as required).
10. In your SERVER HOST environment settings, add the three Supabase values from step 3 and `PUBLIC_SITE_URL=https://YOUR-RUNNING-HOST`.
11. Set `BILLPLZ_MODE=sandbox`. Leave Billplz secrets empty until the client registers.
12. Deploy/redeploy after changing environment values.

Uploading to GitHub does not activate the database connection by itself. GitHub repository Secrets also do not automatically become runtime variables on an unrelated hosting provider.

For local development only: copy `.env.example` to `.env.local`, enter your values, install dependencies and run `corepack pnpm dev`. The website opens at `http://localhost:3000`. Production must use HTTPS. Local account login can be tested; emailed links use the configured HTTPS `PUBLIC_SITE_URL` and payment callbacks require a publicly reachable deployment.

## 7. Create Nisha's administrator login

The approved administrator email is **nisha.nairofficial0728@gmail.com**. A database project and connected email sender are required before the account can be created or reset emails can arrive. No working password is stored in this ZIP.

1. On your own computer, copy `.env.example` to `.env.local` and enter the new Reyaa project's URL, secret key, publishable key and HTTPS `PUBLIC_SITE_URL`. Keep `ADMIN_EMAIL=nisha.nairofficial0728@gmail.com`.
2. Add the same `ADMIN_EMAIL` to your server host environment settings and redeploy.
3. In Supabase Auth **URL Configuration → Redirect URLs**, add both `https://YOUR-HOST/account` and `https://YOUR-HOST/admin/reset`. The final domain needs the same entries when it is ready.
4. With dependencies installed, run `corepack pnpm admin:setup` in your local project terminal. Run this only locally, never in GitHub Actions or a shared build log.
5. The command creates the Auth user, gives it the server-controlled admin role, marks its password as temporary and prints a random temporary password once. Save/deliver it privately. Existing accounts keep their current password; an existing administrator is not recreated.
6. Open `https://YOUR-HOST/admin`. Nisha can enter her temporary login; the portal will direct her to reset it. She can also click **Forgot password?** immediately and enter her administrator email.
7. Click **Email reset link**. Open the newest email and its link, choose a password of at least 12 characters, confirm it, and save.
8. The verified recovery flow clears the temporary-password requirement. Nisha then signs in at `/admin` with her new password. Admin management remains blocked until this step completes.

Use Supabase's default password recovery email template initially, preserving its `{{ .ConfirmationURL }}` link so that `redirect_to=/admin/reset` is honored. The reset page consumes the token fragment, removes it from the browser address bar, verifies admin identity and a recent signed `recovery` authentication claim, and uses a short-lived HttpOnly reset cookie. Ordinary password-login tokens cannot bypass the email reset requirement. Configure SMTP before testing delivery; this feature has not sent an email yet.

`db/ADMIN-ROLE-LATER.sql` is an alternative for an already-created, verified Auth user and is now filled with Nisha's email. Use either the setup command or this SQL as appropriate; do not use customer-editable metadata to grant admin rights. The Supabase dashboard account, database password and boutique admin account are separate things.

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
