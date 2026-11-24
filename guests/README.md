# Гостевые системы Linux (дистрибутивы, которые раздаёт Matrux)

Приложение раздаёт пять гостевых корневых файловых систем (tar + zstd). Это стандартные сборки
дистрибутивов; **пакеты внутри не патчились**, менялся только состав файлов и добавлялись наши скрипты.
Ниже — что именно мы изменили, чтобы каждый мог восстановить соответствующий исходник.

| Образ | Основа | Пакетов | Перечень версий |
|---|---|---|---|
| `alpine-xfce` | Alpine Linux | 427 | `packages-alpine-xfce.csv` |
| `debian-xfce` | Debian GNU/Linux | 490 | `packages-debian-xfce.csv` |
| `ubuntu-xfce` | Ubuntu | 710 | `packages-ubuntu-xfce.csv` |
| `arch-xfce` | Arch Linux | перечень в образе (`/usr/share/licenses`, `/var/lib/pacman/local`) | — |
| `dev-xfce` | Debian/Ubuntu + инструменты разработчика | 927 | `packages-dev-xfce.csv` |

Перечни лежат в [`licenses/`](licenses/) — имя пакета, версия и (где дистрибутив её хранит) лицензия.

## Что удалено из образа

Чтобы образ влезал в телефон, из стандартной системы вырезано:

* `usr/lib/firmware/**` — прошивки устройств (в proot не используются);
* `usr/lib/modules/**` — модули ядра (ядро не наше, грузить их нечем);
* `boot/**` — загрузчик и ядра;
* локали, кроме `ru_*` и `en_*`;
* кеши пакетных менеджеров, логи, `var/tmp`, `tmp`, кеши приложений, `.git`-каталоги;
* из `usr/share/doc` — всё, **кроме `copyright`**; каталоги `usr/share/common-licenses` и
  `usr/share/licenses` сохраняются целиком (это требование GPL/LGPL).

## Что добавлено

* `/usr/local/bin/matrux-session` — наш скрипт запуска сессии (запускает Xvfb/Xvnc, x11vnc, dbus, XFCE,
  настраивает `XDG_CACHE_HOME`, `/etc/resolv.conf`, DISPLAY, PulseAudio). Лицензия Matrux, all rights reserved.
* `/usr/share/licenses/matrux/NOTICE` — уведомление о сторонних компонентах.
* Пользователь `root`, `HOME=/root` (монтируется из данных приложения), `LANG=ru_RU.UTF-8`.
* Предустановлены XFCE, Xvfb, x11vnc, dbus, PulseAudio и зависимости — всё из штатных репозиториев
  дистрибутива, без патчей.

## Где исходники

Для GPL/LGPL-пакетов, которые мы не меняли, полный соответствующий исходник — это исходный пакет
дистрибутива указанной версии:

* Debian: `https://sources.debian.org/src/<пакет>/<версия>/`
* Ubuntu: `https://launchpad.net/ubuntu/+source/<пакет>/<версия>`
* Alpine: `https://git.alpinelinux.org/aports/` (APKBUILD + upstream)
* Arch: `https://archlinux.org/packages/` (PKGBUILD + upstream)

Скрипты, которыми собираются и оптимизируются образы (`image-build/build.sh`, `optimize-image.sh`,
`finalize-image.sh`, `matrux-session`), — в закрытом репозитории Matrux; по запросу на
`matrux@internet.ru` предоставляются копии, соответствующие раздаваемым образам (GPL-2.0 §3).
