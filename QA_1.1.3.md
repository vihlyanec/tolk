# Выпуск 1.1.3 / build 41 — 9 ноября 2026

Пользователь явно разрешил выпуск сообщением «релиз» после проверки исправления видимости капли.

Точный исходник подписанного ZIP: b7d75737e8d5e2abc39b55e6c268e39c38b63966. Опубликована Latest: https://github.com/vihlyanec/tolk/releases/tag/v1.1.3, draft=false. Все4 public assets и стандартный latest appcast скачаны без авторизации и побайтово соответствуют подписанным локальным файлам по SHA-256. Скачивания: /private/tmp/tolk-113-public-downloads.

## Изменение

FocusEdgeController показывает боковой таймер только при существующем сеансе с положительным остатком времени: отсчёт или пауза, включая перерыв. При истечении срока отменяемая expirationTask вызывает sync и скрывает окно, не ожидая новой пользовательской операции. При паузе это ожидание отменяется. На 00:00 и без сеанса явный Show не открывает окно; запуск следующей фазы снова показывает его. Сохранённый законченный сеанс доступен в основном Помодоро. Внешний вид FocusEdgeTimerView побайтово совпадает с 1.1.2 (проверено исходное тело View), размеры, #FF9230, фон и обводка сохранены.

## Проверки

- 158 Swift tests passed на точном исходнике, включая 3 новые регрессии: отсутствие окна без остатка, автоматическое скрытие при deadline и возвращение для запущенной фазы, сохранение окна на паузе после прежнего deadline. Используются in-memory Demo и реальный NSPanel.isVisible.
- 34 Python web +24 JavaScript +14 release-script Python tests passed.
- CI42684362849 полностью success (macos + web, включая universal) на b7d7573: https://github.com/vihlyanec/tolk/actions/runs/42684362849.
- Universal arm64+x86_64, обе minimum macOS14 / linked SDK27. Извлечённый ZIP — 1.1.3/build41, deep strict codesign pass с системным trust store; прежний DR и SHA-256 pin публичного сертификата совпали. Независимая CryptoKit Ed25519 проверка ZIP прошла. Закрытые ключи не экспортировались и не менялись. Все3WAV совпали с одобренными.
- Draft target b7d7573, четыре assets загружены из manifest; publish повторно сверяет digests.

Артефакты /private/tmp/tolk-edge-release-artifacts-final/v1.1.3 и build/releases/v1.1.3. Чистая сборочная копия /private/tmp/tolk-edge-release-clean теперь на b7d7573, scratch /private/tmp/tolk-edge-release-build. Исходник 1.1.2 доступен по a9e4920, его подписанные артефакты не менялись. Git objects новых commit/tree/blob перенесены в чистую копию побайтово вне File Provider; исходные SHA сохранены.

Установленное /Applications/Толк.app, личные данные, сервер и интеграции агент не менял. Новый визуальный рендер не требуется для изменения только lifecycle окна; фактическая видимость проверена unit tests. Известные ограничения живого баннера/notification action, fullscreen и VoiceOver из QA_1.1.2.md не объявляются исправленными этим выпуском.

GitHub подтвердил draft=false, isLatest=true, target b7d75737e8d5e2abc39b55e6c268e39c38b63966. Все результаты в /private/tmp/tolk-113-public-downloads/verification.json. main содержит исходник выпуска и последующую QA-документацию.
