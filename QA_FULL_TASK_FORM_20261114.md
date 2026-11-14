# Полная форма новой задачи — 14 ноября 2026

Пользователь попросил открывать всю форму по верхней кнопке «Задача», сохранив умное название: !1 убирается и задаёт высокий приоритет. На уточнение о контексте ответил: **«Всегда начинать с пустых полей»**. Форма не наследует проект, дату, теги или быстрый черновик текущего раздела. На этапе локальной проверки новый Mac-релиз ещё не был разрешён; последующее разрешение и публикация описаны ниже.

## Реализация

MainView представляет TaskCreationForm нативным sheet. TaskCreationDraft владеет локальным Item до «Добавить»; отмена не пишет задачу или пользовательские настройки. Стандартные значения: Входящие/Без даты/Без приоритета/Не повторять, длительность30мин; контекст списка игнорируется. Глобальный быстрый захват, меню/горячая клавиша и inline строка сохраняют своё поведение.

Используется QuickParser, SmartCaptureInput, InspectorDropdown/Pill, TaskDatePopover, DurationControl, MarkdownEditor и существующие редакторы напоминаний. Есть проект/раздел, дата/время, приоритет, длительность, повтор/интервал, теги, описание, чек-лист, timed/all-day напоминания. Форма600×680pt ограничивается высотой экрана, середина прокручивается; header и Cancel/Add закреплены. SF/адаптивные NSColor/синий акцент сохранены, анимации не добавлены.

!1/проект/теги/длительность применяются по завершении слова пробелом или выходе из названия. Даты и время подсвечиваются, но переносятся при выходе/сохранении целиком, чтобы «12 дек » не съело год и последующее время. Принятые команды удаляются, неизвестные/невалидные остаются буквальными с предупреждением. Не затронутые новой командой ручные поля сохраняются. Программная очистка сохраняет UTF16 caret/selection и emoji. Shift-Return переводит в описание; Add/Return в названии и Cmd-Return добавляют, Escape/Отмена закрывают.

AppState.capture(Item) сохраняет именно draft, без default текущего списка; старый capture(ParsedTask) сначала применяет свой прежний контекст, затем использует общий commit. Проверяются актуальность project/tag и дублированиеUUID. Bodyhashtags сохраняются в той же undo-транзакции. Ошибка оставляет черновик; удалённый тег можно убрать из формы и повторить.

## Проверки

**180 Swift tests passed**, включая11новых регрессий: пустое начало/независимыйquickdraft; команды+ручные значения; unknown/invalid/literal; дата, вводимая по словам; контекст-free save/детали/duplicate/Undo; удалённый проект; UTF16 caret/selection; удалённыйтег+retry; заблокированное тестовое хранилище без создания задачи. Все данные синтетические, SQLiteпути временные. Diff check чистый.

Локальное arm64 Demo minimum14/SDK27, strict ad-hoc codesign. Семь действительных native captures в .impeccable/review/full-task-form/: empty/filled dark+light, short460light, details-scroll dark+light. Это реальные offscreen SwiftUI/AppKit компоненты с вымышленными данными, не живое нажатие в установленном приложении. Просмотрены все7файлов. MainView button/sheet связь проверена по source, модель/commit — тестами.

Запросы запуска тестов один раз были остановлены technical automatic approval HTTP403 и позднее review deadline; действия не выполнялись. Короткие повторы прошли проверку разрешения и тесты выполнены; обхода approval не было.

CUA getState дважды завершился timeout/reset10/21сек; приложения не выбирались/не запускались. Completion: «Зафиксировал недоступность управления Mac». Реальный click/type/menus/keyboard traversal sheet и VoiceOver остаются неподтверждёнными. Установленный Толк, личные задачи, сервер и публичные релизы не менялись.

HTML/CSS detector не применим к нативному AppKit/SwiftUI. Context загружен один раз; отсутствие buildPath и нераспознанное skill-platform macos — прежний дрейф инструментальной документации. Глобальные PRODUCT/DESIGN/sidecar не менялись. Новое surface-only описание фиксирует границы текущей формы.

## Review

Первый fresh finish-review: disposition fix, две material issues — повторное распознавание оставшихся competing commands меняло last choice и Tab вставлял tab в NSTextView. Исправлено: QuickParser.consumeRedundantCommands opt-in только для полной формы, defaultfalse сохраняет quick semantics; form-only tabMovesFocus вызывает selectNextKeyView/selectPreviousKeyView, quickcompletion неизменен. Новые regressions проверяют paste→повторные blur/save→новые команды, default QuickParser, native coordinator forwarding в невидимом probe NSWindow и quickcompletion. После исправлений180tests passed. Финальная arm64minimum14/SDK27strict ad-hoc Demo пересобрана. Те же7состояний сняты заново, побайтово совпали с ранее валидными captures; receipt /private/tmp/tolk-full-form-final-preview.json. Reviewer verdict pass: **ship**, обе material fixes **resolved**. Это оценка этих двух исправлений, source/tests и preview, а не сертификация всей поверхности или разрешение на выпуск. Documenter проверил source/180tests/все7PNG и сохранил глобальные DESIGN/PRODUCT/sidecar; изменён только новый surface brief. DOCUMENT_FULL_TASK_FORM_20261114.md содержит evidence и hashes.

В рабочий корень перенесены7source/test файлов после сверки5baseline файлов на1882453. Все7SHA256 совпадают с tested/reviewed source. DurableDemo и7PNG/logs/receipts в build/full-task-form; копияDemo после очистки FileProvider metadata прошла strictcodesign. Код/документы локальные, не закоммичены и не опубликованы. Worktree /private/tmp/tolk-full-task-form (codex/full-task-form, base1882453), scratch/private/tmp/tolk-full-form-build. Следующий Mac-релиз требует нового разрешения.

## Выпуск 1.1.7

После просмотра формы и сообщения о пределах проверки пользователь ответил «релизим». 1.1.7/build45 опубликована Latest14ноября2026, source b58be50, CI43621651070success. Подписи/SDK/7PNG и4publicasset/latestappcast проверены; QA_1.1.7.md содержит итог. Publication не расширяет scoped reviewer verdict или live click/type/полный sheet traversal/VoiceOver evidence. Установленное приложение и личные записи не менялись.
