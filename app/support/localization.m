#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "app_common.h"

NSString * const ShiroLanguageDidChangeNotification = @"ShiroLanguageDidChangeNotification";

static NSMutableDictionary *gEnglishToRussian;
static NSMutableDictionary *gRussianToEnglish;
static NSMutableDictionary *gEnglishToChinese;
static BOOL gLocalizationInstalled = NO;

static char kShiroRawText;
static char kShiroRawButtonTitles;
static char kShiroRawPlaceholder;
static char kShiroRawControllerTitle;
static char kShiroRawNavigationTitle;
static char kShiroRawBarTitle;

static void ShiroAddTranslation(NSString *english, NSString *russian) {
    if (![english length] || ![russian length]) return;
    [gEnglishToRussian setObject:russian forKey:english];
    [gRussianToEnglish setObject:english forKey:russian];
}

static void ShiroAddChineseTranslation(NSString *english, NSString *chinese) {
    if (![english length] || ![chinese length]) return;
    [gEnglishToChinese setObject:chinese forKey:english];
}

static void ShiroBuildTranslations(void) {
    if (gEnglishToRussian) return;
    gEnglishToRussian = [[NSMutableDictionary alloc] init];
    gRussianToEnglish = [[NSMutableDictionary alloc] init];
    gEnglishToChinese = [[NSMutableDictionary alloc] init];

    /* routing profiles, geo data and per app rules */
    ShiroAddTranslation(@"OpenSSL, certificate chain and hostname verification", @"OpenSSL, проверка цепочки сертификатов и имени сервера");
    ShiroAddChineseTranslation(@"OpenSSL, certificate chain and hostname verification", @"OpenSSL，验证证书链与主机名");
    ShiroAddTranslation(@"Co-developer", @"Соразработчик");
    ShiroAddChineseTranslation(@"Co-developer", @"共同开发者");
    ShiroAddTranslation(@"Addresses", @"Адреса");
    ShiroAddChineseTranslation(@"Addresses", @"地址");
    ShiroAddTranslation(@"All apps", @"Все приложения");
    ShiroAddChineseTranslation(@"All apps", @"所有应用");
    ShiroAddTranslation(@"Apps", @"Приложения");
    ShiroAddChineseTranslation(@"Apps", @"应用");
    ShiroAddTranslation(@"A rule for an app wins over every domain and address rule. Block wins over direct, and direct over the tunnel.", @"Правило приложения сильнее любого правила домена и адреса. Блокировка сильнее прямого соединения, а прямое сильнее туннеля.");
    ShiroAddChineseTranslation(@"A rule for an app wins over every domain and address rule. Block wins over direct, and direct over the tunnel.", @"应用规则优先于所有域名和地址规则。阻止优先于直连，直连优先于隧道。");
    ShiroAddTranslation(@"Choose how each app is routed", @"Выберите маршрут для каждого приложения");
    ShiroAddChineseTranslation(@"Choose how each app is routed", @"为每个应用选择路由");
    ShiroAddTranslation(@"Default", @"По умолчанию");
    ShiroAddChineseTranslation(@"Default", @"默认");
    ShiroAddTranslation(@"%d lists missing", @"Не хватает списков: %d");
    ShiroAddChineseTranslation(@"%d lists missing", @"缺少 %d 个列表");
    ShiroAddTranslation(@"%d not supported", @"не поддерживается: %d");
    ShiroAddChineseTranslation(@"%d not supported", @"%d 条不支持");
    ShiroAddTranslation(@"Domains and addresses", @"Домены и адреса");
    ShiroAddChineseTranslation(@"Domains and addresses", @"域名和地址");
    ShiroAddTranslation(@"Downloading...", @"Загрузка...");
    ShiroAddChineseTranslation(@"Downloading...", @"正在下载...");
    ShiroAddTranslation(@"%d rules", @"правил: %d");
    ShiroAddChineseTranslation(@"%d rules", @"%d 条规则");
    ShiroAddTranslation(@"%d with a rule", @"с правилом: %d");
    ShiroAddChineseTranslation(@"%d with a rule", @"%d 个有规则");
    ShiroAddTranslation(@"Entries marked as not supported (regexp, ext) are skipped. A name that is not written as domain:, full:, keyword: or geosite: matches as part of a name.", @"Записи с пометкой «не поддерживается» (regexp, ext) пропускаются. Имя без domain:, full:, keyword: или geosite: совпадает как часть имени.");
    ShiroAddChineseTranslation(@"Entries marked as not supported (regexp, ext) are skipped. A name that is not written as domain:, full:, keyword: or geosite: matches as part of a name.", @"标记为不支持的条目（regexp、ext）会被跳过。未用 domain:、full:、keyword: 或 geosite: 写出的名称按名称的一部分匹配。");
    ShiroAddTranslation(@"Everything goes through the tunnel, apart from your own rules", @"Всё идёт через туннель, кроме ваших правил");
    ShiroAddChineseTranslation(@"Everything goes through the tunnel, apart from your own rules", @"除您自己的规则外，所有流量都经隧道");
    ShiroAddTranslation(@"Exact domain", @"Точный домен");
    ShiroAddChineseTranslation(@"Exact domain", @"精确域名");
    ShiroAddTranslation(@"Failed: %@", @"Ошибка: %@");
    ShiroAddChineseTranslation(@"Failed: %@", @"失败：%@");
    ShiroAddTranslation(@"Geo data", @"Гео-данные");
    ShiroAddChineseTranslation(@"Geo data", @"地理数据");
    ShiroAddTranslation(@"Geoip list", @"Список geoip");
    ShiroAddChineseTranslation(@"Geoip list", @"geoip 列表");
    ShiroAddTranslation(@"Geosite list", @"Список geosite");
    ShiroAddChineseTranslation(@"Geosite list", @"geosite 列表");
    ShiroAddTranslation(@"Names", @"Имена");
    ShiroAddChineseTranslation(@"Names", @"名称");
    ShiroAddTranslation(@"No apps found.", @"Приложения не найдены.");
    ShiroAddChineseTranslation(@"No apps found.", @"未找到应用。");
    ShiroAddTranslation(@"No rules yet", @"Правил пока нет");
    ShiroAddChineseTranslation(@"No rules yet", @"暂无规则");
    ShiroAddTranslation(@"No subscription has sent a routing profile. A happ panel sends one in its response, and it shows up here after the next refresh.", @"Ни одна подписка не прислала профиль маршрутизации. Панель happ присылает его в ответе, и он появится здесь после следующего обновления.");
    ShiroAddChineseTranslation(@"No subscription has sent a routing profile. A happ panel sends one in its response, and it shows up here after the next refresh.", @"尚无订阅发送路由配置。happ 面板会在响应中发送，下次刷新后会显示在这里。");
    ShiroAddTranslation(@"Not downloaded", @"Не загружено");
    ShiroAddChineseTranslation(@"Not downloaded", @"尚未下载");
    ShiroAddTranslation(@"Not supported, skipped", @"Не поддерживается, пропущено");
    ShiroAddChineseTranslation(@"Not supported, skipped", @"不支持，已跳过");
    ShiroAddTranslation(@"Profile entries", @"Записи профиля");
    ShiroAddChineseTranslation(@"Profile entries", @"配置条目");
    ShiroAddTranslation(@"Profiles come from your subscriptions. A change applies the next time the tunnel connects.", @"Профили приходят из ваших подписок. Изменение вступит в силу при следующем подключении туннеля.");
    ShiroAddChineseTranslation(@"Profiles come from your subscriptions. A change applies the next time the tunnel connects.", @"配置来自您的订阅。更改将在下次连接隧道时生效。");
    ShiroAddTranslation(@"Reading the app list...", @"Чтение списка приложений...");
    ShiroAddChineseTranslation(@"Reading the app list...", @"正在读取应用列表...");
    ShiroAddTranslation(@"Reading the profile from the daemon...", @"Чтение профиля из демона...");
    ShiroAddChineseTranslation(@"Reading the profile from the daemon...", @"正在从守护进程读取配置...");
    ShiroAddTranslation(@"rest direct", @"остальное напрямую");
    ShiroAddChineseTranslation(@"rest direct", @"其余直连");
    ShiroAddTranslation(@"rest through the tunnel", @"остальное через туннель");
    ShiroAddChineseTranslation(@"rest through the tunnel", @"其余经隧道");
    ShiroAddTranslation(@"Routing", @"Маршрутизация");
    ShiroAddChineseTranslation(@"Routing", @"路由");
    ShiroAddTranslation(@"Routing profile", @"Профиль маршрутизации");
    ShiroAddChineseTranslation(@"Routing profile", @"路由配置");
    ShiroAddTranslation(@"Search apps", @"Поиск приложений");
    ShiroAddChineseTranslation(@"Search apps", @"搜索应用");
    ShiroAddTranslation(@"Search logs", @"Поиск по журналу");
    ShiroAddChineseTranslation(@"Search logs", @"搜索日志");
    ShiroAddTranslation(@"Lines: %d", @"Строк: %d");
    ShiroAddChineseTranslation(@"Lines: %d", @"行数：%d");
    ShiroAddTranslation(@"Share", @"Поделиться");
    ShiroAddChineseTranslation(@"Share", @"分享");
    ShiroAddTranslation(@"Continue", @"Продолжить");
    ShiroAddChineseTranslation(@"Continue", @"继续");
    ShiroAddTranslation(@"Remove vless-core", @"Удалить vless-core");
    ShiroAddChineseTranslation(@"Remove vless-core", @"卸载 vless-core");
    ShiroAddTranslation(@"Removing vless-core...", @"Удаляю vless-core...");
    ShiroAddChineseTranslation(@"Removing vless-core...", @"正在卸载 vless-core...");
    ShiroAddTranslation(@"Shiro is happy now :3", @"Shiro снова счастлива :3");
    ShiroAddChineseTranslation(@"Shiro is happy now :3", @"仙狐又开心了 :3");
    ShiroAddTranslation(@"vless-core is still there. Remove it in your package manager.", @"vless-core всё ещё на месте. Удалите его в менеджере пакетов.");
    ShiroAddChineseTranslation(@"vless-core is still there. Remove it in your package manager.", @"vless-core 仍然存在，请在包管理器中卸载。");

    ShiroAddTranslation(@"Showing the first %d of %d entries. ", @"Показаны первые %d из %d записей. ");
    ShiroAddChineseTranslation(@"Showing the first %d of %d entries. ", @"显示前 %d 条，共 %d 条。");
    ShiroAddTranslation(@"The profile names geosite and geoip lists. They are downloaded once and kept for a week.", @"Профиль ссылается на списки geosite и geoip. Они скачиваются один раз и хранятся неделю.");
    ShiroAddChineseTranslation(@"The profile names geosite and geoip lists. They are downloaded once and kept for a week.", @"配置引用了 geosite 和 geoip 列表。它们只下载一次，并保留一周。");
    ShiroAddTranslation(@"Updated %@", @"Обновлено: %@");
    ShiroAddChineseTranslation(@"Updated %@", @"更新于 %@");
    ShiroAddTranslation(@"Update geo data", @"Обновить гео-данные");
    ShiroAddChineseTranslation(@"Update geo data", @"更新地理数据");
    ShiroAddTranslation(@"With a rule", @"С правилом");
    ShiroAddChineseTranslation(@"With a rule", @"已设规则");

    ShiroAddTranslation(@"About", @"О приложении");
    ShiroAddTranslation(@"Amnezia/VLESS Client", @"Клиент Amnezia/VLESS");
    ShiroAddTranslation(@"Model", @"Модель");
    ShiroAddTranslation(@"iOS version", @"Версия iOS");
    ShiroAddTranslation(@"Architecture", @"Архитектура");
    ShiroAddTranslation(@"TLS mode", @"Режим TLS");
    ShiroAddTranslation(@"How it works", @"Как это работает");
    ShiroAddTranslation(@"Apps and system traffic use the selected profile. Routing needs root, and a jailbreak already provides it.", @"Приложения и системный трафик идут через выбранный профиль. Для маршрутизации нужен root, и джейлбрейк его уже даёт.");
    ShiroAddTranslation(@"Transports", @"Транспорты");
    ShiroAddTranslation(@"Compatibility", @"Совместимость");
    ShiroAddTranslation(@"Token-authenticated control socket · subscription SSRF protection · secret redaction · real transport checks.", @"Control socket с токеном · защита подписок от SSRF · скрытие секретов в логах · настоящая проверка транспорта.");
    ShiroAddTranslation(@"Links", @"Ссылки");
    ShiroAddTranslation(@"Credits", @"Благодарности");
    ShiroAddTranslation(@"Special thanks", @"Особая благодарность");
    ShiroAddTranslation(@"Sponsors", @"Спонсоры");
    ShiroAddTranslation(@"Testers", @"Тестировали");
    ShiroAddTranslation(@"Emoji artwork", @"Эмодзи");
    ShiroAddTranslation(@"Twemoji by Twitter, Inc. and contributors (CC BY 4.0)", @"Twemoji от Twitter, Inc. и участников проекта (CC BY 4.0)");
    ShiroAddTranslation(@"system TLS, the compatibility hook is not injected", @"системный TLS, compatibility hook не внедряется");
    ShiroAddTranslation(@"external tlsfix present, shirotlsfix hooks stay off", @"внешний tlsfix найден, хуки shirotlsfix отключены");
    ShiroAddTranslation(@"shirotlsfix, Safari TLS 1.3 when MobileSubstrate is installed", @"shirotlsfix для TLS 1.3 в Safari при установленном MobileSubstrate");
    ShiroAddTranslation(@"PASSWORD", @"ПАРОЛЬ");
    ShiroAddTranslation(@"CIPHER", @"ШИФР");
    ShiroAddTranslation(@"Shadowsocks", @"Shadowsocks");
    ShiroAddTranslation(@"Trojan", @"Trojan");
    ShiroAddTranslation(@"Add", @"Добавить");
    ShiroAddTranslation(@"Available servers: %lu", @"Доступно серверов: %lu");
    ShiroAddTranslation(@"Add server", @"Добавить сервер");
    ShiroAddTranslation(@"Allow insecure", @"Разрешить небезопасное");
    ShiroAddTranslation(@"All", @"Все");
    ShiroAddTranslation(@"all", @"все");
    ShiroAddTranslation(@"Almost done", @"Почти готово");
    ShiroAddTranslation(@"Apply anyway", @"Всё равно применить");
    ShiroAddTranslation(@"Appearance", @"Оформление");
    ShiroAddTranslation(@"Accent", @"Акцент");
    ShiroAddTranslation(@"Cancel", @"Отмена");
    ShiroAddTranslation(@"Check ping", @"Проверить профиль");
    ShiroAddTranslation(@"Check", @"Проверить");
    ShiroAddTranslation(@"Check servers", @"Проверить серверы");
    ShiroAddTranslation(@"Checking package", @"Проверка пакета");
    ShiroAddTranslation(@"Close", @"Закрыть");
    ShiroAddTranslation(@"Complete", @"Готово");
    ShiroAddTranslation(@"connected", @"подключено");
    ShiroAddTranslation(@"connecting", @"подключение");
    ShiroAddTranslation(@"connecting...", @"подключение...");
    ShiroAddTranslation(@"Connection failed", @"Соединение не установлено");
    ShiroAddTranslation(@"connection failed", @"соединение не установлено");
    ShiroAddTranslation(@"Custom", @"Пользовательские");
    ShiroAddTranslation(@"DAEMON", @"ДЕМОН");
    ShiroAddTranslation(@"GENERAL", @"ОБЩИЕ");
    ShiroAddTranslation(@"CONNECTION", @"ПОДКЛЮЧЕНИЕ");
    ShiroAddTranslation(@"Connect at startup", @"Подключаться при старте");
    ShiroAddTranslation(@"Dial the selected server after a reboot",
                        @"Поднимать выбранный сервер после перезагрузки");
    ShiroAddTranslation(@"Reconnect automatically", @"Переподключаться автоматически");
    ShiroAddTranslation(@"After a drop or a change of network",
                        @"После обрыва или смены сети");
    ShiroAddTranslation(@"Try another server", @"Пробовать другой сервер");
    ShiroAddTranslation(@"Only inside the same section, fastest first",
                        @"Только внутри своего раздела, сначала быстрые");
    ShiroAddTranslation(@"Update subscriptions", @"Обновлять подписки");
    ShiroAddTranslation(@"Off", @"Выкл");
    ShiroAddTranslation(@"Every %@", @"Каждые %@");
    ShiroAddTranslation(@"The daemon runs these on its own, with the app closed.",
                        @"Демон выполняет это сам, при закрытом приложении.");
    ShiroAddTranslation(@"The daemon is not answering, so these cannot be read or changed.",
                        @"Демон не отвечает, прочитать и изменить их нельзя.");
    ShiroAddTranslation(@"Daemon is unreachable", @"Демон не отвечает");
    ShiroAddTranslation(@"DEVELOPER", @"РАЗРАБОТЧИКУ");
    ShiroAddTranslation(@"Developer settings", @"Настройки разработчика");
    ShiroAddTranslation(@"Developer settings are now visible in Settings. Tap the section heading five times to hide them again.", @"Настройки разработчика теперь видны в настройках. Чтобы снова скрыть их, пять раз нажмите на заголовок раздела.");
    ShiroAddTranslation(@"Five taps on this heading hide the section again.",
                        @"Пять тапов по этому заголовку убирают раздел.");
    ShiroAddTranslation(@"%d more", @"ещё %d");
    ShiroAddTranslation(@"What was chosen", @"Что выбралось");
    ShiroAddTranslation(@"Copy", @"Копировать");
    ShiroAddTranslation(@"The report is on the clipboard.", @"Отчёт скопирован в буфер.");
    ShiroAddTranslation(@"Asking the daemon...", @"Спрашиваю демона...");
    ShiroAddTranslation(@"Tunnel state", @"Состояние туннеля");
    ShiroAddTranslation(@"Connected for", @"На связи");
    ShiroAddTranslation(@"Redial", @"Перенабор");
    ShiroAddTranslation(@"Egress interface", @"Исходящий интерфейс");
    ShiroAddTranslation(@"Egress address", @"Исходящий адрес");
    ShiroAddTranslation(@"Catalog", @"Каталог");
    ShiroAddTranslation(@"Selected server", @"Выбранный сервер");
    ShiroAddTranslation(@"Transport", @"Транспорт");
    ShiroAddTranslation(@"Flow", @"Flow");
    ShiroAddTranslation(@"Vision", @"Vision");
    ShiroAddTranslation(@"Daemon pid", @"PID демона");
    ShiroAddTranslation(@"Daemon uptime", @"Демон работает");
    ShiroAddTranslation(@"Jailbreak", @"Джейлбрейк");
    ShiroAddTranslation(@"Config file", @"Файл конфигурации");
    ShiroAddTranslation(@"iOS major", @"Версия iOS");
    ShiroAddTranslation(@"iOS version read from", @"Версия iOS определена по");
    ShiroAddTranslation(@"Backend in use", @"Активный бэкенд");
    ShiroAddTranslation(@"Shiro-core eligible", @"shiro-core подходит");
    ShiroAddTranslation(@"Applied on the next connect.", @"Применится при следующем подключении.");
    ShiroAddTranslation(@"Auto", @"Авто");
    ShiroAddTranslation(@"Backend, tunnel, ports, DNS, rules", @"Бэкенд, туннель, порты, DNS, правила");
    ShiroAddTranslation(@"Backend, listeners, trace", @"Бэкенд, слушатели, трассировка");
    ShiroAddTranslation(@"utun tunnel", @"Туннель utun");
    ShiroAddTranslation(@"Forget direct addresses", @"Забыть прямые адреса");
    ShiroAddTranslation(@"Tunnel routes", @"Маршруты туннеля");
    ShiroAddTranslation(@"Show tunnel routes", @"Показать маршруты туннеля");
    ShiroAddTranslation(@"Tunnel DNS", @"DNS туннеля");
    ShiroAddTranslation(@"Tunnel counters", @"Счётчики туннеля");
    ShiroAddTranslation(@"TCP flows", @"TCP-потоки");
    ShiroAddTranslation(@"TCP traffic", @"TCP-трафик");
    ShiroAddTranslation(@"Last TCP error", @"Последняя ошибка TCP");
    ShiroAddTranslation(@"UDP datagrams", @"UDP-датаграммы");
    ShiroAddTranslation(@"Last UDP error", @"Последняя ошибка UDP");
    ShiroAddTranslation(@"Packets", @"Пакеты");
    ShiroAddTranslation(@"Dropped packets", @"Отброшенные пакеты");
    ShiroAddTranslation(@"DNS queries", @"DNS-запросы");
    ShiroAddTranslation(@"Rule verdicts", @"Решения правил");
    ShiroAddTranslation(@"Direct addresses", @"Прямые адреса");
    ShiroAddTranslation(@"Catalog and rules are kept.", @"Каталог и правила остаются.");
    ShiroAddTranslation(@"Catalog is kept.", @"Каталог остаётся.");
    ShiroAddTranslation(@"Checks", @"Проверки");
    ShiroAddTranslation(@"Clear", @"Очистить");
    ShiroAddTranslation(@"Console", @"Консоль");
    ShiroAddTranslation(@"Test fixtures", @"Тестовые данные");
    ShiroAddTranslation(@"Long names", @"Длинные названия");
    ShiroAddTranslation(@"Duplicates", @"Дубли");
    ShiroAddTranslation(@"Empty manual list", @"Пустой список ручных серверов");
    ShiroAddTranslation(@"Only manually added servers are removed.", @"Удаляются только добавленные вручную серверы.");
    ShiroAddTranslation(@"Done.", @"Готово.");
    ShiroAddTranslation(@"Copied in full.", @"Скопировано целиком.");
    ShiroAddTranslation(@"Crash and launch log", @"Лог падения и запуска");
    ShiroAddTranslation(@"Crash log, safe mode, device id, bundle", @"Лог падения, safe mode, id устройства, файл");
    ShiroAddTranslation(@"Delete all rules", @"Удалить все правила");
    ShiroAddTranslation(@"Failed launches", @"Неудачных запусков");
    ShiroAddTranslation(@"FIREWALL", @"ФАЙРВОЛ");
    ShiroAddTranslation(@"Flush DNS cache", @"Сбросить кэш DNS");
    ShiroAddTranslation(@"Force", @"Форс");
    ShiroAddTranslation(@"FORCE", @"ФОРС");
    ShiroAddTranslation(@"FPS overlay", @"Оверлей FPS");
    ShiroAddTranslation(@"LAUNCH", @"ЗАПУСК");
    ShiroAddTranslation(@"New device id", @"Новый id устройства");
    ShiroAddTranslation(@"no answer", @"нет ответа");
    ShiroAddTranslation(@"No servers in the catalog.", @"В каталоге нет серверов.");
    ShiroAddTranslation(@"Off from the next launch.", @"Выключен со следующего запуска.");
    ShiroAddTranslation(@"Reset settings", @"Сбросить настройки");
    ShiroAddTranslation(@"Run", @"Запустить");
    ShiroAddTranslation(@"Safe mode next launch", @"Safe mode при следующем запуске");
    ShiroAddTranslation(@"Session trace", @"Трассировка сессий");
    ShiroAddTranslation(@"SOCKS on 0.0.0.0", @"SOCKS на 0.0.0.0");
    ShiroAddTranslation(@"Staged probes and the tunnel routes", @"Пробы по стадиям и маршруты туннеля");
    ShiroAddTranslation(@"STAGES", @"СТАДИИ");
    ShiroAddTranslation(@"Stock theme, no glass, no decor. Your theme stays on disk.",
                        @"Стоковая тема, без стекла и декора. Ваша тема останется на диске.");
    ShiroAddTranslation(@"Talk to the control socket without ssh", @"Говорить с управляющим сокетом без ssh");
    ShiroAddTranslation(@"The old id is gone for good.", @"Старый id пропадёт навсегда.");
    ShiroAddTranslation(@"Write bundle", @"Записать файл");
    ShiroAddTranslation(@"Export debug bundle", @"Экспорт debug bundle");
    ShiroAddTranslation(@"CHOSEN", @"ВЫБРАНО");
    ShiroAddTranslation(@"SERVER", @"СЕРВЕР");
    ShiroAddTranslation(@"LIVE", @"СЕЙЧАС");
    ShiroAddTranslation(@"DEVICE", @"УСТРОЙСТВО");
    ShiroAddTranslation(@"FORCED", @"ФОРСИРОВАНО");
    ShiroAddTranslation(@"PROCESSES", @"ПРОЦЕССЫ");
    ShiroAddTranslation(@"PATHS", @"ПУТИ");
    ShiroAddTranslation(@"Backend forced to", @"Бэкенд форсирован на");
    ShiroAddTranslation(@"Free memory", @"Свободная память");
    ShiroAddTranslation(@"Shiro resident", @"Shiro занимает");
    ShiroAddTranslation(@"Device uptime", @"Устройство работает");
    ShiroAddTranslation(@"Device", @"Устройство");
    ShiroAddTranslation(@"Battery", @"Батарея");
    ShiroAddTranslation(@"Shiro-core usable", @"shiro-core подходит");
    ShiroAddTranslation(@"Bypass evicted", @"Вытеснено из обхода");
    ShiroAddTranslation(@"iOS read from", @"Версия iOS из");
    ShiroAddTranslation(@"Top rule", @"Топ правило");
    ShiroAddTranslation(@"Rule 2", @"Правило 2");
    ShiroAddTranslation(@"Rule 3", @"Правило 3");
    ShiroAddTranslation(@"Rules", @"Правила");
    ShiroAddTranslation(@"Block response", @"Ответ на блок");
    ShiroAddTranslation(@"Developer", @"Разработчик");
    ShiroAddTranslation(@"@axi8229\nFull Apple A7 support and Hysteria stabilization", @"@axi8229\nПолная поддержка Apple A7 и стабилизация Hysteria");
    ShiroAddTranslation(@"What was chosen, checks, overrides and rescue",
                        @"Что выбралось, проверки, переключатели и аварийный раздел");
    ShiroAddTranslation(@"Rescue", @"Аварийный раздел");
    ShiroAddTranslation(@"Backend pinned to", @"Бэкенд закреплён на");
    ShiroAddTranslation(@"Bypass evictions", @"Вытеснено из таблицы обхода");
    ShiroAddTranslation(@"SOCKS bound to", @"SOCKS слушает");
    ShiroAddTranslation(@"Blocked answers", @"Ответ на заблокированное");
    ShiroAddTranslation(@"DNS cache", @"Кэш DNS");
    ShiroAddTranslation(@"Busiest rule", @"Самое частое правило");
    ShiroAddTranslation(@"Second busiest rule", @"Второе по частоте правило");
    ShiroAddTranslation(@"Third busiest rule", @"Третье по частоте правило");
    ShiroAddTranslation(@"Rule hits", @"Срабатывания правил");
    ShiroAddTranslation(@"Device gating", @"Привязка к устройству");
    ShiroAddTranslation(@"Jailbreak root", @"Корень джейлбрейка");
    ShiroAddTranslation(@"Device id file", @"Файл id устройства");
    ShiroAddTranslation(@"System log", @"Системный лог");
    ShiroAddTranslation(@"Substrate directory", @"Каталог Substrate");
    ShiroAddTranslation(@"CHECK", @"ПРОВЕРКА");
    ShiroAddTranslation(@"Server", @"Сервер");
    ShiroAddTranslation(@"Mode", @"Режим");
    ShiroAddTranslation(@"No server in the catalog", @"В каталоге нет серверов");
    ShiroAddTranslation(@"TCP to the node", @"TCP до узла");
    ShiroAddTranslation(@"Local proxy", @"Локальный прокси");
    ShiroAddTranslation(@"Active tunnel", @"Активный туннель");
    ShiroAddTranslation(@"Profile handshake", @"Рукопожатие профиля");
    ShiroAddTranslation(@"Running...", @"Идёт проверка...");
    ShiroAddTranslation(@"Result", @"Результат");
    ShiroAddTranslation(@"passed in %d ms", @"прошла за %d мс");
    ShiroAddTranslation(@"LISTENERS AND DNS", @"СЛУШАТЕЛИ И DNS");
    ShiroAddTranslation(@"SUBSCRIPTIONS", @"ПОДПИСКИ");
    ShiroAddTranslation(@"DIAGNOSTICS", @"ДИАГНОСТИКА");
    ShiroAddTranslation(@"Backend", @"Бэкенд");
    ShiroAddTranslation(@"Shiro-core", @"shiro-core");
    ShiroAddTranslation(@"Connect hook only", @"Только connect-хук");
    ShiroAddTranslation(@"Zero address", @"Нулевой адрес");
    ShiroAddTranslation(@"Flush the DNS cache", @"Сбросить кэш DNS");
    ShiroAddTranslation(@"Ignore device gating", @"Игнорировать привязку к устройству");
    ShiroAddTranslation(@"Flush", @"Сбросить");
    ShiroAddTranslation(@"Reset", @"Сбросить");
    ShiroAddTranslation(@"Done.", @"Готово.");
    ShiroAddTranslation(@"DEVICE ID", @"ID УСТРОЙСТВА");
    ShiroAddTranslation(@"REMOVE", @"УДАЛЕНИЕ");
    ShiroAddTranslation(@"Crash and launch report", @"Отчёт о падении и запуске");
    ShiroAddTranslation(@"nothing recorded", @"ничего не записано");
    ShiroAddTranslation(@"Leave safe mode", @"Выйти из safe mode");
    ShiroAddTranslation(@"Enter", @"Войти");
    ShiroAddTranslation(@"The next launch runs in safe mode.", @"Следующий запуск пройдёт в safe mode.");
    ShiroAddTranslation(@"Device id", @"ID устройства");
    ShiroAddTranslation(@"Copied to the clipboard.", @"Скопировано в буфер.");
    ShiroAddTranslation(@"Issue", @"Выдать");
    ShiroAddTranslation(@"Diagnostics bundle", @"Файл диагностики");
    ShiroAddTranslation(@"the daemon did not answer", @"демон не ответил");
    ShiroAddTranslation(@"unknown check type", @"неизвестный тип проверки");
    ShiroAddTranslation(@"Last backend error", @"Последняя ошибка бэкенда");
    ShiroAddTranslation(@"Bypass table", @"Таблица обхода");
    ShiroAddTranslation(@"Redirect port", @"Порт перенаправления");
    ShiroAddTranslation(@"DNS port", @"Порт DNS");
    ShiroAddTranslation(@"Live connections", @"Живых соединений");
    ShiroAddTranslation(@"TLS compatibility hook", @"Хук совместимости TLS");
    ShiroAddTranslation(@"Status bar hook", @"Хук строки состояния");
    ShiroAddTranslation(@"Routing rules", @"Правила маршрутизации");
    ShiroAddTranslation(@"Send a domain or a subnet direct, or block it",
                        @"Пустить домен или подсеть напрямую, либо заблокировать");
    ShiroAddTranslation(@"Upstream DNS", @"Внешний DNS");
    ShiroAddTranslation(@"Local DNS port", @"Локальный порт DNS");
    ShiroAddTranslation(@"SOCKS port", @"Порт SOCKS");
    ShiroAddTranslation(@"An IPv4 address, for example 1.1.1.1",
                        @"Адрес IPv4, например 1.1.1.1");
    ShiroAddTranslation(@"A port number between 1 and 65535",
                        @"Номер порта от 1 до 65535");
    ShiroAddTranslation(@"DNS settings apply the next time the tunnel comes up. The SOCKS port applies when the daemon restarts.",
                        @"Настройки DNS применяются при следующем подъёме туннеля. Порт SOCKS - при перезапуске демона.");
    ShiroAddTranslation(@"Reconnect attempts", @"Попыток переподключения");
    ShiroAddTranslation(@"Until it works", @"Пока не получится");
    ShiroAddTranslation(@"%d attempts", @"%d попыток");
    ShiroAddTranslation(@"Save", @"Сохранить");
    ShiroAddTranslation(@"Direct", @"Напрямую");
    ShiroAddTranslation(@"Block", @"Блокировать");
    ShiroAddTranslation(@"Through the tunnel", @"Через туннель");
    ShiroAddTranslation(@"Domain and subdomains", @"Домен и поддомены");
    ShiroAddTranslation(@"Keyword", @"Ключевое слово");
    ShiroAddTranslation(@"IP range", @"Диапазон адресов");
    ShiroAddTranslation(@"What should happen to the traffic?", @"Что делать с трафиком?");
    ShiroAddTranslation(@"What should it match?", @"По чему сопоставлять?");
    ShiroAddTranslation(@"For example example.com", @"Например example.com");
    ShiroAddTranslation(@"For example googlevideo", @"Например googlevideo");
    ShiroAddTranslation(@"For example 10.0.0.0/8", @"Например 10.0.0.0/8");
    ShiroAddTranslation(@"Value", @"Значение");
    ShiroAddTranslation(@"hits", @"срабатываний");
    ShiroAddTranslation(@"Reading the rules from the daemon...",
                        @"Читаю правила у демона...");
    ShiroAddTranslation(@"No rules: everything goes through the tunnel. Add one with the plus button.",
                        @"Правил нет: весь трафик идёт через туннель. Добавьте правило кнопкой «плюс».");
    ShiroAddTranslation(@"Block wins over direct, direct wins over the tunnel, whatever the order. On iOS 12 and later the tunnel core reads the real domain from the connection; below that the rule is matched when the name is resolved, so an address shared by several sites follows the first name that asked for it.",
                        @"Блокировка сильнее «напрямую», «напрямую» сильнее туннеля, порядок правил не важен. На iOS 12 и новее ядро туннеля видит настоящий домен соединения; ниже правило применяется в момент разрешения имени, поэтому адрес, общий для нескольких сайтов, идёт по первому запросившему имени.");
    ShiroAddTranslation(@"APP", @"ПРИЛОЖЕНИЕ");
    ShiroAddTranslation(@"Dark", @"Тёмная");
    ShiroAddTranslation(@"Disconnect first", @"Сначала отключитесь");
    ShiroAddTranslation(@"Done", @"Готово");
    ShiroAddTranslation(@"Edit", @"Изменить");
    ShiroAddTranslation(@"Edit details", @"Изменить параметры");
    ShiroAddTranslation(@"Edit selected server", @"Изменить выбранный сервер");
    ShiroAddTranslation(@"Edit server", @"Изменить сервер");
    ShiroAddTranslation(@"Encrypted subscription", @"Зашифрованная подписка");
    ShiroAddTranslation(@"English", @"Английский");
    ShiroAddTranslation(@"Error", @"Ошибка");
    ShiroAddTranslation(@"expired", @"истёк");
    ShiroAddTranslation(@"Failed", @"Ошибка");
    ShiroAddTranslation(@"Finishing", @"Завершение");
    ShiroAddTranslation(@"FINGERPRINT", @"ОТПЕЧАТОК");
    ShiroAddTranslation(@"FLOW", @"ПОТОК");
    ShiroAddTranslation(@"idle", @"ожидание");
    ShiroAddTranslation(@"Import file", @"Импорт файла");
    ShiroAddTranslation(@"Export configuration", @"Экспорт конфигурации");
    ShiroAddTranslation(@"Restore configuration", @"Восстановить конфигурацию");
    ShiroAddTranslation(@"Export backup", @"Экспорт резервной копии");
    ShiroAddTranslation(@"Restore backup", @"Восстановить резервную копию");
    ShiroAddTranslation(@"Save a config file to Documents", @"Сохранить файл конфигурации в Documents");
    ShiroAddTranslation(@"Validate, then replace configuration", @"Проверить и заменить конфигурацию");
    ShiroAddTranslation(@"Choose a Shiro .deb package", @"Выбрать пакет Shiro .deb");
    ShiroAddTranslation(@"Manually added profiles only", @"Только добавленные вручную профили");
    ShiroAddTranslation(@"validated import", @"импорт с проверкой");
    ShiroAddTranslation(@"Configuration backup", @"Резервная копия");
    ShiroAddTranslation(@"Not a shiro backup", @"Это не резервная копия shiro");
    ShiroAddTranslation(@"Replace configuration?", @"Заменить конфигурацию?");
    ShiroAddTranslation(@"The imported backup will replace all current servers and subscriptions.", @"Импортированная копия заменит все текущие серверы и подписки.");
    ShiroAddTranslation(@"Replace", @"Заменить");
    ShiroAddTranslation(@"Configuration restored", @"Конфигурация восстановлена");
    ShiroAddTranslation(@"Saved to Documents/shiro-backup.shiro", @"Сохранено в Documents/shiro-backup.shiro");
    ShiroAddTranslation(@"Subscription details", @"Данные подписки");
    ShiroAddTranslation(@"Used", @"Использовано");
    ShiroAddTranslation(@"Remaining", @"Осталось");
    ShiroAddTranslation(@"Limit", @"Лимит");
    ShiroAddTranslation(@"Uploaded", @"Отправлено");
    ShiroAddTranslation(@"Expires", @"Действует до");
    ShiroAddTranslation(@"Expired", @"Срок действия истёк");
    ShiroAddTranslation(@"Downloaded", @"Получено");
    ShiroAddTranslation(@"Description", @"Описание");
    ShiroAddTranslation(@"Contact support", @"Связаться с поддержкой");
    ShiroAddTranslation(@"Not provided", @"Нет данных");
    ShiroAddTranslation(@"Install failed", @"Ошибка установки");
    ShiroAddTranslation(@"Installing", @"Установка");
    ShiroAddTranslation(@"Light", @"Светлая");
    ShiroAddTranslation(@"Language", @"Язык");
    ShiroAddTranslation(@"Manual", @"Вручную");
    ShiroAddTranslation(@"NAME", @"НАЗВАНИЕ");
    ShiroAddTranslation(@"Name", @"Название");
    ShiroAddTranslation(@"No camera available", @"Камера недоступна");
    ShiroAddTranslation(@"Camera access could not be requested", @"Не удалось запросить доступ к камере");
    ShiroAddTranslation(@"Camera access is disabled\nEnable it in Settings > Privacy > Camera", @"Доступ к камере отключён\nРазрешите его в Настройки > Конфиденциальность > Камера");
    ShiroAddTranslation(@"No daemon logs available", @"Логи демона недоступны");
    ShiroAddTranslation(@"No app fault report", @"Отчётов о сбоях нет");
    ShiroAddTranslation(@"Loading logs...", @"Загрузка логов...");
    ShiroAddTranslation(@"reading content...", @"чтение содержимого...");
    ShiroAddTranslation(@"removing manual servers...", @"удаление серверов...");
    ShiroAddTranslation(@"manual servers removed", @"серверы удалены");
    ShiroAddTranslation(@"Add subscription", @"Добавить подписку");
    ShiroAddTranslation(@"Paste from clipboard", @"Вставить из буфера");
    ShiroAddTranslation(@"Paste", @"Вставить");
    ShiroAddTranslation(@"Safe mode", @"Безопасный режим");
    ShiroAddTranslation(@"shirod is missing: reinstall the package",
                        @"shirod отсутствует: переустановите пакет");
    ShiroAddTranslation(@"the shirod launch daemon is missing: reinstall the package",
                        @"нет задания launchd для shirod: переустановите пакет");
    ShiroAddTranslation(@"shirod is not running and its log is empty",
                        @"shirod не запущен, его лог пуст");
    ShiroAddTranslation(@"This device received a link back to the same address instead of a subscription feed. Check device access and ask the provider for the feed URL.",
                        @"Устройство получило ссылку на тот же адрес вместо списка серверов. Проверьте доступ устройства к подписке и запросите у провайдера ссылку на список.");
    ShiroAddTranslation(@"The Happ crypt5 bundle on this page could not be opened. It is either damaged or sealed with a key this build does not carry.",
                        @"Бандл Happ crypt5 на этой странице не открылся: он либо повреждён, либо запечатан ключом, которого нет в этой сборке.");
    ShiroAddTranslation(@"This address opens a web page instead of a subscription feed. Copy the subscription link the page offers, not the page address.",
                        @"По этому адресу открывается веб-страница, а не подписка. Скопируйте ссылку на подписку, которую предлагает страница, а не адрес самой страницы.");
    ShiroAddTranslation(@"Shiro failed to start %d times and is running with "
                         "the stock theme. The report is in Logs.",
                        @"Shiro не смог запуститься %d раза и работает со "
                         "стандартной темой. Отчёт лежит в разделе «Логи».");
    ShiroAddTranslation(@"QR code", @"QR-код");
    ShiroAddTranslation(@"Import from file", @"Импорт из файла");
    ShiroAddTranslation(@"Delete all servers", @"Удалить все серверы");
    ShiroAddTranslation(@"Delete", @"Удалить");
    ShiroAddTranslation(@"Every server in the Manual group is removed. Subscriptions are not touched.", @"Все серверы из группы «Вручную» будут удалены. Подписки не затрагиваются.");
    ShiroAddTranslation(@"No servers yet", @"Серверов пока нет");
    ShiroAddTranslation(@"To use a server add a proxy link or a subscription.", @"Чтобы пользоваться сервером, добавьте прокси или подписку.");
    ShiroAddTranslation(@"Device ID (tap to copy)", @"ID устройства (нажмите, чтобы скопировать)");
    ShiroAddTranslation(@"Device ID copied", @"ID устройства скопирован");
    ShiroAddTranslation(@"not available yet", @"пока недоступен");
    ShiroAddTranslation(@"Unknown content type. This is not a server link, a subscription, or a profile Shiro can read.", @"Неизвестный тип контента. Это не ссылка на сервер, не подписка и не профиль, который Shiro умеет читать.");
    ShiroAddTranslation(@"No server Shiro can run was found in this content.", @"В этом содержимом нет ни одного сервера, который Shiro может запустить.");
    ShiroAddTranslation(@"Every server in this content is already saved.", @"Все серверы из этого содержимого уже сохранены.");
    ShiroAddTranslation(@"There was nothing to import.", @"Импортировать нечего.");
    ShiroAddTranslation(@"No configuration is selected. Pick a server first.", @"Ни одна конфигурация не выбрана. Сначала выберите сервер.");
    ShiroAddTranslation(@"The clipboard is empty.", @"Буфер обмена пуст.");
    ShiroAddTranslation(@"The file is empty or could not be read.", @"Файл пуст или его не удалось прочитать.");
    ShiroAddTranslation(@"The subscription refused this device.", @"Подписка отклонила это устройство.");
    ShiroAddTranslation(@"OK", @"ОК");
    ShiroAddTranslation(@"OFF", @"ВЫКЛ");
    ShiroAddTranslation(@"ON", @"ВКЛ");
    ShiroAddTranslation(@"Ping All", @"Проверить");
    ShiroAddTranslation(@"None", @"Нет");
    ShiroAddTranslation(@"none", @"нет");
    ShiroAddTranslation(@"ADDRESS", @"АДРЕС");
    ShiroAddTranslation(@"FLOW", @"FLOW");
    ShiroAddTranslation(@"PATH", @"ПУТЬ");
    ShiroAddTranslation(@"SNI", @"SNI");
    ShiroAddTranslation(@"FINGERPRINT", @"ОТПЕЧАТОК");
    ShiroAddTranslation(@"NAME", @"ИМЯ");
    ShiroAddTranslation(@"PORT", @"ПОРТ");
    ShiroAddTranslation(@"Preparing package", @"Подготовка пакета");
    ShiroAddTranslation(@"Refresh", @"Обновить");
    ShiroAddTranslation(@"Refresh now", @"Обновить сейчас");
    ShiroAddTranslation(@"Refresh the subscription to change it", @"Обновите подписку, чтобы изменить её");
    ShiroAddTranslation(@"Remove", @"Удалить");
    ShiroAddTranslation(@"Restarting shirod", @"Перезапуск shirod");
    ShiroAddTranslation(@"The tunnel could not start. Open System Logs to see whether utun, routes, or the bundled core failed.", @"Не удалось запустить туннель. Откройте системные логи: там указано, что именно не сработало, utun, маршруты или встроенное ядро.");
    ShiroAddTranslation(@"Running dpkg --install", @"Выполнение dpkg --install");
    ShiroAddTranslation(@"Russian", @"Русский");
    ShiroAddTranslation(@"Russian/English", @"Русский/Английский");
    ShiroAddTranslation(@"Save", @"Сохранить");
    ShiroAddTranslation(@"Shiro", @"Shiro :3");
    ShiroAddTranslation(@"Scan QR", @"Сканировать QR");
    ShiroAddTranslation(@"Scan native config", @"Сканировать конфигурацию");
    ShiroAddTranslation(@"Settings", @"Настройки");
    ShiroAddTranslation(@"Starting services", @"Запуск служб");
    ShiroAddTranslation(@"Starting", @"Запуск");
    ShiroAddTranslation(@"State", @"Состояние");
    ShiroAddTranslation(@"Stopping shirod", @"Остановка shirod");
    ShiroAddTranslation(@"Stopping services", @"Остановка служб");
    ShiroAddTranslation(@"Style", @"Стиль");
    ShiroAddTranslation(@"Subscription", @"Подписка");
    ShiroAddTranslation(@"Subscription profile", @"Профиль подписки");
    ShiroAddTranslation(@"Subscription URL", @"URL подписки");
    ShiroAddTranslation(@"Header: value", @"Заголовок: значение");
    ShiroAddTranslation(@"HWID requires a Cookie request header", @"HWID требует заголовок Cookie");
    ShiroAddTranslation(@"Request header", @"Заголовок запроса");
    ShiroAddTranslation(@"System Logs", @"Системные логи");
    ShiroAddTranslation(@"Themes", @"Темы");
    ShiroAddTranslation(@"Update", @"Обновить");
    ShiroAddTranslation(@"Update Shiro", @"Обновить Shiro");
    ShiroAddTranslation(@"UUID", @"UUID");
    ShiroAddTranslation(@"UTILITIES", @"УТИЛИТЫ");
    ShiroAddTranslation(@"Version", @"Версия");
    ShiroAddTranslation(@"choose a .deb package", @"выберите пакет .deb");
    ShiroAddTranslation(@"daemon offline", @"демон недоступен");
    ShiroAddTranslation(@"disconnect to edit", @"отключитесь для редактирования");
    ShiroAddTranslation(@"disconnect to remove", @"отключитесь для удаления");
    ShiroAddTranslation(@"disconnect to reorder", @"отключитесь для изменения порядка");
    ShiroAddTranslation(@"disconnect to switch", @"отключитесь для переключения");
    ShiroAddTranslation(@"disconnect to switch backend", @"отключитесь для смены режима");
    ShiroAddTranslation(@"fetch failed: daemon offline", @"не удалось получить данные: демон недоступен");
    ShiroAddTranslation(@"fetching subscription...", @"получение подписки...");
    ShiroAddTranslation(@"file import failed", @"не удалось импортировать файл");
    ShiroAddTranslation(@"folder", @"папка");
    ShiroAddTranslation(@"group ping complete", @"проверка пинга группы завершена");
    ShiroAddTranslation(@"group profile check complete", @"проверка профилей группы завершена");
    ShiroAddTranslation(@"install a .deb", @"установить .deb");
    ShiroAddTranslation(@"install this package over the current version? settings and subscriptions stay in place", @"установить этот пакет поверх текущей версии? настройки и подписки сохранятся");
    ShiroAddTranslation(@"manual profiles only", @"только ручные профили");
    ShiroAddTranslation(@"manual", @"вручную");
    ShiroAddTranslation(@"name and url required", @"нужны название и URL");
    ShiroAddTranslation(@"no readable folders", @"нет доступных папок");
    ShiroAddTranslation(@"no servers in group", @"в группе нет серверов");
    ShiroAddTranslation(@"no servers to ping", @"нет серверов для проверки");
    ShiroAddTranslation(@"paste a link here", @"вставьте ссылку");
    ShiroAddTranslation(@"paste a subscription URL", @"вставьте URL подписки");
    ShiroAddTranslation(@"pick a server first", @"сначала выберите сервер");
    ShiroAddTranslation(@"ping check complete", @"проверка пинга завершена");
    ShiroAddTranslation(@"profile check complete", @"проверка профилей завершена");
    ShiroAddTranslation(@"QR code is empty or unreadable", @"QR-код пуст или не читается");
    ShiroAddTranslation(@"refreshing subscription...", @"обновление подписки...");
    ShiroAddTranslation(@"refreshing subscriptions...", @"обновление подписок...");
    ShiroAddTranslation(@"saving subscription...", @"сохранение подписки...");
    ShiroAddTranslation(@"section moved", @"раздел перемещён");
    ShiroAddTranslation(@"server moved", @"сервер перемещён");
    ShiroAddTranslation(@"list reloaded", @"список обновлён");
    ShiroAddTranslation(@"subscription added", @"подписка добавлена");
    ShiroAddTranslation(@"subscription not found", @"подписка не найдена");
    ShiroAddTranslation(@"subscription pinned", @"подписка закреплена");
    ShiroAddTranslation(@"subscription removed", @"подписка удалена");
    ShiroAddTranslation(@"removing subscription...", @"удаление подписки...");
    ShiroAddTranslation(@"subscription saved", @"подписка сохранена");
    ShiroAddTranslation(@"daemon offline: cannot save header", @"демон недоступен: нельзя сохранить заголовок");
    ShiroAddTranslation(@"subscription updated", @"подписка обновлена");
    ShiroAddTranslation(@"subscription url has spaces", @"в URL подписки есть пробелы");
    ShiroAddTranslation(@"subscriptions refreshed", @"подписки обновлены");
    ShiroAddTranslation(@"switch timeout", @"тайм-аут переключения");
    ShiroAddTranslation(@"timeout", @"тайм-аут");
    ShiroAddTranslation(@"validating native config...", @"проверка нативной конфигурации...");
    ShiroAddTranslation(@"could not stop shirod", @"не удалось остановить shirod");
    ShiroAddTranslation(@"daemon offline: cannot add", @"демон недоступен: нельзя добавить");
    ShiroAddTranslation(@"daemon offline: cannot edit", @"демон недоступен: нельзя изменить");
    ShiroAddTranslation(@"daemon offline: cannot import", @"демон недоступен: нельзя импортировать");
    ShiroAddTranslation(@"checking daemon...", @"проверка демона...");
    ShiroAddTranslation(@"checking group ping...", @"проверка пинга группы...");
    ShiroAddTranslation(@"checking ping...", @"проверка пинга...");
    ShiroAddTranslation(@"checking server...", @"проверка сервера...");
    ShiroAddTranslation(@"server ping timeout", @"сервер не ответил вовремя");
    ShiroAddTranslation(@"server ping", @"пинг сервера");
    ShiroAddTranslation(@"failed", @"ошибка");
    ShiroAddTranslation(@"checking", @"проверка");
    ShiroAddTranslation(@"WAIT", @"ЖДИТЕ");
    ShiroAddTranslation(@"cannot open folder", @"не удалось открыть папку");
    ShiroAddTranslation(@"empty folder", @"папка пуста");
    ShiroAddTranslation(@"Shiro does not support this protocol", @"Shiro не поддерживает этот протокол");
    ShiroAddTranslation(@"Send HWID in Cookie", @"Отправлять HWID в cookie");
    ShiroAddTranslation(@"Title and URL", @"Название и URL");
    ShiroAddTranslation(@"This theme will lag on iOS 6/7. Liquid glass is laggy on older device.", @"Эта тема будет тормозить на iOS 6/7. Liquid glass медленный на старых устройствах");
    ShiroAddTranslation(@"Dark / Light applies to the selected style. Choice is stored on device.", @"Тёмная или светлая тема зависит от выбранного стиля. Выбор сохраняется на устройстве");
    ShiroAddTranslation(@"Play a short ouch on every button tap.", @"Проигрывать короткий ouch при каждом нажатии");
    ShiroAddTranslation(@"Play a short meow on every button tap.", @"Проигрывать короткий meow при каждом нажатии");
    ShiroAddTranslation(@"the legacy theme for the legacy community", @"для выживших на iOS 6 :D");
    ShiroAddTranslation(@"flat and transparent", @"эстетика 2013 года");
    ShiroAddTranslation(@"meeeeeow :3", @"самая фембойская тема");
    ShiroAddTranslation(@"hehehe mita hehehe miside", @"ыыыыы кепочка ыыыыы мисайд");
    ShiroAddTranslation(@"futuristic maximalism of the past", @"эстетика, опередившая свое время");
    ShiroAddTranslation(@"google pixel aesthetic", @"ыыыы google");
    ShiroAddTranslation(@"modern theme", @"dopamine, palera1n, trollstore и вайб 2021 года");
    ShiroAddTranslation(@"liquid ass... nah, glass", @"нууу такое... tahoe!");
    ShiroAddTranslation(@"QR code not detected\nfill the frame with the code\nand hold the phone still", @"QR-код не обнаружен\nзаполните кадр кодом\nи держите телефон неподвижно");
    ShiroAddTranslation(@"A live profile cannot be edited", @"Активный профиль нельзя изменить");
    ShiroAddTranslation(@"SOCKS is localhost-only by default. socks_public=1 in config opens it to the LAN.", @"SOCKS по умолчанию доступен только локально. socks_public=1 в конфигурации открывает его для сети");
    ShiroAddTranslation(@"Starting install helper", @"Запуск установщика");
    ShiroAddTranslation(@"Tap Close when you are ready.", @"Нажмите «Закрыть», когда будете готовы");
    ShiroAddTranslation(@"unknown error", @"неизвестная ошибка");
    ShiroAddTranslation(@"Could not connect to the server. Check the address, network, and server availability.", @"Не удалось подключиться к серверу. Проверьте адрес, сеть и доступность сервера.");
    ShiroAddTranslation(@"The tunnel could not be opened. Check the server settings, key, and selected transport.", @"Не удалось открыть туннель. Проверьте параметры сервера, ключ и выбранный транспорт.");
    ShiroAddTranslation(@"The local proxy could not start. Restart Shiro and check that another copy is not running.", @"Не удалось запустить локальный прокси. Перезапустите Shiro и проверьте, что другая копия не запущена.");
    ShiroAddTranslation(@"The server name could not be resolved. Check the internet connection and server address.", @"Не удалось найти сервер по имени. Проверьте интернет-соединение и адрес сервера.");
    ShiroAddTranslation(@"The connect hook could not start. Check that shirotlsfix is installed, or pick another backend.", @"Connect-хук не запустился. Проверьте, что shirotlsfix установлен, или выберите другой бэкенд.");
    ShiroAddTranslation(@"The tunnel could not start. Open System Logs to see whether utun, routes, or the server failed.", @"Туннель не запустился. Откройте «Системные логи»: там видно, что отказало — utun, маршруты или сервер.");
    ShiroAddTranslation(@"The tunnel stopped right after it started. Open System Logs for the reason.", @"Туннель остановился сразу после запуска. Причина — в «Системных логах».");
    ShiroAddTranslation(@"This server uses a protocol or security mode that Shiro does not support.", @"Этот сервер использует протокол или режим защиты, который Shiro не поддерживает.");
    ShiroAddTranslation(@"The server link has an invalid UUID. Import the link again from its source.", @"В ссылке сервера неверный UUID. Импортируйте ссылку заново из источника.");
    ShiroAddTranslation(@"The connection attempt timed out. Check the network and try another server.", @"Время ожидания подключения истекло. Проверьте сеть и попробуйте другой сервер.");
    ShiroAddTranslation(@"The Shiro service is not responding. Restart it and try again.", @"Служба Shiro не отвечает. Перезапустите её и повторите попытку.");
    ShiroAddTranslation(@"The server port is reachable, but the profile could not complete a real connection. Check its UUID or password, security, SNI, and transport settings.", @"Порт сервера доступен, но профиль не смог установить настоящее соединение. Проверьте UUID или пароль, защиту, SNI и транспорт.");
    ShiroAddTranslation(@"This profile cannot be checked while another profile is connected. Disconnect first.", @"Нельзя проверить этот профиль, пока подключён другой. Сначала отключитесь.");
    ShiroAddTranslation(@"The server address is invalid, unsafe, or cannot be resolved.", @"Адрес сервера некорректен, небезопасен или не определяется через DNS.");
    ShiroAddTranslation(@"See /tmp/shiro-update.log", @"См. /tmp/shiro-update.log");
    ShiroAddTranslation(@"(no log)", @"(нет лога)");

/* theme editor */
    ShiroAddTranslation(@"STYLE", @"СТИЛЬ");
    ShiroAddTranslation(@"VARIANT", @"ВАРИАНТ");
    ShiroAddTranslation(@"LIGHT COLORS", @"СВЕТЛЫЕ ЦВЕТА");
    ShiroAddTranslation(@"DARK COLORS", @"ТЁМНЫЕ ЦВЕТА");
    ShiroAddTranslation(@"Theme name", @"Название темы");
    ShiroAddTranslation(@"Chrome", @"Панели");
    ShiroAddTranslation(@"Look", @"Вид");
    ShiroAddTranslation(@"Corners", @"Скругление");
    ShiroAddTranslation(@"Editing", @"Редактируем");
    ShiroAddTranslation(@"Classic", @"Классика");
    ShiroAddTranslation(@"Flat", @"Плоское");
    ShiroAddTranslation(@"Glass", @"Стекло");
    ShiroAddTranslation(@"Add dark variant", @"Добавить тёмный вариант");
    ShiroAddTranslation(@"Export to Documents", @"Экспорт в Documents");
    ShiroAddTranslation(@"Delete theme", @"Удалить тему");
    ShiroAddTranslation(@"Delete theme?", @"Удалить тему?");
    ShiroAddTranslation(@"New theme", @"Новая тема");
    ShiroAddTranslation(@"Copy current theme", @"Копировать текущую тему");
    ShiroAddTranslation(@"Import from Documents", @"Импорт из Documents");
    ShiroAddTranslation(@"Import theme", @"Импорт темы");
    ShiroAddTranslation(@"Theme exported", @"Тема экспортирована");
    ShiroAddTranslation(@"Theme imported", @"Тема импортирована");
    ShiroAddTranslation(@"Export failed", @"Не удалось экспортировать");
    ShiroAddTranslation(@"Import failed", @"Не удалось импортировать");
    ShiroAddTranslation(@"Could not create theme", @"Не удалось создать тему");
    ShiroAddTranslation(@"The custom theme limit is reached.", @"Достигнут предел числа своих тем.");
    ShiroAddTranslation(@"made on this device", @"сделана на этом устройстве");
    ShiroAddTranslation(@"Unknown error", @"Неизвестная ошибка");

/* server sorting */
    ShiroAddTranslation(@"Sort servers", @"Сортировка серверов");
    ShiroAddTranslation(@"Stored order", @"Как сохранено");
    ShiroAddTranslation(@"By name", @"По названию");
    ShiroAddTranslation(@"By latency", @"По задержке");

/* home screen: status card and the server detail sheet */
    ShiroAddTranslation(@"Connected", @"Подключено");
    ShiroAddTranslation(@"Connecting", @"Подключение");
    ShiroAddTranslation(@"Disconnected", @"Отключено");
    ShiroAddTranslation(@"Connect", @"Подключить");
    ShiroAddTranslation(@"Disconnect", @"Отключить");
    ShiroAddTranslation(@"No server selected", @"Сервер не выбран");
    ShiroAddTranslation(@"Host", @"Адрес");
    ShiroAddTranslation(@"Transport", @"Транспорт");
    ShiroAddTranslation(@"Security", @"Защита");
    ShiroAddTranslation(@"Latency", @"Задержка");
    ShiroAddTranslation(@"TCP latency", @"Задержка TCP");
    ShiroAddTranslation(@"Source", @"Источник");
    ShiroAddTranslation(@"Link", @"Ссылка");
    ShiroAddTranslation(@"loading", @"загрузка");
    ShiroAddTranslation(@"unavailable", @"недоступна");
    ShiroAddTranslation(@"copied", @"скопирована");
    ShiroAddTranslation(@"unreachable", @"нет ответа");
    ShiroAddTranslation(@"Ping", @"Пинг");
    ShiroAddTranslation(@"Timeout", @"Тайм-аут");
    ShiroAddTranslation(@"Checking connection", @"Проверка подключения");
    ShiroAddTranslation(@"Checking TCP", @"Проверка TCP");
    ShiroAddTranslation(@"Checking server", @"Проверка сервера");
    ShiroAddTranslation(@"Loading servers and subscriptions...", @"Загрузка серверов и подписок...");
    ShiroAddTranslation(@"Refreshing subscriptions", @"Обновление подписок");
    ShiroAddTranslation(@"Checking tunnel", @"Проверка туннеля");
    ShiroAddTranslation(@"Ping complete", @"Пинг завершён");
    ShiroAddTranslation(@"Copy", @"Копировать");
    ShiroAddTranslation(@"This build cannot dial this profile", @"Эта сборка не умеет подключаться к такому профилю");

/* theme editor: palette slots */
    ShiroAddTranslation(@"Background", @"Фон");
    ShiroAddTranslation(@"Background low", @"Фон снизу");
    ShiroAddTranslation(@"Felt", @"Подложка");
    ShiroAddTranslation(@"Online", @"Активно");
    ShiroAddTranslation(@"Online low", @"Активно снизу");
    ShiroAddTranslation(@"Offline", @"Неактивно");
    ShiroAddTranslation(@"Offline low", @"Неактивно снизу");
    ShiroAddTranslation(@"Text", @"Текст");
    ShiroAddTranslation(@"Text muted", @"Текст приглушённый");
    ShiroAddTranslation(@"Accent", @"Акцент");
    ShiroAddTranslation(@"Accent low", @"Акцент нажатый");
    ShiroAddTranslation(@"Chrome low", @"Панели снизу");
    ShiroAddTranslation(@"Cell", @"Ячейка");
    ShiroAddTranslation(@"Cell low", @"Ячейка снизу");
    ShiroAddTranslation(@"Well", @"Углубление");
    ShiroAddTranslation(@"wallpaper top", @"обои сверху");
    ShiroAddTranslation(@"wallpaper bottom", @"обои снизу");
    ShiroAddTranslation(@"list backdrop", @"фон списка");
    ShiroAddTranslation(@"connected button top", @"кнопка подключено, верх");
    ShiroAddTranslation(@"connected button bottom", @"кнопка подключено, низ");
    ShiroAddTranslation(@"disconnected button top", @"кнопка отключено, верх");
    ShiroAddTranslation(@"disconnected button bottom", @"кнопка отключено, низ");
    ShiroAddTranslation(@"primary label", @"основная надпись");
    ShiroAddTranslation(@"secondary label", @"второстепенная надпись");
    ShiroAddTranslation(@"links and glyphs", @"ссылки и значки");
    ShiroAddTranslation(@"pressed accent", @"акцент при нажатии");
    ShiroAddTranslation(@"bars top", @"панели сверху");
    ShiroAddTranslation(@"bars bottom", @"панели снизу");
    ShiroAddTranslation(@"row top", @"строка сверху");
    ShiroAddTranslation(@"row bottom", @"строка снизу");
    ShiroAddTranslation(@"list inset tint", @"подложка списка");

/* theme editor: failures surfaced from storage */
    ShiroAddTranslation(@"Theme is not a custom theme", @"Это не пользовательская тема");
    ShiroAddTranslation(@"Could not serialize theme", @"Не удалось сохранить тему в файл");
    ShiroAddTranslation(@"Could not write to Documents", @"Не удалось записать в Documents");
    ShiroAddTranslation(@"Not a Shiro theme file", @"Это не файл темы Shiro");
    ShiroAddTranslation(@"Could not read the file", @"Не удалось прочитать файл");
    ShiroAddTranslation(@"Unsupported theme format", @"Неподдерживаемый формат темы");
    ShiroAddTranslation(@"Theme file is incomplete", @"Файл темы неполный");
    ShiroAddTranslation(@"Custom theme limit reached", @"Достигнут предел числа своих тем");
    ShiroAddTranslation(@"Download", @"Загрузка");
    ShiroAddTranslation(@"Upload", @"Отдача");
    ShiroAddTranslation(@"Statistics", @"Статистика");
    ShiroAddTranslation(@"Choose a server", @"Выбор сервера");
    ShiroAddTranslation(@"Search a country or a city", @"Поиск страны или города");
    ShiroAddTranslation(@"Fastest server", @"Лучший сервер");
    ShiroAddTranslation(@"Tap to connect", @"Нажми, чтобы подключиться");
    ShiroAddTranslation(@"Looking for the fastest server", @"Ищу самый быстрый сервер");
    ShiroAddTranslation(@"no server answered the check", @"ни один сервер не ответил на проверку");
    ShiroAddTranslation(@"No servers", @"Нет серверов");
    ShiroAddTranslation(@"Add a subscription or a server", @"Добавь подписку или сервер");
    ShiroAddTranslation(@"Tap to open the list", @"Нажми, чтобы открыть список");
    ShiroAddTranslation(@"%d ms", @"%d мс");
    ShiroAddTranslation(@"Mbit/s", @"Мбит/с");
    ShiroAddTranslation(@"Kbit/s", @"Кбит/с");
    ShiroAddTranslation(@"bit/s", @"бит/с");
    ShiroAddTranslation(@"Gbit/s", @"Гбит/с");
    ShiroAddTranslation(@"Done reordering", @"Закончить перестановку");
    ShiroAddTranslation(@"Reorder manual servers", @"Переставить свои серверы");
    ShiroAddTranslation(@"Session", @"Сеанс");
    ShiroAddTranslation(@"Subscriptions", @"Подписки");
    ShiroAddTranslation(@"Status", @"Состояние");
    ShiroAddTranslation(@"Uptime", @"Время работы");
    ShiroAddTranslation(@"Download speed", @"Скорость загрузки");
    ShiroAddTranslation(@"Upload speed", @"Скорость отдачи");
    ShiroAddTranslation(@"%@ of %@", @"%@ из %@");
    ShiroAddTranslation(@"Main", @"Основные");
    ShiroAddTranslation(@"App", @"Приложение");
    ShiroAddTranslation(@"Advanced", @"Дополнительно");
    ShiroAddTranslation(@"Quick connect", @"Быстрое подключение");
    ShiroAddTranslation(@"Theme", @"Тема");
    ShiroAddTranslation(@"Backup", @"Резервная копия");
    ShiroAddTranslation(@"DNS", @"DNS");
    ShiroAddTranslation(@"Split tunneling", @"Раздельное туннелирование");
    ShiroAddTranslation(@"Real delay", @"Реальная задержка");

/* common screen text: Chinese is kept here instead of relying on system
   strings, because the app runs on iOS 5 where no localization bundle exists */
    ShiroAddChineseTranslation(@"About", @"关于");
    ShiroAddChineseTranslation(@"Amnezia/VLESS Client", @"Amnezia/VLESS 客户端");
    ShiroAddChineseTranslation(@"Model", @"型号");
    ShiroAddChineseTranslation(@"iOS version", @"iOS 版本");
    ShiroAddChineseTranslation(@"Architecture", @"架构");
    ShiroAddChineseTranslation(@"TLS mode", @"TLS 模式");
    ShiroAddChineseTranslation(@"How it works", @"工作方式");
    ShiroAddChineseTranslation(@"Apps and system traffic use the selected profile. Routing needs root, and a jailbreak already provides it.", @"应用和系统流量使用选中的配置。路由需要 root，越狱已经提供了权限。");
    ShiroAddChineseTranslation(@"Transports", @"传输协议");
    ShiroAddChineseTranslation(@"Compatibility", @"兼容性");
    ShiroAddChineseTranslation(@"Token-authenticated control socket · subscription SSRF protection · secret redaction · real transport checks.", @"带令牌认证的控制 socket · 防止订阅 SSRF · 日志隐藏密钥 · 真实传输检查。");
    ShiroAddChineseTranslation(@"Links", @"链接");
    ShiroAddChineseTranslation(@"Credits", @"致谢");
    ShiroAddChineseTranslation(@"Special thanks", @"特别感谢");
    ShiroAddChineseTranslation(@"Sponsors", @"赞助者");
    ShiroAddChineseTranslation(@"Testers", @"测试者");
    ShiroAddChineseTranslation(@"Emoji artwork", @"表情图案");
    ShiroAddChineseTranslation(@"Twemoji by Twitter, Inc. and contributors (CC BY 4.0)", @"Twitter, Inc. 及贡献者的 Twemoji（CC BY 4.0）");
    ShiroAddChineseTranslation(@"system TLS, the compatibility hook is not injected", @"系统 TLS，不注入兼容性 hook");
    ShiroAddChineseTranslation(@"external tlsfix present, shirotlsfix hooks stay off", @"检测到外部 tlsfix，保持 shirotlsfix hook 关闭");
    ShiroAddChineseTranslation(@"shirotlsfix, Safari TLS 1.3 when MobileSubstrate is installed", @"shirotlsfix，用于 MobileSubstrate 下 Safari TLS 1.3");
    ShiroAddChineseTranslation(@"Settings", @"设置");
    ShiroAddChineseTranslation(@"Language", @"语言");
    ShiroAddChineseTranslation(@"English", @"English");
    ShiroAddChineseTranslation(@"Russian", @"Русский");
    ShiroAddChineseTranslation(@"Chinese", @"中文");
    ShiroAddChineseTranslation(@"GENERAL", @"常规");
    ShiroAddChineseTranslation(@"APP", @"应用");
    ShiroAddChineseTranslation(@"DEVELOPER", @"开发者");
    ShiroAddChineseTranslation(@"Developer settings", @"开发者设置");
    ShiroAddChineseTranslation(@"Developer settings are now visible in Settings. Tap the section heading five times to hide them again.", @"开发者设置现已显示在设置中。点击该区域标题五次即可再次隐藏。");
    ShiroAddChineseTranslation(@"Server", @"服务器");
    ShiroAddChineseTranslation(@"SERVER", @"服务器");
    ShiroAddChineseTranslation(@"Add", @"添加");
    ShiroAddChineseTranslation(@"Available servers: %lu", @"可用服务器：%lu");
    ShiroAddChineseTranslation(@"Add server", @"添加服务器");
    ShiroAddChineseTranslation(@"Add subscription", @"添加订阅");
    ShiroAddChineseTranslation(@"Cancel", @"取消");
    ShiroAddChineseTranslation(@"Close", @"关闭");
    ShiroAddChineseTranslation(@"OK", @"确定");
    ShiroAddChineseTranslation(@"Save", @"保存");
    ShiroAddChineseTranslation(@"Delete", @"删除");
    ShiroAddChineseTranslation(@"Remove", @"移除");
    ShiroAddChineseTranslation(@"Edit", @"编辑");
    ShiroAddChineseTranslation(@"Copy", @"复制");
    ShiroAddChineseTranslation(@"Done", @"完成");
    ShiroAddChineseTranslation(@"Complete", @"完成");
    ShiroAddChineseTranslation(@"Refresh", @"刷新");
    ShiroAddChineseTranslation(@"Refresh now", @"立即刷新");
    ShiroAddChineseTranslation(@"Update", @"更新");
    ShiroAddChineseTranslation(@"Update Shiro", @"更新 Shiro");
    ShiroAddChineseTranslation(@"Update subscriptions", @"更新订阅");
    ShiroAddChineseTranslation(@"Connect", @"连接");
    ShiroAddChineseTranslation(@"Disconnect", @"断开连接");
    ShiroAddChineseTranslation(@"Connected", @"已连接");
    ShiroAddChineseTranslation(@"Connecting", @"连接中");
    ShiroAddChineseTranslation(@"Disconnected", @"未连接");
    ShiroAddChineseTranslation(@"Connection failed", @"连接失败");
    ShiroAddChineseTranslation(@"Checking", @"检查中");
    ShiroAddChineseTranslation(@"Checking server", @"正在检查服务器");
    ShiroAddChineseTranslation(@"Loading servers and subscriptions...", @"正在加载服务器和订阅...");
    ShiroAddChineseTranslation(@"Checking connection", @"正在检查连接");
    ShiroAddChineseTranslation(@"Checking tunnel", @"正在检查隧道");
    ShiroAddChineseTranslation(@"Ping", @"Ping");
    ShiroAddChineseTranslation(@"Check ping", @"检查 Ping");
    ShiroAddChineseTranslation(@"Check servers", @"检查服务器");
    ShiroAddChineseTranslation(@"Ping complete", @"Ping 完成");
    ShiroAddChineseTranslation(@"Timeout", @"超时");
    ShiroAddChineseTranslation(@"no servers to ping", @"没有可 Ping 的服务器");
    ShiroAddChineseTranslation(@"State", @"状态");
    ShiroAddChineseTranslation(@"Version", @"版本");
    ShiroAddChineseTranslation(@"Sort servers", @"服务器排序");
    ShiroAddChineseTranslation(@"Stored order", @"保存的顺序");
    ShiroAddChineseTranslation(@"By name", @"按名称");
    ShiroAddChineseTranslation(@"By latency", @"按延迟");
    ShiroAddChineseTranslation(@"No server selected", @"未选择服务器");
    ShiroAddChineseTranslation(@"No servers yet", @"还没有服务器");
    ShiroAddChineseTranslation(@"To use a server add a proxy link or a subscription.", @"请添加代理链接或订阅以使用服务器。");
    ShiroAddChineseTranslation(@"Connect at startup", @"启动时连接");
    ShiroAddChineseTranslation(@"Dial the selected server after a reboot", @"重启后连接选中的服务器");
    ShiroAddChineseTranslation(@"Reconnect automatically", @"自动重连");
    ShiroAddChineseTranslation(@"After a drop or a change of network", @"断线或网络变化后");
    ShiroAddChineseTranslation(@"Try another server", @"尝试其他服务器");
    ShiroAddChineseTranslation(@"Only inside the same section, fastest first", @"仅在同一分组内，优先最快的服务器");
    ShiroAddChineseTranslation(@"Off", @"关闭");
    ShiroAddChineseTranslation(@"Every %@", @"每 %@");
    ShiroAddChineseTranslation(@"Reconnect attempts", @"重连次数");
    ShiroAddChineseTranslation(@"Until it works", @"直到成功");
    ShiroAddChineseTranslation(@"%d attempts", @"%d 次");
    ShiroAddChineseTranslation(@"Routing rules", @"路由规则");
    ShiroAddChineseTranslation(@"Send a domain or a subnet direct, or block it", @"让域名或网段直连，或阻止它");
    ShiroAddChineseTranslation(@"Direct", @"直连");
    ShiroAddChineseTranslation(@"Block", @"阻止");
    ShiroAddChineseTranslation(@"Through the tunnel", @"通过隧道");
    ShiroAddChineseTranslation(@"Domain and subdomains", @"域名及子域名");
    ShiroAddChineseTranslation(@"Keyword", @"关键词");
    ShiroAddChineseTranslation(@"IP range", @"IP 网段");
    ShiroAddChineseTranslation(@"What should happen to the traffic?", @"如何处理流量？");
    ShiroAddChineseTranslation(@"What should it match?", @"匹配什么？");
    ShiroAddChineseTranslation(@"Value", @"值");
    ShiroAddChineseTranslation(@"Theme", @"主题");
    ShiroAddChineseTranslation(@"Themes", @"主题");
    ShiroAddChineseTranslation(@"Style", @"风格");
    ShiroAddChineseTranslation(@"Custom", @"自定义");
    ShiroAddChineseTranslation(@"Appearance", @"外观");
    ShiroAddChineseTranslation(@"Dark / Light applies to the selected style. Choice is stored on device.", @"深色和浅色模式应用于所选风格。设置保存在设备上。");
    ShiroAddChineseTranslation(@"Accent", @"强调色");
    ShiroAddChineseTranslation(@"Play a short ouch on every button tap.", @"每次点击按钮时播放短音效。");
    ShiroAddChineseTranslation(@"Play a short meow on every button tap.", @"每次点击按钮时播放短猫叫声。");
    ShiroAddChineseTranslation(@"Dark", @"深色");
    ShiroAddChineseTranslation(@"Light", @"浅色");
    ShiroAddChineseTranslation(@"System Logs", @"系统日志");
    ShiroAddChineseTranslation(@"Export backup", @"导出备份");
    ShiroAddChineseTranslation(@"Restore backup", @"恢复备份");
    ShiroAddChineseTranslation(@"Save a config file to Documents", @"将配置文件保存到 Documents");
    ShiroAddChineseTranslation(@"Validate, then replace configuration", @"验证后替换配置");
    ShiroAddChineseTranslation(@"Choose a Shiro .deb package", @"选择 Shiro .deb 软件包");
    ShiroAddChineseTranslation(@"Developer", @"开发者");
    ShiroAddChineseTranslation(@"@axi8229\nFull Apple A7 support and Hysteria stabilization", @"@axi8229\n完整支持 Apple A7 并稳定 Hysteria");
    ShiroAddChineseTranslation(@"What was chosen, checks, overrides and rescue", @"选择项、检查、覆盖和恢复工具");
    ShiroAddChineseTranslation(@"Transport", @"传输");
    ShiroAddChineseTranslation(@"Security", @"安全");
    ShiroAddChineseTranslation(@"Latency", @"延迟");
    ShiroAddChineseTranslation(@"TCP latency", @"TCP 延迟");
    ShiroAddChineseTranslation(@"Host", @"地址");
    ShiroAddChineseTranslation(@"PASSWORD", @"密码");
    ShiroAddChineseTranslation(@"UUID", @"UUID");
    ShiroAddChineseTranslation(@"ADDRESS", @"地址");
    ShiroAddChineseTranslation(@"PORT", @"端口");
    ShiroAddChineseTranslation(@"SNI", @"SNI");
    ShiroAddChineseTranslation(@"NAME", @"名称");
    ShiroAddChineseTranslation(@"Subscription", @"订阅");
    ShiroAddChineseTranslation(@"Subscription details", @"订阅详情");
    ShiroAddChineseTranslation(@"Subscription URL", @"订阅 URL");
    ShiroAddChineseTranslation(@"Title and URL", @"标题和 URL");
    ShiroAddChineseTranslation(@"Manual", @"手动");
    ShiroAddChineseTranslation(@"Not provided", @"未提供");
    ShiroAddChineseTranslation(@"Used", @"已使用");
    ShiroAddChineseTranslation(@"Remaining", @"剩余");
    ShiroAddChineseTranslation(@"Limit", @"上限");
    ShiroAddChineseTranslation(@"Uploaded", @"上传");
    ShiroAddChineseTranslation(@"Downloaded", @"下载");
    ShiroAddChineseTranslation(@"Expires", @"到期");
    ShiroAddChineseTranslation(@"Expired", @"已过期");
    ShiroAddChineseTranslation(@"Description", @"描述");
    ShiroAddChineseTranslation(@"Contact support", @"联系支持");
    ShiroAddChineseTranslation(@"Paste", @"粘贴");
    ShiroAddChineseTranslation(@"Paste from clipboard", @"从剪贴板粘贴");
    ShiroAddChineseTranslation(@"QR code", @"二维码");
    ShiroAddChineseTranslation(@"Import from file", @"从文件导入");
    ShiroAddChineseTranslation(@"Import file", @"导入文件");
    ShiroAddChineseTranslation(@"Scan QR", @"扫描二维码");
    ShiroAddChineseTranslation(@"Delete all servers", @"删除所有服务器");
    ShiroAddChineseTranslation(@"Every server in the Manual group is removed. Subscriptions are not touched.", @"将删除手动分组中的所有服务器，不会修改订阅。");
    ShiroAddChineseTranslation(@"Configuration backup", @"配置备份");
    ShiroAddChineseTranslation(@"Replace configuration?", @"替换配置？");
    ShiroAddChineseTranslation(@"The imported backup will replace all current servers and subscriptions.", @"导入的备份将替换当前所有服务器和订阅。");
    ShiroAddChineseTranslation(@"Configuration restored", @"配置已恢复");
    ShiroAddChineseTranslation(@"No daemon logs available", @"没有可用的 daemon 日志");
    ShiroAddChineseTranslation(@"Loading logs...", @"正在加载日志...");
    ShiroAddChineseTranslation(@"Error", @"错误");
    ShiroAddChineseTranslation(@"Failed", @"失败");
    ShiroAddChineseTranslation(@"Install failed", @"安装失败");
    ShiroAddChineseTranslation(@"Installing", @"正在安装");
    ShiroAddChineseTranslation(@"Starting", @"正在启动");
    ShiroAddChineseTranslation(@"Starting services", @"正在启动服务");
    ShiroAddChineseTranslation(@"Stopping services", @"正在停止服务");
    ShiroAddChineseTranslation(@"Restarting shirod", @"正在重启 shirod");
    ShiroAddChineseTranslation(@"daemon offline", @"daemon 离线");
    ShiroAddChineseTranslation(@"Shiro", @"Shiro");
    ShiroAddChineseTranslation(@"No server in the catalog", @"目录中没有服务器");
    ShiroAddChineseTranslation(@"No servers in the catalog.", @"目录中没有服务器。");
    ShiroAddChineseTranslation(@"Unknown error", @"未知错误");
    ShiroAddChineseTranslation(@"The report is on the clipboard.", @"报告已复制到剪贴板。");
    ShiroAddChineseTranslation(@"Copied to the clipboard.", @"已复制到剪贴板。");
    ShiroAddChineseTranslation(@"Download", @"下载");
    ShiroAddChineseTranslation(@"Upload", @"上传");
    ShiroAddChineseTranslation(@"Statistics", @"统计");
    ShiroAddChineseTranslation(@"Choose a server", @"选择服务器");
    ShiroAddChineseTranslation(@"Search a country or a city", @"搜索国家或城市");
    ShiroAddChineseTranslation(@"Auto", @"自动");
    ShiroAddChineseTranslation(@"All", @"全部");
    ShiroAddChineseTranslation(@"Fastest server", @"最快的服务器");
    ShiroAddChineseTranslation(@"Tap to connect", @"点击连接");
    ShiroAddChineseTranslation(@"Looking for the fastest server", @"正在寻找最快的服务器");
    ShiroAddChineseTranslation(@"no server answered the check", @"没有服务器响应检测");
    ShiroAddChineseTranslation(@"No servers", @"没有服务器");
    ShiroAddChineseTranslation(@"Add a subscription or a server", @"添加订阅或服务器");
    ShiroAddChineseTranslation(@"Tap to open the list", @"点击打开列表");
    ShiroAddChineseTranslation(@"%d ms", @"%d 毫秒");
    ShiroAddChineseTranslation(@"Mbit/s", @"Mbit/s");
    ShiroAddChineseTranslation(@"Kbit/s", @"Kbit/s");
    ShiroAddChineseTranslation(@"Done reordering", @"完成排序");
    ShiroAddChineseTranslation(@"Reorder manual servers", @"调整手动服务器顺序");
    ShiroAddChineseTranslation(@"Session", @"会话");
    ShiroAddChineseTranslation(@"Subscriptions", @"订阅");
    ShiroAddChineseTranslation(@"Status", @"状态");
    ShiroAddChineseTranslation(@"Uptime", @"运行时间");
    ShiroAddChineseTranslation(@"Download speed", @"下载速度");
    ShiroAddChineseTranslation(@"Upload speed", @"上传速度");
    ShiroAddChineseTranslation(@"%@ of %@", @"%@ / %@");
    ShiroAddChineseTranslation(@"expired", @"已过期");
    ShiroAddChineseTranslation(@"Main", @"常规");
    ShiroAddChineseTranslation(@"App", @"应用");
    ShiroAddChineseTranslation(@"Advanced", @"高级");
    ShiroAddChineseTranslation(@"Quick connect", @"快速连接");
    ShiroAddChineseTranslation(@"Theme", @"主题");
    ShiroAddChineseTranslation(@"Backup", @"备份");
    ShiroAddChineseTranslation(@"DNS", @"DNS");
    ShiroAddChineseTranslation(@"Split tunneling", @"分流");
    ShiroAddChineseTranslation(@"Real delay", @"真实延迟");
    ShiroAddChineseTranslation(@"Local DNS port", @"本地 DNS 端口");
    ShiroAddChineseTranslation(@"SOCKS port", @"SOCKS 端口");
    ShiroAddChineseTranslation(@"unreachable", @"无法访问");
    ShiroAddChineseTranslation(@"%d more", @"还有 %d 项");
    ShiroAddChineseTranslation(@"A port number between 1 and 65535", @"请输入 1 到 65535 之间的端口号");
    ShiroAddChineseTranslation(@"Active tunnel", @"当前隧道");
    ShiroAddChineseTranslation(@"Add dark variant", @"添加深色版本");
    ShiroAddChineseTranslation(@"An IPv4 address, for example 1.1.1.1", @"请输入 IPv4 地址，例如 1.1.1.1");
    ShiroAddChineseTranslation(@"Applied on the next connect.", @"下次连接时生效。");
    ShiroAddChineseTranslation(@"Asking the daemon...", @"正在查询守护进程…");
    ShiroAddChineseTranslation(@"Backend", @"后端");
    ShiroAddChineseTranslation(@"Backend, listeners, trace", @"后端、监听器、跟踪");
    ShiroAddChineseTranslation(@"Backend, tunnel, ports, DNS, rules", @"后端、隧道、端口、DNS、规则");
    ShiroAddChineseTranslation(@"Backup export failed", @"导出备份失败");
    ShiroAddChineseTranslation(@"Backup restore failed", @"恢复备份失败");
    ShiroAddChineseTranslation(@"Blocked answers", @"已阻止的响应");
    ShiroAddChineseTranslation(@"CHECK", @"检查");
    ShiroAddChineseTranslation(@"CIPHER", @"加密方式");
    ShiroAddChineseTranslation(@"Catalog and rules are kept.", @"服务器目录和规则已保留。");
    ShiroAddChineseTranslation(@"Catalog is kept.", @"服务器目录已保留。");
    ShiroAddChineseTranslation(@"Checks", @"检查");
    ShiroAddChineseTranslation(@"Classic", @"经典");
    ShiroAddChineseTranslation(@"Clear", @"清除");
    ShiroAddChineseTranslation(@"Connect hook only", @"仅连接钩子");
    ShiroAddChineseTranslation(@"Console", @"控制台");
    ShiroAddChineseTranslation(@"Copied in full.", @"已完整复制。");
    ShiroAddChineseTranslation(@"Copy current theme", @"复制当前主题");
    ShiroAddChineseTranslation(@"Corners", @"圆角");
    ShiroAddChineseTranslation(@"Could not create theme", @"无法创建主题");
    ShiroAddChineseTranslation(@"Could not stage backup", @"无法暂存备份");
    ShiroAddChineseTranslation(@"Crash and launch log", @"崩溃与启动日志");
    ShiroAddChineseTranslation(@"Crash and launch report", @"崩溃与启动报告");
    ShiroAddChineseTranslation(@"Crash log, safe mode, device id, bundle", @"崩溃日志、安全模式、设备 ID、诊断包");
    ShiroAddChineseTranslation(@"DARK COLORS", @"深色配色");
    ShiroAddChineseTranslation(@"DEVICE ID", @"设备 ID");
    ShiroAddChineseTranslation(@"DIAGNOSTICS", @"诊断");
    ShiroAddChineseTranslation(@"Daemon is unreachable", @"无法连接守护进程");
    ShiroAddChineseTranslation(@"Delete all rules", @"删除所有规则");
    ShiroAddChineseTranslation(@"Delete theme", @"删除主题");
    ShiroAddChineseTranslation(@"Delete theme?", @"删除主题？");
    ShiroAddChineseTranslation(@"Device ID (tap to copy)", @"设备 ID（点击复制）");
    ShiroAddChineseTranslation(@"Device ID copied", @"设备 ID 已复制");
    ShiroAddChineseTranslation(@"Device id", @"设备 ID");
    ShiroAddChineseTranslation(@"Diagnostics bundle", @"诊断包");
    ShiroAddChineseTranslation(@"Done.", @"已完成。");
    ShiroAddChineseTranslation(@"Duplicates", @"重复项");
    ShiroAddChineseTranslation(@"Edit details", @"编辑详情");
    ShiroAddChineseTranslation(@"Edit server", @"编辑服务器");
    ShiroAddChineseTranslation(@"Editing", @"正在编辑");
    ShiroAddChineseTranslation(@"Empty manual list", @"清空手动列表");
    ShiroAddChineseTranslation(@"Enter", @"输入");
    ShiroAddChineseTranslation(@"Export debug bundle", @"导出调试包");
    ShiroAddChineseTranslation(@"Export failed", @"导出失败");
    ShiroAddChineseTranslation(@"Export to Documents", @"导出到 Documents");
    ShiroAddChineseTranslation(@"FINGERPRINT", @"指纹");
    ShiroAddChineseTranslation(@"FIREWALL", @"防火墙");
    ShiroAddChineseTranslation(@"FLOW", @"流控");
    ShiroAddChineseTranslation(@"FORCE", @"强制");
    ShiroAddChineseTranslation(@"FPS overlay", @"FPS 浮窗");
    ShiroAddChineseTranslation(@"Failed launches", @"启动失败次数");
    ShiroAddChineseTranslation(@"Flat", @"扁平");
    ShiroAddChineseTranslation(@"Flush", @"清空");
    ShiroAddChineseTranslation(@"Flush DNS cache", @"清空 DNS 缓存");
    ShiroAddChineseTranslation(@"For example 10.0.0.0/8", @"例如 10.0.0.0/8");
    ShiroAddChineseTranslation(@"For example example.com", @"例如 example.com");
    ShiroAddChineseTranslation(@"For example googlevideo", @"例如 googlevideo");
    ShiroAddChineseTranslation(@"Force", @"强制");
    ShiroAddChineseTranslation(@"Forget direct addresses", @"清除直连地址");
    ShiroAddChineseTranslation(@"Glass", @"玻璃");
    ShiroAddChineseTranslation(@"HWID requires a Cookie request header", @"HWID 需要 Cookie 请求头");
    ShiroAddChineseTranslation(@"Header: value", @"请求头：值");
    ShiroAddChineseTranslation(@"Ignore device gating", @"忽略设备限制");
    ShiroAddChineseTranslation(@"Import", @"导入");
    ShiroAddChineseTranslation(@"Import failed", @"导入失败");
    ShiroAddChineseTranslation(@"Import from Documents", @"从 Documents 导入");
    ShiroAddChineseTranslation(@"Import theme", @"导入主题");
    ShiroAddChineseTranslation(@"Issue", @"问题");
    ShiroAddChineseTranslation(@"LAUNCH", @"启动");
    ShiroAddChineseTranslation(@"LIGHT COLORS", @"浅色配色");
    ShiroAddChineseTranslation(@"LISTENERS AND DNS", @"监听器与 DNS");
    ShiroAddChineseTranslation(@"Leave safe mode", @"退出安全模式");
    ShiroAddChineseTranslation(@"Local proxy", @"本地代理");
    ShiroAddChineseTranslation(@"Long names", @"长名称");
    ShiroAddChineseTranslation(@"Long names, duplicates and an empty manual list", @"长名称、重复项和空的手动列表");
    ShiroAddChineseTranslation(@"Look", @"外观");
    ShiroAddChineseTranslation(@"Mode", @"模式");
    ShiroAddChineseTranslation(@"Name", @"名称");
    ShiroAddChineseTranslation(@"New device id", @"生成新设备 ID");
    ShiroAddChineseTranslation(@"New theme", @"新建主题");
    ShiroAddChineseTranslation(@"No app fault report", @"没有应用崩溃报告");
    ShiroAddChineseTranslation(@"No rules: everything goes through the tunnel. Add one with the plus button.", @"没有规则：所有流量都经过隧道。点击加号添加规则。");
    ShiroAddChineseTranslation(@"None", @"无");
    ShiroAddChineseTranslation(@"Not a shiro backup", @"不是 Shiro 备份文件");
    ShiroAddChineseTranslation(@"Off from the next launch.", @"下次启动时关闭。");
    ShiroAddChineseTranslation(@"Only manually added servers are removed.", @"只会删除手动添加的服务器。");
    ShiroAddChineseTranslation(@"PATH", @"路径");
    ShiroAddChineseTranslation(@"Profile handshake", @"配置握手");
    ShiroAddChineseTranslation(@"REMOVE", @"移除");
    ShiroAddChineseTranslation(@"Reading the rules from the daemon...", @"正在从守护进程读取规则…");
    ShiroAddChineseTranslation(@"Refreshing subscriptions", @"正在刷新订阅");
    ShiroAddChineseTranslation(@"Replace", @"替换");
    ShiroAddChineseTranslation(@"Rescue", @"恢复");
    ShiroAddChineseTranslation(@"Reset", @"重置");
    ShiroAddChineseTranslation(@"Reset settings", @"重置设置");
    ShiroAddChineseTranslation(@"Restore configuration", @"恢复配置");
    ShiroAddChineseTranslation(@"Result", @"结果");
    ShiroAddChineseTranslation(@"Run", @"运行");
    ShiroAddChineseTranslation(@"Running...", @"运行中…");
    ShiroAddChineseTranslation(@"SOCKS on 0.0.0.0", @"在 0.0.0.0 上监听 SOCKS");
    ShiroAddChineseTranslation(@"STAGES", @"阶段");
    ShiroAddChineseTranslation(@"STYLE", @"风格");
    ShiroAddChineseTranslation(@"SUBSCRIPTIONS", @"订阅");
    ShiroAddChineseTranslation(@"Safe mode", @"安全模式");
    ShiroAddChineseTranslation(@"Safe mode next launch", @"下次启动进入安全模式");
    ShiroAddChineseTranslation(@"Saved to Documents/shiro-backup.shiro", @"已保存到 Documents/shiro-backup.shiro");
    ShiroAddChineseTranslation(@"Send HWID in Cookie", @"在 Cookie 中发送 HWID");
    ShiroAddChineseTranslation(@"Shiro-core", @"Shiro-core");
    ShiroAddChineseTranslation(@"Session trace", @"会话跟踪");
    ShiroAddChineseTranslation(@"Show tunnel routes", @"显示隧道路由");
    ShiroAddChineseTranslation(@"Staged probes and the tunnel routes", @"分阶段检测和隧道路由");
    ShiroAddChineseTranslation(@"Stock theme, no glass, no decor. Your theme stays on disk.", @"使用默认主题，不显示玻璃与装饰效果。原主题仍保存在设备上。");
    ShiroAddChineseTranslation(@"TCP to the node", @"连接节点的 TCP");
    ShiroAddChineseTranslation(@"Talk to the control socket without ssh", @"无需 SSH 即可访问控制套接字");
    ShiroAddChineseTranslation(@"Test fixtures", @"测试数据");
    ShiroAddChineseTranslation(@"The custom theme limit is reached.", @"自定义主题数量已达上限。");
    ShiroAddChineseTranslation(@"The daemon is not answering, so these cannot be read or changed.", @"守护进程没有响应，因此无法读取或更改这些设置。");
    ShiroAddChineseTranslation(@"The next launch runs in safe mode.", @"下次启动将进入安全模式。");
    ShiroAddChineseTranslation(@"The old id is gone for good.", @"旧设备 ID 已永久删除。");
    ShiroAddChineseTranslation(@"The subscription refused this device.", @"订阅拒绝此设备。");
    ShiroAddChineseTranslation(@"Theme exported", @"主题已导出");
    ShiroAddChineseTranslation(@"Theme imported", @"主题已导入");
    ShiroAddChineseTranslation(@"Theme name", @"主题名称");
    ShiroAddChineseTranslation(@"This URL sends the subscription without TLS. Import it only if you trust this network and provider.", @"此 URL 未使用 TLS 传输订阅。请仅在信任网络和服务商时导入。");
    ShiroAddChineseTranslation(@"This build cannot dial this profile", @"此版本无法连接该配置");
    ShiroAddChineseTranslation(@"Tunnel routes", @"隧道路由");
    ShiroAddChineseTranslation(@"Unencrypted subscription", @"未加密的订阅");
    ShiroAddChineseTranslation(@"VARIANT", @"版本");
    ShiroAddChineseTranslation(@"Zero address", @"空地址");
    ShiroAddChineseTranslation(@"all", @"全部");
    ShiroAddChineseTranslation(@"checking", @"检查中");
    ShiroAddChineseTranslation(@"copied", @"已复制");
    ShiroAddChineseTranslation(@"hits", @"命中次数");
    ShiroAddChineseTranslation(@"loading", @"加载中");
    ShiroAddChineseTranslation(@"name and url required", @"请填写名称和 URL");
    ShiroAddChineseTranslation(@"no answer", @"无响应");
    ShiroAddChineseTranslation(@"not available yet", @"暂时不可用");
    ShiroAddChineseTranslation(@"nothing recorded", @"没有记录");
    ShiroAddChineseTranslation(@"passed in %d ms", @"耗时 %d 毫秒，通过");
    ShiroAddChineseTranslation(@"the daemon did not answer", @"守护进程没有响应");
    ShiroAddChineseTranslation(@"unavailable", @"不可用");
    ShiroAddChineseTranslation(@"utun tunnel", @"utun 隧道");
    ShiroAddChineseTranslation(@"(no log)", @"（无日志）");
    ShiroAddChineseTranslation(@"A live profile cannot be edited", @"正在使用的配置无法编辑");
    ShiroAddChineseTranslation(@"Accent", @"强调色");
    ShiroAddChineseTranslation(@"Accent low", @"强调色底部");
    ShiroAddChineseTranslation(@"Allow insecure", @"允许不安全连接");
    ShiroAddChineseTranslation(@"Almost done", @"即将完成");
    ShiroAddChineseTranslation(@"Apply anyway", @"仍然应用");
    ShiroAddChineseTranslation(@"Backend forced to", @"强制后端");
    ShiroAddChineseTranslation(@"Backend in use", @"当前后端");
    ShiroAddChineseTranslation(@"Backend pinned to", @"固定后端");
    ShiroAddChineseTranslation(@"Background", @"背景");
    ShiroAddChineseTranslation(@"Background low", @"背景底部");
    ShiroAddChineseTranslation(@"Battery", @"电池");
    ShiroAddChineseTranslation(@"Block response", @"阻止响应");
    ShiroAddChineseTranslation(@"Busiest rule", @"命中最多的规则");
    ShiroAddChineseTranslation(@"Bypass evicted", @"已移除的绕过项");
    ShiroAddChineseTranslation(@"Bypass evictions", @"绕过项移除次数");
    ShiroAddChineseTranslation(@"Bypass table", @"绕过表");
    ShiroAddChineseTranslation(@"CHOSEN", @"已选择");
    ShiroAddChineseTranslation(@"CONNECTION", @"连接");
    ShiroAddChineseTranslation(@"Camera access could not be requested", @"无法请求相机权限");
    ShiroAddChineseTranslation(@"Camera access is disabled\nEnable it in Settings > Privacy > Camera", @"相机权限已关闭\n请在设置 > 隐私 > 相机中开启");
    ShiroAddChineseTranslation(@"Catalog", @"服务器目录");
    ShiroAddChineseTranslation(@"Cell", @"列表项");
    ShiroAddChineseTranslation(@"Cell low", @"列表项底部");
    ShiroAddChineseTranslation(@"Check", @"检查");
    ShiroAddChineseTranslation(@"Checking TCP", @"正在检查 TCP");
    ShiroAddChineseTranslation(@"Checking package", @"正在检查软件包");
    ShiroAddChineseTranslation(@"Chrome", @"导航栏");
    ShiroAddChineseTranslation(@"Chrome low", @"导航栏底部");
    ShiroAddChineseTranslation(@"Config file", @"配置文件");
    ShiroAddChineseTranslation(@"Connected for", @"连接时长");
    ShiroAddChineseTranslation(@"Could not connect to the server. Check the address, network, and server availability.", @"无法连接服务器。请检查地址、网络和服务器状态。");
    ShiroAddChineseTranslation(@"Could not read the file", @"无法读取文件");
    ShiroAddChineseTranslation(@"Could not serialize theme", @"无法编码主题");
    ShiroAddChineseTranslation(@"Could not write to Documents", @"无法写入 Documents");
    ShiroAddChineseTranslation(@"Custom theme limit reached", @"自定义主题数量已达上限");
    ShiroAddChineseTranslation(@"DAEMON", @"守护进程");
    ShiroAddChineseTranslation(@"DEVICE", @"设备");
    ShiroAddChineseTranslation(@"DNS cache", @"DNS 缓存");
    ShiroAddChineseTranslation(@"DNS port", @"DNS 端口");
    ShiroAddChineseTranslation(@"DNS queries", @"DNS 查询");
    ShiroAddChineseTranslation(@"DNS settings apply the next time the tunnel comes up. The SOCKS port applies when the daemon restarts.", @"DNS 设置将在下次建立隧道时生效。SOCKS 端口将在守护进程重启后生效。");
    ShiroAddChineseTranslation(@"Daemon pid", @"守护进程 PID");
    ShiroAddChineseTranslation(@"Daemon uptime", @"守护进程运行时间");
    ShiroAddChineseTranslation(@"Device", @"设备");
    ShiroAddChineseTranslation(@"Device gating", @"设备限制");
    ShiroAddChineseTranslation(@"Device id file", @"设备 ID 文件");
    ShiroAddChineseTranslation(@"Device uptime", @"设备运行时间");
    ShiroAddChineseTranslation(@"Direct addresses", @"直连地址");
    ShiroAddChineseTranslation(@"Disconnect first", @"请先断开连接");
    ShiroAddChineseTranslation(@"Dropped packets", @"丢弃的数据包");
    ShiroAddChineseTranslation(@"Edit selected server", @"编辑选中的服务器");
    ShiroAddChineseTranslation(@"Egress address", @"出口地址");
    ShiroAddChineseTranslation(@"Egress interface", @"出口接口");
    ShiroAddChineseTranslation(@"Encrypted subscription", @"加密订阅");
    ShiroAddChineseTranslation(@"Every server in this content is already saved.", @"此内容中的所有服务器均已保存。");
    ShiroAddChineseTranslation(@"Export configuration", @"导出配置");
    ShiroAddChineseTranslation(@"FORCED", @"已强制");
    ShiroAddChineseTranslation(@"Felt", @"列表背景");
    ShiroAddChineseTranslation(@"Finishing", @"正在完成");
    ShiroAddChineseTranslation(@"Five taps on this heading hide the section again.", @"点击此标题五次即可再次隐藏该区域。");
    ShiroAddChineseTranslation(@"Flow", @"流控");
    ShiroAddChineseTranslation(@"Flush the DNS cache", @"清空 DNS 缓存");
    ShiroAddChineseTranslation(@"Free memory", @"可用内存");
    ShiroAddChineseTranslation(@"Gbit/s", @"Gbit/s");
    ShiroAddChineseTranslation(@"Jailbreak", @"越狱");
    ShiroAddChineseTranslation(@"Jailbreak root", @"越狱根目录");
    ShiroAddChineseTranslation(@"LIVE", @"实时");
    ShiroAddChineseTranslation(@"Last TCP error", @"上次 TCP 错误");
    ShiroAddChineseTranslation(@"Last UDP error", @"上次 UDP 错误");
    ShiroAddChineseTranslation(@"Last backend error", @"上次后端错误");
    ShiroAddChineseTranslation(@"Link", @"链接");
    ShiroAddChineseTranslation(@"Live connections", @"当前连接数");
    ShiroAddChineseTranslation(@"Manually added profiles only", @"仅手动添加的配置");
    ShiroAddChineseTranslation(@"No camera available", @"没有可用的相机");
    ShiroAddChineseTranslation(@"No configuration is selected. Pick a server first.", @"尚未选择配置。请先选择服务器。");
    ShiroAddChineseTranslation(@"No server Shiro can run was found in this content.", @"此内容中没有 Shiro 可用的服务器。");
    ShiroAddChineseTranslation(@"Not a Shiro theme file", @"不是 Shiro 主题文件");
    ShiroAddChineseTranslation(@"OFF", @"关闭");
    ShiroAddChineseTranslation(@"ON", @"开启");
    ShiroAddChineseTranslation(@"Offline", @"离线");
    ShiroAddChineseTranslation(@"Offline low", @"离线底部");
    ShiroAddChineseTranslation(@"Online", @"在线");
    ShiroAddChineseTranslation(@"Online low", @"在线底部");
    ShiroAddChineseTranslation(@"PATHS", @"路径");
    ShiroAddChineseTranslation(@"PROCESSES", @"进程");
    ShiroAddChineseTranslation(@"Packets", @"数据包");
    ShiroAddChineseTranslation(@"Ping All", @"检查全部延迟");
    ShiroAddChineseTranslation(@"Preparing package", @"正在准备软件包");
    ShiroAddChineseTranslation(@"QR code is empty or unreadable", @"二维码为空或无法读取");
    ShiroAddChineseTranslation(@"QR code not detected\nfill the frame with the code\nand hold the phone still", @"未检测到二维码\n请将二维码放入画面中央\n并保持设备稳定");
    ShiroAddChineseTranslation(@"Redial", @"重新拨号");
    ShiroAddChineseTranslation(@"Redirect port", @"重定向端口");
    ShiroAddChineseTranslation(@"Refresh the subscription to change it", @"刷新订阅以更新此值");
    ShiroAddChineseTranslation(@"Request header", @"请求头");
    ShiroAddChineseTranslation(@"Rule 2", @"规则 2");
    ShiroAddChineseTranslation(@"Rule 3", @"规则 3");
    ShiroAddChineseTranslation(@"Rule hits", @"规则命中次数");
    ShiroAddChineseTranslation(@"Rule verdicts", @"规则结果");
    ShiroAddChineseTranslation(@"Rules", @"规则");
    ShiroAddChineseTranslation(@"Running dpkg --install", @"正在运行 dpkg --install");
    ShiroAddChineseTranslation(@"Russian/English", @"俄语/英语");
    ShiroAddChineseTranslation(@"SOCKS bound to", @"SOCKS 绑定地址");
    ShiroAddChineseTranslation(@"SOCKS is localhost-only by default. socks_public=1 in config opens it to the LAN.", @"SOCKS 默认仅本机可用。在配置中设置 socks_public=1 可供局域网访问。");
    ShiroAddChineseTranslation(@"Scan native config", @"扫描原生配置");
    ShiroAddChineseTranslation(@"Second busiest rule", @"命中第二多的规则");
    ShiroAddChineseTranslation(@"See /tmp/shiro-update.log", @"查看 /tmp/shiro-update.log");
    ShiroAddChineseTranslation(@"Selected server", @"选中的服务器");
    ShiroAddChineseTranslation(@"Shiro does not support this protocol", @"Shiro 不支持此协议");
    ShiroAddChineseTranslation(@"Shiro resident", @"Shiro 常驻内存");
    ShiroAddChineseTranslation(@"Shiro-core eligible", @"可使用 Shiro-core");
    ShiroAddChineseTranslation(@"Shiro-core usable", @"Shiro-core 可用");
    ShiroAddChineseTranslation(@"Shadowsocks", @"Shadowsocks");
    ShiroAddChineseTranslation(@"Source", @"来源");
    ShiroAddChineseTranslation(@"Starting install helper", @"正在启动安装助手");
    ShiroAddChineseTranslation(@"Status bar hook", @"状态栏钩子");
    ShiroAddChineseTranslation(@"Stopping shirod", @"正在停止 shirod");
    ShiroAddChineseTranslation(@"Subscription profile", @"订阅配置");
    ShiroAddChineseTranslation(@"Substrate directory", @"Substrate 目录");
    ShiroAddChineseTranslation(@"System log", @"系统日志");
    ShiroAddChineseTranslation(@"TCP flows", @"TCP 连接流");
    ShiroAddChineseTranslation(@"TCP traffic", @"TCP 流量");
    ShiroAddChineseTranslation(@"TLS compatibility hook", @"TLS 兼容钩子");
    ShiroAddChineseTranslation(@"Tap Close when you are ready.", @"准备好后点击“关闭”。");
    ShiroAddChineseTranslation(@"Text", @"文字");
    ShiroAddChineseTranslation(@"Text muted", @"次要文字");
    ShiroAddChineseTranslation(@"The Happ crypt5 bundle on this page could not be opened. It is either damaged or sealed with a key this build does not carry.", @"无法打开此页面的 Happ crypt5 配置包。文件可能损坏，或使用了当前版本没有的密钥。");
    ShiroAddChineseTranslation(@"The Shiro service is not responding. Restart it and try again.", @"Shiro 服务没有响应。请重启后重试。");
    ShiroAddChineseTranslation(@"The clipboard is empty.", @"剪贴板为空。");
    ShiroAddChineseTranslation(@"The connect hook could not start. Check that shirotlsfix is installed, or pick another backend.", @"连接钩子无法启动。请检查是否已安装 shirotlsfix，或选择其他后端。");
    ShiroAddChineseTranslation(@"The connection attempt timed out. Check the network and try another server.", @"连接超时。请检查网络并尝试其他服务器。");
    ShiroAddChineseTranslation(@"The daemon runs these on its own, with the app closed.", @"即使应用关闭，守护进程也会自动执行这些操作。");
    ShiroAddChineseTranslation(@"The file is empty or could not be read.", @"文件为空或无法读取。");
    ShiroAddChineseTranslation(@"The local proxy could not start. Restart Shiro and check that another copy is not running.", @"本地代理无法启动。请重启 Shiro，并检查是否已有另一个实例正在运行。");
    ShiroAddChineseTranslation(@"The server address is invalid, unsafe, or cannot be resolved.", @"服务器地址无效、不安全或无法解析。");
    ShiroAddChineseTranslation(@"The server link has an invalid UUID. Import the link again from its source.", @"服务器链接中的 UUID 无效。请从来源重新导入链接。");
    ShiroAddChineseTranslation(@"The server name could not be resolved. Check the internet connection and server address.", @"无法解析服务器域名。请检查网络连接和服务器地址。");
    ShiroAddChineseTranslation(@"The server port is reachable, but the profile could not complete a real connection. Check its UUID or password, security, SNI, and transport settings.", @"服务器端口可访问，但配置无法完成实际连接。请检查 UUID 或密码、安全设置、SNI 和传输设置。");
    ShiroAddChineseTranslation(@"The tunnel could not be opened. Check the server settings, key, and selected transport.", @"无法打开隧道。请检查服务器设置、密钥和传输方式。");
    ShiroAddChineseTranslation(@"The tunnel could not start. Open System Logs to see whether utun, routes, or the bundled core failed.", @"隧道无法启动。请打开系统日志，查看 utun、路由或内置核心的错误。");
    ShiroAddChineseTranslation(@"The tunnel could not start. Open System Logs to see whether utun, routes, or the server failed.", @"隧道无法启动。请打开系统日志，查看 utun、路由或服务器的错误。");
    ShiroAddChineseTranslation(@"The tunnel stopped right after it started. Open System Logs for the reason.", @"隧道启动后立即停止。请在系统日志中查看原因。");
    ShiroAddChineseTranslation(@"Theme file is incomplete", @"主题文件不完整");
    ShiroAddChineseTranslation(@"Theme is not a custom theme", @"这不是自定义主题");
    ShiroAddChineseTranslation(@"There was nothing to import.", @"没有可导入的内容。");
    ShiroAddChineseTranslation(@"Third busiest rule", @"命中第三多的规则");
    ShiroAddChineseTranslation(@"This address opens a web page instead of a subscription feed. Copy the subscription link the page offers, not the page address.", @"此地址打开的是网页，而非订阅内容。请复制网页提供的订阅链接，不要复制网页地址。");
    ShiroAddChineseTranslation(@"This device received a link back to the same address instead of a subscription feed. Check device access and ask the provider for the feed URL.", @"此设备收到指向同一地址的链接，而不是订阅内容。请检查设备权限，并向服务商索取订阅地址。");
    ShiroAddChineseTranslation(@"This profile cannot be checked while another profile is connected. Disconnect first.", @"连接其他配置时无法检查此配置。请先断开连接。");
    ShiroAddChineseTranslation(@"This server uses a protocol or security mode that Shiro does not support.", @"此服务器使用 Shiro 不支持的协议或安全模式。");
    ShiroAddChineseTranslation(@"This theme will lag on iOS 6/7. Liquid glass is laggy on older device.", @"此主题在 iOS 6/7 上可能运行缓慢。旧设备上的玻璃效果性能较低。");
    ShiroAddChineseTranslation(@"Top rule", @"命中最多的规则");
    ShiroAddChineseTranslation(@"Trojan", @"Trojan");
    ShiroAddChineseTranslation(@"Tunnel DNS", @"隧道 DNS");
    ShiroAddChineseTranslation(@"Tunnel counters", @"隧道计数器");
    ShiroAddChineseTranslation(@"Tunnel state", @"隧道状态");
    ShiroAddChineseTranslation(@"UDP datagrams", @"UDP 数据报");
    ShiroAddChineseTranslation(@"UTILITIES", @"工具");
    ShiroAddChineseTranslation(@"Unknown content type. This is not a server link, a subscription, or a profile Shiro can read.", @"未知内容类型。这不是 Shiro 可读取的服务器链接、订阅或配置。");
    ShiroAddChineseTranslation(@"Unsupported theme format", @"不支持的主题格式");
    ShiroAddChineseTranslation(@"Upstream DNS", @"上游 DNS");
    ShiroAddChineseTranslation(@"Vision", @"Vision");
    ShiroAddChineseTranslation(@"WAIT", @"请稍候");
    ShiroAddChineseTranslation(@"Well", @"凹槽");
    ShiroAddChineseTranslation(@"What was chosen", @"当前选择");
    ShiroAddChineseTranslation(@"Write bundle", @"写入诊断包");
    ShiroAddChineseTranslation(@"bars bottom", @"导航栏底部");
    ShiroAddChineseTranslation(@"bars top", @"导航栏顶部");
    ShiroAddChineseTranslation(@"bit/s", @"bit/s");
    ShiroAddChineseTranslation(@"cannot open folder", @"无法打开文件夹");
    ShiroAddChineseTranslation(@"checking daemon...", @"正在检查守护进程…");
    ShiroAddChineseTranslation(@"checking group ping...", @"正在检查分组延迟…");
    ShiroAddChineseTranslation(@"checking ping...", @"正在检查延迟…");
    ShiroAddChineseTranslation(@"checking server...", @"正在检查服务器…");
    ShiroAddChineseTranslation(@"choose a .deb package", @"请选择 .deb 软件包");
    ShiroAddChineseTranslation(@"connected", @"已连接");
    ShiroAddChineseTranslation(@"connected button bottom", @"连接按钮底部");
    ShiroAddChineseTranslation(@"connected button top", @"连接按钮顶部");
    ShiroAddChineseTranslation(@"connecting", @"连接中");
    ShiroAddChineseTranslation(@"connecting...", @"连接中…");
    ShiroAddChineseTranslation(@"connection failed", @"连接失败");
    ShiroAddChineseTranslation(@"could not stop shirod", @"无法停止 shirod");
    ShiroAddChineseTranslation(@"daemon offline: cannot add", @"守护进程离线：无法添加");
    ShiroAddChineseTranslation(@"daemon offline: cannot edit", @"守护进程离线：无法编辑");
    ShiroAddChineseTranslation(@"daemon offline: cannot import", @"守护进程离线：无法导入");
    ShiroAddChineseTranslation(@"daemon offline: cannot save header", @"守护进程离线：无法保存请求头");
    ShiroAddChineseTranslation(@"disconnect to edit", @"请断开连接后编辑");
    ShiroAddChineseTranslation(@"disconnect to remove", @"请断开连接后移除");
    ShiroAddChineseTranslation(@"disconnect to reorder", @"请断开连接后调整顺序");
    ShiroAddChineseTranslation(@"disconnect to switch", @"请断开连接后切换");
    ShiroAddChineseTranslation(@"disconnect to switch backend", @"请断开连接后切换后端");
    ShiroAddChineseTranslation(@"disconnected button bottom", @"断开按钮底部");
    ShiroAddChineseTranslation(@"disconnected button top", @"断开按钮顶部");
    ShiroAddChineseTranslation(@"empty folder", @"文件夹为空");
    ShiroAddChineseTranslation(@"failed", @"失败");
    ShiroAddChineseTranslation(@"fetch failed: daemon offline", @"获取失败：守护进程离线");
    ShiroAddChineseTranslation(@"fetching subscription...", @"正在获取订阅…");
    ShiroAddChineseTranslation(@"file import failed", @"文件导入失败");
    ShiroAddChineseTranslation(@"folder", @"文件夹");
    ShiroAddChineseTranslation(@"group ping complete", @"分组延迟检查完成");
    ShiroAddChineseTranslation(@"group profile check complete", @"分组配置检查完成");
    ShiroAddChineseTranslation(@"iOS major", @"iOS 主版本");
    ShiroAddChineseTranslation(@"iOS read from", @"iOS 版本来源");
    ShiroAddChineseTranslation(@"iOS version read from", @"iOS 版本读取来源");
    ShiroAddChineseTranslation(@"idle", @"空闲");
    ShiroAddChineseTranslation(@"install a .deb", @"安装 .deb 软件包");
    ShiroAddChineseTranslation(@"install this package over the current version? settings and subscriptions stay in place", @"用此软件包覆盖当前版本？设置和订阅将保留");
    ShiroAddChineseTranslation(@"links and glyphs", @"链接和图标");
    ShiroAddChineseTranslation(@"list backdrop", @"列表背景");
    ShiroAddChineseTranslation(@"list inset tint", @"列表内侧色调");
    ShiroAddChineseTranslation(@"list reloaded", @"列表已刷新");
    ShiroAddChineseTranslation(@"manual", @"手动");
    ShiroAddChineseTranslation(@"manual profiles only", @"仅手动配置");
    ShiroAddChineseTranslation(@"manual servers removed", @"手动服务器已移除");
    ShiroAddChineseTranslation(@"no readable folders", @"没有可读取的文件夹");
    ShiroAddChineseTranslation(@"no servers in group", @"分组中没有服务器");
    ShiroAddChineseTranslation(@"none", @"无");
    ShiroAddChineseTranslation(@"paste a link here", @"在此粘贴链接");
    ShiroAddChineseTranslation(@"paste a subscription URL", @"粘贴订阅 URL");
    ShiroAddChineseTranslation(@"pick a server first", @"请先选择服务器");
    ShiroAddChineseTranslation(@"ping check complete", @"延迟检查完成");
    ShiroAddChineseTranslation(@"pressed accent", @"按下时的强调色");
    ShiroAddChineseTranslation(@"primary label", @"主要文字");
    ShiroAddChineseTranslation(@"profile check complete", @"配置检查完成");
    ShiroAddChineseTranslation(@"reading content...", @"正在读取内容…");
    ShiroAddChineseTranslation(@"refreshing subscription...", @"正在刷新订阅…");
    ShiroAddChineseTranslation(@"refreshing subscriptions...", @"正在刷新订阅…");
    ShiroAddChineseTranslation(@"removing manual servers...", @"正在移除手动服务器…");
    ShiroAddChineseTranslation(@"removing subscription...", @"正在移除订阅…");
    ShiroAddChineseTranslation(@"row bottom", @"列表项底部");
    ShiroAddChineseTranslation(@"row top", @"列表项顶部");
    ShiroAddChineseTranslation(@"saving subscription...", @"正在保存订阅…");
    ShiroAddChineseTranslation(@"secondary label", @"次要文字");
    ShiroAddChineseTranslation(@"section moved", @"分组已移动");
    ShiroAddChineseTranslation(@"shirod is missing: reinstall the package", @"缺少 shirod：请重新安装软件包");
    ShiroAddChineseTranslation(@"shirod is not running and its log is empty", @"shirod 未运行，日志为空");
    ShiroAddChineseTranslation(@"server moved", @"服务器已移动");
    ShiroAddChineseTranslation(@"server ping", @"服务器延迟");
    ShiroAddChineseTranslation(@"server ping timeout", @"服务器延迟检查超时");
    ShiroAddChineseTranslation(@"subscription added", @"订阅已添加");
    ShiroAddChineseTranslation(@"subscription not found", @"未找到订阅");
    ShiroAddChineseTranslation(@"subscription pinned", @"订阅已置顶");
    ShiroAddChineseTranslation(@"subscription removed", @"订阅已移除");
    ShiroAddChineseTranslation(@"subscription saved", @"订阅已保存");
    ShiroAddChineseTranslation(@"subscription updated", @"订阅已更新");
    ShiroAddChineseTranslation(@"subscription url has spaces", @"订阅 URL 包含空格");
    ShiroAddChineseTranslation(@"subscriptions refreshed", @"订阅已刷新");
    ShiroAddChineseTranslation(@"switch timeout", @"切换超时");
    ShiroAddChineseTranslation(@"the shirod launch daemon is missing: reinstall the package", @"缺少 shirod 启动服务：请重新安装软件包");
    ShiroAddChineseTranslation(@"timeout", @"超时");
    ShiroAddChineseTranslation(@"unknown check type", @"未知检查类型");
    ShiroAddChineseTranslation(@"unknown error", @"未知错误");
    ShiroAddChineseTranslation(@"validated import", @"已验证导入内容");
    ShiroAddChineseTranslation(@"validating native config...", @"正在验证原生配置…");
    ShiroAddChineseTranslation(@"wallpaper bottom", @"壁纸底部");
    ShiroAddChineseTranslation(@"wallpaper top", @"壁纸顶部");
    ShiroAddChineseTranslation(@"Block wins over direct, direct wins over the tunnel, whatever the order. On iOS 12 and later the tunnel core reads the real domain from the connection; below that the rule is matched when the name is resolved, so an address shared by several sites follows the first name that asked for it.", @"规则顺序不会改变优先级：阻止优先于直连，直连优先于隧道。iOS 12 及以上版本会从连接中读取实际域名；旧版系统在解析域名时匹配规则，因此多个网站共用的地址会采用首次请求该地址的域名规则。");
    ShiroAddChineseTranslation(@"Shiro failed to start %d times and is running with the stock theme. The report is in Logs.", @"Shiro 连续 %d 次启动失败，当前使用默认主题。报告位于日志页面。");
    ShiroAddChineseTranslation(@"the legacy theme for the legacy community", @"为怀旧社区打造的经典主题");
    ShiroAddChineseTranslation(@"flat and transparent", @"扁平而通透");
    ShiroAddChineseTranslation(@"modern theme", @"现代主题");
    ShiroAddChineseTranslation(@"liquid ass... nah, glass", @"流动玻璃风格");
    ShiroAddChineseTranslation(@"meeeeeow :3", @"喵喵喵 :3");
    ShiroAddChineseTranslation(@"hehehe mita hehehe miside", @"嘿嘿，米塔来了");
    ShiroAddChineseTranslation(@"futuristic maximalism of the past", @"复古未来的绚丽风格");
    ShiroAddChineseTranslation(@"google pixel aesthetic", @"谷歌 Pixel 风格");
    ShiroAddChineseTranslation(@"made on this device", @"在此设备上创建");
    ShiroAddTranslation(@"Falling foxes", @"Падающие лисицы");
    ShiroAddTranslation(@"Registration proxy", @"Прокси регистрации");
    ShiroAddChineseTranslation(@"Registration proxy", @"注册代理");
    ShiroAddTranslation(@"SOCKS5 or HTTP URL. Empty disables.", @"URL SOCKS5 или HTTP. Пусто: выключить.");
    ShiroAddChineseTranslation(@"SOCKS5 or HTTP URL. Empty disables.", @"SOCKS5 或 HTTP 地址，留空禁用。");
    ShiroAddTranslation(@"The proxy is used only for WARP registration. Optional login: scheme://user:password@host:port.", @"Прокси используется только для регистрации WARP. С логином: схема://логин:пароль@сервер:порт.");
    ShiroAddChineseTranslation(@"The proxy is used only for WARP registration. Optional login: scheme://user:password@host:port.", @"代理仅用于 WARP 注册。可选认证：协议://用户名:密码@主机:端口。");
    ShiroAddTranslation(@"Invalid registration proxy", @"Некорректный прокси регистрации");
    ShiroAddChineseTranslation(@"Invalid registration proxy", @"注册代理配置无效");
    ShiroAddTranslation(@"Disconnect and wait for registration to finish before changing the proxy", @"Отключитесь и дождитесь завершения регистрации перед изменением прокси");
    ShiroAddChineseTranslation(@"Disconnect and wait for registration to finish before changing the proxy", @"更改代理前请先断开连接并等待注册结束");
    ShiroAddTranslation(@"Use socks5://host:port or http://host:port, with optional user:password@. Leave empty to disable.", @"Введите socks5://сервер:порт или http://сервер:порт. Можно добавить логин:пароль@. Пустое поле выключает прокси.");
    ShiroAddChineseTranslation(@"Use socks5://host:port or http://host:port, with optional user:password@. Leave empty to disable.", @"请输入 socks5://主机:端口 或 http://主机:端口，可添加 用户名:密码@，留空禁用。");
    ShiroAddTranslation(@"Could not save the registration proxy", @"Не удалось сохранить прокси регистрации");
    ShiroAddChineseTranslation(@"Could not save the registration proxy", @"无法保存注册代理");
    ShiroAddChineseTranslation(@"Falling foxes", @"飘落的小狐狸");
    ShiroAddTranslation(@"Cloudflare WARP client", @"Клиент Cloudflare WARP");
    ShiroAddChineseTranslation(@"Cloudflare WARP client", @"Cloudflare WARP 客户端");
    ShiroAddTranslation(@"Credits", @"Авторы");
    ShiroAddChineseTranslation(@"Credits", @"制作人员");
    ShiroAddTranslation(@"Device", @"Устройство");
    ShiroAddChineseTranslation(@"Device", @"设备");
    ShiroAddTranslation(@"Developer", @"Разработчик");
    ShiroAddChineseTranslation(@"Developer", @"开发者");
    ShiroAddTranslation(@"Model", @"Модель");
    ShiroAddChineseTranslation(@"Model", @"型号");
    ShiroAddTranslation(@"iOS version", @"Версия iOS");
    ShiroAddChineseTranslation(@"iOS version", @"iOS 版本");
    ShiroAddTranslation(@"Architecture", @"Архитектура");
    ShiroAddChineseTranslation(@"Architecture", @"架构");
    ShiroAddTranslation(@"TLS mode", @"Режим TLS");
    ShiroAddChineseTranslation(@"TLS mode", @"TLS 模式");
    ShiroAddTranslation(@"How it works", @"Как это работает");
    ShiroAddChineseTranslation(@"How it works", @"工作原理");
    ShiroAddTranslation(@"Compatibility", @"Совместимость");
    ShiroAddChineseTranslation(@"Compatibility", @"兼容性");
    ShiroAddTranslation(@"Security", @"Безопасность");
    ShiroAddChineseTranslation(@"Security", @"安全性");
    ShiroAddTranslation(@"System log", @"Системный журнал");
    ShiroAddChineseTranslation(@"System log", @"系统日志");
    ShiroAddTranslation(@"License", @"Лицензия");
    ShiroAddChineseTranslation(@"License", @"许可证");
    ShiroAddTranslation(@"Links", @"Ссылки");
    ShiroAddChineseTranslation(@"Links", @"链接");
    ShiroAddTranslation(@"Version", @"Версия");
    ShiroAddChineseTranslation(@"Version", @"版本");
    ShiroAddTranslation(@"Apps and system traffic use Cloudflare WARP through a root-owned WireGuard tunnel.", @"Трафик приложений и системы идёт через Cloudflare WARP по туннелю WireGuard, которым управляет root-демон.");
    ShiroAddChineseTranslation(@"Apps and system traffic use Cloudflare WARP through a root-owned WireGuard tunnel.", @"应用与系统流量通过由 root 守护进程管理的 WireGuard 隧道接入 Cloudflare WARP。");
    ShiroAddTranslation(@"Peer-validated local control socket. Account keys stay in a root-owned file. Registration verifies the certificate chain and hostname.", @"Локальный сокет проверяет пользователя на другом конце. Ключи аккаунта хранятся в файле root. При регистрации проверяются цепочка сертификатов и имя сервера.");
    ShiroAddChineseTranslation(@"Peer-validated local control socket. Account keys stay in a root-owned file. Registration verifies the certificate chain and hostname.", @"本地控制套接字会验证对端用户身份。账户密钥保存在 root 专属文件中。注册时会验证证书链与主机名。");
    ShiroAddTranslation(@"iOS 5+ · armv7 + arm64 + arm64e", @"iOS 5 и новее · armv7 + arm64 + arm64e");
    ShiroAddChineseTranslation(@"iOS 5+ · armv7 + arm64 + arm64e", @"iOS 5 及以上 · armv7 + arm64 + arm64e");

}

