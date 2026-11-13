# Выпуск 1.1.6 / build44 — 13 ноября 2026

Пользователь разрешил публикацию ответом «давай» на вопрос «Релизим?» после просмотра формы и сообщения об ограничениях живой проверки. Разрешение относится к Mac-релизу с глобальной заметкой паузы. Сервер/установленное приложение/личные данные не меняются.

## Исходник и проверка

Глобальная centered nonactivating KeyPanel, заметка рядом с paused timer, сохранение прежнего значения и отсутствие failed sync publication при ошибке. Детали QA_GLOBAL_FOCUS_PAUSE_20261113.md и REVIEW_GLOBAL_FOCUS_PAUSE_20261113.md. Final implementation169Swift tests passed, локальная arm64 min14 SDK27 strict ad-hoc сборка и4native captures. Источники root и clean checkout совпадают по SHA256.

Нативный source, notes и surface/QA документы сохранены в release commit. Точный source_commit фиксирует manifest. Подписи, universal, CI, visual ZIP comparison и публичные download hashes будут внесены после проверки.

## Ограничения

Реальные global keyboard input/неактивация другого приложения, pointer hover/fullscreen/Spaces и VoiceOver остаются неподтверждёнными: CUA видел Stage Manager thumbnails, popupVisible/key audit не установил inactive-app case. Пользователь получил это ограничение до разрешения на публикацию. Новый релиз не превращает offscreen capture или scoped reviewer verdict в проверку этих сценариев. Ранее известные notification/Gatekeeper/Intel-device/macOS14-device ограничения сохраняются.
