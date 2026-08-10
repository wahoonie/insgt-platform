# Cypress Testing Patterns

Reference for the three-test-per-feature pattern used across all InsightPhotos Angular apps.
Read this file when writing Cypress specs or setting up fixtures for a new feature.

---

## Spec structure — three tests per feature

Every feature needs exactly these three specs. They cover 90% of the real failure surface
without over-investing in coverage that won't pay off.

```ts
// cypress/e2e/things/things.cy.ts
describe('Things', () => {

  // ── Happy path ────────────────────────────────────────────────────────
  it('lists, creates, edits, and deletes a thing', () => {
    cy.intercept('GET', '/api/things', { fixture: 'things/list.json' }).as('loadThings');
    cy.intercept('POST', '/api/things', { fixture: 'things/created.json' }).as('createThing');
    cy.intercept('PUT', '/api/things/*', { fixture: 'things/updated.json' }).as('updateThing');
    cy.intercept('DELETE', '/api/things/*', { statusCode: 204 }).as('deleteThing');

    cy.visit('/things');
    cy.wait('@loadThings');

    cy.get('[data-cy="thing-list"]').should('be.visible');
    cy.get('[data-cy="thing-list-item"]').should('have.length', 3);

    // Create
    cy.get('[data-cy="add-thing-btn"]').click();
    cy.get('[data-cy="thing-name-input"]').type('New Thing');
    cy.get('[data-cy="save-btn"]').click();
    cy.wait('@createThing');
    cy.get('[data-cy="thing-list"]').should('contain', 'New Thing');

    // Edit
    cy.get('[data-cy="thing-list-item"]').first().find('[data-cy="edit-btn"]').click();
    cy.get('[data-cy="thing-name-input"]').clear().type('Updated Thing');
    cy.get('[data-cy="save-btn"]').click();
    cy.wait('@updateThing');
    cy.get('[data-cy="thing-list"]').should('contain', 'Updated Thing');

    // Delete
    cy.get('[data-cy="thing-list-item"]').first().find('[data-cy="delete-btn"]').click();
    cy.get('[data-cy="confirm-delete-btn"]').click();
    cy.wait('@deleteThing');
    cy.get('[data-cy="thing-list-item"]').should('have.length', 2);
  });

  // ── Empty state ───────────────────────────────────────────────────────
  it('shows empty state when no things exist', () => {
    cy.intercept('GET', '/api/things', {
      body: { data: [], metadata: { totalCount: 0 } },
    });

    cy.visit('/things');
    cy.get('[data-cy="empty-state"]').should('be.visible');
    cy.get('[data-cy="thing-list-item"]').should('not.exist');
  });

  // ── Error state ───────────────────────────────────────────────────────
  it('shows error state when API fails', () => {
    cy.intercept('GET', '/api/things', { statusCode: 500 }).as('loadError');

    cy.visit('/things');
    cy.wait('@loadError');
    cy.get('[data-cy="error-state"]').should('be.visible');
    cy.get('[data-cy="thing-list"]').should('not.exist');
  });

});
```

---

## Fixture structure

```
cypress/
├── e2e/
│   └── things/
│       └── things.cy.ts
└── fixtures/
    └── things/
        ├── list.json       # 2-3 realistic items with valid field values
        ├── created.json    # single newly created item
        └── updated.json    # single updated item
```

Use realistic fixture data — plausible names, real-looking IDs, valid enum values.
`"name": "test123"` makes failures harder to diagnose than `"name": "Main Bedroom"`.

```json
// fixtures/things/list.json
{
  "data": [
    { "id": "abc-123", "name": "Main Bedroom", "position": 1 },
    { "id": "def-456", "name": "Kitchen", "position": 2 },
    { "id": "ghi-789", "name": "Living Room", "position": 3 }
  ],
  "metadata": { "totalCount": 3, "page": 1, "perPage": 25 }
}
```

---

## `data-cy` attribute conventions

Add `data-cy` to every interactive element and every meaningful display region.
CSS classes and Angular selectors break on refactors; `data-cy` attributes are stable.

```html
<!-- ✅ stable selectors -->
<div data-cy="thing-list">
  @for (thing of vm.things; track thing.id) {
    <div data-cy="thing-list-item">
      <span data-cy="thing-name">{{ thing.name }}</span>
      <button data-cy="edit-btn">Edit</button>
      <button data-cy="delete-btn">Delete</button>
    </div>
  }
</div>
<button data-cy="add-thing-btn">Add Thing</button>

<!-- Standard region names to use consistently -->
<!-- data-cy="[feature]-list"         — the list container -->
<!-- data-cy="[feature]-list-item"    — each row/card -->
<!-- data-cy="empty-state"            — zero data message -->
<!-- data-cy="error-state"            — API error message -->
<!-- data-cy="add-[feature]-btn"      — primary create CTA -->
<!-- data-cy="edit-btn"               — edit action on an item -->
<!-- data-cy="delete-btn"             — delete action on an item -->
<!-- data-cy="save-btn"               — form submit -->
<!-- data-cy="cancel-btn"             — form cancel -->
<!-- data-cy="confirm-delete-btn"     — delete confirmation -->
<!-- data-cy="[field]-input"          — form inputs -->
```

---

## Intercept patterns

```ts
// Stub collection load
cy.intercept('GET', '/api/things', { fixture: 'things/list.json' }).as('loadThings');

// Stub with query params (search/filter)
cy.intercept('GET', '/api/things?*', { fixture: 'things/list.json' }).as('loadThings');

// Stub nested resource
cy.intercept('GET', '/api/orders/*/photos', { fixture: 'photos/list.json' }).as('loadPhotos');

// Stub failure
cy.intercept('GET', '/api/things', { statusCode: 500 }).as('loadError');

// Stub empty
cy.intercept('GET', '/api/things', { body: { data: [], metadata: { totalCount: 0 } } });

// Wait and assert on request
cy.wait('@createThing').its('request.body').should('deep.include', { thing: { name: 'New Thing' } });
```

---

## Two rules that apply to every spec

**Boy scout rule** — when you open a feature file to change it, leave it with a spec that didn't exist before. Minimum: one happy path test. Don't open files just to add tests; let active development drive accumulation.

**Regression rule** — when a bug is found, write the failing test first, then fix the bug. This is the highest-ROI test you can write — it targets a confirmed real failure mode and ensures it never regresses.