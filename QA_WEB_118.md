# Веб-выпуск путей проекта и этапа — 17 ноября 2026

Разрешение: пользователь «релизим»; parent подтвердил source 235bd123e5d1153b346979535959c9248cbbc4e9 и выполнение веб-деплоя. Старый SSH ControlMaster отсутствовал, обычный BatchMode отклонён publickey/password. Пользователь открыл новую foreground master-сессию /private/tmp/tolk-118-ssh/control; её средствами выполнен deploy. Пароли и ключи не читались.

В 17:26 МСК (14:26UTC) обновлены только public/smart.js, public/app.js, public/sw.js, public/index.html. Все4 исходных SHA совпали с main452be23; неизменные server/wsgi.py и compose.yaml также совпали. Проверены существующие контейнеры webhealthy/pushrunning и read-only bind mount /opt/tolk-web/public→/app/public. WSGI читает static assets на запросе, поэтому рестарты/HUP не понадобились. Docker/host/Nginx/соседние службы не менялись. Миграций базы нет.

До файловых изменений сделана online SQLitebackup /opt/tolk-web/data/backups/20261117T142639857639Z-before-project-path-118.sqlite, 9342976bytes, quick_check ok при создании и независимом повторном чтении. Существующие backups не удалялись и не перезаписывались. Старые4файла сохранены в /opt/tolk-project-path-before-118-20261117T142639857639Z. Атомарные замены имеют проверку SHA, исходных owner/mode и guarded rollback; откат не потребовался. Receipt /opt/tolk-project-path-118-20261117T142639857639Z-receipt.json.

Host и loopback-served SHA всех4файлов совпали с source235bd123. Дополнительно все4публичных HTTPS asset и2versionedURL (app.js?v=20261117-project-path, smart.js?v=20261117-project-path) скачаны без авторизации на Mac и совпалиSHA256. API/session200 с accountnull; POSTcapture/options без credentials401, capture401, cross-origincapture403. Ключи capture не создавались/не читались/не отзывались, личные записи не менялись радиQA. Serviceworker cachev10, index/app import version20261117-project-path. Пользователю достаточно обновитьстраницу.

Локальные функциональные тесты родительской задачи:191Swift+45Python+28JS; здесь повторно не запускались. ФизическийiPhone/VoiceOver/liveglobalControlQ по-прежнему не проверены. HTTPS/SHA/authcheck не расширяют scopedUIreview.

Доказательства рядом: deploy.py и deploy-template.py, payload-sha256.json, preflight.json, deployment.json, public-before.json, public-verification.json, summary.json и скачанные before/afterpublic assets. Все данные в этих файлах публичные исходники или неперсональные operationalmetadata; privateconfigs/credentials не включены.
