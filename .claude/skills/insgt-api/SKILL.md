---
name: insgt-api
description: Rails conventions for insgt-api, the Rails 7.2 API-only backend for InsightPhotos. Use this skill for any task involving models, services, jobs, controllers, or migrations in the insgt-api repo. Load this skill before writing any Ruby code.
---

# insgt-api — Rails Conventions

Rails 7.2 API-only backend. Ruby 3.4. PostgreSQL/PostGIS. Sidekiq/Redis. Hosted on Heroku (a move to Render.com is planned, not done — the runbooks in `insgt-platform/docs/runbooks/` deploy via `git push heroku`). AWS S3/SSM/STS for file storage and secrets.

---

## 1. Inline Documentation

### The dual-audience rule
Every non-trivial comment has two readers: a human engineer onboarding to the codebase, and a future Claude Code session that needs to understand intent before making changes. Comments should explain *why* an approach was chosen — not restate what the code does. Focus on invariants, constraints, and rejected alternatives.

### ARCHITECTURE NOTES block
Any service object, model concern, or Sidekiq job with non-obvious design choices must open with an `ARCHITECTURE NOTES` comment block. This is the first thing a reader sees when entering the file.
```ruby
# ARCHITECTURE NOTES
#
# Why ai_features is immutable after creation:
#   Regeneration appends new ListingFeature records rather than updating the
#   existing ones. This preserves a full audit trail of model output over time
#   and prevents silent data loss if a regeneration produces lower-quality output.
#   The active copy is resolved at read time via `edited_features.presence || ai_features`.
#
# Why description_unlocked is a boolean and not a credit counter:
#   Billing is prepaid per-listing access. A credit counter would require tracking
#   generation costs on the model with no corresponding business value under the
#   current billing model. Promote to an enum if usage tiers are introduced.
#
# Invariants that must hold:
#   - ai_features is never updated after the initial record is created.
#   - edited_features starts nil and is only set by explicit agent action.
#   - description_unlocked must be true before generation is attempted.
```

Add an ARCHITECTURE NOTES block when the file contains any of:
- An append-only or immutable pattern
- A gate, flag, or guard controlling access to a feature
- A non-obvious ordering or priority rule (e.g., tiered photo selection logic)
- A deliberate constraint from an external standard (Fair Housing Act, AB 723, CRMLS 1,500-char limit)
- A pattern that looks simplifiable but isn't, with a reason why

### Inline why-comments
For constraints that don't warrant a full block, a brief inline comment is enough:
```ruby
# Confidence used as tiebreaker within scene type only —
# never to promote a lower-tier scene over a higher-tier one.
candidates.sort_by { |p| [-p.tier, -p.classification_confidence] }

# AB 723: digitally altered photos must be flagged before delivery
# regardless of who initiated the alteration.
photo.requires_disclosure_label = true if photo.virtually_staged?

# CRMLS public remarks cap is 1,500 characters. Use this as the
# conservative default for all San Diego-area MLSs.
MAX_DESCRIPTION_LENGTH = 1_500
```

### What not to document
Skip comments that restate the obvious:
```ruby
# ❌ restates the code — adds no value
listings = Listing.all # gets all listings

# ✅ explains the constraint
# Scoped to unlocked listings only — generation without unlock
# is a billing violation and must be caught at the service layer,
# not the controller.
listings = Listing.where(description_unlocked: true)
```

---

## 2. Service Objects

Business logic lives in service objects under `app/services/`, not in models or controllers. Controllers are thin — they validate params, call a service, and render. Models are persistence — validations, associations, scopes. Anything else is a service.

### Naming
- `ListingDescriptionService` — generates AI copy for a listing
- `PhotoClassificationService` — classifies a photo via Claude API
- `ListingFeaturesService` — derives features from classified photos

