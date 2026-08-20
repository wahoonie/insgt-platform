# Decision: Public ID Strategy

**Status**: Proposed
**Date**: 2026-02-11

## Context

Orders use a "token" field as their public-facing identifier. This token serves multiple roles: URL slugs for client-facing apps (galleries, downloads, disclosure pages), invoice IDs on documentation provided to customers, and API lookup keys. The token is generated via the `token.rb` module.

Years of organic growth have created inconsistencies in how public IDs are handled across the system. Some models use tokens, some expose database IDs directly, and the naming is inconsistent across repos. Client-facing apps each handle token resolution slightly differently.

## Problem

- The term "token" is overloaded — it conflicts with auth token terminology and is unclear to new code readers
- Not all models that need public IDs have them
- Some client-facing URLs leak sequential database IDs
- The `token.rb` module has accumulated logic that mixes generation, validation, and lookup concerns
- Invoice references are coupled to the same value used for URL routing, making either hard to change independently

## Options Considered

_To be filled in during dedicated cleanup work._

## Decision

_Pending._

## Consequences

_Pending._

## Notes

- Any solution must preserve existing customer-facing URLs and invoice references, or provide a migration path
- The galleries, disclosure-gallery, and client-app repos all resolve tokens differently and would need coordinated updates
- This is a prerequisite for cleaning up several other areas — changing this will ripple across most repos
