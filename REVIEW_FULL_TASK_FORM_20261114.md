disposition: fix

Scope: fresh finish review of local macOS source and seven offscreen native captures; this is not release certification or proof of live click/type, full keyboard traversal, or VoiceOver. No approved comp, concept round, or QUALITY BAR card applies to this precisely scoped extension of the incumbent native system. PRODUCT.md and DESIGN.md were supplied from the working root because the isolated artifact does not contain them. No detector ran: HTML/CSS checks do not apply to this AppKit/SwiftUI surface.

## persistence

Pass. The supplied working-root PRODUCT.md and DESIGN.md exist and establish the native SF/SF Symbols, adaptive NSColor, blue accent, and inspector-pill system. The artifact's six-block surface brief records the user request, the confirmed empty-fields answer, the top-button-only boundary, and the existing-world extension. A surface documenter update remains part of completion after fixes; no replacement global design system is warranted.

All seven required PNGs exist and were opened: empty dark/light, filled dark/light, short light, and intentionally scrolled details dark/light. Their geometry is consistent with the declared 600×680pt or 600×460pt views at Retina scale. None is blank, malformed, or mislabeled. Header and footer remain visible; details captures show the intended lower content. The packaged/debug comparison receipt reports all seven byte-identical. The test log ends with 178 passing Swift tests. These are evidence of the stated local scope only.

## fidelity

| Element / promise | Classification | Evidence |
| --- | --- | --- |
| TYPE | match | Native system typography, clear 20pt heading, larger editable title, compact property labels; matches incumbent DESIGN.md rather than a website display-face rule. |
| MATERIAL | match | Ordinary macOS controls, SF Symbols, InspectorDropdown/Pill, dividers and flat adaptive surfaces; no imitation physical material or decorative cards. |
| GROUND | match | Source uses Palette.sidebar/canvas and native adaptive colors. Both captured themes retain the incumbent neutral ground. |
| THESIS: complete the task in one pass | contradicted | Visible form provides the requested fields, but repeated smart commands can silently change the accepted value on a later recognition pass; see fix 1. |
| OWN-WORLD | match | Existing native controls, semantic date/priority/tag colors and spacing are reused. No palette or global identity change. |
| STORY: upper Task button → blank draft → save/cancel | match | MainView changes only the task branch of the upper button. Default TaskCreationDraft uses an empty Item; AppState.capture(Item) does not apply list context. Cancel only dismisses. Existing quick/menu/inline paths remain separately routed. |
| FIRST VIEWPORT | adaptation | At 680pt, title and properties plus description/checklist heading are visible; the remaining detail controls scroll under a fixed action footer. At 460pt, metadata also scrolls. This is the explicit scrollable-middle allowance in FORM, not omitted controls. Both bottom captures expose checklist and reminders. |
| FORM: native sheet and keyboard entry | contradicted | The 600pt sheet and fixed actions render as promised, but the title's Tab handler falls through to ordinary NSTextView tab insertion instead of moving focus; see fix 2. |
| Smart single command !1 → high priority, syntax removed | match | TaskCreationDraft.recognize transfers accepted priority to item.priority and replaces title with parsed.title. The filled captures show clean title and high-priority pill; model tests cover this flow. |
| Manual values / dates / invalid text | match | Only fields named by accepted tokens are replaced. Deferred date parsing preserves the complete date phrase. Unknown, invalid and literalized tokens are retained; tests cover these cases. |
| Save, cancel, errors | match | Only save commits; UUID duplicate guard, storage failure and deleted relation checks prevent a second/invalid record. Error leaves the draft and displays a recovery message. Body hashtags and task share one undoable change. Add is disabled for empty parsed title; Escape/Cancel dismiss. |

The memory test retains a native task form with a smart title, aligned property rows, and fixed Cancel/Add controls. The exact request makes a comp/concept seed inapplicable; it does not authorize a new visual world. Synthetic preview data is explicitly identified in QA and instantiated by the development renderer. No product claim, external asset, or shipping raster material is fabricated.

## ceiling

Reached for the narrow visual scope: native density, SF Symbols, semantic pills, clear grouping, theme adaptation, and stationary actions serve task entry. Additional ornament or authored motion would dilute this frequent operation. Live active-window control appearance, complete keyboard traversal, menus and VoiceOver remain unverified; the screenshots cannot certify them.

## material_fixes

1. **Smart-title correctness — preserve one recognition transaction and last-command precedence.** QuickParser consumes matches in reverse order but accepts only one project/priority token per parse. With `План !1 !3 `, the first recognize sets priority 3 and leaves `План !1 `; the title's trailing-whitespace onChange then recognizes again and silently sets priority 1. Duplicate project commands have the same issue. Consume/resolve recognized competing commands as one transaction, or otherwise prevent leftovers from being reinterpreted as new user commands. Cover pasted duplicate priority and project commands, blur/save stability, and sequential later user commands with regression tests.
2. **FORM / keyboard access — give the full-form title native focus traversal.** TaskCreationForm supplies no completion callback; SmartCaptureInput's insertTab branch returns its default false. CaptureTextView is an ordinary editable NSTextView, so this permits tab insertion rather than advancing to the next form control. Add form-scoped Tab and Shift-Tab traversal while retaining the quick input's completion behavior. Verify forward/backward focus exit from the title, no inserted tab, and that leaving the title still transfers its pending date/commands.

## keep

Keep the empty context-independent draft, clean smart title with visible semantic fields, atomic save/Undo and recoverable errors, existing quick capture routing, native SF/NSColor/pills, fixed Cancel/Add footer, and explicit source/offscreen-preview verification limits; a new release remains unauthorized.

---

Post-fix verdict — 14 November 2026. Scoring only the two material fixes above. The same seven required capture paths were reopened; all remain valid and visually unchanged. The final-preview receipt confirms their hashes match the previously reviewed captures. The exact-source log now ends with 180 passing Swift tests after 3.697s.

## verdict

1. **Resolved — smart-title recognition transaction.** The full-form draft and its parsed preview opt into `consumeRedundantCommands`; accepted competing priority/project commands are removed together while the selected last matching value persists. The regression verifies `План !1 !3 /Первый /Второй ` becomes clean `План ` with priority 3/project Второй, survives repeated recognition and save, and accepts later new commands. The default parser remains unchanged for quick capture. The recaptures retain the clean title and visible semantic fields, with no visual regression.
2. **Resolved — title focus traversal.** The form opts into `tabMovesFocus`; the coordinator handles Tab and Shift-Tab through native `selectNextKeyView`/`selectPreviousKeyView` and consumes those commands. Its probe-window regression verifies both forwarding directions, unchanged title text, and preserved quick-input completion. This verifies the source behavior that caused the finding, not the complete live sheet key-view loop. The same native controls/layout remain in all recaptures.

## remaining

Clear for the scored fixes; no regressions from this fix batch found in the supplied source/tests or seven recaptures. This ship verdict covers the two scored fixes only, not the whole surface or release certification. Live top-button click, typing, full sheet keyboard traversal and VoiceOver remain unverified, and a new release remains unauthorized.

disposition: ship
