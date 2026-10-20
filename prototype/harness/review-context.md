# Review context: iOS planner prototype (web mock-up on a design canvas)

## What is being reviewed
- Source: `/tmp/claude-0/-home-user-calc-pedant/8e002c7c-0888-5764-8ca8-3488a9936005/scratchpad/planner-canvas/project/Main.dc.html`
  One self-contained "Design Component" file: an HTML template inside `<x-dc>` plus a logic class in `<script data-dc-script>`.
  It renders a 390x844 phone screen. Other `*.dc.html` files in that folder only import `Main` with a `scene` prop.
- Rendered screenshots (Chromium, 2x scale, Linux fallback fonts instead of SF Pro, so text is ~5-8% wider than on a real iPhone):
  `/tmp/claude-0/-home-user-calc-pedant/8e002c7c-0888-5764-8ca8-3488a9936005/scratchpad/harness/out3/`
  - `Main.png` day view (today, pinned to 12:00), `ThreeDays.png`, `List.png` (week as list), `Matrix.png` (Eisenhower), `Backlog.png` (drawer open),
    `Drag.png` (a backlog task being dragged over 16:00), `Resize.png` (task selected: resize handle + duration chip), `Overdue.png` (overdue sheet with move options), `Voice.png` (voice result).
  - `ix-*.png` are taken during a scripted interaction run: 01 selected, 02 resizing (handle dragged), 03 resized, 04 dragging from backlog while hovering weekday tab "22" (day switched), 05 dragging over the column (time preview),
    06 dropped + auto-selected, 07 dragging a timeline block over the drawer, 07b a short block moved 2h up, 08 drawer opened by swipe, 09 quick-add toast, 10 view menu, 11 matrix drag between quadrants, 12 matrix after drop, 13 after "fit overdue into today", 14 three-day view with a selected block.
- Automated results: all 17 interaction checks pass; a DOM overlap scanner reports nothing except the "now" line's 10px dot poking out of its 2px line (intentional).

## The user's requirements (Russian original, then meaning)
1. "менять продолжительность задачи прямо на экране календаря тапом по таску и растягиванием" — change a task's duration right on the calendar: tap the task, then stretch it.
2. "добавь вид матрицы эйзенхауэра и цвета должны быть привязаны к четвертям: красный важное срочное, желтый важное не срочное, синий не важное срочное и серый" — add an Eisenhower matrix view; colours bound to quadrants: red = important+urgent, yellow = important+not urgent, blue = urgent+not important, grey = neither. The same colours must be used everywhere a task appears.
3. "если я вытягиваю что-то из бэклога, то я могу протянуть это по таймлайну и по дням и бросить задачу" — pulling a task out of the backlog, I can drag it along the timeline AND across days, and drop it.
4. "бэклог по свайпу должен тоже открываться; все задачи в бэклог пихай сверху новые, снизу старые" — the backlog drawer must also open with a swipe; newest backlog tasks on top, oldest at the bottom.
5. "один экран без таббара, только иконки сверху, остальное рабочее" — one screen, no tab bar, only icons at the top, the rest is the working surface.
6. "мне нравится, как реализована фишка овердью" (from Todoist) — keep the Overdue button/sheet idea.
7. "Поработай над UI так, чтобы всё было максимально вылизано и не заходило друг на друга" — polish the UI: nothing may overlap or collide, spacing/alignment consistent.
8. Earlier: Russian natural-language quick add; voice input mock.

## Intentional decisions (do not report as defects)
- Time is frozen at 13:40 for the demo; dates are real (today = 20 Oct 2026).
- Dark theme, mint accent #3EE0A6, system font stack (SF on iOS).
- Done tasks are dimmed and struck through; routines (daily) never show as overdue.
- The drag ghost is rotated -2deg and follows the pointer; it may overlap the header while dragging.
- The "now" line's dot is wider than the line.
- Backlog drawer: 130px collapsed (header + input row), opens to 130 + up to 6 rows.
- Screenshots use fallback fonts (DejaVu/Liberation) — slight text-width differences vs iOS are not defects, but anything that would ALSO break with SF Pro is.

## Key rules of the .dc.html format (for the format lens)
- `{{ hole }}` must be a dotted lookup only (no expressions); values come from `renderVals()`.
- Events use JSX camelCase attribute names (`onClick`, `onPointerDown`, ...) bound to functions from renderVals.
- `<sc-if value="{{ cond }}" hint-placeholder-val="{{ true|false }}">`, `<sc-for list="{{ items }}" as="x" hint-placeholder-count="N">`.
- Every non-void element must be closed, every attribute quoted; no emoji; icons are inline stroke SVG with aria-hidden or role=img.
- Logic: `class Component extends DCLogic`, classic JS, no imports; React class lifecycle available; `renderVals()` returns template inputs.
- Accessibility: real `<button>`/`<input>`+`<label>`; aria-label on icon-only buttons; hit targets >= 44px in mock content where feasible; text contrast >= 4.5:1 (3:1 at 24px+).
- `data-props` is single-quoted JSON on the script tag.
