---
name: clean-typescript
description: Use this skill when writing, reviewing, or refactoring TypeScript code. Invoke for questions about enums vs const objects, type vs interface, nullability patterns, error typing, generics, function signatures, or any situation where TypeScript design choices are being made. Use it proactively when generating new TypeScript — don't wait to be asked.
---

# Clean TypeScript

**TypeScript is a correctness and clarity tool, not ceremony.** Every type annotation should either catch a real bug or make intent clearer to the next reader. If it does neither, it's noise.

---

## Type vs. Interface

Prefer `type` for most things. Use `interface` when you specifically need declaration merging or a publicly extendable shape — the kind of thing a library consumer would `extend`.

```ts
// ✅ type alias — covers the majority of cases
type UserId = string;
type ApiResponse<T> = { data: T; status: number };

// ✅ interface — appropriate when consumers will extend it
interface Plugin {
  name: string;
  execute(): void;
}
// third-party code can do: interface MyPlugin extends Plugin { ... }

// ❌ interface for an internal, non-extendable shape — no benefit over type
interface Coordinates { lat: number; lng: number; }
// just use: type Coordinates = { lat: number; lng: number }
```

The practical difference is small for internal code. The distinction matters most at API boundaries.

---

## Enums

Avoid TypeScript `enum`. They emit real JavaScript objects at runtime, produce surprising reverse-mappings for numeric enums, and can interfere with tree-shaking. Use union types for simple sets of values, and `as const` objects when you need both the type and a runtime iterable.

```ts
// ❌ enum — unexpected JS output, reverse-mapping surprises
enum Direction { Up, Down, Left, Right }
// compiles to: { 0: 'Up', Up: 0, 1: 'Down', Down: 1, ... }

// ✅ union type — zero runtime cost, clear intent
type Direction = 'up' | 'down' | 'left' | 'right';

// ✅ as const object — when you need runtime access to the values
const Direction = { Up: 'up', Down: 'down', Left: 'left', Right: 'right' } as const;
type Direction = typeof Direction[keyof typeof Direction];
// Direction.Up === 'up' at runtime, and Direction is iterable
```

---

## Nullability

Handle `null` and `undefined` explicitly through control flow and type guards. Non-null assertions (`!`) suppress the type error without fixing the underlying uncertainty — they're technical debt that becomes a runtime crash.

```ts
// ❌ non-null assertion — hides the problem
const city = user!.address!.city;

// ✅ control flow narrowing — explicit about what can go wrong
if (!user?.address) return;
const city = user.address.city;

// ✅ type guard for unknown shapes
function isUser(value: unknown): value is User {
  return typeof value === 'object' && value !== null && 'id' in value;
}
```

Prefer `unknown` over `any` for values whose type you don't know yet — it forces you to narrow before use, which is the point.

```ts
// ❌ any — silences the compiler entirely
function parseConfig(raw: any) { return raw.timeout; }

// ✅ unknown — you must narrow before accessing properties
function parseConfig(raw: unknown) {
  if (typeof raw !== 'object' || raw === null) throw new Error('Invalid config');
  return (raw as { timeout?: number }).timeout;
}
```

---

## Error Handling

Type your errors explicitly rather than catching `unknown` and hoping. Result objects make error states part of the function's public contract rather than a surprise branch.

```ts
// ❌ error state is invisible in the return type
async function fetchUser(id: string): Promise<User> {
  const res = await api.get(id);
  return res.json(); // can throw — caller doesn't know
}

// ✅ result object — success and failure are both typed
type Result<T, E = Error> = { ok: true; value: T } | { ok: false; error: E };

async function fetchUser(id: string): Promise<Result<User, ApiError>> {
  try {
    const user = await api.get<User>(id);
    return { ok: true, value: user };
  } catch (e) {
    return { ok: false, error: toApiError(e) };
  }
}

// caller is forced to handle both cases
const result = await fetchUser(id);
if (!result.ok) { showError(result.error); return; }
doSomething(result.value);
```

Throwing is still appropriate for truly unexpected states (programmer errors, invariant violations). Use result objects for expected failure modes — network errors, not-found, validation failures.

---

## Functions & Generics

Explicit return types on public functions make the contract visible without reading the body. They also catch the common mistake of accidentally returning `undefined` from one branch.

```ts
// ❌ return type inferred — caller has to read the implementation
function formatDate(date: Date) { ... }

// ✅ explicit return type — contract is at the signature
function formatDate(date: Date): string { ... }
```

Keep generics as narrow as the constraint actually requires. An overly broad generic (`<T>`) signals that the function doesn't actually care about the type — in which case `unknown` is more honest.

```ts
// ❌ generic that doesn't constrain anything
function first<T>(arr: T[]): T | undefined { return arr[0]; }
// fine here, T is genuinely needed

// ❌ generic used as any
function log<T>(value: T): void { console.log(value); }
// just use: function log(value: unknown): void
```

Avoid function overloads unless two genuinely distinct call signatures are needed. Overloads with subtle differences invite misuse. A well-named helper function is almost always clearer.

---

## General Principles

**Types should explain intent.** If a type requires a comment to explain what it means, rename it. `UserId` is better than `string`, `PositiveInteger` is better than `number`.

**If a type is hard to write, it's probably wrong.** Complex conditional types and mapped type gymnastics often signal that the underlying data model needs simplification, not that the types need to be cleverer.

**Inference is fine when it's obvious and stable.** Don't annotate every local variable. Do annotate function parameters, return types, and anything that crosses a module boundary.

```ts
// ✅ let inference do its job for local variables
const items = ['a', 'b', 'c']; // string[] — obvious
const count = items.length;    // number — obvious

// ✅ annotate at boundaries
export function processItems(items: string[]): ProcessedItem[] { ... }
```