BOOL ShiroLanguageIsRussian(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:SHIRO_LANGUAGE_KEY] == ShiroLanguageRussian;
}

BOOL ShiroLanguageIsChinese(void) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:SHIRO_LANGUAGE_KEY] == ShiroLanguageChinese;
}

NSString *ShiroRedactSecrets(NSString *text) {
    if (![text length]) return text;
    NSMutableString *safe = [NSMutableString stringWithString:text];
    NSArray *rules = [NSArray arrayWithObjects:
        @"(?i)(authorization|proxy-authorization|cookie|set-cookie|privatekey|presharedkey)\\s*[:=]\\s*[^\\r\\n]+",
        @"(://)[^/@\\s]+@",
        @"(?i)([?&](token|key|password|pass|uuid|pbk|sid)=)[^&#\\s]+", nil];
    NSArray *replacements = [NSArray arrayWithObjects:@"$1: <redacted>",
        @"$1<redacted>@", @"$1<redacted>", nil];
    for (NSUInteger i = 0; i < [rules count]; ++i) {
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:[rules objectAtIndex:i] options:0 error:NULL];
        if (!rx) continue;
        [rx replaceMatchesInString:safe options:0 range:NSMakeRange(0, [safe length])
                       withTemplate:[replacements objectAtIndex:i]];
    }
    return safe;
}

