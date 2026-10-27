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

    /// Locale used for on-device dictation in this interface language.
    var speechLocale: Locale {
        switch self {
        case .en: Locale(identifier: "en_US")
        case .ru: Locale(identifier: "ru_RU")
        case .fr: Locale(identifier: "fr_FR")
        case .es: Locale(identifier: "es_ES")
        case .zh: Locale(identifier: "zh_CN")
        case .pt: Locale(identifier: "pt_BR")
        case .de: Locale(identifier: "de_DE")
        case .it: Locale(identifier: "it_IT")
        case .ja: Locale(identifier: "ja_JP")
        case .ko: Locale(identifier: "ko_KR")
        }
    }

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

    /// "now" / "5 min" / "3 h"; past a day the formatter takes over, when given.
    static func age(since date: Date, olderThanADay formatter: DateFormatter? = nil) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return t(.ageNow) }
        if minutes < 60 { return f(.ageMin, minutes) }
        if let formatter, minutes >= 60 * 24 { return formatter.string(from: date) }
        return f(.ageHour, minutes / 60)
    }
}

/// String table. Order per row: en, ru, fr, es, zh, pt, de, it, ja, ko.
enum L10nKey {
    // Module titles
    case modPlaybooks, modCalendar, modEmail, modClipboard, modNotes, modChats
    case modMusic, modTimer, modShelf, modSystem, modAssistant
    case comingSoonSub

    // Widget chrome
    case menuSettings, menuQuit

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
    case calAllDay, calJoin, calNow, calNoEvents, calToday, calTomorrow
    case calStartsInMinutes, calStartsInHours
    case calNewEvent, calEditEvent, calTitleField, calStarts, calEnds
    case calLocationField, calURLField, calNotesField, calAttendees, calOrganizer
    case calOpenInCalendar, calInviteesHint, calDelete, calConfirmDelete, calSave, calEdit
    case timerCustomPlaceholder

    // Notes
    case notesEmptyTitle, notesEmptySub, notesQuickPlaceholder, notesNew
    case notesFolder, notesChange

    // Speech
    case speechListening, speechDenied, speechOpenSettings

    // Email
    case setAccounts
    case mailSetupTitle, mailSetupSub, mailSetupAction
    case mailInboxEmpty, mailOpenInApp, mailNoBody, mailNoSubject
    case mailProvider, mailAddress, mailPassword, mailPasswordHint, mailOutlookWarning
    case mailImapHost, mailSmtpHost
    case mailCheck, mailChecking, mailCheckOk, mailRemove
    case mailReply, mailReplyPlaceholder, mailSend, mailSending, mailSent, mailCancel, mailShowImages, mailHideImages
    case mailReplyAll, mailForward, mailCc, mailForwardedHeader
    case mailSearchPlaceholder, mailNoResults, mailArchive, mailRefresh, mailSearch
    case mailToField, mailSubjectField, mailNewMessage, mailBodyPlaceholder
    case mailboxPrimary, mailboxStarred, mailboxImportant, mailboxSent, mailboxSpam

    // Assistant
    case asstSetupTitle, asstSetupSub, asstHint, asstPlaceholder, asstThinking
    case asstBaseURL, asstModel, asstKey, asstKeyHint
    case asstProviderClaude, asstProviderCodex, asstProviderAPI
    case asstPreset, asstModelOptional, asstCLIMissing, asstVoiceHint, asstEmptyTitle
    case asstPlaybookConfirm, asstPlaybookRun

    // Playbooks
    case playNew, playEmpty, playDone, playClosed, playOpened, playErrors, playAdd
    case playApps, playCloseRest, playFocus
    case playStepOpenApps, playStepCloseOthers, playStepShortcut, playStepFocus, playStepTimer, playStepURLs
    case playAddStep, playLayout, playGrantAccess, playLayoutHint
    case playLayoutNone, playLayoutLeftRight, playLayoutThirds, playLayoutGrid2x2, playLayoutMainSide, playLayoutFullscreen
    case playName, playIcon, playSteps, playNoSteps, playSearchApps, playAddBundleID, playSelectedCount
    case playChooseShortcut, playShortcutName, playMinutes, playURLsHint, playLinks

    // Metrics
    case sysMemory, sysNetwork, sysBattery, sysCharging, sysVolume

    // Settings
    case setTitle, setGeneral, setAppearance, setModules, setHotkeys
    case setBehavior, setLaunch, setLaunchSub
    case setIdle, setIdleSub, setIdleInvisible, setIdleCompact
    case setLanguage, setLanguageSub
    case setShellTheme, setCapsule, setCapsuleSub, setWidgetMaterial, setWidgetMaterialSub
    case setLight, setDark, setAuto
    case setModulesHint, setDefaultTag, setSoonTag
    case setOpenSettings, setExpandIsland, setExpandIslandSub
    case setOutsideClick, setOutsideClickSub
    case setHideWidget, setHideWidgetSub, setPinPanel, setPinPanelSub
    case setModeToggle, setModeToggleSub
    case setDemoSection, setDemo, setDemoSub, setDemoEvents, setDemoEventsSub

    // Welcome tour
    case obTour, obTourSub, obShow, obShowAtLaunch, obShowAtLaunchSub
    case obNext, obBack, obStart, obBackToTour, obConnect
    case obAllowAccess, obAccessGranted, obOpenPrivacy, obSaved
    case obWelcomeKicker, obReadyKicker
    case obCalendarTitle, obMailTitle, obPlaybooksTitle, obNotesTitle, obAssistantTitle, obFinishTitle
    case obWelcomeBody, obCalendarBody, obMailBody, obPlaybooksBody, obNotesBody, obAssistantBody, obFinishBody
    case obMockEvent1, obMockEvent2, obMockEvent3, obMockEvent4
    case obMockMail1, obMockMail2, obMockMail3, obMockReply
    case obMockPlaybook1, obMockPlaybook2
    case obMockNoteTitle, obMockNoteBody, obMockNoteDictation
    case obMockAsk, obMockAnswer

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
        case .modAssistant: return ["Assistant", "Ассистент", "Assistant", "Asistente", "助手", "Assistente", "Assistent", "Assistente", "アシスタント", "어시스턴트"]
        case .comingSoonSub: return ["Connects in a later build.", "Подключится в следующих версиях.", "Disponible dans une prochaine version.", "Se conecta en una versión futura.", "将在后续版本中接入。", "Chega numa versão futura.", "Kommt in einer späteren Version.", "Arriva in una versione futura.", "今後のバージョンで対応します。", "이후 버전에서 연결됩니다."]

        case .menuSettings: return ["Settings…", "Настройки…", "Réglages…", "Ajustes…", "设置…", "Ajustes…", "Einstellungen…", "Impostazioni…", "設定…", "설정…"]
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
        case .calJoin: return ["Join", "Войти", "Rejoindre", "Unirse", "加入", "Entrar", "Beitreten", "Entra", "参加", "참여"]
        case .calNow: return ["now", "сейчас", "maintenant", "ahora", "现在", "agora", "jetzt", "ora", "今", "지금"]
        case .calStartsInMinutes: return ["in %d min", "через %d мин", "dans %d min", "en %d min", "%d 分钟后", "em %d min", "in %d Min.", "tra %d min", "%d分後", "%d분 후"]
        case .calStartsInHours: return ["in %dh %02dm", "через %dч %02dм", "dans %dh %02dm", "en %dh %02dm", "%d小时%02d分后", "em %dh %02dm", "in %dh %02dm", "tra %dh %02dm", "%d時間%02d分後", "%d시간 %02d분 후"]
        case .calNoEvents: return ["no events", "нет событий", "aucun événement", "sin eventos", "没有日程", "sem eventos", "keine Termine", "nessun evento", "予定なし", "일정 없음"]
        case .calToday: return ["Today", "Сегодня", "Aujourd'hui", "Hoy", "今天", "Hoje", "Heute", "Oggi", "今日", "오늘"]
        case .calTomorrow: return ["Tomorrow", "Завтра", "Demain", "Mañana", "明天", "Amanhã", "Morgen", "Domani", "明日", "내일"]
        case .calNewEvent: return ["New event", "Новое событие", "Nouvel événement", "Nuevo evento", "新建日程", "Novo evento", "Neuer Termin", "Nuovo evento", "新規イベント", "새 일정"]
        case .calEditEvent: return ["Edit event", "Изменить событие", "Modifier l'événement", "Editar evento", "编辑日程", "Editar evento", "Termin bearbeiten", "Modifica evento", "イベントを編集", "일정 편집"]
        case .calTitleField: return ["Title", "Название", "Titre", "Título", "标题", "Título", "Titel", "Titolo", "タイトル", "제목"]
        case .calStarts: return ["Starts", "Начало", "Début", "Inicio", "开始", "Início", "Beginn", "Inizio", "開始", "시작"]
        case .calEnds: return ["Ends", "Конец", "Fin", "Fin", "结束", "Fim", "Ende", "Fine", "終了", "종료"]
        case .calLocationField: return ["Location", "Место", "Lieu", "Ubicación", "地点", "Local", "Ort", "Luogo", "場所", "위치"]
        case .calURLField: return ["URL", "Ссылка", "URL", "URL", "网址", "URL", "URL", "URL", "URL", "URL"]
        case .calNotesField: return ["Notes", "Заметки", "Notes", "Notas", "备注", "Notas", "Notizen", "Note", "メモ", "메모"]
        case .calAttendees: return ["Attendees", "Участники", "Participants", "Asistentes", "参与者", "Participantes", "Teilnehmer", "Partecipanti", "参加者", "참석자"]
        case .calOrganizer: return ["Organizer", "Организатор", "Organisateur", "Organizador", "组织者", "Organizador", "Organisator", "Organizzatore", "主催者", "주최자"]
        case .calOpenInCalendar: return ["Open in Calendar", "Открыть в Календаре", "Ouvrir dans Calendrier", "Abrir en Calendario", "在日历中打开", "Abrir no Calendário", "In Kalender öffnen", "Apri in Calendario", "カレンダーで開く", "캘린더에서 열기"]
        case .calInviteesHint: return ["Invitees are added in Calendar", "Участники добавляются в Календаре", "Les invités s'ajoutent dans Calendrier", "Los invitados se añaden en Calendario", "邀请对象在日历中添加", "Os convidados são adicionados no Calendário", "Eingeladene werden im Kalender hinzugefügt", "Gli invitati si aggiungono in Calendario", "参加者はカレンダーで追加します", "초대 대상은 캘린더에서 추가합니다"]
        case .calDelete: return ["Delete", "Удалить", "Supprimer", "Eliminar", "删除", "Apagar", "Löschen", "Elimina", "削除", "삭제"]
        case .calConfirmDelete: return ["Confirm delete", "Подтвердить удаление", "Confirmer la suppression", "Confirmar eliminación", "确认删除", "Confirmar exclusão", "Löschen bestätigen", "Conferma eliminazione", "削除を確認", "삭제 확인"]
        case .calSave: return ["Save", "Сохранить", "Enregistrer", "Guardar", "保存", "Guardar", "Sichern", "Salva", "保存", "저장"]
        case .calEdit: return ["Edit", "Изменить", "Modifier", "Editar", "编辑", "Editar", "Bearbeiten", "Modifica", "編集", "편집"]
        case .timerCustomPlaceholder: return ["min", "мин", "min", "min", "分", "min", "Min", "min", "分", "분"]

