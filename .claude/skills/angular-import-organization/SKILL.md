---
name: angular-import-organization
description: Use this skill when organizing, commenting, or sorting imports in any InsightPhotos Angular file (insgt-ops or insgt-app). Invoke whenever asked to clean up imports, add import section headers, organize import blocks, or when generating a new component/service with multiple imports that need grouping. Applies to all .ts files across both apps.
---

# Angular Import Organization

All TypeScript files in InsightPhotos Angular apps use a consistent import block structure: grouped by category, each group preceded by a labeled divider comment. This makes it fast to scan what a file depends on and where each dependency belongs.

## The Categories (in order)

Use exactly these categories, in this sequence. Do not add new ones. Omit a category entirely if no imports belong to it — don't leave an empty section.

```ts
// ────────────────────────────────
// 🅰️ Angular
// ────────────────────────────────

// ────────────────────────────────
// 📡 State
// ────────────────────────────────

// ────────────────────────────────
// 🧱 Application
// ────────────────────────────────

// ────────────────────────────────
// 📦 Data Models
// ────────────────────────────────

// ────────────────────────────────
// 🛠️ Pipes & Directives
// ────────────────────────────────

// ────────────────────────────────
// 🧩 UI Components
// ────────────────────────────────

// ────────────────────────────────
// 🧰 Utility Libraries
// ────────────────────────────────

// ────────────────────────────────
// 🎨 Icons
// ────────────────────────────────

// ────────────────────────────────
// 📦 Third-Party Dependencies
// ────────────────────────────────
```

## Classification Rules

**🅰️ Angular** — anything from `@angular/*`, `@ngrx/store`, `@ngrx/effects`, `@ngrx/entity`, `rxjs`, `rxjs/operators`, Angular CDK (`@angular/cdk/*`), and Angular Material (`@angular/material/*`).

**📡 State** — NgRx actions, selectors, reducers, effects, state interfaces, and facade services. Anything from a feature's `state/` or `store/` directory, and `*-facade.service.ts` files.

**🧱 Application** — shared app services, guards, interceptors, auth, config, and core utilities from `@app/core/*` or `@app/shared/*` that are not models, pipes, directives, or components.

**📦 Data Models** — interfaces, types, enums, and constants from `*.model.ts` files or `@app/shared/models`.

**🛠️ Pipes & Directives** — custom Angular pipes and directives from the app codebase.

**🧩 UI Components** — Angular components imported for use in a template's `imports` array, from `@app/*` or relative paths ending in a component file.

**🧰 Utility Libraries** — `moment`, `lodash`, general-purpose utilities that are not Angular-specific and not icon libraries.

**🎨 Icons** — `@fortawesome/*` and any other icon imports.

**📦 Third-Party Dependencies** — any remaining third-party packages that don't fit the categories above (e.g., `@fancyapps/ui`, `animate.css`, other npm packages).

---

## Worked Example

```ts
// ────────────────────────────────
// 🅰️ Angular
// ────────────────────────────────
import { Component, OnInit, signal, computed, inject, DestroyRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { takeUntilDestroyed } from '@angular/core/rxjs-interop';
import { MatDialogModule } from '@angular/material/dialog';
import { MatTableModule } from '@angular/material/table';
import { toSignal } from '@angular/core/rxjs-interop';

// ────────────────────────────────
// 📡 State
// ────────────────────────────────
import { OrderFacade } from '../../data-access/order-facade.service';
import * as orderActions from '../../data-access/state/order.actions';
import { selectLoadingAll, selectCurrentOrder } from '../../data-access/state/order.selectors';

// ────────────────────────────────
// 🧱 Application
// ────────────────────────────────
import { AuthGuardService } from '@app/core/auth/auth-guard.service';
import { ToastService } from '@app/shared/services/toast.service';

// ────────────────────────────────
// 📦 Data Models
// ────────────────────────────────
import { Order, OrderSearch, orderFields } from '../../data-access/order.model';
import { Meta } from '@app/shared/models';

// ────────────────────────────────
// 🧩 UI Components
// ────────────────────────────────
import { OrderCardComponent } from '../../components/order-card/order-card';
import { SpinnerComponent } from '@app/shared/components/spinner/spinner';

// ────────────────────────────────
// 🧰 Utility Libraries
// ────────────────────────────────
import * as moment from 'moment';

// ────────────────────────────────
// 🎨 Icons
// ────────────────────────────────
import { FontAwesomeModule } from '@fortawesome/angular-fontawesome';
import { faPlus, faTrash, faPencil } from '@fortawesome/pro-regular-svg-icons';
```

---

## Rules

- **Never add new categories.** If something doesn't cleanly fit, use the closest existing one. When genuinely ambiguous, prefer the more specific category (e.g., a facade goes under State, not Application).
- **Omit empty categories** — don't leave a divider with no imports under it.
- **One blank line** between the closing divider of one section and the opening divider of the next. No blank lines within a section between individual imports.
- **Keep the divider format exact** — 32 dashes, emoji, label. Don't abbreviate or reformat.
- **Apply to the whole file** when reorganizing — don't partially organize a file and leave the rest unsorted.