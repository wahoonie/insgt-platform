# insgt-virtual-tour

## Purpose
Public-facing property listing pages for MLS platforms — the "virtual tour" URL an agent puts on a listing. Renders photo carousels, property details, agent info, embedded tours, and the AB 723 disclosure link. Stateless: it has no database and is purely a view layer over insgt-api.

## Public URLs
- Production: https://insightlistings.com
- Custom domains: listings can have vanity domains (e.g. `www.3737hillviewway.com`) routed directly to the listing page
- Hosting: Render.com, auto-deploys from git

## Tech Stack
- Framework: Rails 8.0, no ActiveRecord models, no database
- CSS: Tailwind CSS 3.3 via the `tailwindcss-rails` gem
- JS: no framework — vanilla JS in a `_script.html.erb` partial
- Vendored libraries: Pannellum (360 viewer), Fancybox (lightbox), lozad (lazy loading), all checked into `vendor/assets/javascripts/`

## How It Connects
Every request resolves a listing through `InsightPhoto` (`lib/insight_photo.rb`), a plain Ruby HTTP client that calls insgt-api and returns hashes:

```
Request → CustomDomainConstraint or standard route
       → ListingsController#show
       → InsightPhoto.find_listing(id: or custom_domain:)
       → GET insgt-api /listings/{id}/virtual.json
       → @listing hash + @image_handler → views
```

The app does **not** call MLS APIs. insgt-api fetches and caches MLS data and hands over a pre-assembled payload: property details (address, beds, baths, sqft, price, HOA, days on market), MLS number and status, account/agent data with organization memberships, features and room dimensions, area data, walk score, and all media references.

Organizations arrive as an array in `account[:organizations]`; the controller injects accessors by `typeOfName` — `[:brokerage]`, `[:mls]`, `[:agent_team]`.

## Key Behaviors

### Page structure (`listings/show.html.erb`)

```
Hero carousel (auto-playing slideshow)
├── Music player toggle (if slideshowMusicUrl)
├── Language switcher (EN/ES, if Spanish available)
└── Lazy-loaded photos via lozad.js

Header      — price, listing status badge, address, agent details (branded only)
Property    — description (HTML, Spanish-capable), embedded media, photo grid with
              Fancybox lightbox + AB 723 disclosure link, floor plans, property
              table, Google Maps embed with area info and walk score
Agent       — headshot, name, phone, email, website, MLS number, team and
              brokerage logos, plus a second agent on multi-account listings
Footer      — copyright, language switcher, terms
```

Two more views: `listings/account.html.erb` is a paginated grid of an agent's active listings at `/r/:account_slug`; `panos/show.html.erb` is a Pannellum 360 viewer supporting hotspots with pitch/yaw coordinates.

### Embedded content types

| `typeOf` | Content | Rendering |
|---|---|---|
| 1 | MLS listing | not rendered |
| 4 | YouTube | iframe |
| 5 | Matterport 3D | iframe |
| 6 | Vimeo | iframe, with custom URL rewriting |
| 7 | Aerial 360 | Pannellum, on its own route |
| 10 | Zillow 3D | iframe |

### Branded vs unbranded
Every listing has two URL variants. Branded (`/b/`) shows agent headshot, team and brokerage logos, contact info, and the "Request showing" CTA. Unbranded (`/ub/`) hides all of it. Driven by `params[:branded]` and the `branded?` helper.

### i18n
Locale comes from the subdomain (`es.insightlistings.com` → Spanish), falling back to English when the listing lacks `spanishListings: true`. Locale files in `config/locales/`, with `hreflang` alternate tags for SEO.

## AB 723 Impact

This is the highest-stakes disclosure surface — these pages appear on MLS platforms the agent may not control.

The mechanism is the **disclosure gallery link**. The photo grid (`components/_photo_grid.html.erb`) checks whether *any* photo has `alterationType` 2 or 3; if so it renders a "Digital Alterations Disclosure Gallery" link to `ENV['DISCLOSURE_GALLERY_URL']/<order_id>`, satisfying the law's requirement for a link or QR code to the unaltered original. If no photo is altered, no link and no labels appear at all — progressive disclosure.

Per-photo labels are applied by the `photo_caption` helper, which appends the `watermark_label` (`Digitally Altered` / `Virtually Staged`) to the caption text.

This app does **not** display unaltered photos inline (that is insgt-disclosure-gallery's job) and does not determine alteration status (the API supplies it).

⚠️ **The watermark image transform is commented out.** In `lib/image_handler.rb#url`, the block that would pass `edits[:watermark]` through to CloudFront is commented out, so this app applies no rendered watermark — labeling here is caption text plus the disclosure link only. If a baked-in watermark is expected on the image itself, it must be coming from upstream processing; that should be confirmed rather than assumed.

## Deployment

Render.com, auto-deploy from git, config in `render.yaml`. Build (`bin/render-build.sh`): `bundle install` → download the Tailwind standalone binary → `rake tailwindcss:build` → `rake assets:precompile` → `rake assets:clean`. Start: `bundle exec puma -C config/puma.rb`.

| Variable | Purpose |
|---|---|
| `INSIGHT_API_ENDPOINT` | API base URL (dev `http://localhost:3000`) |
| `INSIGHT_API_REQUEST_TOKEN` | Auth token for API requests |
| `IMAGE_HANDLER_ENDPOINT` | CloudFront CDN for image transforms — differs dev/prod |
| `IMAGE_HANDLER_BUCKET` | S3 bucket (`insgt`) |
| `GOOGLE_MAP_API_KEY` | Maps embed |
| `LISTING_DOMAIN` | Canonical domain |
| `DISCLOSURE_GALLERY_URL` | AB 723 link target (dev `http://localhost:4500/gallery`) |
| `S3_REGION` | `us-west-1` |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Configured on `ImageHandler#s3_resource` |
| `RAILS_MASTER_KEY` | Credentials decryption |

## Known Debt / Gotchas

- **Custom-domain routing hits the API on every request, uncached** — and `InsightPhoto.listing_exists?` *loops* over an API subdomain allowlist, so a single request can make several blocking HTTP calls before routing resolves.
- **Floor-plan PDFs are served from unsigned, public S3 URLs.** The `:print` branch of `ImageHandler#url` returns `https://{bucket}.s3-us-west-1.amazonaws.com/{key}` directly — no signature, no expiration. `ImageHandler#s3_resource` builds an `Aws::S3::Resource` with credentials but **is never called**; it is dead code.
- Vendored JS is updated by hand-replacing files.
- No app-specific Claude skill covers this repo.