/* the daemon prefixes the panel's own wording, which stays untranslated */
static NSString * const kGatePrefix = @"subscription refused this device: ";

/* the daemon keeps its english reasons for logs; only known sentences are translated */
static NSString *ShiroNetworkErrorTextForLanguage(NSString *text, NSInteger language) {
    static NSString * const messages[][3] = {
        { @"the server did not open the chosen transport: check the path, host and transport type", @"Сервер не открыл выбранный транспорт. Проверьте путь, Host и тип транспорта.", @"服务器未建立所选传输连接。请检查路径、Host 和传输类型。" },
        { @"this device could not open the connection: restart Shiro and check System Logs", @"Устройство не смогло открыть соединение. Перезапустите Shiro и проверьте системные логи.", @"设备无法建立连接。请重启 Shiro 并查看系统日志。" },
        { @"this device has no network route to the server: check the internet connection", @"Нет сетевого соединения с сервером. Проверьте доступ к интернету.", @"设备无法访问服务器。请检查网络连接。" },
        { @"the server refused the connection on port %@: check the port and whether the server is running", @"Сервер отклонил соединение на порту %@. Проверьте порт и запущен ли сервер.", @"服务器拒绝了端口 %@ 的连接。请检查端口及服务器是否运行。" },
        { @"the server does not answer: it is off, the address is wrong, or the network blocks it", @"Сервер не отвечает. Проверьте адрес, доступность сервера и блокировки в сети.", @"服务器无响应。请检查地址、服务器状态及网络限制。" },
        { @"the connection was reset during the handshake: check the network and the server settings", @"Соединение оборвалось при подключении. Проверьте сеть и настройки сервера.", @"连接在握手时被重置。请检查网络及服务器设置。" },
        { @"the server closed the connection during the handshake: check the port and the security setting", @"Сервер закрыл соединение при подключении. Проверьте порт и режим защиты.", @"服务器在握手时关闭了连接。请检查端口和安全设置。" },
        { @"the server does not speak TLS on port %@: check the port and the security setting", @"На порту %@ сервер ответил без TLS. Проверьте порт и режим защиты.", @"服务器端口 %@ 未使用 TLS。请检查端口和安全设置。" },
        { @"the server certificate is for another name: check the SNI", @"Сертификат сервера выдан для другого имени. Проверьте SNI.", @"服务器证书对应另一个域名。请检查 SNI。" },
        { @"the server certificate is not trusted: it is self-signed or from an unknown issuer", @"Сертификат сервера не подтверждён доверенным центром. Проверьте сертификат сервера.", @"服务器证书不受信任。请检查服务器证书及签发机构。" },
        { @"the server certificate has expired", @"Срок сертификата сервера истёк по часам устройства. Проверьте дату устройства и сертификат.", @"按设备时间，服务器证书已过期。请检查设备日期和证书。" },
        { @"the server certificate is not valid yet: check the device date and the certificate dates", @"Сертификат сервера ещё не действует по часам устройства. Проверьте дату устройства и сертификат.", @"按设备时间，服务器证书尚未生效。请检查设备日期和证书。" },
        { @"REALITY did not accept the connection: check the public key, the short id and the SNI", @"Не удалось подтвердить сервер REALITY. Проверьте публичный ключ, short ID и SNI.", @"无法验证 REALITY 服务器。请检查公钥、short ID 和 SNI。" },
        { @"the server has no such path (HTTP 404): check the path", @"Сервер не нашёл указанный путь (HTTP 404). Проверьте путь подключения.", @"服务器找不到指定路径（HTTP 404）。请检查连接路径。" },
        { @"the server rejected the request (HTTP 400): check the path and the transport type", @"Сервер отклонил запрос (HTTP 400). Проверьте путь и тип транспорта.", @"服务器拒绝了请求（HTTP 400）。请检查路径和传输类型。" },
        { @"the server refused access (HTTP 403): check the path and the host", @"Сервер запретил доступ (HTTP 403). Проверьте путь и Host.", @"服务器禁止访问（HTTP 403）。请检查路径和 Host。" },
        { @"the server front answered HTTP %@: check the server and its proxy service", @"Сервер вернул HTTP %@. Проверьте сервер и его прокси-службу.", @"服务器返回 HTTP %@。请检查服务器及其代理服务。" },
        { @"the server answered HTTP %@ instead of opening the transport: check the path and the transport type", @"Сервер вернул HTTP %@ вместо подключения. Проверьте путь и тип транспорта.", @"服务器返回 HTTP %@，未建立传输连接。请检查路径和传输类型。" },
        { @"the server has no such gRPC service: check the service name", @"Сервер не нашёл службу gRPC. Проверьте имя службы.", @"服务器找不到 gRPC 服务。请检查服务名称。" },
        { @"the server answered gRPC status %@: check the service name", @"Служба gRPC отклонила запрос (статус %@). Проверьте имя службы.", @"gRPC 服务返回状态 %@。请检查服务名称。" },
        { @"the TLS handshake with the server failed: check the SNI and the security setting", @"Не удалось установить защищённое соединение с сервером. Проверьте SNI и режим защиты.", @"无法与服务器建立 TLS 连接。请检查 SNI 和安全设置。" },
        { @"the server name does not resolve: check the address and the internet connection", @"Не удалось найти сервер по имени. Проверьте адрес и доступ к интернету.", @"无法解析服务器域名。请检查地址和网络连接。" },
        { @"the server closed the request without an answer: check the UUID and the device clock", @"Сервер закрыл соединение без ответа. Проверьте UUID и дату и время устройства.", @"服务器未响应便关闭连接。请检查 UUID 和设备日期与时间。" },
        { @"the server closed the request without an answer: check the %@", @"Сервер закрыл соединение без ответа. Проверьте %@.", @"服务器未响应便关闭连接。请检查 %@。" },
        { @"the server did not return an answer: check the %@; also check whether the server can reach the internet", @"Сервер не прислал ответ. Проверьте %@ и доступ сервера к интернету.", @"服务器未返回响应。请检查 %@ 及服务器的互联网连接。" },
        { @"the server answer does not decrypt: check the %@, or this is not a %@ server", @"Не удалось расшифровать ответ сервера. Проверьте %@ и что сервер использует %@.", @"无法解密服务器响应。请检查 %@ 及服务器是否使用 %@。" },
        { @"the server answered as a website instead of carrying the request: check the %@", @"Сервер ответил как обычный сайт. Проверьте %@ и настройки прокси.", @"服务器返回了网站内容。请检查 %@ 及代理设置。" },
        { @"the proxy refused the user name or password", @"Прокси отклонил имя пользователя или пароль.", @"代理拒绝了用户名或密码。" },
        { @"the server answer is not %@: check the protocol and the port", @"Ответ сервера не соответствует %@. Проверьте протокол и порт.", @"服务器响应不符合 %@。请检查协议和端口。" },
        { @"the connection check received HTTP %@ instead of 204: check the %@ and whether the server can reach the check website", @"Проверка соединения получила HTTP %@ вместо ожидаемого ответа. Проверьте %@ и доступ сервера к проверочному сайту.", @"连接检查收到 HTTP %@，未收到预期响应。请检查 %@ 及服务器能否访问检测网站。" },
        { @"The tunnel device could not start or stopped: restart Shiro and check System Logs", @"Не удалось запустить туннель или он остановился. Перезапустите Shiro и проверьте системные логи.", @"隧道设备无法启动或已停止。请重启 Shiro 并查看系统日志。" },
        { @"the device clock appears %@ days ahead compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства спешат на %@ дн. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能快 %@ 天。请检查自动日期与时间。" },
        { @"the device clock appears %@ days behind compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства отстают на %@ дн. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能慢 %@ 天。请检查自动日期与时间。" },
        { @"the device clock appears %@ hours ahead compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства спешат на %@ ч. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能快 %@ 小时。请检查自动日期与时间。" },
        { @"the device clock appears %@ hours behind compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства отстают на %@ ч. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能慢 %@ 小时。请检查自动日期与时间。" },
        { @"the device clock appears %@ minutes ahead compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства спешат на %@ мин. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能快 %@ 分钟。请检查自动日期与时间。" },
        { @"the device clock appears %@ minutes behind compared with the HTTP check: verify automatic date and time", @"Возможно, часы устройства отстают на %@ мин. по сравнению с HTTP-проверкой. Проверьте автоматическую дату и время.", @"与 HTTP 检测相比，设备时钟可能慢 %@ 分钟。请检查自动日期与时间。" },
        { @"password and the cipher", @"пароль и шифр", @"密码及加密方式" },
        { @"user name and password", @"имя пользователя и пароль", @"用户名和密码" },
        { @"password", @"пароль", @"密码" },
    };
    if (![text length]) return nil;
    for (NSUInteger i = 0; i < sizeof messages / sizeof messages[0]; ++i) {
        NSString *target = messages[i][language];
        for (NSUInteger sourceLanguage = 0; sourceLanguage < 3; ++sourceLanguage) {
            NSString *source = messages[i][sourceLanguage];
            NSRange placeholder = [source rangeOfString:@"%@"];
            if (placeholder.location == NSNotFound) {
                if ([text isEqualToString:source]) return target;
                continue;
            }
            if (![text hasPrefix:[source substringToIndex:placeholder.location]]) continue;
            NSString *pattern = [[NSRegularExpression escapedPatternForString:source]
                stringByReplacingOccurrencesOfString:@"%@" withString:@"(.+?)"];
            NSRegularExpression *rx = [NSRegularExpression regularExpressionWithPattern:
                [NSString stringWithFormat:@"^%@$", pattern] options:0 error:NULL];
            NSTextCheckingResult *match = [rx firstMatchInString:text options:0
                range:NSMakeRange(0, [text length])];
            if (!match) continue;
            NSString *a = [text substringWithRange:[match rangeAtIndex:1]];
            NSString *translated = ShiroNetworkErrorTextForLanguage(a, language);
            if (translated) a = translated;
            if ([match numberOfRanges] == 2) return [NSString stringWithFormat:target, a];
            NSString *b = [text substringWithRange:[match rangeAtIndex:2]];
            return [NSString stringWithFormat:target, a, b];
        }
    }
    return nil;
}