### Structure
```ruby
# frozen_string_literal: true

class ListingDescriptionService
  # ARCHITECTURE NOTES (if applicable — see Section 1)

  def initialize(listing)
    @listing = listing
  end

  # Returns the new ai_description string. Does not persist — caller decides
  # whether to save. Raises if listing is not unlocked.
  def call
    raise UnlockedError, "description_unlocked must be true" unless @listing.description_unlocked?
    generate_description
  end

  private

  def generate_description
    # ...
  end
end
```

- `#call` is the single public entry point.
- Raise named error classes for expected failure modes (`UnlockedError`, `InsufficientPhotosError`). Don't rescue and swallow inside the service — let the caller decide.
- Document `#call`'s return value and any preconditions in a comment above the method.

---

## 3. Models

Models own: validations, associations, scopes, and simple computed attributes. They do not own: API calls, multi-step workflows, external service calls, or anything that requires a second model to execute.

### Scopes over class methods
```ruby
# ✅ scope — chainable, lazy, composable
scope :unlocked,    -> { where(description_unlocked: true) }
scope :with_photos, -> { joins(:photos).distinct }

# ❌ class method for a simple filter — use a scope
def self.unlocked
  where(description_unlocked: true)
end
```

### Document non-obvious validations and callbacks
```ruby
# Presence validated at application layer only — the DB column allows null
# because ai_description is set asynchronously after record creation.
validates :ai_description, presence: true, on: :update, if: :description_unlocked?

# before_save intentionally omitted: classification happens in a background
# job (PhotoClassificationJob) to avoid blocking the upload response.
```

### Immutable fields
Flag immutable fields explicitly so future sessions don't introduce mutations:
```ruby
# Immutable after creation. Use ListingFeaturesService to append new records.
# Never call update on this attribute directly.
attr_readonly :ai_features
```

### Enums
Integer-backed, values start at 1 so NULL stays the only unset state
(`docs/architecture/account-classification.md` §3.0). The older enumerated columns are frozen
hashes instead — see `<repo>/CLAUDE.md`; that is the legacy pattern, not the one to copy.

**Declare with `prefix: true` when any value is a generic word** — `internal`, `other`,
`commercial`, `active`. Unprefixed, the enum takes `internal?` and `Model.internal`, which read as
questions about the record rather than about one column, and it spends one bare scope name per
value on a model that may already carry query concerns and raw SQL. Prefixed, they are
`category_type_internal?` and `OrderType.category_type_internal` — longer, and unambiguous at every
call site.

The serialized value is the enum name either way (`"internal"`), so the prefix never reaches the
API. It changes Ruby call sites only.

```ruby
enum :category_type, { property: 1, brand: 2, marketing: 3, internal: 4, recovery: 5 }, prefix: true
```

**Nullability is a separate decision from the enum.** A column whose NULL means "not yet
classified" takes no default and no presence validation, and its factory sets nothing — see
"Adding a nullable column whose NULL means something" in `insgt-api/CLAUDE.md`. A column that must
always be answered takes `null: false` plus a presence validation, so the model reports the
omission through `errors` rather than raising `NotNullViolation`.

---

## 4. Sidekiq Jobs

Jobs live in `app/jobs/`. One class, one responsibility.
```ruby
# frozen_string_literal: true

class PhotoClassificationJob < ApplicationJob
  # ARCHITECTURE NOTES (if applicable)
  #
  # Enqueued after photo upload completes. Calls Claude API to classify
  # scene_type, detected_features, and description. Results are written
  # directly to the Photo record; no intermediate state.
  #
  # Idempotency: re-running the job overwrites the classification fields —
  # safe because classification is deterministic for a given photo.

  queue_as :default

  def perform(photo_id)
    photo = Photo.find(photo_id)
    PhotoClassificationService.new(photo).call
  end
end
```

- Document: queue choice and reason, idempotency guarantee (or lack thereof), what triggers the job, and any retry behavior that differs from the default.
- Jobs should be thin: find the record, call a service, done. Business logic belongs in the service.

---

## 5. Controllers

