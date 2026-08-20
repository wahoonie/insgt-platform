# insgt-galleries

## Purpose
A public-facing photo gallery that agents share with their clients, 
stagers, designers, and other parties who need to see property photos. 
This is a showcase/preview tool — not a virtual tour and not intended 
for MLS use, and not intended for any marketing use.

## Public URLs
- Production: https://gallery.insightphotos.net
- Hosting: render.com (auto-deploys from main)

## Tech Stack
- Framework: Ruby on Rails with TailwindCSS (via tailwindcss-rails gem)
- Image loading: lozad.js (lazy loading)
- Build/deploy: render.com (see bin/render-build.sh, render.yaml)

## How It Connects
Galleries are accessed via a public URL tied to an order token. The 
service pulls order and photo data from the API to render the gallery. 
A gallery operates at the parent order level, aggregating photos from 
all child orders.

## Key Behaviors
- Galleries are public and unauthenticated — anyone with the link can 
  view the photos
- This is explicitly NOT for MLS use. Agents use this to share with 
  people involved in the listing process, not for public marketing
- Images are lazy-loaded for performance since galleries can contain 
  large photo sets

## AB 723 Impact
Galleries display photos to third parties, which raises the question 
of whether altered images shown here require disclosure. Since these 
galleries are not MLS listings and are shared privately between agents 
and their contacts, the compliance requirements are less clear-cut 
than for MLS or public advertising. However, the gallery should still 
differentiate between altered and unaltered photos when both exist.

It currently only shows the enhanced Photo, it does not show the Unaltered photo.

## Known Debt / Gotchas
- Hosted on render.com separately from the main infrastructure 
  (most other services are on Heroku or AWS)
- Still using Rails with TailwindCSS rather than Angular like the 
  other client-facing apps
- This is being considered for migration to Angular.