static NSString *ShiroNetworkErrorText(NSString *text) {
    return ShiroNetworkErrorTextForLanguage(text,
        ShiroLanguageIsChinese() ? 2 : ShiroLanguageIsRussian() ? 1 : 0);
}

NSString *ShiroHumanReadableError(NSString *text) {
    NSString *raw = [text stringByTrimmingCharactersInSet:
                     [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([raw hasPrefix:@"ERR "]) raw = [raw substringFromIndex:4];
    NSString *detail = [raw hasPrefix:@"server: "] ? [raw substringFromIndex:8] : raw;
    NSString *network = ShiroNetworkErrorText(detail);
    if (network) return network;
    NSString *message = nil;
    if ([raw hasPrefix:@"error cannot open a utun"] || [raw hasPrefix:@"error the utun device failed"])
        message = @"The tunnel device could not start or stopped: restart Shiro and check System Logs";
    if (message) return ShiroNetworkErrorText(message);
    if ([raw isEqualToString:@"socks: tunnel open failed"] ||
        [raw isEqualToString:@"socks: tunnel verify failed"])
        message = @"The tunnel could not be opened. Check the server settings, key, and selected transport.";
    else if ([raw isEqualToString:@"socks: socks listener failed"] ||
             [raw isEqualToString:@"socks: socks listen connect failed"])
        message = @"The local proxy could not start. Restart Shiro and check that another copy is not running.";
    else if ([raw isEqualToString:@"server: dns resolution failed"])
        message = @"The server name could not be resolved. Check the internet connection and server address.";
    else if ([raw isEqualToString:@"routing: the connect hook could not start"])
        message = @"The connect hook could not start. Check that shirotlsfix is installed, or pick another backend.";
    else if ([raw isEqualToString:@"routing: the tunnel stopped before its check could run"])
        message = @"The tunnel stopped right after it started. Open System Logs for the reason.";
    else if ([raw isEqualToString:@"tunnel: shiro-core could not start; open System Logs for the exact cause"])
        message = @"The tunnel could not start. Open System Logs to see whether utun, routes, or the bundled core failed.";
    else if ([raw isEqualToString:@"server: unsupported protocol or security"])
        message = @"This server uses a protocol or security mode that Shiro does not support.";
    else if ([raw isEqualToString:@"server: bad uuid in server link"])
        message = @"The server link has an invalid UUID. Import the link again from its source.";
    else if ([raw hasPrefix:@"this address only hands back its own link"])
        message = @"This device received a link back to the same address instead of a subscription feed. Check device access and ask the provider for the feed URL.";
    else if ([raw hasPrefix:@"the happ crypt5 bundle on this page could not be opened"])
        message = @"The Happ crypt5 bundle on this page could not be opened. It is either damaged or sealed with a key this build does not carry.";
    else if ([raw hasPrefix:@"this address opens a web page"])
        message = @"This address opens a web page instead of a subscription feed. Copy the subscription link the page offers, not the page address.";
    else if ([raw isEqualToString:@"connect timeout"] || [raw isEqualToString:@"switch timeout"])
        message = @"The connection attempt timed out. Check the network and try another server.";
    else if ([raw hasPrefix:@"daemon offline"] || [raw isEqualToString:@"daemon offline"])
        message = @"The Shiro service is not responding. Restart it and try again.";
    else if ([raw isEqualToString:@"server: no working server"])
        message = @"Could not connect to the server. Check the address, network, and server availability.";
    else if ([raw hasPrefix:@"profile handshake failed:"])
        message = @"The server port is reachable, but the profile could not complete a real connection. Check its UUID or password, security, SNI, and transport settings.";
    else if ([raw isEqualToString:@"disconnect before checking another profile"])
        message = @"This profile cannot be checked while another profile is connected. Disconnect first.";
    else if ([raw isEqualToString:@"server address is invalid"] ||
             [raw isEqualToString:@"server address is unsafe or cannot be resolved"] ||
             [raw isEqualToString:@"unsafe or unresolved address"])
        message = @"The server address is invalid, unsafe, or cannot be resolved.";
    else if ([raw isEqualToString:@"profile uses an unsupported transport or security mode"])
        message = @"This server uses a protocol or security mode that Shiro does not support.";
    else if ([raw isEqualToString:@"profile has an invalid UUID"])
        message = @"The server link has an invalid UUID. Import the link again from its source.";
    else if ([raw hasPrefix:@"socks:"])
        message = @"The tunnel could not be opened. Check the server settings, key, and selected transport.";
    else if ([raw hasPrefix:@"routing:"])
        message = @"The connect hook could not start. Check that shirotlsfix is installed, or pick another backend.";
    else if ([raw hasPrefix:@"error utun"] || [raw hasPrefix:@"error route"])
        message = @"The tunnel could not start. Open System Logs to see whether utun, routes, or the server failed.";
    else if ([raw isEqualToString:@"unknown content type"])
        message = @"Unknown content type. This is not a server link, a subscription, or a profile Shiro can read.";
    else if ([raw isEqualToString:@"no server shiro can run in this file"])
        message = @"No server Shiro can run was found in this content.";
    else if ([raw isEqualToString:@"every server in this file is already saved"])
        message = @"Every server in this content is already saved.";
    else if ([raw isEqualToString:@"nothing to import"])
        message = @"There was nothing to import.";
    else if ([raw isEqualToString:@"no configuration is selected"])
        message = @"No configuration is selected. Pick a server first.";
    else if ([raw isEqualToString:@"the clipboard is empty"])
        message = @"The clipboard is empty.";
    else if ([raw isEqualToString:@"the file is empty or could not be read"])
        message = @"The file is empty or could not be read.";
    else if ([raw hasPrefix:kGatePrefix])
        return [ShiroLocalizedText(@"The subscription refused this device.")
                stringByAppendingFormat:@" %@",
                [raw substringFromIndex:[kGatePrefix length]]];
    return ShiroLocalizedText(message ? message : raw);
}

NSString *ShiroLanguageName(void) {
    if (ShiroLanguageIsChinese()) return @"中文";
    return ShiroLanguageIsRussian() ? @"Русский" : @"English";
}

static NSString *ShiroRussianPlural(NSInteger number,
                                    NSString *one,
                                    NSString *few,
                                    NSString *many) {
    NSInteger n = number < 0 ? -number : number;
    NSInteger last = n % 10;
    NSInteger lastTwo = n % 100;
    if (last == 1 && lastTwo != 11) return one;
    if (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14)) return few;
    return many;
}

NSString *ShiroHoursText(int hours) {
    if (ShiroLanguageIsChinese()) return [NSString stringWithFormat:@"%d 小时", hours];
    if (ShiroLanguageIsRussian())
        return [NSString stringWithFormat:@"%d %@", hours,
                ShiroRussianPlural(hours, @"час", @"часа", @"часов")];
    return [NSString stringWithFormat:hours == 1 ? @"%d hour" : @"%d hours", hours];
}

static BOOL ShiroAllDigits(NSString *text) {
    if (![text length]) return NO;
    for (NSUInteger i = 0; i < [text length]; ++i) {
        unichar c = [text characterAtIndex:i];
        if (c < '0' || c > '9') return NO;
    }
    return YES;
}

/* bulk actions answer with "<verb> <n> server(s)[ tail]", and the bare count
   rule below would read the verb as the number */
/* the skip summary shirod appends to an import: "skipped 3: tuic 2, ssr 1".
   protocol names stay as they are; the reasons shiro words itself are translated */
static NSString *ShiroSkipTailRu(NSString *tail) {
    static NSString * const kPairs[][2] = {
        { @"skipped ", @"пропущено " },
        { @" already saved", @" уже есть" },
        { @"malformed link", @"битая ссылка" },
        { @"tcp with an http header", @"tcp с http-заголовком" },
        { @"httpupgrade transport", @"транспорт httpupgrade" },
        { @"kcp transport", @"транспорт kcp" },
        { @"quic transport", @"транспорт quic" },
        { @"trojan over reality", @"trojan через reality" },
        { @"vless encryption", @"шифрование vless" },
        { @"invalid vless id", @"неверный id vless" },
        { @"invalid vmess id", @"неверный id vmess" },
        { @"vmess does not use flow", @"у vmess нет flow" },
        { @"shadowsocks plugin", @"плагин shadowsocks" },
        { @"shadowsocks userinfo that does not decode", @"нечитаемые данные shadowsocks" },
        { @"shadowsocks cipher that is not a name", @"нечитаемый шифр shadowsocks" },
        { @"happ link that does not open", @"нераскрываемая ссылка happ" },
        { @"malformed profile entry", @"битая запись профиля" },
        { @"hysteria v1", @"hysteria 1" },
        { @"unsupported trojan transport", @"trojan через неподдерживаемый транспорт" },
        { @"shadowsocks over another transport", @"shadowsocks не через tcp" },
        { @"socks over tls", @"socks через tls" },
        { @"link too long", @"слишком длинная ссылка" },
        { @", other ", @", прочее " },
    };
    NSString *out = tail;
    for (size_t i = 0; i < sizeof kPairs / sizeof kPairs[0]; ++i)
        out = [out stringByReplacingOccurrencesOfString:kPairs[i][0] withString:kPairs[i][1]];
    return out;
}

static NSString *ShiroServerCountReply(NSString *text) {
    static NSString * const kVerbs[] = { @"imported ", @"removed ", @"refreshed " };
    static NSString * const kRussian[] = { @"импортировано", @"удалено", @"обновлено" };
    for (size_t i = 0; i < sizeof kVerbs / sizeof kVerbs[0]; ++i) {
        if (![text hasPrefix:kVerbs[i]]) continue;
        NSString *rest = [text substringFromIndex:[kVerbs[i] length]];
        NSScanner *scanner = [NSScanner scannerWithString:rest];
        int count = 0;
        if (![scanner scanInt:&count]) return nil;
        NSString *tail = [rest substringFromIndex:[scanner scanLocation]];
        if (![tail hasPrefix:@" server"]) return nil;
        tail = [tail stringByReplacingOccurrencesOfString:@" server(s)" withString:@""];
        tail = [tail stringByReplacingOccurrencesOfString:@" from the first 512 KB"
                                               withString:@" из первых 512 КБ"];
        tail = [tail stringByReplacingOccurrencesOfString:@" (list full)"
                                               withString:@" (список заполнен)"];
        tail = ShiroSkipTailRu(tail);
        return [NSString stringWithFormat:@"%@ %d %@%@", kRussian[i], count,
                ShiroRussianPlural(count, @"сервер", @"сервера", @"серверов"), tail];
    }
    return nil;
}

/* the reason shirod gives for a failed subscription fetch */
static NSString *ShiroFetchReasonRu(NSString *why) {
    NSString *host = nil;
    if ([why hasPrefix:@"cannot resolve or connect to "])
        return [@"не удалось найти или подключиться к " stringByAppendingString:
                [why substringFromIndex:29]];
    if ([why hasPrefix:@"tls or connection to "] && [why hasSuffix:@" failed"]) {
        host = [why substringWithRange:NSMakeRange(21, [why length] - 21 - 7)];
        return [NSString stringWithFormat:@"ошибка TLS или соединения с %@", host];
    }
    NSRange r = [why rangeOfString:@" answered HTTP "];
    if (r.location != NSNotFound)
        return [NSString stringWithFormat:@"%@ ответил HTTP %@",
                [why substringToIndex:r.location], [why substringFromIndex:NSMaxRange(r)]];
    if ([why hasSuffix:@" sent a response shiro cannot read"])
        return [NSString stringWithFormat:@"%@ прислал ответ, который shiro не может прочитать",
                [why substringToIndex:[why length] - 34]];
    if ([why hasPrefix:@"the subscription from "] && [why hasSuffix:@" is too large"]) {
        host = [why substringWithRange:NSMakeRange(22, [why length] - 22 - 13)];
        return [NSString stringWithFormat:@"подписка с %@ слишком большая", host];
    }
    if ([why hasSuffix:@" redirected too often or to an unusable address"])
        return [NSString stringWithFormat:@"%@ перенаправляет слишком много раз или на неподходящий адрес",
                [why substringToIndex:[why length] - 47]];
    if ([why isEqualToString:@"the subscription url is invalid"])
        return @"неверная ссылка на подписку";
    if ([why isEqualToString:@"no reason given"])
        return @"причина неизвестна";
    return why;
}

static NSString *ShiroLocalizedDynamic(NSString *text) {
    if (![text length]) return text;

    if ([text hasPrefix:@"fetch failed: "])
        return [@"не удалось загрузить подписку: " stringByAppendingString:
                ShiroFetchReasonRu([text substringFromIndex:14])];
    if ([text hasPrefix:@"subscription added, refresh failed: "])
        return [@"подписка добавлена, но не загрузилась: " stringByAppendingString:
                ShiroFetchReasonRu([text substringFromIndex:36])];

    if ([text hasPrefix:@"subscription added, no server shiro can run in the first 512 KB ("])
        return [@"подписка добавлена, но в первых 512 КБ нет серверов, которые shiro может запустить ("
                stringByAppendingString:ShiroSkipTailRu([text substringFromIndex:65])];
    if ([text hasPrefix:@"subscription added, no server shiro can run ("])
        return [@"подписка добавлена, но в ней нет серверов, которые shiro может запустить ("
                stringByAppendingString:ShiroSkipTailRu([text substringFromIndex:45])];
    if ([text hasPrefix:@"subscription added, "] && [text rangeOfString:@" server"].location != NSNotFound) {
        NSString *count = ShiroServerCountReply([@"imported " stringByAppendingString:
                                                 [text substringFromIndex:20]]);
        if (count)
            return [@"подписка добавлена, " stringByAppendingString:
                    [count stringByReplacingOccurrencesOfString:@"импортировано " withString:@""]];
    }
    if ([text hasPrefix:@"no server shiro can run in the first 512 KB ("])
        return [@"в первых 512 КБ подписки нет серверов, которые shiro может запустить (" stringByAppendingString:
                ShiroSkipTailRu([text substringFromIndex:45])];
    if ([text hasPrefix:@"no server shiro can run ("])
        return [@"нет серверов, которые shiro может запустить (" stringByAppendingString:
                ShiroSkipTailRu([text substringFromIndex:25])];
    if ([text hasPrefix:@"no server shiro can run in this file ("])
        return [@"в этом файле нет серверов, которые shiro может запустить (" stringByAppendingString:
                ShiroSkipTailRu([text substringFromIndex:38])];

    NSString *countReply = ShiroServerCountReply(text);
    if (countReply) return countReply;

    NSRange r = [text rangeOfString:@" server"];
    if (r.location != NSNotFound) {
        NSString *numberText = [text substringToIndex:r.location];
        NSInteger number = [numberText integerValue];
        if (ShiroAllDigits(numberText) && number >= 0) {
            NSString *tail = [text substringFromIndex:r.location + r.length];
            if ([tail hasPrefix:@"s"]) tail = [tail substringFromIndex:1];
            tail = [tail stringByReplacingOccurrencesOfString:@"until " withString:@"до "];
            if ([tail hasSuffix:@"expired"])
                tail = [tail stringByReplacingOccurrencesOfString:@"expired" withString:@"истёк"];
            return [NSString stringWithFormat:@"%ld %@%@", (long)number,
                    ShiroRussianPlural(number, @"сервер", @"сервера", @"серверов"), tail];
        }
    }
    r = [text rangeOfString:@" single config"];
    if (r.location != NSNotFound) {
        NSString *numberText = [text substringToIndex:r.location];
        NSInteger number = [numberText integerValue];
        if (ShiroAllDigits(numberText) && number >= 0) {
            NSString *tail = [text substringFromIndex:r.location + r.length];
            if ([tail hasPrefix:@"s"]) tail = [tail substringFromIndex:1];
            return [NSString stringWithFormat:@"%ld %@%@", (long)number,
                    ShiroRussianPlural(number, @"отдельная конфигурация", @"отдельные конфигурации", @"отдельных конфигураций"), tail];
        }
    }
    if ([text hasSuffix:@" ms"]) {
        NSString *number = [text substringToIndex:text.length - 3];
        if ([number integerValue] >= 0)
            return [NSString stringWithFormat:@"%@ мс", number];
    }
    if ([text hasPrefix:@"Installed "])
        return [NSString stringWithFormat:@"Установлено %@", [text substringFromIndex:10]];
    if ([text hasPrefix:@"Done: "])
        return [NSString stringWithFormat:@"Готово: %@", [text substringFromIndex:6]];
    if ([text hasPrefix:@"Package: "])
        return [NSString stringWithFormat:@"Пакет: %@", [text substringFromIndex:9]];
    if ([text hasPrefix:@"shirod is not running, last log line: "])
        return [NSString stringWithFormat:@"shirod не запущен, последняя строка лога: %@",
                [text substringFromIndex:38]];
    if ([text hasPrefix:@"Version "])
        return [NSString stringWithFormat:@"Версия %@", [text substringFromIndex:8]];
    if ([text rangeOfString:@"    Dark"].location != NSNotFound)
        return [text stringByReplacingOccurrencesOfString:@"    Dark" withString:@"    Тёмная"];
    if ([text rangeOfString:@"    Light"].location != NSNotFound)
        return [text stringByReplacingOccurrencesOfString:@"    Light" withString:@"    Светлая"];
    if ([text hasPrefix:@"until "])
        return [NSString stringWithFormat:@"до %@", [text substringFromIndex:6]];
    return text;
}

static NSString *ShiroBaseText(NSString *text) {
    if (![text length]) return text;
    ShiroBuildTranslations();
    NSString *english = [gRussianToEnglish objectForKey:text];
    if (english) return english;
    english = ShiroNetworkErrorTextForLanguage(text, 0);
    return english ? english : text;
}

NSString *ShiroLocalizedText(NSString *text) {
    if (![text length]) return text;
    NSString *english = ShiroBaseText(text);
    NSString *network = ShiroNetworkErrorText(english);
    if (network) return network;
    ShiroBuildTranslations();
    if (ShiroLanguageIsChinese()) {
        NSString *chinese = [gEnglishToChinese objectForKey:english];
        return chinese ? chinese : english;
    }
    if (!ShiroLanguageIsRussian()) return english;
    NSString *russian = [gEnglishToRussian objectForKey:english];
    return russian ? russian : ShiroLocalizedDynamic(english);
}

void ShiroSetLanguage(ShiroLanguage language) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (language < ShiroLanguageEnglish || language > ShiroLanguageChinese)
        language = ShiroLanguageEnglish;
    [defaults setInteger:language forKey:SHIRO_LANGUAGE_KEY];
    [defaults synchronize];
    ShiroRelocalizeAllWindows();
    [[NSNotificationCenter defaultCenter] postNotificationName:ShiroLanguageDidChangeNotification object:nil];
}

