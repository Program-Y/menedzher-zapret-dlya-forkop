# Forkop + Zapret (расширение для OpenWrt)

Расширение для [Forkop](https://github.com/ushan0v/forkop): автоподбор стратегий zapret
по секциям, проверка блокировки доменов и проверка доступности через forkop.

## Состав

```
addon/                  файлы расширения (копируются на роутер)
  runner.sh             движок автоподбора
  parser.sh             сбор доменов (включая community_lists и rule_set .srs/.json)
  check.sh              проверка доменов (блокировка + через forkop/netns)
  rpcd/forkop.zapret    RPCD-бэкенд LuCI
  view/forkop-zapret/main.js   LuCI-вью
  menu.d/, acl.d/       меню и права LuCI
install/
  install-forkop.sh         мастер установки Forkop (+ zapret, extended sing-box, авто-настройка)
  install-addon.sh          установка расширения
  install-forkop-zapret.sh  полная установка: Forkop + расширение
config/                 очищенная конфигурация (без ключей/подписок)
  forkop                конфиг Forkop (subscription_url и VPN-ключи удалены)
  forkop_zapret         конфиг расширения
  forkop_zapret.conf
  zapret, sing-box
  forkop_rules_rus.json локальный список доменов
  *.srs                 локальные rule-set
scripts/
  install-sing-box-extended-x86.sh   extended sing-box для x86_64
```

## Установка

На роутере (OpenWrt 24.10+):

```sh
# скопируйте репозиторий на роутер, например через scp/git, затем:
cd /path/to/repo
sh install/install-forkop-zapret.sh
```

Скрипт `install-forkop.sh` спросит:
- установить ли extended sing-box (на роутерах — из фидов; на x86 — отдельный скрипт);
- установить ли zapret;
- применить ли сохранённую конфигурацию из `config/`.

Неинтерактивно: `ASSUME_YES=1 sh install/install-forkop-zapret.sh`.

## Конфигурация

- `config/forkop` — очищенная конфигурация: удалён блок `subscription_url` (токен подписки)
  и персональные домены:
  `senkuro.me`, `auto.mmzvympel.ru`, `mail.mmzvympel.ru`, `parrotslivesmatter.info.gf`,
  `PigeonsLivesMatter.mooo.com`, `CatsLivesMatter.mooo.com`, `afteronthe.mooo.com`,
  `TopOnePUBGersInTheWorld.mooo.com`.
- Локальные списки `forkop_rules_rus.json` и `*.srs` включены (очищены от тех же доменов).
- **VPN-подписка/ключи не входят в репозиторий.** После установки добавьте свою подписку
  или ключи в LuCI → Forkop.

## Расширение: что умеет

- Автоподбор стратегий zapret по секциям (контроль → боевая → кастомная → полный перебор).
- Порядок и приоритет: все домены секции доступны + максимум доменов ZM.
- Вкладка «Проверка доменов»: статусы «доступен / нет в DNS / блок по IP / блок по DPI»,
  проверка через forkop (netns+veth к br-lan), фильтры и проверка одного домена.
- Мульти-DNS (DoH/DoT/UDP, несколько серверов по очереди).
- Зеркало стратегии: «Применять настройки из секции».

## Требования

- OpenWrt 24.10+.
- `kmod-veth` для проверки через forkop (`opkg install kmod-veth`).
- `sing-box` / `sing-box-extended`, `zapret` — по желанию.

## Безопасность

В репозитории нет приватных ключей, токенов подписок и подключений.
