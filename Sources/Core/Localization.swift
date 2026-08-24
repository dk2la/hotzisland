import Foundation
import Observation

/// Interface languages. The chosen language translates the whole widget,
/// island and settings UI at once.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en, ru, fr, es, zh, pt, de, it, ja, ko

    var id: String { rawValue }

    /// Native display name for the language picker.
    var title: String {
        switch self {
        case .en: "English"
        case .ru: "Русский"
        case .fr: "Français"
        case .es: "Español"
        case .zh: "中文"
        case .pt: "Português"
        case .de: "Deutsch"
        case .it: "Italiano"
        case .ja: "日本語"
        case .ko: "한국어"
        }
    }

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    /// Best match for the user's system languages; falls back to English.
    static var system: AppLanguage {
        for pref in Locale.preferredLanguages {
            let code = String(pref.prefix(2)).lowercased()
            if let match = AppLanguage(rawValue: code) { return match }
        }
        return .en
    }
}

/// Observable language holder — any view that reads `L10n.t(...)` during
/// body evaluation re-renders when the language changes.
@Observable
@MainActor
final class L10n {
    static let shared = L10n()
    var language: AppLanguage = .en

    static func t(_ key: L10nKey) -> String {
        let row = key.row
        let index = shared.language.index
        return index < row.count ? row[index] : row[0]
    }

    static func f(_ key: L10nKey, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }
}

/// String table. Order per row: en, ru, fr, es, zh, pt, de, it, ja, ko.
enum L10nKey {
    // Module titles
    case modPlaybooks, modCalendar, modEmail, modClipboard, modNotes, modChats
    case modMusic, modTimer, modShelf, modSystem
    case comingSoon, comingSoonSub

    // Widget chrome
    case menuSettings, menuIslandMode, menuQuit

    // Timer
    case focusReady, focusRunning, timerStart, timerPause, timerReset, timerDoneNote

    // Media
    case mediaIdle, mediaSilent, mediaNoSignal

    // Clipboard
    case clipCopied, clipClear, clipEmptyTitle, clipEmptySub, clipMemoryNote
    case ageNow, ageMin, ageHour, kindLink, kindText

    // Shelf
    case shelfDrop, shelfLinksNote

    // Calendar
    case calAllDay, calJoin, calNow, calNoEvents

    // Playbooks
    case playNew, playEmpty, playDone, playClosed, playOpened, playErrors, playEdit, playAdd

    // Metrics
    case sysMemory, sysNetwork, sysBattery, sysCharging, sysVolume

    // Settings
    case setTitle, setGeneral, setAppearance, setModules, setPlaybooks, setHotkeys
    case setBehavior, setLaunch, setLaunchSub, setDisplayMode, setDisplayModeSub
    case setIsland, setWidget, setIdle, setIdleSub, setIdleInvisible, setIdleCompact
    case setLanguage, setLanguageSub
    case setShellTheme, setCapsule, setCapsuleSub, setWidgetMaterial, setWidgetMaterialSub
    case setLight, setDark, setAuto
    case setModulesHint, setDefaultTag, setSoonTag
    case setOpenSettings, setExpandIsland, setExpandIslandSub, setHotkeysSoon