static void ShiroSwizzle(Class cls, SEL original, SEL replacement) {
    Method a = class_getInstanceMethod(cls, original);
    Method b = class_getInstanceMethod(cls, replacement);
    if (a && b) method_exchangeImplementations(a, b);
}

static void ShiroRelocalizeView(UIView *view);

static void ShiroRelocalizeController(UIViewController *controller) {
    if (!controller) return;
    NSString *title = objc_getAssociatedObject(controller, &kShiroRawControllerTitle);
    if (!title) title = ShiroBaseText(controller.title);
    if (title) controller.title = title;
    UINavigationItem *item = controller.navigationItem;
    NSString *navTitle = objc_getAssociatedObject(item, &kShiroRawNavigationTitle);
    if (!navTitle) navTitle = ShiroBaseText(item.title);
    if (navTitle) item.title = navTitle;
    NSArray *bars = [NSArray arrayWithObjects:
                     item.leftBarButtonItem ? item.leftBarButtonItem : [NSNull null],
                     item.rightBarButtonItem ? item.rightBarButtonItem : [NSNull null], nil];
    for (id object in bars) {
        if ([object isKindOfClass:[UIBarButtonItem class]]) {
            UIBarButtonItem *bar = object;
            NSString *raw = objc_getAssociatedObject(bar, &kShiroRawBarTitle);
            if (!raw) raw = ShiroBaseText(bar.title);
            if (raw) bar.title = ShiroLocalizedText(raw);
        }
    }
    ShiroRelocalizeView(controller.view);
    /* ios 4.3 answers childViewControllers privately with an NSHashTable, not
       the ordered array ios 5 made public with didMoveToParentViewController: */
    NSArray *children = nil;
    if ([controller isKindOfClass:[UINavigationController class]])
        children = ((UINavigationController *)controller).viewControllers;
    else if ([controller respondsToSelector:@selector(didMoveToParentViewController:)])
        children = controller.childViewControllers;
    for (UIViewController *child in children)
        ShiroRelocalizeController(child);
    ShiroRelocalizeController(ShiroPresentedController(controller));
}