        case .notesEmptyTitle: return ["no notes", "нет заметок", "aucune note", "sin notas", "没有备忘录", "sem notas", "keine Notizen", "nessuna nota", "メモなし", "메모 없음"]
        case .notesEmptySub: return ["Type below — Enter saves a note", "Напишите ниже — Enter сохранит заметку", "Écrivez ci-dessous — Entrée enregistre", "Escribe abajo — Enter guarda la nota", "在下方输入 — 回车保存", "Escreva abaixo — Enter guarda a nota", "Unten tippen — Enter speichert", "Scrivi sotto — Invio salva la nota", "下に入力 — Enterで保存", "아래에 입력 — Enter로 저장"]
        case .notesQuickPlaceholder: return ["Quick note…", "Быстрая заметка…", "Note rapide…", "Nota rápida…", "快速记录…", "Nota rápida…", "Schnellnotiz…", "Nota rapida…", "クイックメモ…", "빠른 메모…"]
        case .notesNew: return ["New", "Новая", "Nouvelle", "Nueva", "新建", "Nova", "Neu", "Nuova", "新規", "새로 만들기"]
        case .notesFolder: return ["Notes folder", "Папка заметок", "Dossier des notes", "Carpeta de notas", "备忘录文件夹", "Pasta de notas", "Notizen-Ordner", "Cartella note", "メモフォルダ", "메모 폴더"]
        case .notesChange: return ["Change…", "Изменить…", "Modifier…", "Cambiar…", "更改…", "Alterar…", "Ändern…", "Cambia…", "変更…", "변경…"]

        case .speechListening: return ["Listening…", "Слушаю…", "J'écoute…", "Escuchando…", "正在聆听…", "A ouvir…", "Höre zu…", "In ascolto…", "聞き取り中…", "듣는 중…"]
        case .speechDenied: return ["Microphone or speech recognition is not allowed", "Нет доступа к микрофону или распознаванию речи", "Micro ou reconnaissance vocale non autorisés", "Micrófono o reconocimiento de voz no permitidos", "麦克风或语音识别未授权", "Microfone ou reconhecimento de voz não autorizados", "Mikrofon oder Spracherkennung nicht erlaubt", "Microfono o riconoscimento vocale non consentiti", "マイクまたは音声認識が許可されていません", "마이크 또는 음성 인식이 허용되지 않음"]
        case .speechOpenSettings: return ["Open System Settings", "Открыть настройки системы", "Ouvrir Réglages Système", "Abrir Ajustes del Sistema", "打开系统设置", "Abrir Definições do Sistema", "Systemeinstellungen öffnen", "Apri Impostazioni di Sistema", "システム設定を開く", "시스템 설정 열기"]