    var row: [String] {
        switch self {
        case .modPlaybooks: return ["Playbooks", "Плейбуки", "Playbooks", "Playbooks", "行动手册", "Playbooks", "Playbooks", "Playbook", "プレイブック", "플레이북"]
        case .modCalendar: return ["Calendar", "Календарь", "Calendrier", "Calendario", "日历", "Calendário", "Kalender", "Calendario", "カレンダー", "캘린더"]
        case .modEmail: return ["Email", "Почта", "E-mail", "Correo", "邮件", "E-mail", "E-Mail", "E-mail", "メール", "메일"]
        case .modClipboard: return ["Clipboard", "Буфер", "Presse-papiers", "Portapapeles", "剪贴板", "Área de transferência", "Zwischenablage", "Appunti", "クリップボード", "클립보드"]
        case .modNotes: return ["Notes", "Заметки", "Notes", "Notas", "备忘录", "Notas", "Notizen", "Note", "メモ", "메모"]
        case .modChats: return ["Chats", "Чаты", "Discussions", "Chats", "聊天", "Conversas", "Chats", "Chat", "チャット", "채팅"]
        case .modMusic: return ["Music", "Музыка", "Musique", "Música", "音乐", "Música", "Musik", "Musica", "ミュージック", "음악"]
        case .modTimer: return ["Timer", "Таймер", "Minuteur", "Temporizador", "计时器", "Temporizador", "Timer", "Timer", "タイマー", "타이머"]
        case .modShelf: return ["Shelf", "Полка", "Étagère", "Estante", "暂存架", "Prateleira", "Ablage", "Mensola", "シェルフ", "선반"]
        case .modSystem: return ["System", "Система", "Système", "Sistema", "系统", "Sistema", "System", "Sistema", "システム", "시스템"]
        case .comingSoon: return ["Coming soon", "Скоро", "Bientôt", "Próximamente", "即将推出", "Em breve", "Bald verfügbar", "In arrivo", "近日公開", "곧 제공"]
        case .comingSoonSub: return ["Connects in a later build.", "Подключится в следующих версиях.", "Disponible dans une prochaine version.", "Se conecta en una versión futura.", "将在后续版本中接入。", "Chega numa versão futura.", "Kommt in einer späteren Version.", "Arriva in una versione futura.", "今後のバージョンで対応します。", "이후 버전에서 연결됩니다."]

        case .menuSettings: return ["Settings…", "Настройки…", "Réglages…", "Ajustes…", "设置…", "Ajustes…", "Einstellungen…", "Impostazioni…", "設定…", "설정…"]
        case .menuIslandMode: return ["Island mode", "Режим острова", "Mode îlot", "Modo isla", "灵动岛模式", "Modo ilha", "Insel-Modus", "Modalità isola", "アイランドモード", "아일랜드 모드"]
        case .menuQuit: return ["Quit HotzIsland", "Завершить HotzIsland", "Quitter HotzIsland", "Salir de HotzIsland", "退出 HotzIsland", "Sair do HotzIsland", "HotzIsland beenden", "Esci da HotzIsland", "HotzIslandを終了", "HotzIsland 종료"]

        case .focusReady: return ["focus · ready", "фокус · готов", "focus · prêt", "foco · listo", "专注 · 就绪", "foco · pronto", "Fokus · bereit", "focus · pronto", "フォーカス · 準備完了", "집중 · 준비"]
        case .focusRunning: return ["focus · running", "фокус · идёт", "focus · en cours", "foco · en curso", "专注 · 进行中", "foco · em curso", "Fokus · läuft", "focus · in corso", "フォーカス · 実行中", "집중 · 진행 중"]
        case .timerStart: return ["Start", "Старт", "Démarrer", "Iniciar", "开始", "Iniciar", "Start", "Avvia", "開始", "시작"]
        case .timerPause: return ["Pause", "Пауза", "Pause", "Pausa", "暂停", "Pausa", "Pause", "Pausa", "一時停止", "일시정지"]
        case .timerReset: return ["Reset", "Сброс", "Réinitialiser", "Reiniciar", "重置", "Repor", "Zurücksetzen", "Azzera", "リセット", "재설정"]
        case .timerDoneNote: return ["done → live event + sound", "по концу → live-событие + звук", "fin → événement live + son", "fin → evento live + sonido", "结束 → 灵动事件 + 声音", "fim → evento live + som", "Ende → Live-Event + Ton", "fine → evento live + suono", "終了 → ライブイベント + サウンド", "종료 → 라이브 이벤트 + 소리"]

        case .mediaIdle: return ["Nothing is playing", "Ничего не играет", "Rien ne joue", "Nada suena", "没有播放内容", "Nada a tocar", "Nichts spielt", "Niente in riproduzione", "再生中の曲はありません", "재생 중인 항목 없음"]
        case .mediaSilent: return ["%@ is silent", "%@ молчит", "%@ est muet", "%@ está en silencio", "%@ 无声", "%@ está em silêncio", "%@ ist stumm", "%@ è muto", "%@ は無音です", "%@ 무음"]
        case .mediaNoSignal: return ["no signal", "нет сигнала", "pas de signal", "sin señal", "无信号", "sem sinal", "kein Signal", "nessun segnale", "信号なし", "신호 없음"]

        case .clipCopied: return ["Copied", "Готово", "Copié", "Copiado", "已复制", "Copiado", "Kopiert", "Copiato", "コピー済み", "복사됨"]
        case .clipClear: return ["Clear", "Очистить", "Effacer", "Limpiar", "清除", "Limpar", "Leeren", "Svuota", "クリア", "지우기"]
        case .clipEmptyTitle: return ["empty", "пусто", "vide", "vacío", "空", "vazio", "leer", "vuoto", "空", "비어 있음"]
        case .clipEmptySub: return ["Copied text will appear here", "Скопированный текст появится здесь", "Le texte copié apparaîtra ici", "El texto copiado aparecerá aquí", "复制的文本会显示在这里", "O texto copiado aparecerá aqui", "Kopierter Text erscheint hier", "Il testo copiato apparirà qui", "コピーしたテキストがここに表示されます", "복사한 텍스트가 여기에 표시됩니다"]
        case .clipMemoryNote: return ["In memory · secrets skipped", "В памяти · секреты не сохраняются", "En mémoire · secrets ignorés", "En memoria · secretos omitidos", "仅内存 · 跳过密码", "Em memória · segredos ignorados", "Im Speicher · Geheimnisse ausgelassen", "In memoria · segreti esclusi", "メモリ内 · 機密は除外", "메모리 저장 · 비밀 제외"]
        case .ageNow: return ["now", "сейчас", "à l'instant", "ahora", "刚刚", "agora", "jetzt", "adesso", "たった今", "방금"]
        case .ageMin: return ["%d min", "%d мин", "%d min", "%d min", "%d 分钟", "%d min", "%d Min.", "%d min", "%d分", "%d분"]
        case .ageHour: return ["%d h", "%d ч", "%d h", "%d h", "%d 小时", "%d h", "%d Std.", "%d h", "%d時間", "%d시간"]
        case .kindLink: return ["link", "ссылка", "lien", "enlace", "链接", "ligação", "Link", "link", "リンク", "링크"]
        case .kindText: return ["text", "текст", "texte", "texto", "文本", "texto", "Text", "testo", "テキスト", "텍스트"]

        case .shelfDrop: return ["Drop files here", "Перетащите файлы сюда", "Déposez des fichiers ici", "Suelta archivos aquí", "拖放文件到这里", "Largue ficheiros aqui", "Dateien hier ablegen", "Trascina i file qui", "ここにファイルをドロップ", "여기에 파일을 놓으세요"]
        case .shelfLinksNote: return ["Links only — originals stay in place", "Только ссылки — оригиналы остаются на месте", "Liens seulement — les originaux restent en place", "Solo enlaces — los originales no se mueven", "仅链接 — 原文件保持原位", "Só ligações — os originais ficam no lugar", "Nur Links — Originale bleiben am Ort", "Solo link — gli originali restano al loro posto", "リンクのみ — 元ファイルは移動しません", "링크만 — 원본은 그대로"]

        case .calAllDay: return ["all day", "весь день", "toute la journée", "todo el día", "全天", "o dia todo", "ganztägig", "tutto il giorno", "終日", "종일"]
        case .calJoin: return ["join", "войти", "rejoindre", "unirse", "加入", "entrar", "beitreten", "entra", "参加", "참여"]
        case .calNow: return ["now", "сейчас", "maintenant", "ahora", "现在", "agora", "jetzt", "ora", "今", "지금"]
        case .calNoEvents: return ["no events", "нет событий", "aucun événement", "sin eventos", "没有日程", "sem eventos", "keine Termine", "nessun evento", "予定なし", "일정 없음"]

        case .playNew: return ["+ new", "+ новый", "+ nouveau", "+ nuevo", "+ 新建", "+ novo", "+ neu", "+ nuovo", "+ 新規", "+ 새로 만들기"]
        case .playEmpty: return ["empty", "пустой", "vide", "vacío", "空", "vazio", "leer", "vuoto", "空", "비어 있음"]
        case .playDone: return ["done", "выполнен", "terminé", "hecho", "已完成", "concluído", "fertig", "fatto", "完了", "완료"]
        case .playClosed: return ["closed %d", "закрыто %d", "fermé %d", "cerradas %d", "已关闭 %d", "fechadas %d", "geschlossen %d", "chiuse %d", "終了 %d", "닫음 %d"]
        case .playOpened: return ["opened %d", "открыто %d", "ouvert %d", "abiertas %d", "已打开 %d", "abertas %d", "geöffnet %d", "aperte %d", "起動 %d", "열림 %d"]
        case .playErrors: return ["errors %d", "ошибок %d", "erreurs %d", "errores %d", "错误 %d", "erros %d", "Fehler %d", "errori %d", "エラー %d", "오류 %d"]
        case .playEdit: return ["Edit", "Изменить", "Modifier", "Editar", "编辑", "Editar", "Bearbeiten", "Modifica", "編集", "편집"]
        case .playAdd: return ["Add playbook…", "Добавить плейбук…", "Ajouter un playbook…", "Añadir playbook…", "添加行动手册…", "Adicionar playbook…", "Playbook hinzufügen…", "Aggiungi playbook…", "プレイブックを追加…", "플레이북 추가…"]

        case .sysMemory: return ["Memory", "Память", "Mémoire", "Memoria", "内存", "Memória", "Speicher", "Memoria", "メモリ", "메모리"]
        case .sysNetwork: return ["Network", "Сеть", "Réseau", "Red", "网络", "Rede", "Netzwerk", "Rete", "ネットワーク", "네트워크"]
        case .sysBattery: return ["Battery", "Батарея", "Batterie", "Batería", "电池", "Bateria", "Batterie", "Batteria", "バッテリー", "배터리"]
        case .sysCharging: return ["charging", "заряжается", "en charge", "cargando", "充电中", "a carregar", "lädt", "in carica", "充電中", "충전 중"]
        case .sysVolume: return ["Volume", "Громкость", "Volume", "Volumen", "音量", "Volume", "Lautstärke", "Volume", "音量", "음량"]

        case .setTitle: return ["Settings", "Настройки", "Réglages", "Ajustes", "设置", "Ajustes", "Einstellungen", "Impostazioni", "設定", "설정"]
        case .setGeneral: return ["General", "Общие", "Général", "General", "通用", "Geral", "Allgemein", "Generali", "一般", "일반"]
        case .setAppearance: return ["Appearance", "Вид", "Apparence", "Apariencia", "外观", "Aparência", "Aussehen", "Aspetto", "外観", "모양"]
        case .setModules: return ["Modules", "Модули", "Modules", "Módulos", "模块", "Módulos", "Module", "Moduli", "モジュール", "모듈"]
        case .setPlaybooks: return ["Playbooks", "Плейбуки", "Playbooks", "Playbooks", "行动手册", "Playbooks", "Playbooks", "Playbook", "プレイブック", "플레이북"]
        case .setHotkeys: return ["Hotkeys", "Хоткеи", "Raccourcis", "Atajos", "快捷键", "Atalhos", "Kurzbefehle", "Scorciatoie", "ショートカット", "단축키"]
        case .setBehavior: return ["Behavior", "Поведение", "Comportement", "Comportamiento", "行为", "Comportamento", "Verhalten", "Comportamento", "動作", "동작"]
        case .setLaunch: return ["Launch at login", "Запускать при входе", "Lancer à l'ouverture de session", "Abrir al iniciar sesión", "登录时启动", "Abrir ao iniciar sessão", "Beim Anmelden starten", "Avvia all'accesso", "ログイン時に起動", "로그인 시 실행"]
        case .setLaunchSub: return ["Menu-bar agent, no Dock icon", "Агент меню-бара, без иконки в доке", "Agent de barre de menus, sans icône Dock", "Agente de barra de menús, sin icono en el Dock", "菜单栏代理，无 Dock 图标", "Agente da barra de menus, sem ícone na Dock", "Menüleisten-Agent, ohne Dock-Symbol", "Agente della barra dei menu, senza icona nel Dock", "メニューバー常駐、Dockアイコンなし", "메뉴 막대 에이전트, Dock 아이콘 없음"]
        case .setDisplayMode: return ["Display mode", "Режим отображения", "Mode d'affichage", "Modo de visualización", "显示模式", "Modo de exibição", "Anzeigemodus", "Modalità di visualizzazione", "表示モード", "표시 모드"]
        case .setDisplayModeSub: return ["Modules at the notch or as an edge widget — live events stay on the notch", "Модули у выреза или виджетом у края — live-события всегда на вырезе", "Modules au notch ou en widget de bord — les événements live restent au notch", "Módulos en el notch o como widget lateral — los eventos live quedan en el notch", "模块显示在刘海处或屏幕边缘 — 灵动事件始终在刘海", "Módulos no notch ou como widget na borda — eventos live ficam no notch", "Module am Notch oder als Rand-Widget — Live-Events bleiben am Notch", "Moduli al notch o come widget sul bordo — gli eventi live restano al notch", "モジュールをノッチまたは端のウィジェットに — ライブイベントはノッチに表示", "노치 또는 가장자리 위젯으로 표시 — 라이브 이벤트는 노치에 유지"]
        case .setIsland: return ["Island", "Остров", "Îlot", "Isla", "灵动岛", "Ilha", "Insel", "Isola", "アイランド", "아일랜드"]
        case .setWidget: return ["Widget", "Виджет", "Widget", "Widget", "小组件", "Widget", "Widget", "Widget", "ウィジェット", "위젯"]
        case .setIdle: return ["Idle mode", "Режим покоя", "Mode veille", "Modo inactivo", "空闲状态", "Modo inativo", "Ruhemodus", "Modalità inattiva", "アイドル時", "대기 모드"]
        case .setIdleSub: return ["What is visible when nothing happens", "Что видно, когда ничего не происходит", "Ce qui est visible quand rien ne se passe", "Qué se ve cuando no pasa nada", "无事件时显示的内容", "O que aparece quando nada acontece", "Was sichtbar ist, wenn nichts passiert", "Cosa si vede quando non succede nulla", "何もないときの表示", "아무 일도 없을 때 표시"]
        case .setIdleInvisible: return ["Invisible", "Невидим", "Invisible", "Invisible", "隐藏", "Invisível", "Unsichtbar", "Invisibile", "非表示", "숨김"]
        case .setIdleCompact: return ["Indicators", "Индикаторы", "Indicateurs", "Indicadores", "指示器", "Indicadores", "Indikatoren", "Indicatori", "インジケーター", "표시기"]
        case .setLanguage: return ["Language", "Язык", "Langue", "Idioma", "语言", "Idioma", "Sprache", "Lingua", "言語", "언어"]
        case .setLanguageSub: return ["Translates the widget, island and settings", "Переводит виджет, остров и настройки", "Traduit le widget, l'îlot et les réglages", "Traduce el widget, la isla y los ajustes", "翻译小组件、灵动岛和设置", "Traduz o widget, a ilha e os ajustes", "Übersetzt Widget, Insel und Einstellungen", "Traduce widget, isola e impostazioni", "ウィジェット・アイランド・設定を翻訳", "위젯·아일랜드·설정을 번역"]
        case .setShellTheme: return ["Shell theme", "Тема оболочки", "Thème de coque", "Tema del armazón", "外壳主题", "Tema da carcaça", "Gehäuse-Thema", "Tema della shell", "シェルテーマ", "셸 테마"]
        case .setCapsule: return ["Capsule", "Капсула", "Capsule", "Cápsula", "胶囊", "Cápsula", "Kapsel", "Capsula", "カプセル", "캡슐"]
        case .setCapsuleSub: return ["Affects only the island", "Влияет только на остров", "N'affecte que l'îlot", "Solo afecta a la isla", "仅影响灵动岛", "Afeta apenas a ilha", "Betrifft nur die Insel", "Riguarda solo l'isola", "アイランドのみに適用", "아일랜드에만 적용"]
        case .setWidgetMaterial: return ["Widget material", "Материал виджета", "Matériau du widget", "Material del widget", "小组件材质", "Material do widget", "Widget-Material", "Materiale del widget", "ウィジェットの素材", "위젯 재질"]
        case .setWidgetMaterialSub: return ["Glass at the screen edge — the island is always dark", "Стекло у края экрана — остров всегда тёмный", "Verre au bord de l'écran — l'îlot reste sombre", "Vidrio en el borde — la isla siempre es oscura", "屏幕边缘的玻璃 — 灵动岛始终为深色", "Vidro na borda — a ilha é sempre escura", "Glas am Bildschirmrand — die Insel bleibt dunkel", "Vetro sul bordo — l'isola resta scura", "画面端のガラス — アイランドは常にダーク", "가장자리 유리 — 아일랜드는 항상 어두움"]
        case .setLight: return ["Light", "Светлый", "Clair", "Claro", "浅色", "Claro", "Hell", "Chiaro", "ライト", "라이트"]
        case .setDark: return ["Dark", "Тёмный", "Sombre", "Oscuro", "深色", "Escuro", "Dunkel", "Scuro", "ダーク", "다크"]
        case .setAuto: return ["Auto", "Авто", "Auto", "Auto", "自动", "Auto", "Auto", "Auto", "自動", "자동"]
        case .setModulesHint: return ["Everything is replaceable — the first six just ship enabled. Drag to reorder; the last enabled module cannot be turned off.", "Всё заменяемо — первые шесть просто включены из коробки. Порядок — перетаскиванием; последний включённый модуль выключить нельзя.", "Tout est remplaçable — les six premiers sont juste activés par défaut. Glissez pour réordonner ; le dernier module actif ne peut pas être désactivé.", "Todo es reemplazable — los seis primeros vienen activados. Arrastra para reordenar; el último módulo activo no se puede apagar.", "一切皆可替换 — 前六个只是默认启用。拖动排序；最后一个启用的模块无法关闭。", "Tudo é substituível — os seis primeiros vêm ativados. Arraste para reordenar; o último módulo ativo não pode ser desligado.", "Alles ist ersetzbar — die ersten sechs sind nur ab Werk aktiv. Ziehen zum Sortieren; das letzte aktive Modul lässt sich nicht abschalten.", "Tutto è sostituibile — i primi sei sono solo attivi di default. Trascina per riordinare; l'ultimo modulo attivo non si può spegnere.", "すべて入れ替え可能 — 最初の6つは初期状態で有効なだけです。ドラッグで並び替え。最後の有効モジュールはオフにできません。", "모두 교체 가능 — 처음 여섯 개는 기본 활성화일 뿐입니다. 드래그로 순서 변경, 마지막 활성 모듈은 끌 수 없습니다."]
        case .setDefaultTag: return ["default", "по умолчанию", "par défaut", "predeterminado", "默认", "padrão", "Standard", "predefinito", "デフォルト", "기본"]
        case .setSoonTag: return ["soon", "скоро", "bientôt", "pronto", "即将", "em breve", "bald", "presto", "近日", "곧"]
        case .setOpenSettings: return ["Open settings", "Открыть настройки", "Ouvrir les réglages", "Abrir ajustes", "打开设置", "Abrir ajustes", "Einstellungen öffnen", "Apri impostazioni", "設定を開く", "설정 열기"]
        case .setExpandIsland: return ["Expand the island", "Раскрыть остров", "Déployer l'îlot", "Expandir la isla", "展开灵动岛", "Expandir a ilha", "Insel aufklappen", "Espandi l'isola", "アイランドを展開", "아일랜드 펼치기"]
        case .setExpandIslandSub: return ["Hover the cursor over the notch", "Наведение курсора на вырез", "Survolez le notch", "Pasa el cursor por el notch", "将光标悬停在刘海上", "Passe o cursor sobre o notch", "Cursor über den Notch bewegen", "Passa il cursore sul notch", "ノッチにカーソルを合わせる", "노치에 커서를 올리기"]
        case .setHotkeysSoon: return ["Custom shortcuts are planned.", "Настраиваемые сочетания — в планах.", "Raccourcis personnalisés à venir.", "Atajos personalizables en camino.", "自定义快捷键即将推出。", "Atalhos personalizados a caminho.", "Eigene Kurzbefehle sind geplant.", "Scorciatoie personalizzate in arrivo.", "カスタムショートカットは今後対応予定。", "사용자 지정 단축키는 준비 중입니다."]
        }
    }
}