static void ShiroRelocalizeView(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        NSString *raw = objc_getAssociatedObject(label, &kShiroRawText);
        if (!raw) raw = ShiroBaseText(label.text);
        if (raw) label.text = raw;
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        NSDictionary *titles = objc_getAssociatedObject(button, &kShiroRawButtonTitles);
        /* the swizzled setTitle:forState: rewrites this same dictionary, and ios 12
           throws on mutation during fast enumeration */
        for (NSNumber *stateNumber in [titles allKeys]) {
            NSString *raw = [titles objectForKey:stateNumber];
            [button setTitle:raw forState:[stateNumber unsignedIntegerValue]];
        }
    }
    if ([view isKindOfClass:[UITextField class]]) {
        UITextField *field = (UITextField *)view;
        NSString *raw = objc_getAssociatedObject(field, &kShiroRawPlaceholder);
        if (!raw) raw = ShiroBaseText(field.placeholder);
        if (raw) field.placeholder = raw;
    }
    for (UIView *child in view.subviews)
        ShiroRelocalizeView(child);
}

void ShiroRelocalizeAllWindows(void) {
    if (!gLocalizationInstalled || ![UIApplication sharedApplication]) return;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        ShiroRelocalizeController(window.rootViewController);
        ShiroRelocalizeView(window);
    }
}