        case .setAccounts: return ["Accounts", "Аккаунты", "Comptes", "Cuentas", "账户", "Contas", "Konten", "Account", "アカウント", "계정"]
        case .mailSetupTitle: return ["no account", "нет аккаунта", "aucun compte", "sin cuenta", "未设置账户", "sem conta", "kein Konto", "nessun account", "アカウントなし", "계정 없음"]
        case .mailSetupSub: return ["Connect your mailbox — it stays between your Mac and your provider", "Подключите ящик — данные ходят только между Mac и вашим провайдером", "Connectez votre boîte — tout reste entre votre Mac et votre fournisseur", "Conecta tu buzón — todo queda entre tu Mac y tu proveedor", "连接邮箱 — 数据仅在您的 Mac 与邮件服务商之间传输", "Ligue a sua caixa — tudo fica entre o Mac e o fornecedor", "Postfach verbinden — alles bleibt zwischen Mac und Anbieter", "Collega la casella — resta tra il tuo Mac e il provider", "メールボックスを接続 — データはMacとプロバイダ間のみ", "메일함 연결 — 데이터는 Mac과 제공업체 사이에만"]
        case .mailSetupAction: return ["Set up account", "Настроить аккаунт", "Configurer le compte", "Configurar cuenta", "设置账户", "Configurar conta", "Konto einrichten", "Configura account", "アカウントを設定", "계정 설정"]
        case .mailInboxEmpty: return ["inbox is empty", "входящие пусты", "boîte vide", "bandeja vacía", "收件箱为空", "caixa vazia", "Posteingang leer", "posta vuota", "受信トレイは空", "받은편지함 비어 있음"]
        case .mailOpenInApp: return ["Open in Mail", "Открыть в почте", "Ouvrir dans Mail", "Abrir en Mail", "在邮件App中打开", "Abrir no Mail", "In Mail öffnen", "Apri in Mail", "メールで開く", "Mail에서 열기"]
        case .mailNoBody: return ["(no text)", "(нет текста)", "(pas de texte)", "(sin texto)", "（无正文）", "(sem texto)", "(kein Text)", "(nessun testo)", "（本文なし）", "(본문 없음)"]
        case .mailNoSubject: return ["(no subject)", "(без темы)", "(sans objet)", "(sin asunto)", "（无主题）", "(sem assunto)", "(kein Betreff)", "(nessun oggetto)", "（件名なし）", "(제목 없음)"]
        case .mailReply: return ["Reply", "Ответить", "Répondre", "Responder", "回复", "Responder", "Antworten", "Rispondi", "返信", "답장"]
        case .mailReplyAll: return ["Reply all", "Ответить всем", "Répondre à tous", "Responder a todos", "全部回复", "Responder a todos", "Allen antworten", "Rispondi a tutti", "全員に返信", "전체 답장"]
        case .mailForward: return ["Forward", "Переслать", "Transférer", "Reenviar", "转发", "Reencaminhar", "Weiterleiten", "Inoltra", "転送", "전달"]
        case .mailCc: return ["Cc", "Копия", "Cc", "Cc", "抄送", "Cc", "Cc", "Cc", "Cc", "참조"]
        case .mailForwardedHeader: return ["Forwarded message", "Пересланное сообщение", "Message transféré", "Mensaje reenviado", "转发的邮件", "Mensagem reencaminhada", "Weitergeleitete Nachricht", "Messaggio inoltrato", "転送メッセージ", "전달된 메시지"]
        case .mailReplyPlaceholder: return ["Your reply…", "Ваш ответ…", "Votre réponse…", "Tu respuesta…", "你的回复…", "A sua resposta…", "Ihre Antwort…", "La tua risposta…", "返信を入力…", "답장 입력…"]
        case .mailSend: return ["Send", "Отправить", "Envoyer", "Enviar", "发送", "Enviar", "Senden", "Invia", "送信", "보내기"]
        case .mailSending: return ["Sending…", "Отправка…", "Envoi…", "Enviando…", "发送中…", "A enviar…", "Senden…", "Invio…", "送信中…", "보내는 중…"]
        case .mailSent: return ["Sent", "Отправлено", "Envoyé", "Enviado", "已发送", "Enviado", "Gesendet", "Inviato", "送信済み", "보냄"]
        case .mailCancel: return ["Cancel", "Отмена", "Annuler", "Cancelar", "取消", "Cancelar", "Abbrechen", "Annulla", "キャンセル", "취소"]
        case .mailShowImages: return ["Show images", "Показать картинки", "Afficher les images", "Mostrar imágenes", "显示图片", "Mostrar imagens", "Bilder anzeigen", "Mostra immagini", "画像を表示", "이미지 표시"]
        case .mailHideImages: return ["Hide images", "Скрыть картинки", "Masquer les images", "Ocultar imágenes", "隐藏图片", "Ocultar imagens", "Bilder ausblenden", "Nascondi immagini", "画像を隠す", "이미지 숨기기"]
        case .mailSearchPlaceholder: return ["Search mail…", "Поиск по почте…", "Rechercher…", "Buscar…", "搜索邮件…", "Pesquisar…", "Mail durchsuchen…", "Cerca…", "メールを検索…", "메일 검색…"]
        case .mailNoResults: return ["nothing found", "ничего не найдено", "aucun résultat", "sin resultados", "未找到", "nada encontrado", "nichts gefunden", "nessun risultato", "見つかりません", "결과 없음"]
        case .mailArchive: return ["Archive", "В архив", "Archiver", "Archivar", "归档", "Arquivar", "Archivieren", "Archivia", "アーカイブ", "보관"]
        case .mailRefresh: return ["Refresh", "Обновить", "Actualiser", "Actualizar", "刷新", "Atualizar", "Aktualisieren", "Aggiorna", "更新", "새로 고침"]
        case .mailSearch: return ["Search", "Поиск", "Rechercher", "Buscar", "搜索", "Pesquisar", "Suchen", "Cerca", "検索", "검색"]
        case .mailToField: return ["To", "Кому", "À", "Para", "收件人", "Para", "An", "A", "宛先", "받는 사람"]
        case .mailSubjectField: return ["Subject", "Тема", "Objet", "Asunto", "主题", "Assunto", "Betreff", "Oggetto", "件名", "제목"]
        case .mailNewMessage: return ["New message", "Новое письмо", "Nouveau message", "Mensaje nuevo", "新邮件", "Nova mensagem", "Neue Nachricht", "Nuovo messaggio", "新規メッセージ", "새 메시지"]
        case .mailBodyPlaceholder: return ["Message…", "Сообщение…", "Message…", "Mensaje…", "正文…", "Mensagem…", "Nachricht…", "Messaggio…", "本文…", "메시지…"]
        case .mailboxPrimary: return ["Primary", "Основные", "Principale", "Principal", "主要", "Principal", "Allgemein", "Principale", "メイン", "기본"]
        case .mailboxStarred: return ["Starred", "Помеченные", "Suivis", "Destacados", "已加星标", "Com estrela", "Markiert", "Speciali", "スター付き", "별표"]
        case .mailboxImportant: return ["Important", "Важные", "Importants", "Importantes", "重要", "Importantes", "Wichtig", "Importanti", "重要", "중요"]
        case .mailboxSent: return ["Sent", "Отправленные", "Envoyés", "Enviados", "已发送", "Enviados", "Gesendet", "Inviati", "送信済み", "보낸편지함"]
        case .mailboxSpam: return ["Spam", "Спам", "Spam", "Spam", "垃圾邮件", "Spam", "Spam", "Spam", "迷惑メール", "스팸"]
        case .asstSetupTitle: return ["no provider", "нет провайдера", "aucun fournisseur", "sin proveedor", "未设置服务商", "sem fornecedor", "kein Anbieter", "nessun provider", "プロバイダなし", "제공자 없음"]
        case .asstSetupSub: return ["Connect any OpenAI-compatible endpoint — OpenAI, OpenRouter or a local Ollama", "Подключите любой OpenAI-совместимый эндпоинт — OpenAI, OpenRouter или локальную Ollama", "Connectez tout point d'accès compatible OpenAI — OpenAI, OpenRouter ou Ollama local", "Conecta cualquier endpoint compatible con OpenAI — OpenAI, OpenRouter u Ollama local", "连接任意兼容 OpenAI 的接口 — OpenAI、OpenRouter 或本地 Ollama", "Ligue qualquer endpoint compatível com OpenAI — OpenAI, OpenRouter ou Ollama local", "Beliebigen OpenAI-kompatiblen Endpunkt verbinden — OpenAI, OpenRouter oder lokales Ollama", "Collega qualsiasi endpoint compatibile OpenAI — OpenAI, OpenRouter o Ollama locale", "OpenAI互換のエンドポイントを接続 — OpenAI、OpenRouter、ローカルのOllama", "OpenAI 호환 엔드포인트 연결 — OpenAI, OpenRouter 또는 로컬 Ollama"]
        case .asstHint: return ["Set a timer, check today's events, capture a note — just ask", "Поставить таймер, узнать события на сегодня, записать заметку — просто спросите", "Minuteur, agenda du jour, note rapide — demandez simplement", "Pon un temporizador, revisa la agenda, guarda una nota — solo pide", "设定计时器、查看今日日程、记笔记 — 直接开口", "Temporizador, agenda de hoje, nota rápida — é só pedir", "Timer stellen, heutige Termine, Notiz erfassen — einfach fragen", "Timer, eventi di oggi, una nota al volo — basta chiedere", "タイマー設定、今日の予定、メモ — 何でも聞いて", "타이머 설정, 오늘 일정, 메모 — 그냥 물어보세요"]
        case .asstPlaceholder: return ["Ask anything…", "Спросите что-нибудь…", "Demandez…", "Pregunta lo que sea…", "随便问…", "Pergunte algo…", "Frag etwas…", "Chiedi pure…", "何でも聞いて…", "무엇이든 물어보세요…"]
        case .asstThinking: return ["Thinking…", "Думаю…", "Réflexion…", "Pensando…", "思考中…", "A pensar…", "Denke nach…", "Sto pensando…", "考え中…", "생각 중…"]
        case .asstBaseURL: return ["Base URL", "Base URL", "URL de base", "URL base", "基础 URL", "URL base", "Basis-URL", "URL di base", "ベースURL", "기본 URL"]
        case .asstModel: return ["Model", "Модель", "Modèle", "Modelo", "模型", "Modelo", "Modell", "Modello", "モデル", "모델"]
        case .asstKey: return ["API key", "API-ключ", "Clé API", "Clave API", "API 密钥", "Chave de API", "API-Schlüssel", "Chiave API", "APIキー", "API 키"]
        case .asstProviderClaude: return ["Uses the local claude CLI — covered by your Claude subscription", "Через локальный claude CLI — расходует вашу подписку Claude", "Via le CLI claude local — inclus dans votre abonnement Claude", "Usa el CLI claude local — incluido en tu suscripción de Claude", "使用本地 claude CLI — 计入你的 Claude 订阅", "Usa o CLI claude local — incluído na sua subscrição Claude", "Nutzt die lokale claude-CLI — über dein Claude-Abo", "Usa la CLI claude locale — inclusa nel tuo abbonamento Claude", "ローカルの claude CLI を使用 — Claudeサブスクリプションに含まれます", "로컬 claude CLI 사용 — Claude 구독에 포함"]
        case .asstProviderCodex: return ["Uses the local codex CLI — covered by your ChatGPT subscription", "Через локальный codex CLI — расходует вашу подписку ChatGPT", "Via le CLI codex local — inclus dans votre abonnement ChatGPT", "Usa el CLI codex local — incluido en tu suscripción de ChatGPT", "使用本地 codex CLI — 计入你的 ChatGPT 订阅", "Usa o CLI codex local — incluído na sua subscrição ChatGPT", "Nutzt die lokale codex-CLI — über dein ChatGPT-Abo", "Usa la CLI codex locale — inclusa nel tuo abbonamento ChatGPT", "ローカルの codex CLI を使用 — ChatGPTサブスクリプションに含まれます", "로컬 codex CLI 사용 — ChatGPT 구독에 포함"]
        case .asstProviderAPI: return ["Any OpenAI-compatible endpoint, billed per token", "Любой OpenAI-совместимый эндпоинт, оплата за токены", "Tout point d'accès compatible OpenAI, facturé au token", "Cualquier endpoint compatible con OpenAI, pago por tokens", "任意兼容 OpenAI 的接口，按 token 计费", "Qualquer endpoint compatível com OpenAI, pago por token", "Beliebiger OpenAI-kompatibler Endpunkt, Abrechnung pro Token", "Qualsiasi endpoint compatibile OpenAI, a consumo", "OpenAI互換エンドポイント、トークン課金", "OpenAI 호환 엔드포인트, 토큰 과금"]
        case .asstVoiceHint: return ["Voice mode — tap the mic, speak, and the answer is read back", "Голосовой режим — нажмите микрофон, говорите, ответ прозвучит вслух", "Mode vocal — appuyez sur le micro, parlez, la réponse est lue", "Modo voz — toca el micro, habla y la respuesta se lee en voz alta", "语音模式 — 点击麦克风说话，答案会朗读出来", "Modo de voz — toque no micro, fale e a resposta é lida", "Sprachmodus — Mikro antippen, sprechen, die Antwort wird vorgelesen", "Modalità vocale — tocca il microfono, parla, la risposta viene letta", "音声モード — マイクをタップして話すと、回答が読み上げられます", "음성 모드 — 마이크를 누르고 말하면 답변을 읽어 줍니다"]
        case .asstEmptyTitle: return ["no messages", "нет сообщений", "aucun message", "sin mensajes", "没有消息", "sem mensagens", "keine Nachrichten", "nessun messaggio", "メッセージなし", "메시지 없음"]
        case .asstPreset: return ["Preset", "Пресет", "Préréglage", "Preajuste", "预设", "Predefinição", "Voreinstellung", "Preset", "プリセット", "프리셋"]
        case .asstModelOptional: return ["Optional — leave empty for the CLI's default", "Необязательно — пусто = модель по умолчанию в CLI", "Facultatif — vide pour le modèle par défaut du CLI", "Opcional — vacío para el modelo por defecto del CLI", "可选 — 留空则使用 CLI 默认模型", "Opcional — vazio para o modelo padrão do CLI", "Optional — leer für das Standardmodell der CLI", "Opzionale — vuoto per il modello predefinito della CLI", "任意 — 空欄でCLIの既定モデル", "선택 사항 — 비우면 CLI 기본 모델"]
        case .asstCLIMissing: return ["%@ CLI not found. Install it and sign in, then press Check.", "%@ CLI не найден. Установите его, войдите в аккаунт и нажмите «Проверить».", "CLI %@ introuvable. Installez-le, connectez-vous, puis cliquez sur Vérifier.", "No se encontró el CLI %@. Instálalo, inicia sesión y pulsa Comprobar.", "未找到 %@ CLI。请安装并登录后点击检查。", "CLI %@ não encontrado. Instale, inicie sessão e prima Verificar.", "%@-CLI nicht gefunden. Installieren, anmelden, dann auf Prüfen klicken.", "CLI %@ non trovata. Installala, accedi e premi Verifica.", "%@ CLI が見つかりません。インストールしてサインイン後、チェックを押してください。", "%@ CLI를 찾을 수 없습니다. 설치 후 로그인하고 확인을 누르세요."]
        case .asstPlaybookConfirm: return ["Run playbook “%@”?", "Запустить плейбук «%@»?", "Lancer le playbook « %@ » ?", "¿Iniciar el playbook «%@»?", "运行行动手册“%@”？", "Iniciar o playbook “%@”?", "Playbook „%@“ starten?", "Avviare il playbook “%@”?", "プレイブック「%@」を実行しますか？", "플레이북 “%@”을(를) 실행할까요?"]
        case .asstPlaybookRun: return ["Run", "Запустить", "Lancer", "Iniciar", "运行", "Iniciar", "Starten", "Avvia", "実行", "실행"]
        case .asstKeyHint: return ["Stored in the Keychain; leave empty for a local Ollama", "Хранится в Keychain; для локальной Ollama оставьте пустым", "Stockée dans le trousseau ; vide pour Ollama local", "Se guarda en el llavero; vacía para Ollama local", "保存在钥匙串；本地 Ollama 可留空", "Guardada nas Chaves; vazia para Ollama local", "Im Schlüsselbund gespeichert; für lokales Ollama leer lassen", "Salvata nel portachiavi; vuota per Ollama locale", "キーチェーンに保存。ローカルのOllamaは空欄でOK", "키체인에 저장. 로컬 Ollama는 비워 두세요"]
        case .mailProvider: return ["Provider", "Провайдер", "Fournisseur", "Proveedor", "服务商", "Fornecedor", "Anbieter", "Provider", "プロバイダ", "제공업체"]
        case .mailAddress: return ["Email address", "Адрес почты", "Adresse e-mail", "Dirección de correo", "邮箱地址", "Endereço de e-mail", "E-Mail-Adresse", "Indirizzo e-mail", "メールアドレス", "이메일 주소"]
        case .mailPassword: return ["App password", "Пароль приложения", "Mot de passe d'application", "Contraseña de aplicación", "应用专用密码", "Palavra-passe de aplicação", "App-Passwort", "Password per le app", "アプリパスワード", "앱 암호"]
        case .mailPasswordHint: return ["Issued by your provider for mail apps (2FA required) — not your main password", "Выдаётся провайдером для почтовых программ (нужна 2FA) — не основной пароль", "Fourni par votre fournisseur pour les apps mail (2FA requise) — pas votre mot de passe principal", "Lo emite tu proveedor para apps de correo (requiere 2FA) — no es tu contraseña principal", "由服务商为邮件应用签发（需要两步验证）— 不是主密码", "Emitida pelo fornecedor para apps de e-mail (requer 2FA) — não é a palavra-passe principal", "Vom Anbieter für Mail-Apps ausgestellt (2FA nötig) — nicht das Hauptpasswort", "Rilasciata dal provider per le app di posta (serve 2FA) — non la password principale", "プロバイダがメールアプリ用に発行（2FA必須）— メインのパスワードではありません", "메일 앱용으로 제공업체가 발급 (2FA 필요) — 기본 비밀번호가 아님"]
        case .mailOutlookWarning: return ["Microsoft requires OAuth for personal accounts — a password will likely fail", "Microsoft требует OAuth для личных аккаунтов — пароль скорее всего не сработает", "Microsoft exige OAuth pour les comptes personnels — le mot de passe échouera probablement", "Microsoft exige OAuth para cuentas personales — la contraseña probablemente falle", "Microsoft 个人账户需要 OAuth — 密码很可能无法使用", "A Microsoft exige OAuth para contas pessoais — a palavra-passe deverá falhar", "Microsoft verlangt OAuth für Privatkonten — Passwort schlägt vermutlich fehl", "Microsoft richiede OAuth per gli account personali — la password probabilmente fallirà", "Microsoftの個人アカウントはOAuth必須 — パスワードは失敗する可能性大", "Microsoft 개인 계정은 OAuth 필요 — 비밀번호는 실패할 가능성 높음"]
        case .mailImapHost: return ["IMAP server", "IMAP-сервер", "Serveur IMAP", "Servidor IMAP", "IMAP 服务器", "Servidor IMAP", "IMAP-Server", "Server IMAP", "IMAPサーバ", "IMAP 서버"]
        case .mailSmtpHost: return ["SMTP server", "SMTP-сервер", "Serveur SMTP", "Servidor SMTP", "SMTP 服务器", "Servidor SMTP", "SMTP-Server", "Server SMTP", "SMTPサーバ", "SMTP 서버"]
        case .mailCheck: return ["Check", "Проверить", "Vérifier", "Comprobar", "检查", "Verificar", "Prüfen", "Verifica", "確認", "확인"]
        case .mailChecking: return ["Checking…", "Проверяю…", "Vérification…", "Comprobando…", "检查中…", "A verificar…", "Prüfe…", "Verifica…", "確認中…", "확인 중…"]
        case .mailCheckOk: return ["Connected", "Подключено", "Connecté", "Conectado", "已连接", "Ligado", "Verbunden", "Connesso", "接続済み", "연결됨"]
        case .mailRemove: return ["Remove account", "Удалить аккаунт", "Supprimer le compte", "Eliminar cuenta", "移除账户", "Remover conta", "Konto entfernen", "Rimuovi account", "アカウントを削除", "계정 제거"]

