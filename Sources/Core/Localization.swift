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
}

/// String table. Order per row: en, ru, fr, es, zh, pt, de, it, ja, ko.
enum L10nKey {
    // Module titles
    case modPlaybooks, modCalendar, modEmail, modClipboard, modNotes, modChats
    case modMusic, modTimer, modShelf, modSystem, modAssistant
    case comingSoon, comingSoonSub

    // Widget chrome
    case menuSettings, menuIslandMode, menuWidgetMode, menuQuit

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
    case timerCustomPlaceholder

    // Notes
    case notesEmptyTitle, notesEmptySub, notesQuickPlaceholder, notesNew, notesDone
    case notesFolder, notesChange

    // Speech
    case speechListening, speechDenied, speechOpenSettings

    // Email
    case setAccounts
    case mailSetupTitle, mailSetupSub, mailSetupAction
    case mailInboxEmpty, mailOpenInApp, mailNoBody, mailNoSubject
    case mailProvider, mailAddress, mailPassword, mailPasswordHint, mailOutlookWarning
    case mailImapHost, mailSmtpHost
    case mailCheck, mailChecking, mailCheckOk, mailSave, mailRemove
    case mailReply, mailReplyPlaceholder, mailSend, mailSending, mailSent, mailCancel, mailShowImages, mailHideImages
    case mailSearchPlaceholder, mailNoResults, mailArchive, mailRefresh, mailSearch
    case mailToField, mailSubjectField, mailNewMessage, mailBodyPlaceholder

    // Assistant
    case asstSetupTitle, asstSetupSub, asstHint, asstPlaceholder, asstThinking
    case asstBaseURL, asstModel, asstKey, asstKeyHint
    case asstProviderClaude, asstProviderCodex, asstProviderAPI
    case asstPreset, asstModelOptional, asstCLIMissing, asstVoiceHint, asstEmptyTitle

    // Playbooks
    case playNew, playEmpty, playDone, playClosed, playOpened, playErrors, playEdit, playAdd
    case playApps, playCloseRest, playFocus, playLaunch

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
    case setOpenSettings, setExpandIsland, setExpandIslandSub
    case setOutsideClick, setOutsideClickSub
    case setHideWidget, setHideWidgetSub, setPinPanel, setPinPanelSub
    case setModeToggle, setModeToggleSub

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
        case .comingSoon: return ["Coming soon", "Скоро", "Bientôt", "Próximamente", "即将推出", "Em breve", "Bald verfügbar", "In arrivo", "近日公開", "곧 제공"]
        case .comingSoonSub: return ["Connects in a later build.", "Подключится в следующих версиях.", "Disponible dans une prochaine version.", "Se conecta en una versión futura.", "将在后续版本中接入。", "Chega numa versão futura.", "Kommt in einer späteren Version.", "Arriva in una versione futura.", "今後のバージョンで対応します。", "이후 버전에서 연결됩니다."]

        case .menuSettings: return ["Settings…", "Настройки…", "Réglages…", "Ajustes…", "设置…", "Ajustes…", "Einstellungen…", "Impostazioni…", "設定…", "설정…"]
        case .menuIslandMode: return ["Island mode", "Режим острова", "Mode îlot", "Modo isla", "灵动岛模式", "Modo ilha", "Insel-Modus", "Modalità isola", "アイランドモード", "아일랜드 모드"]
        case .menuWidgetMode: return ["Widget mode", "Режим виджета", "Mode widget", "Modo widget", "小组件模式", "Modo widget", "Widget-Modus", "Modalità widget", "ウィジェットモード", "위젯 모드"]
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
        case .calToday: return ["Today", "Сегодня", "Aujourd'hui", "Hoy", "今天", "Hoje", "Heute", "Oggi", "今日", "오늘"]
        case .calTomorrow: return ["Tomorrow", "Завтра", "Demain", "Mañana", "明天", "Amanhã", "Morgen", "Domani", "明日", "내일"]
        case .timerCustomPlaceholder: return ["min", "мин", "min", "min", "分", "min", "Min", "min", "分", "분"]

        case .notesEmptyTitle: return ["no notes", "нет заметок", "aucune note", "sin notas", "没有备忘录", "sem notas", "keine Notizen", "nessuna nota", "メモなし", "메모 없음"]
        case .notesEmptySub: return ["Type below — Enter saves a note", "Напишите ниже — Enter сохранит заметку", "Écrivez ci-dessous — Entrée enregistre", "Escribe abajo — Enter guarda la nota", "在下方输入 — 回车保存", "Escreva abaixo — Enter guarda a nota", "Unten tippen — Enter speichert", "Scrivi sotto — Invio salva la nota", "下に入力 — Enterで保存", "아래에 입력 — Enter로 저장"]
        case .notesQuickPlaceholder: return ["Quick note…", "Быстрая заметка…", "Note rapide…", "Nota rápida…", "快速记录…", "Nota rápida…", "Schnellnotiz…", "Nota rapida…", "クイックメモ…", "빠른 메모…"]
        case .notesNew: return ["New", "Новая", "Nouvelle", "Nueva", "新建", "Nova", "Neu", "Nuova", "新規", "새로 만들기"]
        case .notesDone: return ["Done", "Готово", "Terminé", "Listo", "完成", "Concluído", "Fertig", "Fatto", "完了", "완료"]
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
        case .mailSave: return ["Save", "Сохранить", "Enregistrer", "Guardar", "保存", "Guardar", "Sichern", "Salva", "保存", "저장"]
        case .mailRemove: return ["Remove account", "Удалить аккаунт", "Supprimer le compte", "Eliminar cuenta", "移除账户", "Remover conta", "Konto entfernen", "Rimuovi account", "アカウントを削除", "계정 제거"]