Controllers are thin. The pattern is: authenticate → authorize → call service → render.
```ruby
# frozen_string_literal: true

class Api::V1::ListingsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_listing, only: [:show, :update, :destroy]

  def show
    render json: ListingSerializer.new(@listing)
  end

  def update
    if @listing.update(listing_params)
      render json: ListingSerializer.new(@listing)
    else
      render json: { errors: @listing.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_listing
    @listing = current_user.listings.find(params[:id])
  end

  def listing_params
    params.require(:listing).permit(:address, :description_unlocked)
  end
end
```

- No business logic in controllers. If a controller action is longer than ~15 lines, the logic belongs in a service.
- Document non-obvious `before_action` chains or authorization rules inline.

---

## 6. JSON Response Casing

**All outbound JSON is camelCase.** `config/environment.rb` sets `Jbuilder.key_format camelize: :lower`, so every jbuilder view emits lowerCamelCase keys regardless of the snake_case written in the template (`json.lifetime_value_cents` → `lifetimeValueCents`). Write jbuilder in snake_case as usual — camelization is automatic.

**Gotcha — `json.merge!` bypasses `key_format`.** Merging a Ruby hash copies its keys verbatim, so a snake_case service hash ships snake_case and breaks the convention (this is exactly how `order_metrics` silently shipped snake_case). Wrap merged hashes — and any raw `render json:` hash — in `deep_camelize` (defined in `ApplicationHelper`, so available in views and controllers):

```ruby
json.merge!(@result)                 # ❌ ships snake_case — merge! skips the global camelize
json.merge!(deep_camelize(@result))  # ✅ camelCase, consistent with every other endpoint
render json: deep_camelize(@result)  # ✅ same fix for a controller rendering a raw hash
```

Request specs should assert camelCase response keys (`body['monthlyTrend']`, `body['rollup']['turnaroundTimeMinutes']`) — see `spec/requests/accounts_order_metrics_spec.rb`. Inbound params are the inverse: camelCase request bodies are auto-converted to snake_case (`config/initializers/json_param_key_transform.rb`).

---

## 7. AI Integration (Claude API)

Services that call the Claude API must document their prompt strategy and any compliance constraints inline.
```ruby
# frozen_string_literal: true

class ListingDescriptionService
  # ARCHITECTURE NOTES
  #
  # Prompt constraints:
  #   - Fair Housing Act compliance: prompt explicitly excludes language implying
  #     neighborhood character or demographic composition.
  #   - No em-dashes in output: em-dashes are a detectable AI marker; banned via
  #     system prompt instruction.
  #   - Prohibited phrases banned via system prompt: "move-in-ready", "flows seamlessly",
  #     "excellent value", "don't miss this opportunity".
  #   - Output capped at 1,500 characters (CRMLS public remarks limit).
  #
  # Photo selection — tiered priority:
  #   Tier 1: Kitchen, Living Room, Primary Bedroom, Exterior Front
  #   Tier 2: Dining Room, Primary Bathroom, Backyard
  #   Tier 3: all remaining classified scenes
  #   Gate: classification_confidence >= 0.7 required for inclusion.
  #   Tiebreaker: confidence used within a tier only — never to elevate a
  #   lower-tier scene over a higher-tier one.
  #   Max photos sent to Claude: 20.
```

- Document the model in use at the call site (`claude-sonnet-4-5` or current equivalent).
- Document any multi-turn or system/user prompt structure.
- Document idempotency expectations — is calling the service twice safe?

---

## 8. General Rules

- **No logic in initializers** — `config/initializers/` is for wiring, not business decisions. A conditional in an initializer is almost always a sign that something belongs in a service or environment config.
- **Keyword arguments for services with 3+ parameters** — positional args become unreadable fast.
- **Constants belong in the model or service that owns them** — not in a global `Constants` module unless they're genuinely cross-cutting.
- **Migrations are permanent** — never edit a committed migration. Write a new one. Add a comment if the migration corrects or extends a previous one.
- **`frozen_string_literal: true`** on every file — reduces object allocation and catches accidental string mutation.