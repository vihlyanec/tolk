# Выпуск1.1.7 / build45 — 14 ноября2026

Пользователь разрешил публикацию словом «релизим» после сообщения о полной форме и пределах живой проверки. Это разрешение на новый Mac-релиз. Установленный Толк/личные записи/сервер не меняются.

Изменение: верхняя «Задача» представляет полную native форму с независимым пустым draft и умным названием. Синтаксис приоритета/проекта/тега/длительности переносится в поля по завершении команды, дата/время — при blur/save целиком. Ручные поля сохраняются, duplicate commands атомарны, Tab/ShiftTab form-only; общий quick сохранил default семантику. Детали QA_FULL_TASK_FORM_20261114.md, REVIEW_FULL_TASK_FORM_20261114.md и DOCUMENT_FULL_TASK_FORM_20261114.md.

Финальный локальный source:180Swift tests passed, arm64minimum14/SDK27strict ad-hoc Demo,7validnative captures. Root11source/docs побайтово совпали с tested/reviewed worktree до release notes. Source commit фиксирует manifest; CI/universal/signatures/ZIP renders/public download verification будут внесены по результату.

Живое нажатие верхней кнопки, ввод, полный key-view порядок sheet и VoiceOver не подтверждены: CUA дважды timeout/reset без выбора приложения. Пользователь знал это до разрешения. Offscreen компоненты и невидимое probe окно не доказывают живой workflow. Прежние ограничения notification/fullscreen/Gatekeeper/Intel-device/macOS14-device сохраняются. Следующий выпуск требует нового разрешения.