        case .playNew: return ["+ new", "+ новый", "+ nouveau", "+ nuevo", "+ 新建", "+ novo", "+ neu", "+ nuovo", "+ 新規", "+ 새로 만들기"]
        case .playEmpty: return ["empty", "пустой", "vide", "vacío", "空", "vazio", "leer", "vuoto", "空", "비어 있음"]
        case .playApps: return ["%d apps", "%d прил.", "%d apps", "%d apps", "%d 个应用", "%d apps", "%d Apps", "%d app", "%d個のApp", "앱 %d개"]
        case .playCloseRest: return ["closes others", "закрывает прочие", "ferme le reste", "cierra el resto", "关闭其他", "fecha o resto", "schließt andere", "chiude il resto", "他を閉じる", "다른 앱 닫기"]
        case .playFocus: return ["focus", "фокус", "focus", "enfoque", "专注", "foco", "Fokus", "focus", "集中", "집중"]
        case .playLaunch: return ["Launch", "Запустить", "Lancer", "Iniciar", "启动", "Iniciar", "Starten", "Avvia", "起動", "실행"]
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
        case .setOutsideClick: return ["Close panel on outside click", "Закрывать панель по клику вне виджета", "Fermer le panneau en cliquant à l'extérieur", "Cerrar el panel al hacer clic fuera", "点击外部时关闭面板", "Fechar o painel ao clicar fora", "Panel bei Klick außerhalb schließen", "Chiudi il pannello cliccando fuori", "外側をクリックでパネルを閉じる", "밖을 클릭하면 패널 닫기"]
        case .setOutsideClickSub: return ["Off = the panel stays pinned. ⌃⌥P toggles this anywhere.", "Выкл = панель закреплена. ⌃⌥P переключает откуда угодно.", "Désactivé = panneau épinglé. ⌃⌥P bascule partout.", "Desactivado = panel fijado. ⌃⌥P lo alterna en cualquier lugar.", "关闭 = 面板固定。⌃⌥P 随处切换。", "Desligado = painel fixado. ⌃⌥P alterna em qualquer lugar.", "Aus = Panel bleibt angeheftet. ⌃⌥P schaltet überall um.", "Off = pannello fissato. ⌃⌥P lo commuta ovunque.", "オフ = パネルを固定。⌃⌥P でどこでも切替。", "끄면 패널 고정. ⌃⌥P로 어디서든 전환."]
        case .setHideWidget: return ["Hide / show the widget", "Скрыть / показать виджет", "Masquer / afficher le widget", "Ocultar / mostrar el widget", "隐藏 / 显示小组件", "Ocultar / mostrar o widget", "Widget aus- / einblenden", "Nascondi / mostra il widget", "ウィジェットを隠す / 表示", "위젯 숨기기 / 표시"]
        case .setHideWidgetSub: return ["Collapses the strip into a small square when it is in the way", "Сворачивает рейку в маленький квадрат, когда она мешает", "Réduit la barre en petit carré quand elle gêne", "Colapsa la barra en un cuadrito cuando estorba", "碍事时把工具条折叠成小方块", "Recolhe a barra num quadradinho quando atrapalha", "Faltet die Leiste zu einem kleinen Quadrat, wenn sie stört", "Riduce la barra a un quadratino quando è d'intralcio", "邪魔なときにストリップを小さな四角に畳みます", "방해될 때 스트립을 작은 사각형으로 접기"]
        case .setModeToggle: return ["Widget / island", "Виджет / остров", "Widget / îlot", "Widget / isla", "小组件 / 灵动岛", "Widget / ilha", "Widget / Insel", "Widget / isola", "ウィジェット / アイランド", "위젯 / 아일랜드"]
        case .setModeToggleSub: return ["Flips between the edge widget and the notch island", "Переключает между виджетом у края и островом у выреза", "Bascule entre le widget de bord et l'îlot du notch", "Alterna entre el widget lateral y la isla del notch", "在边缘小组件和刘海灵动岛之间切换", "Alterna entre o widget na borda e a ilha do notch", "Wechselt zwischen Rand-Widget und Notch-Insel", "Alterna tra il widget sul bordo e l'isola del notch", "端のウィジェットとノッチのアイランドを切り替えます", "가장자리 위젯과 노치 아일랜드 사이를 전환합니다"]
        case .setPinPanel: return ["Pin the panel", "Закрепить панель", "Épingler le panneau", "Fijar el panel", "固定面板", "Fixar o painel", "Panel anheften", "Fissa il pannello", "パネルを固定", "패널 고정"]
        case .setPinPanelSub: return ["Toggles \"close on outside click\"", "Переключает «закрывать по клику вне виджета»", "Bascule « fermer au clic extérieur »", "Alterna «cerrar al hacer clic fuera»", "切换「点击外部关闭」", "Alterna «fechar ao clicar fora»", "Schaltet \"bei Klick außerhalb schließen\" um", "Commuta «chiudi al clic esterno»", "「外側クリックで閉じる」を切替", "\"밖 클릭 시 닫기\" 전환"]
        }
    }
}