@interface UILabel (ShiroLocalization)
- (void)shiro_setText:(NSString *)text;
@end

@implementation UILabel (ShiroLocalization)
- (void)shiro_setText:(NSString *)text {
    NSString *raw = ShiroBaseText(text);
    objc_setAssociatedObject(self, &kShiroRawText, raw, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self shiro_setText:ShiroLocalizedText(raw)];
}
@end

@interface UIButton (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title forState:(NSUInteger)state;
@end

@implementation UIButton (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title forState:(NSUInteger)state {
    NSString *raw = ShiroBaseText(title);
    NSMutableDictionary *titles = objc_getAssociatedObject(self, &kShiroRawButtonTitles);
    if (!titles) {
        titles = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(self, &kShiroRawButtonTitles, titles, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (raw) [titles setObject:raw forKey:[NSNumber numberWithUnsignedInteger:state]];
    else [titles removeObjectForKey:[NSNumber numberWithUnsignedInteger:state]];
    [self shiro_setTitle:ShiroLocalizedText(raw) forState:state];
}
@end

@interface UITextField (ShiroLocalization)
- (void)shiro_setPlaceholder:(NSString *)placeholder;
@end

@implementation UITextField (ShiroLocalization)
- (void)shiro_setPlaceholder:(NSString *)placeholder {
    NSString *raw = ShiroBaseText(placeholder);
    objc_setAssociatedObject(self, &kShiroRawPlaceholder, raw, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self shiro_setPlaceholder:ShiroLocalizedText(raw)];
}
@end

@interface UIViewController (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title;
@end

@implementation UIViewController (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title {
    NSString *raw = ShiroBaseText(title);
    objc_setAssociatedObject(self, &kShiroRawControllerTitle, raw, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self shiro_setTitle:ShiroLocalizedText(raw)];
}
@end

@interface UINavigationItem (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title;
@end

@implementation UINavigationItem (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title {
    NSString *raw = ShiroBaseText(title);
    objc_setAssociatedObject(self, &kShiroRawNavigationTitle, raw, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self shiro_setTitle:ShiroLocalizedText(raw)];
}
@end

@interface UIBarButtonItem (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title;
- (id)shiro_initWithBarButtonSystemItem:(UIBarButtonSystemItem)item
                                target:(id)target
                                action:(SEL)action;
@end

@implementation UIBarButtonItem (ShiroLocalization)
- (void)shiro_setTitle:(NSString *)title {
    NSString *raw = ShiroBaseText(title);
    objc_setAssociatedObject(self, &kShiroRawBarTitle, raw, OBJC_ASSOCIATION_COPY_NONATOMIC);
    [self shiro_setTitle:ShiroLocalizedText(raw)];
}

/* a system item keeps the width uikit measured for its own english word, so
   putting a longer one on it makes the control grow and then clip the word in
   the middle ("Го...во"). the word bearing items are built as titled items
   instead, which measure their own text. Add and Refresh are glyphs and are
   left alone: a title on those would replace the icon */
- (id)shiro_initWithBarButtonSystemItem:(UIBarButtonSystemItem)item
                                target:(id)target
                                action:(SEL)action {
    NSString *raw = nil;
    UIBarButtonItemStyle style = UIBarButtonItemStylePlain;
    switch (item) {
        case UIBarButtonSystemItemDone:
            raw = @"Done"; style = UIBarButtonItemStyleDone; break;
        case UIBarButtonSystemItemSave:
            raw = @"Save"; style = UIBarButtonItemStyleDone; break;
        case UIBarButtonSystemItemCancel:
            raw = @"Cancel"; break;
        default: break;
    }
    if (!raw)
        return [self shiro_initWithBarButtonSystemItem:item target:target action:action];
/* setTitle: is swizzled, so the raw word is recorded by the initializer and a
   later language change relocalizes it through the same path */
    return [self initWithTitle:ShiroLocalizedText(raw) style:style
                        target:target action:action];
}
@end

void ShiroLocalizationInstall(void) {
    if (gLocalizationInstalled) return;
    ShiroBuildTranslations();
    ShiroSwizzle([UILabel class], @selector(setText:), @selector(shiro_setText:));
    ShiroSwizzle([UIButton class], @selector(setTitle:forState:), @selector(shiro_setTitle:forState:));
    ShiroSwizzle([UITextField class], @selector(setPlaceholder:), @selector(shiro_setPlaceholder:));
    ShiroSwizzle([UIViewController class], @selector(setTitle:), @selector(shiro_setTitle:));
    ShiroSwizzle([UINavigationItem class], @selector(setTitle:), @selector(shiro_setTitle:));
    ShiroSwizzle([UIBarButtonItem class], @selector(setTitle:), @selector(shiro_setTitle:));
    ShiroSwizzle([UIBarButtonItem class], @selector(initWithBarButtonSystemItem:target:action:), @selector(shiro_initWithBarButtonSystemItem:target:action:));
    gLocalizationInstalled = YES;
}
