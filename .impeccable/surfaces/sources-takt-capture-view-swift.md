# Пути проекта и этапа в умном вводе

Mode: Operate. Narrow extension of native CaptureView / SmartCaptureInput / TaskCreationForm and web smart capture. Preserve existing SF Symbols, system fonts, Palette and semantic project colors, sizes and instant keyboard behavior. No new animation, images or visual world; global DESIGN.md, PRODUCT.md and sidecar preserved.

User: `/Личное/Спорт` selects an existing project and stage; old `/"Личное"/"Спорт"`, mixed quoted paths and project-only commands remain compatible. Ordinary multiword names also omit quotes: `/Личное пространство/Спорт силовой`. Matching uses the longest existing active task-project/stage name. Names containing slash, quote or backslash use JSON-style quoted/escaped components; stored names stay literal.

Confirmed fallback: an unknown stage selects only the known project, `Без раздела`, with an explanatory warning; no stage is created. An unknown unquoted component stops at whitespace, leaving subsequent words in the title. An unknown project remains title text.

Quality bar: valid stage survives parser → form/quick capture → SQLite → account wire round trip; path is one UTF-16 project token, Backspace opt-out preserves it; project suggestions replace the entire unfinished path and show its stage. Full form defers project paths until blur/save to avoid consuming multiword prefixes. Preserve priority/date/tag behavior and blank form defaults.

Persistence: Item.projectID remains UUID?, Item.section remains String, Project.sections remains [String]; ParsedTask.section is transient and QuickTokenKind is unchanged. No schema migration or new visual tokens.

Evidence: all eleven captures in `.impeccable/review/project-path/` inspected: native offscreen dark/light forms and suggestions, live CUA native form/saved inspector, browser desktop/mobile fixtures. QA reports native form blur/save and inline Return completion/save plus valid/unknown-stage web saves; 191 Swift, 45 Python and 28 JS tests passed. Shared parser/suggestion/helper behavior is covered automatically. No approved comp: code-led extension of incumbent UI. `REVIEW_PROJECT_PATH_20261117.md`: ship for the local scope, no material fixes; `DOCUMENT_PROJECT_PATH_20261117.md`: documentation complete.

Limits: physical iPhone, VoiceOver and live global Control-Q were not checked. No release authorized; installed application, personal data and production server were not changed.
