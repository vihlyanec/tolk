# Сверка требований «Толка»

26 октября 2026. Базовый публичный выпуск: 1.0.1 / 25, commit 568aff2. Установленный Mach-O совпадает с бинарником архива 1.0.1 по SHA-256. Для проверки публичного приложения используется копия того же бинарника с идентификатором Demo и данными в памяти.

Наличие реализации и автоматическая проверка не заменяют физический жест, системное уведомление или прослушивание звука. В таблице эти уровни разделены. Публикация 1.0.0 и 1.0.1 сама по себе не вырезала перечисленные модули; найдены ошибки взаимодействия и неполные сценарии.

| Запрос из чата | Реализация / проверка | Результат аудита |
|---|---|---|
| Ctrl-Q из любого приложения | HotKeys, App.openQuick; Carbon global hotkeys | Есть; при конфликте используется Ctrl-Shift-Q, статус в настройках |
| / проект, # тег, ! приоритет | QuickParser, CaptureView, CaptureBehavior | Есть; общие автоматические проверки |
| Enter сначала применяет команду | commandEnterAppliesBeforeCreating | Есть |
| Enter создаёт, Escape отменяет; компактная строка без системной шапки | KeyPanel, QuickCaptureView | Есть; публичная UI-копия проверяется отдельно |
| Разные цвета распознанных команд и приоритетов | SmartCaptureInput, SemanticTint, CaptureRecognitionTests | Есть |
| Delete превращает распознание в текст, пробел сохраняет распознание | CaptureLiteralTests, CaptureRecognitionTests | Есть |
| «через месяц», «через час», «полчаса», «через 10 минут» | QuickParser, naturalRelativeTimesAndDurations | Есть |
| Shift-Enter раскрывает описание | CaptureDescriptionTests, CaptureTextView | Есть; глобальная и встроенная строки |
| Длительность в быстром вводе | DurationControl, parsed duration | Есть |
| Встроенная строка создания в списках | InlineQuickEntry | Есть |
| Полные метаданные строки, цветные капсулы тегов/приоритетов | TaskRow, Metadata, SemanticStyle | Есть |
| Обновление строки сразу после правки | existingRowReadsEditsWithoutChangingScope | Есть |
| Список, группировки, сортировки; Kanban по проекту | TaskListView, AppState.groups | Есть |
| Удаление и восстановление задач, удаление тегов | InteractionTests, ItemContextMenu | Есть |
| Компактный инспектор без дублирования приоритета | ItemInspector, InspectorDropdown | Есть |
| Убрать подпись «Вид», выровнять встроенный ввод | labelsHidden, CaptureTextView vertical centering | Есть |
| Проекты и теги: создание, яркие цвета и расширенная палитра | CreationSheet, ProjectTagPalette | Есть |
| Случайный свободный цвет нового проекта/тега | CreationColorTests | Есть |
| Перестановка проектов | acceptProjectDrop, moveProject | **Исправлено в 1.0.2:** старый drop вставлял только перед целью, движение вниз могло ничего не менять; новый native drop различает верх/низ строки |
| Перенос задачи из списка в проект | ProjectTaskDropTests, Sidebar drop | Есть; перенос задачи сохраняется в новом native drop |
| Счётчики папок, проектов, тегов и разделов | AppState.taskCount/folderTaskCount | Есть; **исправляется:** тег должен считать и показывать также заметки |
| Боковая панель компактнее, текст и число не перекрываются | Sidebar 252pt, layoutPriority, fixedSize badges | Есть |
| Различимые иконки навигации | checklist, calendar, square.and.pencil | Есть |
| Убрать застревающую синюю рамку, сохранить клавиатуру | IconButton focusEffectDisabled, NSTextView focusRingType | Есть; визуальная аппаратная проверка отдельно |
| Календарь: неделя с почасовой сеткой, удобная геометрия | CalendarView, DayColumn | Есть |
| Все семь дней при уменьшении окна | GeometryReader, dayWidth от доступной ширины | Есть; render 1080/1280/1680 |
| Параллельные задачи рядом | CalendarLayout, identicalHourTasksShareDayWidth | Есть |
| Цветные полупрозрачные плашки; непрозрачность при наведении/выборе | CalendarEvent.emphasized | Есть |
| Перенос из очереди на календарь | CalendarDropDelegate, QueueReturnTests | В 1.0.1 исправлен конфликт внутренней кнопки; перенос данных проверен, физический жест требует проверки |
| Изменение длительности за край, граница следует курсору | CalendarResizeRegion, CalendarResizeMath | Есть; непрерывная геометрия и snap в конце |
| Создание временного интервала протягиванием | DayColumn.creationRange | Есть |
| Выполнение прямо из календаря; выполненная задача остаётся | calendarRetainsCompletedTasksIndependentlyOfListPreference | Есть |
| Будущие повторения при переходе недели | RecurringCalendarTests, calendarItems | Есть; исключения и старые цепочки покрыты |
| «Через X дней» | intervalDays, repeatEveryDays, CoreTests | Есть |
| Дата и время через собственный календарь | TaskDatePopover | Есть |
| Для «Весь день» скрыть длительность | ItemInspector.scheduling | Есть |
| Много задач на весь день не теряются | ScrollView области all-day в 1.0.1 | Есть; 14 задач в render, прокрутка отдельно от часов |
| Очередь: поиск, фильтры, сортировка | queueFilteringSortingAndCountsStayIndependentOfMainSearch | Есть |
| Фильтр «Без времени» | withoutTimeQueueIncludesDatedAndUndatedTasksButNeverTimedTasks | Есть |
| Компактные одинаковые карточки очереди | PlanningQueue.queueCard, фиксированная высота | Есть |
| Очередь «Все»: клик открывает задачу | собственный editingID, onTapGesture, keyboard Return | Есть; публичная копия открывает инспектор |
| Возврат в очередь снимает время, сохраняет дату; «Без даты» снимает обе | QueueReturnTests | Есть |
| Свайп двумя пальцами перелистывает неделю, уменьшить чувствительность | CalendarSwipeAccumulator: 150pt, dominance 1.8 | Есть; физическое ощущение не заменяется тестом |
| «Сегодня»: просроченные + «Отложить» | todayIncludesOverdueAndPostponesAsSingleUndoableChange | Есть |
| Раздельные настройки нескольких напоминаний для времени/всего дня | NotificationPlan, ReminderControls, SettingsView | Есть |
| Уведомление с иконкой и звуком, устранить дубль старого «Такт» | Reminders, NotificationPlan; legacy cleanup и отдельные attachment files | Есть; настоящая доставка зависит от разрешений macOS и проверяется отдельно |
| Звук и тактильная отдача при выполнении | CompletionFeedback, completionFeedbackFollowsSuccessfulCompletionOnly | Есть; Force Touch / слышимость требуют физической проверки |
| Ctrl-D: плавающий стикер | HotKeys, App.openSticky | Есть |
| Двойной клик по краю сворачивает стикер в полоску, перемещение и восстановление | StickyGeometry, StickyDragRegion, InteractionTests | Есть |
| Заметки как Apple Notes: список слева, документ справа | NotesWorkspace, NoteDocumentEditor | Есть; публичная 1.0.1 показывает эту компоновку |
| Один режим заметки с немедленным форматированием | RichNoteEditor, RichNoteTests | Есть; дополнительно приводится к нему запасной note-inspector |
| Расширенный Markdown и кликабельные ссылки | MarkdownHTML, RichNoteEditor, TagTextView | Есть; таблицы, код, списки, чек-листы, ссылки; полной совместимости со всеми Markdown-диалектами не заявляется |
| # работает в заметках и описаниях | Hashtags, TagTextView, RichNoteEditor | **Исправлено в 1.0.2:** конечный новый тег терял завершение из-за нормализации Markdown; добавлен commit по пробелу/Enter/выходу из поля |
| Нажать тег и найти заметку | AppState.items, NotesWorkspace, FlowTags | **Исправлено в 1.0.2:** общий тег раньше исключал kind=note; добавлены общий состав результатов, переход в документ и фильтр тегов списка заметок |
| Название «Толк», логотип и иконка | Info.plist, BrandIcon.png, AppIcon.icns | Включены в публичный архив |
| Обновления через GitHub, сохранение собственных данных пользователей | AppUpdater, UpdateConfiguration, release.py | 1.0.0 обнаруживает 1.0.1; данные вне bundle, в ZIP их нет |
| Инструкция при блокировке Apple | INSTALLATION.md и описание релиза | Есть; DMG сам по себе не заменяет Developer ID / notarization |
| TickTick-синхронизация | TICKTICK_SYNC_PLAN.md, Experiments вне сборки | Отложена по явному запросу пользователя, в этот аудит внедрение не входит |

## Новые регрессионные проверки

ReleaseParityTests проверяют перенос проекта вниз после цели и вверх перед целью с Undo; заметку и задачу с общим тегом; группировку теговых результатов по проектам; открытие заметки документом; создание заметки в выбранном теге; создание конечного тега без промежуточных тегов на каждую букву. RichNoteTests проверяет реальное сообщение commitTags из WebKit после пробела.

## Проверка исправленной версии

75 Swift-тестов и 7 Python-проверок выпуска прошли. В живом Demo назначен тег #идеи заметке: нажатие капсулы оставляет её в списке с фильтром; общий раздел #идеи показывает три задачи и одну заметку, счётчик 4; нажатие найденной заметки открывает полноценный документ с фильтром #идеи и форматированным телом. Записи вымышленные.

Нативный CUA drag возвращает noWindowsAvailable до отправки события; физическое перетаскивание проекта и ощущение трекпада этим аудитом не подтверждаются. Автоматически проверены оба направления перестановки, назначение проекта задаче, Undo, системный текстовый payload, обработка заметок, WebKit-форматирование и сообщение завершения тега. Системные баннеры, слышимость и Force Touch не воспроизводились на личных задачах.