        case .playNew: return ["+ new", "+ новый", "+ nouveau", "+ nuevo", "+ 新建", "+ novo", "+ neu", "+ nuovo", "+ 新規", "+ 새로 만들기"]
        case .playEmpty: return ["empty", "пустой", "vide", "vacío", "空", "vazio", "leer", "vuoto", "空", "비어 있음"]
        case .playApps: return ["%d apps", "%d прил.", "%d apps", "%d apps", "%d 个应用", "%d apps", "%d Apps", "%d app", "%d個のApp", "앱 %d개"]
        case .playCloseRest: return ["closes others", "закрывает прочие", "ferme le reste", "cierra el resto", "关闭其他", "fecha o resto", "schließt andere", "chiude il resto", "他を閉じる", "다른 앱 닫기"]
        case .playFocus: return ["focus", "фокус", "focus", "enfoque", "专注", "foco", "Fokus", "focus", "集中", "집중"]
        case .playDone: return ["done", "выполнен", "terminé", "hecho", "已完成", "concluído", "fertig", "fatto", "完了", "완료"]
        case .playClosed: return ["closed %d", "закрыто %d", "fermé %d", "cerradas %d", "已关闭 %d", "fechadas %d", "geschlossen %d", "chiuse %d", "終了 %d", "닫음 %d"]
        case .playOpened: return ["opened %d", "открыто %d", "ouvert %d", "abiertas %d", "已打开 %d", "abertas %d", "geöffnet %d", "aperte %d", "起動 %d", "열림 %d"]
        case .playErrors: return ["errors %d", "ошибок %d", "erreurs %d", "errores %d", "错误 %d", "erros %d", "Fehler %d", "errori %d", "エラー %d", "오류 %d"]
        case .playStepOpenApps: return ["Open apps", "Открыть приложения", "Ouvrir des apps", "Abrir apps", "打开应用", "Abrir apps", "Apps öffnen", "Apri app", "Appを開く", "앱 열기"]
        case .playStepCloseOthers: return ["Close other apps", "Закрыть остальные приложения", "Fermer les autres apps", "Cerrar las demás apps", "关闭其他应用", "Fechar as outras apps", "Andere Apps schließen", "Chiudi le altre app", "他のAppを閉じる", "다른 앱 닫기"]
        case .playStepShortcut: return ["Run shortcut", "Запустить быструю команду", "Lancer un raccourci", "Ejecutar atajo", "运行快捷指令", "Executar atalho", "Kurzbefehl ausführen", "Esegui comando rapido", "ショートカットを実行", "단축어 실행"]
        case .playStepFocus: return ["Set Focus (via shortcut)", "Включить фокус (через команду)", "Définir Concentration (via raccourci)", "Activar Modo de concentración (vía atajo)", "设置专注模式（通过快捷指令）", "Definir Foco (via atalho)", "Fokus setzen (per Kurzbefehl)", "Imposta Full Immersion (via comando)", "集中モードを設定（ショートカット経由）", "집중 모드 설정 (단축어로)"]
        case .playStepTimer: return ["Start timer", "Запустить таймер", "Lancer le minuteur", "Iniciar temporizador", "启动计时器", "Iniciar temporizador", "Timer starten", "Avvia timer", "タイマーを開始", "타이머 시작"]
        case .playStepURLs: return ["Open links", "Открыть ссылки", "Ouvrir des liens", "Abrir enlaces", "打开链接", "Abrir links", "Links öffnen", "Apri link", "リンクを開く", "링크 열기"]
        case .playAddStep: return ["Add step", "Добавить шаг", "Ajouter une étape", "Añadir paso", "添加步骤", "Adicionar passo", "Schritt hinzufügen", "Aggiungi passaggio", "ステップを追加", "단계 추가"]
        case .playLayout: return ["Window layout", "Расположение окон", "Disposition des fenêtres", "Disposición de ventanas", "窗口布局", "Disposição das janelas", "Fensteranordnung", "Disposizione finestre", "ウインドウの配置", "창 배치"]
        case .playGrantAccess: return ["Grant access", "Дать доступ", "Autoriser l'accès", "Conceder acceso", "授予权限", "Conceder acesso", "Zugriff erlauben", "Concedi accesso", "アクセスを許可", "접근 허용"]
        case .playLayoutHint: return ["Arranging windows needs Accessibility access", "Для расстановки окон нужен доступ к Универсальному доступу", "Disposer les fenêtres requiert l'accès Accessibilité", "Ordenar ventanas requiere acceso de Accesibilidad", "排列窗口需要辅助功能权限", "Organizar janelas requer acesso de Acessibilidade", "Fensteranordnung braucht Bedienungshilfen-Zugriff", "Disporre le finestre richiede l'accesso Accessibilità", "ウインドウの配置にはアクセシビリティの許可が必要です", "창 배치에는 손쉬운 사용 접근 권한이 필요합니다"]
        case .playLayoutNone: return ["Leave as is", "Оставить как есть", "Laisser tel quel", "Dejar como está", "保持原样", "Deixar como está", "So lassen", "Lascia com'è", "そのまま", "그대로 두기"]
        case .playLayoutLeftRight: return ["Side by side", "Рядом", "Côte à côte", "Lado a lado", "并排", "Lado a lado", "Nebeneinander", "Affiancate", "左右に並べる", "나란히"]
        case .playLayoutThirds: return ["Three columns", "Три колонки", "Trois colonnes", "Tres columnas", "三列", "Três colunas", "Drei Spalten", "Tre colonne", "3列", "세 열"]
        case .playLayoutGrid2x2: return ["2 × 2 grid", "Сетка 2 × 2", "Grille 2 × 2", "Cuadrícula 2 × 2", "2 × 2 网格", "Grelha 2 × 2", "2 × 2-Raster", "Griglia 2 × 2", "2 × 2 グリッド", "2 × 2 격자"]
        case .playLayoutMainSide: return ["Main + sidebar", "Главное + боковое", "Principale + latérale", "Principal + lateral", "主窗口 + 侧栏", "Principal + lateral", "Haupt + Seitenleiste", "Principale + laterale", "メイン + サイド", "메인 + 사이드"]
        case .playLayoutFullscreen: return ["Fill the screen", "Во весь экран", "Remplir l'écran", "Llenar la pantalla", "填满屏幕", "Preencher o ecrã", "Bildschirm füllen", "Riempi lo schermo", "画面いっぱい", "화면 채우기"]
        case .playName: return ["Name", "Название", "Nom", "Nombre", "名称", "Nome", "Name", "Nome", "名前", "이름"]
        case .playIcon: return ["Icon", "Иконка", "Icône", "Icono", "图标", "Ícone", "Symbol", "Icona", "アイコン", "아이콘"]
        case .playSteps: return ["Steps", "Шаги", "Étapes", "Pasos", "步骤", "Passos", "Schritte", "Passaggi", "ステップ", "단계"]
        case .playNoSteps: return ["No steps yet — add the first one below", "Шагов пока нет — добавьте первый ниже", "Aucune étape — ajoutez la première ci-dessous", "Sin pasos aún — añade el primero abajo", "还没有步骤 — 在下方添加第一个", "Ainda sem passos — adicione o primeiro abaixo", "Noch keine Schritte — unten den ersten hinzufügen", "Nessun passaggio — aggiungi il primo qui sotto", "まだステップがありません — 下から追加", "아직 단계가 없습니다 — 아래에서 추가하세요"]
        case .playSearchApps: return ["Search all applications…", "Поиск по всем приложениям…", "Rechercher dans toutes les apps…", "Buscar en todas las apps…", "搜索所有应用…", "Procurar em todas as apps…", "Alle Apps durchsuchen…", "Cerca tra tutte le app…", "すべてのAppを検索…", "모든 앱 검색…"]
        case .playAddBundleID: return ["Add by bundle ID (e.g. com.figma.Desktop)", "Добавить по bundle ID (например, com.figma.Desktop)", "Ajouter par bundle ID (ex. com.figma.Desktop)", "Añadir por bundle ID (p. ej. com.figma.Desktop)", "按 bundle ID 添加（如 com.figma.Desktop）", "Adicionar por bundle ID (ex. com.figma.Desktop)", "Per Bundle-ID hinzufügen (z. B. com.figma.Desktop)", "Aggiungi per bundle ID (es. com.figma.Desktop)", "バンドルIDで追加（例: com.figma.Desktop）", "번들 ID로 추가 (예: com.figma.Desktop)"]
        case .playSelectedCount: return ["%d selected", "выбрано %d", "%d sélectionnée(s)", "%d seleccionadas", "已选 %d", "%d selecionadas", "%d ausgewählt", "%d selezionate", "%d個を選択", "%d개 선택됨"]
        case .playChooseShortcut: return ["Choose a shortcut…", "Выберите команду…", "Choisir un raccourci…", "Elegir un atajo…", "选择快捷指令…", "Escolher um atalho…", "Kurzbefehl wählen…", "Scegli un comando…", "ショートカットを選択…", "단축어 선택…"]
        case .playShortcutName: return ["Or type a shortcut name", "Или введите название команды", "Ou saisir un nom de raccourci", "O escribe el nombre del atajo", "或输入快捷指令名称", "Ou escreva o nome do atalho", "Oder Kurzbefehl-Namen eingeben", "O digita il nome del comando", "またはショートカット名を入力", "또는 단축어 이름 입력"]
        case .playMinutes: return ["Minutes", "Минуты", "Minutes", "Minutos", "分钟", "Minutos", "Minuten", "Minuti", "分", "분"]
        case .playURLsHint: return ["One link per line", "По одной ссылке на строку", "Un lien par ligne", "Un enlace por línea", "每行一个链接", "Um link por linha", "Ein Link pro Zeile", "Un link per riga", "1行に1リンク", "한 줄에 링크 하나"]
        case .playLinks: return ["%d links", "%d ссыл.", "%d liens", "%d enlaces", "%d 个链接", "%d links", "%d Links", "%d link", "%d件のリンク", "링크 %d개"]
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
        case .setHotkeys: return ["Hotkeys", "Хоткеи", "Raccourcis", "Atajos", "快捷键", "Atalhos", "Kurzbefehle", "Scorciatoie", "ショートカット", "단축키"]
        case .setBehavior: return ["Behavior", "Поведение", "Comportement", "Comportamiento", "行为", "Comportamento", "Verhalten", "Comportamento", "動作", "동작"]
        case .setLaunch: return ["Launch at login", "Запускать при входе", "Lancer à l'ouverture de session", "Abrir al iniciar sesión", "登录时启动", "Abrir ao iniciar sessão", "Beim Anmelden starten", "Avvia all'accesso", "ログイン時に起動", "로그인 시 실행"]
        case .setLaunchSub: return ["Menu-bar agent, no Dock icon", "Агент меню-бара, без иконки в доке", "Agent de barre de menus, sans icône Dock", "Agente de barra de menús, sin icono en el Dock", "菜单栏代理，无 Dock 图标", "Agente da barra de menus, sem ícone na Dock", "Menüleisten-Agent, ohne Dock-Symbol", "Agente della barra dei menu, senza icona nel Dock", "メニューバー常駐、Dockアイコンなし", "메뉴 막대 에이전트, Dock 아이콘 없음"]
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
        case .setExpandIsland: return ["Open settings on the notch", "Открыть настройки на вырезе", "Ouvrir les réglages sur le notch", "Abrir ajustes en el notch", "在刘海处打开设置", "Abrir ajustes no notch", "Einstellungen am Notch öffnen", "Apri le impostazioni sul notch", "ノッチで設定を開く", "노치에서 설정 열기"]
        case .setExpandIslandSub: return ["Click the notch; click outside or ✕ to close", "Клик по вырезу; закрыть — клик снаружи или ✕", "Cliquez sur le notch ; cliquez à côté ou ✕ pour fermer", "Haz clic en el notch; clic fuera o ✕ para cerrar", "点击刘海；点击外部或 ✕ 关闭", "Clique no notch; clique fora ou ✕ para fechar", "Notch anklicken; außerhalb klicken oder ✕ zum Schließen", "Fai clic sul notch; clic fuori o ✕ per chiudere", "ノッチをクリック。外側クリックか ✕ で閉じる", "노치를 클릭; 바깥 클릭 또는 ✕로 닫기"]
        case .setOutsideClick: return ["Close panel on outside click", "Закрывать панель по клику вне виджета", "Fermer le panneau en cliquant à l'extérieur", "Cerrar el panel al hacer clic fuera", "点击外部时关闭面板", "Fechar o painel ao clicar fora", "Panel bei Klick außerhalb schließen", "Chiudi il pannello cliccando fuori", "外側をクリックでパネルを閉じる", "밖을 클릭하면 패널 닫기"]
        case .setOutsideClickSub: return ["Off = the panel stays pinned. ⌃⌥P toggles this anywhere.", "Выкл = панель закреплена. ⌃⌥P переключает откуда угодно.", "Désactivé = panneau épinglé. ⌃⌥P bascule partout.", "Desactivado = panel fijado. ⌃⌥P lo alterna en cualquier lugar.", "关闭 = 面板固定。⌃⌥P 随处切换。", "Desligado = painel fixado. ⌃⌥P alterna em qualquer lugar.", "Aus = Panel bleibt angeheftet. ⌃⌥P schaltet überall um.", "Off = pannello fissato. ⌃⌥P lo commuta ovunque.", "オフ = パネルを固定。⌃⌥P でどこでも切替。", "끄면 패널 고정. ⌃⌥P로 어디서든 전환."]
        case .setHideWidget: return ["Hide / show the widget", "Скрыть / показать виджет", "Masquer / afficher le widget", "Ocultar / mostrar el widget", "隐藏 / 显示小组件", "Ocultar / mostrar o widget", "Widget aus- / einblenden", "Nascondi / mostra il widget", "ウィジェットを隠す / 表示", "위젯 숨기기 / 표시"]
        case .setHideWidgetSub: return ["Collapses the strip into a small square when it is in the way", "Сворачивает рейку в маленький квадрат, когда она мешает", "Réduit la barre en petit carré quand elle gêne", "Colapsa la barra en un cuadrito cuando estorba", "碍事时把工具条折叠成小方块", "Recolhe a barra num quadradinho quando atrapalha", "Faltet die Leiste zu einem kleinen Quadrat, wenn sie stört", "Riduce la barra a un quadratino quando è d'intralcio", "邪魔なときにストリップを小さな四角に畳みます", "방해될 때 스트립을 작은 사각형으로 접기"]
        case .setModeToggle: return ["Settings island", "Остров настроек", "Îlot des réglages", "Isla de ajustes", "设置灵动岛", "Ilha de ajustes", "Einstellungs-Insel", "Isola delle impostazioni", "設定アイランド", "설정 아일랜드"]
        case .setModeToggleSub: return ["Opens or closes the settings on the notch", "Открывает или закрывает настройки на вырезе", "Ouvre ou ferme les réglages sur le notch", "Abre o cierra los ajustes en el notch", "打开或关闭刘海处的设置", "Abre ou fecha os ajustes no notch", "Öffnet oder schließt die Einstellungen am Notch", "Apre o chiude le impostazioni sul notch", "ノッチの設定を開閉します", "노치의 설정을 열거나 닫습니다"]
        case .setPinPanel: return ["Pin the panel", "Закрепить панель", "Épingler le panneau", "Fijar el panel", "固定面板", "Fixar o painel", "Panel anheften", "Fissa il pannello", "パネルを固定", "패널 고정"]
        case .setPinPanelSub: return ["Toggles \"close on outside click\"", "Переключает «закрывать по клику вне виджета»", "Bascule « fermer au clic extérieur »", "Alterna «cerrar al hacer clic fuera»", "切换「点击外部关闭」", "Alterna «fechar ao clicar fora»", "Schaltet \"bei Klick außerhalb schließen\" um", "Commuta «chiudi al clic esterno»", "「外側クリックで閉じる」を切替", "\"밖 클릭 시 닫기\" 전환"]
        case .setDemoSection: return ["Demo", "Демо", "Démo", "Demo", "演示", "Demo", "Demo", "Demo", "デモ", "데모"]
        case .setDemo: return ["Demo mode", "Демо-режим", "Mode démo", "Modo demo", "演示模式", "Modo demo", "Demo-Modus", "Modalità demo", "デモモード", "데모 모드"]
        case .setDemoSub: return ["Sample data in every module for screenshots and videos. Nothing is saved; off again on restart.", "Пример данных во всех модулях для скриншотов и видео. Ничего не сохраняется; после перезапуска выключен.", "Données d'exemple dans chaque module pour captures et vidéos. Rien n'est enregistré ; désactivé au redémarrage.", "Datos de ejemplo en cada módulo para capturas y vídeos. No se guarda nada; se apaga al reiniciar.", "每个模块显示示例数据，用于截图和视频。不保存任何内容；重启后关闭。", "Dados de exemplo em cada módulo para capturas e vídeos. Nada é guardado; desliga ao reiniciar.", "Beispieldaten in jedem Modul für Screenshots und Videos. Nichts wird gespeichert; nach Neustart wieder aus.", "Dati di esempio in ogni modulo per screenshot e video. Nulla viene salvato; disattivo al riavvio.", "スクリーンショットや動画用にすべてのモジュールへサンプルデータを表示。何も保存されず、再起動でオフ。", "스크린샷과 영상용으로 모든 모듈에 샘플 데이터를 표시. 아무것도 저장되지 않으며 재시작 시 꺼짐."]
        case .setDemoEvents: return ["Island events", "События острова", "Événements de l'îlot", "Eventos de la isla", "灵动岛事件", "Eventos da ilha", "Insel-Ereignisse", "Eventi dell'isola", "アイランドのイベント", "아일랜드 이벤트"]
        case .setDemoEventsSub: return ["Closes the settings and flashes a sample event on the notch", "Закрывает настройки и показывает пример события на вырезе", "Ferme les réglages et affiche un événement d'exemple sur le notch", "Cierra los ajustes y muestra un evento de ejemplo en el notch", "关闭设置并在刘海处闪现示例事件", "Fecha os ajustes e mostra um evento de exemplo no notch", "Schließt die Einstellungen und zeigt ein Beispiel-Ereignis am Notch", "Chiude le impostazioni e mostra un evento di esempio sul notch", "設定を閉じてノッチにサンプルイベントを表示", "설정을 닫고 노치에 샘플 이벤트를 표시"]
        case .obTour: return ["Welcome tour", "Знакомство", "Visite guidée", "Recorrido", "新手导览", "Tour guiado", "Willkommenstour", "Tour guidato", "ようこそツアー", "둘러보기"]
        case .obTourSub: return ["A one-minute look at the main modules", "Минутный обзор главных модулей", "Un aperçu d'une minute des modules principaux", "Un minuto por los módulos principales", "一分钟了解主要模块", "Um minuto pelos módulos principais", "Die wichtigsten Module in einer Minute", "Un minuto tra i moduli principali", "主なモジュールを1分で紹介", "주요 모듈을 1분 만에 살펴보기"]
        case .obShow: return ["Show", "Показать", "Afficher", "Mostrar", "显示", "Mostrar", "Zeigen", "Mostra", "表示", "보기"]
        case .obShowAtLaunch: return ["Show at launch", "Показывать при запуске", "Afficher au lancement", "Mostrar al iniciar", "启动时显示", "Mostrar ao iniciar", "Beim Start zeigen", "Mostra all'avvio", "起動時に表示", "시작할 때 표시"]
        case .obShowAtLaunchSub: return ["The tour opens every time the app starts", "Знакомство открывается при каждом запуске", "La visite s'ouvre à chaque lancement", "El recorrido se abre en cada inicio", "每次启动应用时打开导览", "O tour abre sempre que a app inicia", "Die Tour öffnet sich bei jedem Start", "Il tour si apre a ogni avvio", "アプリを起動するたびにツアーを開きます", "앱을 시작할 때마다 둘러보기가 열립니다"]
        case .obNext: return ["Next", "Дальше", "Suivant", "Siguiente", "下一步", "Seguinte", "Weiter", "Avanti", "次へ", "다음"]
        case .obBack: return ["Back", "Назад", "Retour", "Atrás", "上一步", "Voltar", "Zurück", "Indietro", "戻る", "이전"]
        case .obStart: return ["Get started", "Начать", "Commencer", "Empezar", "开始使用", "Começar", "Los geht's", "Inizia", "はじめる", "시작하기"]
        case .obBackToTour: return ["Back to tour", "К знакомству", "Retour à la visite", "Volver al recorrido", "返回导览", "Voltar ao tour", "Zurück zur Tour", "Torna al tour", "ツアーに戻る", "둘러보기로 돌아가기"]
        case .obConnect: return ["Connect", "Подключить", "Connecter", "Conectar", "连接", "Ligar", "Verbinden", "Collega", "接続", "연결"]
        case .obAllowAccess: return ["Allow access", "Разрешить доступ", "Autoriser l'accès", "Permitir acceso", "允许访问", "Permitir acesso", "Zugriff erlauben", "Consenti accesso", "アクセスを許可", "접근 허용"]
        case .obAccessGranted: return ["Access granted", "Доступ есть", "Accès autorisé", "Acceso concedido", "已获得访问权限", "Acesso concedido", "Zugriff erlaubt", "Accesso consentito", "アクセス許可済み", "접근 허용됨"]
        case .obOpenPrivacy: return ["Open Privacy settings", "Открыть настройки приватности", "Ouvrir Confidentialité", "Abrir Privacidad", "打开隐私设置", "Abrir Privacidade", "Datenschutz öffnen", "Apri Privacy", "プライバシー設定を開く", "개인정보 보호 설정 열기"]
        case .obSaved: return ["saved", "сохранено", "enregistré", "guardado", "已保存", "guardado", "gespeichert", "salvato", "保存済み", "저장됨"]
        case .obWelcomeKicker: return ["Welcome", "Привет", "Bienvenue", "Bienvenido", "欢迎", "Bem-vindo", "Willkommen", "Benvenuto", "ようこそ", "환영합니다"]
        case .obReadyKicker: return ["Ready", "Готово", "Prêt", "Listo", "就绪", "Pronto", "Bereit", "Pronto", "準備完了", "준비 완료"]
        case .obCalendarTitle: return ["The day at a glance", "День как на ладони", "La journée en un coup d'œil", "El día de un vistazo", "一眼看清今天", "O dia num relance", "Der Tag auf einen Blick", "La giornata a colpo d'occhio", "一日をひと目で", "하루를 한눈에"]
        case .obMailTitle: return ["Mail without switching", "Почта без переключений", "Le courrier sans changer d'app", "Correo sin cambiar de app", "无需切换的邮件", "E-mail sem trocar de app", "Mail ohne App-Wechsel", "Posta senza cambiare app", "切り替えなしでメール", "앱 전환 없는 메일"]
        case .obPlaybooksTitle: return ["One button to start", "Одна кнопка — и за работу", "Un bouton pour démarrer", "Un botón para empezar", "一键开工", "Um botão para começar", "Ein Knopf zum Loslegen", "Un pulsante per iniziare", "ボタンひとつで始める", "버튼 하나로 시작"]
        case .obNotesTitle: return ["Thoughts in plain files", "Мысли в простых файлах", "Des idées en fichiers simples", "Ideas en archivos simples", "想法存为普通文件", "Ideias em ficheiros simples", "Gedanken als einfache Dateien", "Idee in semplici file", "考えをシンプルなファイルに", "생각을 평범한 파일로"]
        case .obAssistantTitle: return ["Ask in plain words", "Спросите своими словами", "Demandez simplement", "Pregunta con tus palabras", "用自己的话提问", "Pergunte por palavras suas", "Frag einfach drauflos", "Chiedi a parole tue", "ふだんの言葉で聞く", "평소 말투로 물어보세요"]
        case .obFinishTitle: return ["Make it yours", "Настройте под себя", "À vous de jouer", "Hazlo tuyo", "按你的方式来", "Torne-o seu", "Mach es zu deinem", "Rendilo tuo", "自分好みに", "나에게 맞게"]
        case .obWelcomeBody: return ["One small widget for the whole day. It lives at the edge of the screen and opens right where you work. Here's a one-minute tour.", "Один небольшой виджет на весь день. Он живёт у края экрана и открывается там, где вы работаете. Вот короткое знакомство.", "Un petit widget pour toute la journée. Il vit au bord de l'écran et s'ouvre là où vous travaillez. Voici une visite d'une minute.", "Un pequeño widget para todo el día. Vive en el borde de la pantalla y se abre justo donde trabajas. Aquí tienes un recorrido de un minuto.", "一个小组件，陪你一整天。它停靠在屏幕边缘，在你工作的地方随手打开。下面用一分钟带你看看。", "Um pequeno widget para o dia todo. Vive na margem do ecrã e abre mesmo onde trabalha. Eis um tour de um minuto.", "Ein kleines Widget für den ganzen Tag. Es sitzt am Bildschirmrand und öffnet sich genau dort, wo du arbeitest. Hier ist eine Tour in einer Minute.", "Un piccolo widget per tutta la giornata. Vive sul bordo dello schermo e si apre proprio dove lavori. Ecco un tour di un minuto.", "一日じゅう使える小さなウィジェット。画面の端にいて、作業しているその場で開きます。1分で見ていきましょう。", "하루 종일 함께하는 작은 위젯. 화면 가장자리에 머물다가 작업하는 바로 그 자리에서 열립니다. 1분 만에 둘러보세요."]
        case .obCalendarBody: return ["The next meeting and how soon it starts, a join button when it's time, and a new event in a couple of clicks.", "Ближайшая встреча и сколько до неё осталось, кнопка входа в звонок и новое событие в пару кликов.", "La prochaine réunion et dans combien de temps elle commence, un bouton pour la rejoindre et un nouvel événement en deux clics.", "La próxima reunión y cuánto falta, un botón para unirte a tiempo y un evento nuevo en un par de clics.", "下一场会议还有多久开始、到点一键加入，新建日程只需点两下。", "A próxima reunião e quanto falta, um botão para entrar na hora e um novo evento em dois cliques.", "Das nächste Meeting und wann es beginnt, ein Beitreten-Knopf zur rechten Zeit und ein neuer Termin mit zwei Klicks.", "La prossima riunione e quanto manca, un pulsante per entrare al momento giusto e un nuovo evento in due clic.", "次の会議と開始までの時間、時間になったら参加ボタン、新しいイベントも数クリックで。", "다음 회의와 시작까지 남은 시간, 때가 되면 참여 버튼, 새 일정도 클릭 몇 번이면 됩니다."]
        case .obMailBody: return ["Read, reply and archive right in the widget. Any IMAP mailbox works.", "Читайте, отвечайте и убирайте в архив прямо в виджете. Подойдёт любой IMAP-ящик.", "Lisez, répondez et archivez directement dans le widget. N'importe quelle boîte IMAP convient.", "Lee, responde y archiva sin salir del widget. Funciona con cualquier buzón IMAP.", "直接在小组件里阅读、回复和归档。支持任何 IMAP 邮箱。", "Leia, responda e arquive diretamente no widget. Funciona com qualquer caixa IMAP.", "Lesen, antworten und archivieren direkt im Widget. Jedes IMAP-Postfach funktioniert.", "Leggi, rispondi e archivia direttamente nel widget. Va bene qualsiasi casella IMAP.", "ウィジェットの中で読んで、返信して、アーカイブ。IMAPメールならどれでも使えます。", "위젯 안에서 바로 읽고, 답장하고, 보관하세요. 어떤 IMAP 메일함이든 됩니다."]
        case .obPlaybooksBody: return ["A playbook opens your apps, lays out the windows, turns on Focus and starts a timer — all at once.", "Плейбук открывает нужные приложения, раскладывает окна, включает фокус и запускает таймер — разом.", "Un playbook ouvre vos apps, range les fenêtres, active la concentration et lance un minuteur — d'un coup.", "Un playbook abre tus apps, ordena las ventanas, activa el modo concentración y pone un temporizador, todo a la vez.", "一个行动手册就能打开应用、排好窗口、开启专注模式并启动计时器，一步到位。", "Um playbook abre as suas apps, organiza as janelas, ativa o foco e inicia um temporizador — tudo de uma vez.", "Ein Playbook öffnet deine Apps, ordnet die Fenster, schaltet den Fokus ein und startet einen Timer — alles auf einmal.", "Un playbook apre le tue app, dispone le finestre, attiva la concentrazione e avvia un timer, tutto insieme.", "プレイブックはAppを開き、ウインドウを並べ、集中モードをオンにしてタイマーを始めます。すべて一度に。", "플레이북 하나로 앱을 열고, 창을 배치하고, 집중 모드를 켜고, 타이머까지 한 번에 시작합니다."]
        case .obNotesBody: return ["Notes are Markdown files in a folder you pick — Obsidian opens them too. Type or dictate; everything saves as you go.", "Заметки — это Markdown-файлы в выбранной вами папке, их откроет и Obsidian. Пишите или диктуйте — всё сохраняется сразу.", "Les notes sont des fichiers Markdown dans le dossier de votre choix — Obsidian les ouvre aussi. Tapez ou dictez : tout s'enregistre au fil de l'eau.", "Las notas son archivos Markdown en la carpeta que elijas; Obsidian también las abre. Escribe o dicta: todo se guarda al momento.", "笔记就是你所选文件夹里的 Markdown 文件，Obsidian 也能打开。输入或口述，内容随写随存。", "As notas são ficheiros Markdown numa pasta à sua escolha — o Obsidian também as abre. Escreva ou dite; tudo é guardado na hora.", "Notizen sind Markdown-Dateien in einem Ordner deiner Wahl — auch Obsidian öffnet sie. Tippen oder diktieren; alles wird sofort gespeichert.", "Le note sono file Markdown in una cartella a tua scelta: le apre anche Obsidian. Scrivi o detta, tutto si salva subito.", "メモは選んだフォルダに置かれるMarkdownファイル。Obsidianでも開けます。入力でも音声でも、書いたそばから保存されます。", "메모는 직접 고른 폴더의 Markdown 파일이라 Obsidian에서도 열립니다. 타이핑이든 받아쓰기든 바로바로 저장돼요."]
        case .obAssistantBody: return ["The assistant works with your calendar, mail and notes, runs playbooks and can answer out loud. Claude, Codex or any OpenAI-compatible API.", "Ассистент работает с календарём, почтой и заметками, запускает плейбуки и умеет отвечать голосом. Claude, Codex или любой OpenAI-совместимый API.", "L'assistant travaille avec votre calendrier, vos mails et vos notes, lance des playbooks et peut répondre à voix haute. Claude, Codex ou toute API compatible OpenAI.", "El asistente trabaja con tu calendario, correo y notas, ejecuta playbooks y puede responder en voz alta. Claude, Codex o cualquier API compatible con OpenAI.", "助手能处理你的日历、邮件和笔记，运行行动手册，还能语音回答。支持 Claude、Codex 或任何兼容 OpenAI 的 API。", "O assistente trabalha com o calendário, o e-mail e as notas, executa playbooks e pode responder em voz alta. Claude, Codex ou qualquer API compatível com OpenAI.", "Der Assistent arbeitet mit Kalender, Mail und Notizen, startet Playbooks und kann laut antworten. Claude, Codex oder jede OpenAI-kompatible API.", "L'assistente lavora con calendario, posta e note, avvia i playbook e può rispondere a voce. Claude, Codex o qualsiasi API compatibile con OpenAI.", "アシスタントはカレンダー、メール、メモを扱い、プレイブックを実行し、声で答えることもできます。Claude、Codex、またはOpenAI互換のAPIで動きます。", "어시스턴트는 캘린더, 메일, 메모를 다루고 플레이북을 실행하며 음성으로 답할 수도 있습니다. Claude, Codex 또는 OpenAI 호환 API를 지원합니다."]
        case .obFinishBody: return ["Drag the widget by its dots to any edge of the screen. Settings and this tour are a right-click away.", "Перетащите виджет за точки к любому краю экрана. Настройки и это знакомство — по правому клику.", "Faites glisser le widget par ses points vers n'importe quel bord de l'écran. Réglages et visite sont à un clic droit.", "Arrastra el widget por sus puntos a cualquier borde de la pantalla. Los ajustes y este recorrido están a un clic derecho.", "按住圆点把小组件拖到屏幕任意边缘。设置和本导览随时右键即可打开。", "Arraste o widget pelos pontos para qualquer margem do ecrã. Os ajustes e este tour estão a um clique direito.", "Zieh das Widget an den Punkten an einen beliebigen Bildschirmrand. Einstellungen und diese Tour sind einen Rechtsklick entfernt.", "Trascina il widget dai puntini su qualsiasi bordo dello schermo. Impostazioni e questo tour sono a un clic destro.", "ドットをつかんでウィジェットを画面のどの端へでもドラッグ。設定とこのツアーは右クリックからいつでも。", "점을 잡고 위젯을 화면 아무 가장자리로나 끌어 놓으세요. 설정과 이 둘러보기는 오른쪽 클릭 한 번이면 열립니다."]
        case .obMockEvent1: return ["Team standup", "Стендап команды", "Point d'équipe", "Reunión diaria", "团队站会", "Reunião diária", "Team-Standup", "Standup del team", "チーム朝会", "팀 스탠드업"]
        case .obMockEvent2: return ["Design review", "Ревью дизайна", "Revue du design", "Revisión de diseño", "设计评审", "Revisão de design", "Design-Review", "Revisione design", "デザインレビュー", "디자인 리뷰"]
        case .obMockEvent3: return ["Call with Anna", "Созвон с Анной", "Appel avec Anna", "Llamada con Anna", "与 Anna 通话", "Chamada com a Anna", "Call mit Anna", "Chiamata con Anna", "アンナと通話", "Anna와 통화"]
        case .obMockEvent4: return ["Gym", "Спортзал", "Salle de sport", "Gimnasio", "健身", "Ginásio", "Fitnessstudio", "Palestra", "ジム", "헬스장"]
        case .obMockMail1: return ["Final creative round — 3 options", "Финальный раунд креативов — 3 варианта", "Dernier tour créatif — 3 options", "Ronda creativa final: 3 opciones", "最终创意方案——3 个选项", "Ronda criativa final — 3 opções", "Finale Kreativrunde — 3 Optionen", "Round creativo finale — 3 opzioni", "最終クリエイティブ案 — 3案", "최종 크리에이티브 시안 — 3가지"]
        case .obMockMail2: return ["Board deck: my comments", "Презентация для совета: мои правки", "Deck du conseil : mes commentaires", "Presentación del consejo: mis comentarios", "董事会演示稿：我的意见", "Apresentação do conselho: comentários", "Board-Deck: meine Anmerkungen", "Deck per il board: i miei commenti", "取締役会資料：コメント", "이사회 자료: 의견 남겼어요"]
        case .obMockMail3: return ["Lunch at 13:00?", "Обед в 13:00?", "Déjeuner à 13h ?", "¿Comemos a las 13:00?", "13:00 一起吃午饭？", "Almoço às 13:00?", "Mittagessen um 13:00?", "Pranzo alle 13:00?", "13時にランチ？", "13시에 점심 어때요?"]
        case .obMockReply: return ["Yes, see you there!", "Да, увидимся!", "Oui, à tout à l'heure !", "¡Sí, nos vemos allí!", "好的，到时见！", "Sim, até já!", "Ja, bis gleich!", "Sì, a dopo!", "はい、では後ほど！", "좋아요, 거기서 봬요!"]
        case .obMockPlaybook1: return ["Morning review", "Утренний обзор", "Revue du matin", "Repaso matinal", "晨间回顾", "Revisão da manhã", "Morgenrunde", "Revisione mattutina", "朝のレビュー", "아침 점검"]
        case .obMockPlaybook2: return ["Deep work", "Глубокая работа", "Travail profond", "Trabajo profundo", "深度工作", "Trabalho focado", "Deep Work", "Lavoro profondo", "ディープワーク", "딥 워크"]
        case .obMockNoteTitle: return ["Launch plan", "План запуска", "Plan de lancement", "Plan de lanzamiento", "发布计划", "Plano de lançamento", "Launch-Plan", "Piano di lancio", "ローンチ計画", "출시 계획"]
        case .obMockNoteBody: return ["— Final copy for the landing\n— Record the promo video", "— Финальный текст лендинга\n— Записать промо-видео", "— Textes finaux de la page d'accueil\n— Tourner la vidéo promo", "— Textos finales de la landing\n— Grabar el vídeo promocional", "— 定稿落地页文案\n— 录制宣传视频", "— Texto final da landing page\n— Gravar o vídeo promocional", "— Finale Texte für die Landingpage\n— Promo-Video aufnehmen", "— Testi finali della landing\n— Girare il video promo", "— ランディングページの最終文案\n— プロモ動画を撮影", "— 랜딩 페이지 최종 문구\n— 홍보 영상 촬영"]
        case .obMockNoteDictation: return ["— Book the venue for Friday", "— Забронировать зал на пятницу", "— Réserver la salle pour vendredi", "— Reservar la sala para el viernes", "— 预订周五的场地", "— Reservar a sala para sexta", "— Location für Freitag buchen", "— Prenotare la sala per venerdì", "— 金曜日の会場を予約", "— 금요일 장소 예약하기"]
        case .obMockAsk: return ["What's on tomorrow?", "Что у меня завтра?", "Qu'est-ce que j'ai demain ?", "¿Qué tengo mañana?", "我明天有什么安排？", "O que tenho amanhã?", "Was steht morgen an?", "Cosa ho domani?", "明日の予定は？", "내일 일정이 뭐야?"]
        case .obMockAnswer: return ["Three meetings: standup at 10:00, design review at 13:30 and a call with Anna at 16:00. The evening is free.", "Три встречи: стендап в 10:00, ревью дизайна в 13:30 и созвон с Анной в 16:00. Вечер свободен.", "Trois réunions : point d'équipe à 10h, revue du design à 13h30 et appel avec Anna à 16h. La soirée est libre.", "Tres reuniones: la diaria a las 10:00, revisión de diseño a las 13:30 y llamada con Anna a las 16:00. La noche está libre.", "三场会议：10:00 团队站会、13:30 设计评审、16:00 与 Anna 通话。晚上有空。", "Três reuniões: a diária às 10:00, revisão de design às 13:30 e chamada com a Anna às 16:00. A noite está livre.", "Drei Termine: Standup um 10:00, Design-Review um 13:30 und Call mit Anna um 16:00. Der Abend ist frei.", "Tre riunioni: standup alle 10:00, revisione design alle 13:30 e chiamata con Anna alle 16:00. La sera è libera.", "会議は3つ。10:00に朝会、13:30にデザインレビュー、16:00にアンナと通話。夜は空いています。", "회의가 세 개 있어요. 10:00 스탠드업, 13:30 디자인 리뷰, 16:00 Anna와 통화. 저녁은 비어 있어요."]
        }
    }
}

extension DateFormatter {
    /// Localized from a template ("EEE d MMM") — field order follows the locale.
    convenience init(template: String) {
        self.init()
        setLocalizedDateFormatFromTemplate(template)
    }

    /// Fixed format, the same in every locale.
    convenience init(format: String) {
        self.init()
        dateFormat = format
    }
}
