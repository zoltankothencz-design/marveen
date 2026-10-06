// === Dashboard language switcher (HU / EN) ===
// The dashboard markup and app.js are written in Hungarian. Instead of
// threading a t() call through every template string, this layer translates
// the rendered DOM: static markup, dynamically rendered content (via a
// MutationObserver), and alert()/confirm()/prompt() messages. Original
// Hungarian text is remembered per node so switching back to HU is lossless.
// Anything missing from EN_DICT simply stays Hungarian.
(() => {
  const LANG_KEY = 'marveen-lang'
  const ATTRS = ['placeholder', 'title', 'alt', 'aria-label']

  const EN_DICT = {
    // --- navigation / titles ---
    'Áttekintés': 'Overview', 'Ügynökök': 'Agents', 'Ügynök': 'Agent', 'Ágens': 'Agent', 'Csapat': 'Team',
    'Ütemezések': 'Schedules', 'Ütemezés': 'Schedule', 'Memória': 'Memory', 'Napló': 'Log', 'Háttér': 'Background',
    'Skillek': 'Skills', 'Frissítések': 'Updates', 'Témaváltás': 'Toggle theme', 'Költöztetés': 'Migration',
    'Háttérfeladatok': 'Background tasks', 'Háttérben futó feladatok indítása és követése': 'Start and track background tasks',
    'Időzített feladatok kezelése': 'Manage scheduled tasks', 'AI csapattagok kezelése': 'Manage AI team members',
    'AI csapat tudásbázisa': 'AI team knowledge base', 'MCP szerverek kezelése': 'Manage MCP servers',
    'Session recall: napi naplók és emlékek visszakeresése': 'Session recall: search daily logs and memories',
    'Ügynök token-fogyasztás nyomon követése': 'Track agent token usage',
    'Korábbi AI asszisztens rendszer átmigrálása': 'Migrate a previous AI assistant system',
    'Rendszer költöztetés': 'System migration', 'Új költöztetés': 'New migration', 'Költöztetés indítása': 'Start migration',
    'Költöztetés...': 'Migrating...', 'Költöztetés kész!': 'Migration complete!',
    'Korábbi AI asszisztens rendszer átmigrálása. Töltsd fel a workspace fájljait (.md, .txt, .json) -- az AI automatikusan felismeri és besorolja a memóriákat, személyiséget és beállításokat.':
      'Migrate a previous AI assistant system. Upload your workspace files (.md, .txt, .json) -- the AI automatically recognizes and sorts memories, personality and settings.',
    // --- overview ---
    'Aktív ügynökök': 'Active agents', 'Aktivitás': 'Activity', 'Szolgáltatások': 'Services', 'Állapot': 'Status',
    'Státusz': 'Status', 'Statusz': 'Status', 'Összesen': 'Total', 'Összesen:': 'Total:', 'élő állapot': 'live status',
    'online': 'online', 'Online': 'Online', 'Aktív': 'Active', 'aktív': 'active', 'Fut': 'Running', 'Leállva': 'Stopped',
    'Leállítva': 'Stopped', '○ Leállva': '○ Stopped', '○ inaktív': '○ inactive', '● aktív': '● active', 'Hibás': 'Faulty',
    'Hiba': 'Error', 'Hiba!': 'Error!', 'Hiba: ': 'Error: ', 'Hiba:': 'Error:', 'Kész': 'Done', 'Kész!': 'Done!',
    'Folyamatban': 'In progress', 'Tervezett': 'Planned', 'Várakozik': 'Waiting', 'Vár': 'Waiting', 'Vár...': 'Waiting...',
    'Claude szolgáltatások állapota': 'Claude services status', 'Incidensek': 'Incidents',
    'Nincs korabbi incidens': 'No previous incidents', 'Nincs friss esemény.': 'No recent events.',
    'Ma futott feladat': 'Tasks run today', 'ebből ${d.skills.today} ma': '${d.skills.today} today',
    'bejegyzés · ${d.memories.categories} category': 'entries · ${d.memories.categories} categories',
    'Chat Marveen-nel': 'Chat with Marveen', 'Írj üzenetet Marveen-nel...': 'Write a message to Marveen...',
    'Írj üzenetet Marveen-nek...': 'Write a message to Marveen...', 'Küld': 'Send', 'Küldés': 'Send',
    'Hozzáadás': 'Add', 'Hozzáadás...': 'Adding...', 'Hozzaad': 'Add', 'Hozzárendelés ügynökökhöz': 'Assign to agents',
    'Hozzarendeles': 'Assignment', 'Mégse': 'Cancel', 'Mentés': 'Save', 'Mentés...': 'Saving...', 'Törlés': 'Delete',
    'Torles': 'Delete', 'Törl.': 'Del.', 'Szerk.': 'Edit', 'Szerkesztés': 'Edit', 'Modosit': 'Modify', 'Mutat': 'Show',
    'Bezárás': 'Close', 'Vissza': 'Back', 'Tovább': 'Next', 'Keresés': 'Search', 'Keresés...': 'Search...',
    'Újra': 'Retry', 'Beállítások': 'Settings', 'Frissítés': 'Refresh', 'Frissítés most': 'Refresh now',
    'Másol': 'Copy', 'Másolás': 'Copy', 'Masolas': 'Copy', 'Másolva!': 'Copied!', 'Vágólapra másolva': 'Copied to clipboard',
    'Importálás': 'Import', 'Importálás...': 'Importing...', 'Importálva': 'Imported', 'Import hiba': 'Import error',
    'Létrehozás': 'Create', 'Létrehozás...': 'Creating...', 'Generálás...': 'Generating...', 'Feldolgozás...': 'Processing...',
    'Betöltés...': 'Loading...', 'Betöltés hiba:': 'Load error:', 'Nem sikerült betölteni': 'Failed to load',
    'Hiba a betöltés során': 'Error while loading', 'Hiba a betöltésnél': 'Error while loading', 'Hiba a betoltes soran': 'Error while loading',
    'Hiba a katalógus betöltésekor': 'Error loading the catalog', 'Katalógus betöltése...': 'Loading catalog...',
    'Halozati hiba': 'Network error', 'Kapcsolodasi hiba': 'Connection error', 'Nincs adat': 'No data', 'Nem található': 'Not found',
    'Részletek': 'Details', 'Részletek betöltése sikertelen': 'Failed to load details', 'Ez néhány másodpercig tarthat': 'This may take a few seconds',
    'Mind': 'All', 'Összes': 'All', 'Osszes': 'All', 'Minden ügynök': 'All agents', 'Minden ágens': 'All agents',
    'Inaktívak is': 'Include inactive', 'Befejezettek is': 'Include completed', 'Jelenlegi:': 'Current:', 'Forrás:': 'Source:',
    'Projekt:': 'Project:', 'Név': 'Name', 'Cím': 'Title', 'Leírás': 'Description', 'Leiras (opcionalis)': 'Description (optional)',
    'Típus': 'Type', 'Tipus': 'Type', 'Tartalom': 'Content', 'Parancs': 'Command', 'Argumentumok': 'Arguments',
    'Idő': 'Time', 'Időpont': 'Time', 'Határidő': 'Due date', 'Prioritás': 'Priority', 'Felelős': 'Assignee',
    'Alacsony': 'Low', 'Normál': 'Normal', 'Magas': 'High', 'Sürgős': 'Urgent',
    'Hétfő': 'Monday', 'Kedd': 'Tuesday', 'Szerda': 'Wednesday', 'Csütörtök': 'Thursday', 'Péntek': 'Friday',
    'Szombat': 'Saturday', 'Vasárnap': 'Sunday', 'Hétköznap': 'Weekdays',
    'Hétfőn': 'Mondays', 'Kedden': 'Tuesdays', 'Szerdán': 'Wednesdays', 'Csütörtökön': 'Thursdays', 'Pénteken': 'Fridays', 'Szombaton': 'Saturdays',
    // --- kanban ---
    'Új kártya': 'New card', 'Kártya': 'Card', 'Kártya szerkesztése': 'Edit card', 'Kártya létrehozva': 'Card created',
    'Kártya frissítve': 'Card updated', 'Kártya törölve': 'Card deleted', 'Kártya archiválva': 'Card archived',
    'Archiválás': 'Archive', 'Megjegyzések': 'Comments', 'Megjegyzés írása...': 'Write a comment...',
    'Komment szerzője:': 'Comment author:', 'Kanban határidő figyelő': 'Kanban deadline monitor', 'Subtask-ok': 'Subtasks',
    'Subtask-ok létrehozása': 'Create subtasks', 'Breakdown javaslat': 'Breakdown suggestion', 'Lista nézet': 'List view',
    'Heti nézet': 'Weekly view', 'Napi idővonal': 'Daily timeline', 'Idővonal': 'Timeline', 'Heti ablak': 'Weekly window',
    '5 órás ablak': '5-hour window', '>5 órás ablak</div>': '>5-hour window</div>',
    '⚡ AI szétbont': '⚡ AI breakdown', 'Intelligens kibővítés': 'Smart expansion', 'Prompt kibővítése': 'Expand prompt',
    'Prompt kibővítve!': 'Prompt expanded!', 'Feladat szerkesztése': 'Edit task', 'Feladat frissítve': 'Task updated',
    'Feladat törölve': 'Task deleted', 'Új feladat': 'New task', 'Feladat leírása...': 'Task description...',
    'Feladat megnevezése': 'Task name', 'Részletek, kontextus...': 'Details, context...',
    'Válassz legalább egy subtask-ot': 'Select at least one subtask',
    'A komment szerzője. A kártya felelőse fent, a Felelős mezőre kattintva állítható.': 'The comment author. The card assignee is shown above and can be changed by clicking the Assignee field.',
    'Autodelegálás: a vezető maga szétbontja és kiosztja a feladatot': 'Auto-delegation: the leader breaks down and assigns the task itself',
    'Ha nincs bepipálva, a vezető csak javaslatot ad, te hagyod jóvá Telegramon.': 'If unchecked, the leader only makes a suggestion and you approve it on Telegram.',
    // --- agents ---
    'Új ügynök': 'New agent', 'Új ügynök létrehozása': 'Create new agent', 'Ügynök részletek': 'Agent details',
    'Ügynök skilljei': 'Agent skills', 'Cél ügynök': 'Target agent', 'Avatar frissítve': 'Avatar updated',
    'Avatar változtatás': 'Change avatar', 'Válassz avatart': 'Choose an avatar', 'Válassz új avatart': 'Choose a new avatar',
    'Kép feltöltése (max 1 MB)': 'Upload image (max 1 MB)', 'Max 1 MB méretű kép': 'Image up to 1 MB', 'Galéria': 'Gallery',
    'Indítás': 'Start', 'Leállítás': 'Stop', 'Leállítási hiba': 'Stop error', 'Szerep': 'Role', 'Személyiség': 'Personality',
    'Modell': 'Model', 'Sablon': 'Template', 'Profil': 'Profile', 'Konfig': 'Config', 'Általános mappa': 'General folder',
    'Haiku 4.5 (leggyorsabb)': 'Haiku 4.5 (fastest)', 'Opus 4.8 (legújabb)': 'Opus 4.8 (latest)',
    'Sonnet 4.6 (alapértelmezett)': 'Sonnet 4.6 (default)', 'Sonnet 4.6 (gyors és okos)': 'Sonnet 4.6 (fast and smart)',
    'Öröklött (alapértelmezett)': 'Inherited (default)', 'Biztonsági profil': 'Security profile',
    'Autonómia': 'Autonomy', 'Autonóm, utólag jelent': 'Autonomous, reports afterwards', 'Csak jelez': 'Notify only',
    'Javasol, jóváhagyásra vár': 'Suggests, awaits approval', 'Feladat (mindig szól)': 'Task (always notifies)',
    'Heartbeat (csak ha fontos)': 'Heartbeat (only if important)', 'Heartbeat fokozatos autonómia szintek': 'Heartbeat graduated autonomy levels',
    'Nem sikerült betölteni az autonómia konfigot.': 'Failed to load the autonomy config.',
    'Írd le szabadon, mit szeretnél hogy csináljon ez az ügynök': 'Describe freely what you want this agent to do',
    'Írd le szabadon, mit csináljon ez a skill': 'Describe freely what this skill should do',
    'CLAUDE.md generálás...': 'Generating CLAUDE.md...', 'Főagent konfiguráció -- csak olvasható': 'Main agent configuration -- read-only',
    'A főagent identitás-fájljai biztonsági okból dashboardról nem szerkeszthetők (token szivárgás esetén távoli identitás-átírás kockázata). Szerkesztéshez nyisd meg fájlrendszerből a projekt gyökerében:':
      'For security reasons the main agent\'s identity files cannot be edited from the dashboard (risk of remote identity rewriting if a token leaks). To edit them, open them from the file system in the project root:',
    'fo asszisztens': 'main assistant', 'csapatvezető': 'team leader', 'Csapatvezető (leader)': 'Team leader', 'Beosztott (member)': 'Member',
    'Kinek jelent': 'Reports to', 'Ki kinek jelent és ki kinek delegál': 'Who reports to whom and who delegates to whom',
    'Kiknek delegálhat (csak leaderhez)': 'Who can it delegate to (leaders only)',
    'A szerep és a beosztott/vezető kapcsolatok az ügynök részletek &gt; Csapat fülén szerkeszthetők.': 'Roles and member/leader relationships can be edited in Agent details > Team tab.',
    'A szerep és a beosztott/vezető kapcsolatok az ügynök részletek > Csapat fülén szerkeszthetők.': 'Roles and member/leader relationships can be edited in Agent details > Team tab.',
    'Explicit megbízható kapcsolatok (opcionális)': 'Explicit trusted connections (optional)',
    'A router alapból a jelent-kapcsolat és a delegálási lista alapján dönti el, hogy egy üzenet megbízható csapattárstól jön-e. Itt további ügynököket jelölhetsz kézzel — pl. egy cross-team együttműködő partner, akivel nincs hierarchikus kapcsolat, de a levelezése mégis csapattársi.':
      'By default the router decides from the reporting relationship and the delegation list whether a message comes from a trusted teammate. Here you can mark additional agents manually — e.g. a cross-team collaborator with no hierarchical relationship whose messages still count as teammate messages.',
    'Szinkron': 'Sync', 'Szinkronizálás...': 'Syncing...',
    // --- memory ---
    'Új emlék': 'New memory', 'Uj emlek': 'New memory', 'Emlék szerkesztése': 'Edit memory', 'Emlék frissítve': 'Memory updated',
    'Emlék létrehozva': 'Memory created', 'Emlék törölve': 'Memory deleted', 'emlék importálva': 'memories imported',
    'Keresés az emlékekben...': 'Search memories...', 'Keresés a napló szövegében...': 'Search log text...',
    'Mit kell megjegyezni...': 'What should be remembered...', 'Nincs emlék ebben a kategóriában': 'No memories in this category',
    'Nincs elég emlék a gráf megjelenítéshez': 'Not enough memories to display the graph',
    'Gráf betöltés hiba:': 'Graph load error:', 'Memória betöltés hiba:': 'Memory load error:', 'Stats hiba:': 'Stats error:',
    '&#128293; Hot (aktiv)': '🔥 Hot (active)', '🔥 Hot (aktiv)': '🔥 Hot (active)', '🌡️ Warm (stabil)': '🌡️ Warm (stable)',
    '❄️ Cold (archiv)': '❄️ Cold (archive)', '🔗 Shared (megosztott)': '🔗 Shared (shared)', '📋 Naplo': '📋 Log', '🕸️ Graf': '🕸️ Graph',
    'Hot memória': 'Hot memory', 'Warm memória': 'Warm memory', 'Cold memória': 'Cold memory', 'Megosztott': 'Shared',
    'Hibrid kereses': 'Hybrid search', 'Kulcsszavas': 'Keyword', 'Kulcsszavak': 'Keywords', 'Vektorok generalasa': 'Generate vectors',
    'Elozo nap': 'Previous day', 'Kovetkezo nap': 'Next day', 'Nincs naplobejegyzes ezen a napon': 'No log entries on this day',
    'Nincs találat ebben a kategóriában': 'No results in this category', 'Nincs találat erre az időszakra.': 'No results for this period.',
    'pl. tegnap, múlt héten...': 'e.g. yesterday, last week...', 'Kereses a kulcsok kozott...': 'Search keys...',
    '(vesszoval elvalasztva, keresest segiti)': '(comma separated, helps search)',
    // --- schedules ---
    'Új ütemezett feladat': 'New scheduled task', 'Nincsenek ütemezett feladatok': 'No scheduled tasks', 'Válassz ütemezést': 'Choose a schedule',
    'Cron kifejezés': 'Cron expression', 'Egyéni cron...': 'Custom cron...', 'Egyéni...': 'Custom...', 'Gyakoriság': 'Frequency',
    'Naponta': 'Daily', 'Óránként': 'Hourly', 'Hetente (hétfő)': 'Weekly (Monday)', 'Hetente (péntek)': 'Weekly (Friday)',
    '2 óránként': 'Every 2 hours', '4 óránként': 'Every 4 hours', '30 percenként': 'Every 30 minutes',
    '(perc óra nap hónap hétnap)': '(minute hour day month weekday)', 'Mit csinál ez a feladat': 'What this task does',
    'Röviden írd le mit csináljon (pl. \'nézd meg az emailjeimet és foglald össze\')': 'Briefly describe what it should do (e.g. \'check my emails and summarize them\')',
    'Riasztás esedékes, a következő tick küldi': 'Alert due, the next tick will send it', '⏳ riasztás esedékes': '⏳ alert due',
    '⚠️ riasztás elküldve': '⚠️ alert sent', 'Telegram riasztás elküldve': 'Telegram alert sent',
    'Naptár figyelő': 'Calendar monitor', 'Email figyelő': 'Email monitor', 'Cégfigyelő': 'Company monitor',
    'Cég hozzáadása': 'Add company', '+ Cég hozzáadása': '+ Add company', 'Új cég': 'New company', 'Cég szerkesztése': 'Edit company',
    'Cégnév *': 'Company name *', 'Career URL (opcionális)': 'Career URL (optional)', 'Nincs cég a listában.': 'No companies in the list.',
    'iGaming karrier-scan figyelt cégek és recruiterek': 'iGaming career scan: watched companies and recruiters',
    'pl. Betsson': 'e.g. Betsson', 'pl. reggeli-napindito': 'e.g. morning-kickoff', 'Nincsenek ütemezett feladatok.': 'No scheduled tasks.',
    'Ütemezés betöltés hiba:': 'Schedule load error:', 'Nincs háttérfeladat.': 'No background tasks.', 'Futtatás...': 'Running...',
    // --- skills ---
    'Új skill': 'New skill', 'Skill neve': 'Skill name', 'Skill hozzáadva': 'Skill added', 'Skill törölve': 'Skill deleted',
    'Skill generálás': 'Skill generation', 'Generált skillek': 'Generated skills', 'Skill reszletek': 'Skill details',
    'Skill detail hiba:': 'Skill detail error:', 'Skills betoltes hiba:': 'Skills load error:', 'Skillek betoltese...': 'Loading skills...',
    'Nincsenek skillek': 'No skills', 'Nincsenek skillek hozzáadva': 'No skills added', 'Skill fájl (.skill)': 'Skill file (.skill)',
    'Válassz egy .skill fájlt': 'Select a .skill file', 'Kattints vagy húzd ide a .skill fájlt': 'Click or drag the .skill file here',
    'Kattints vagy húzd ide a fájlokat': 'Click or drag files here', 'Válassz legalább egy fájlt': 'Select at least one file',
    'Fájl (.md, .txt, .json)': 'File (.md, .txt, .json)', 'Fájlok feldolgozása...': 'Processing files...', 'SKILL.md tartalom': 'SKILL.md content',
    'A Claude Code által látott skillek (user mappa + plugin cache)': 'Skills seen by Claude Code (user folder + plugin cache)',
    'Beépített képesség': 'Built-in capability', 'Dokumentált': 'Documented', 'Telepített': 'Installed',
    'Telepítés': 'Install', 'Telepites': 'Install', 'Telepítve!': 'Installed!', 'Telepítés...': 'Installing...',
    'Telepítés folyamatban...': 'Installation in progress...', 'Minden itt listázott skill automatikusan elérhető minden sub-agent számára, mert ugyanabban a HOME-ban futnak, mint a fő session. A Claude CLI beépített slash-parancsai (init, review, security-review, loop, schedule, stb.) mindig elérhetők, de itt nem szerepelnek, mert a `claude` binárisban élnek és nem fájlrendszeri források. Új skillt a jobb felső "Új skill" gombbal tudsz létrehozni vagy importálni.':
      'Every skill listed here is automatically available to every sub-agent because they run in the same HOME as the main session. The Claude CLI\'s built-in slash commands (init, review, security-review, loop, schedule, etc.) are always available but not listed here, because they live in the `claude` binary and are not file-system sources. You can create or import a new skill with the "New skill" button at the top right.',
    'Eltávolítva': 'Removed', 'Eltávolítás': 'Remove', 'Eltávolítási hiba': 'Removal error',
    'pl. piackutato, riport-keszito': 'e.g. market-researcher, report-builder', 'pl. kutató, copywriter, fejlesztő': 'e.g. researcher, copywriter, developer',
    'pl. marketing, kampany, ROI': 'e.g. marketing, campaign, ROI',
    'pl. Piackutatási riportokat készít: versenytárs elemzés, piaci trendek, SWOT analízis. A riportot strukturáltan, táblázatokkal adja vissza magyarul.':
      'e.g. Produces market research reports: competitor analysis, market trends, SWOT analysis. Returns the report structured, with tables, in English.',
    'pl. Piackutatást végez, versenytársakat elemez, táblázatos összefoglalókat készít magyarul.':
      'e.g. Does market research, analyzes competitors, produces tabular summaries in English.',
    // --- MCP / connectors / vault ---
    'Connectorok': 'Connectors', 'Új connector': 'New connector', 'Connector részletek': 'Connector details',
    'Connectorok betoltese...': 'Loading connectors...', 'Nincsenek MCP connectorok': 'No MCP connectors', 'MCP szerver': 'MCP server',
    'MCP telepítés': 'MCP installation', 'Mentés és telepítés': 'Save and install', 'Mentés és szinkron': 'Save and sync',
    'MCP lista még nem töltődött be. Kattints a Frissítés gombra, vagy várj egy percet a dashboard indulása után.':
      'The MCP list has not loaded yet. Click Refresh, or wait a minute after the dashboard starts.',
    'Claude MCP lista frissítése': 'Refresh Claude MCP list', 'Lista frissítése': 'Refresh list', 'Kezelhető: claude.ai': 'Managed at: claude.ai',
    'Auth szükséges': 'Auth required', 'Auth-flow indítása': 'Start auth flow', 'Csatlakozva': 'Connected', 'Csatlakozas...': 'Connecting...',
    'Újracsatlakozás...': 'Reconnecting...', 'Bejelentkezés': 'Sign in', 'Eszközök': 'Tools', 'Hatókör': 'Scope', 'Hatokor': 'Scope',
    'Globális (minden projekt)': 'Global (all projects)', 'Projekt szintű': 'Project level', 'Claude globális': 'Claude global', 'Helyi': 'Local',
    'Projekt': 'Project', 'Alkalmazás': 'Application', 'Plugin': 'Plugin', 'Pénzügy': 'Finance', 'Produktivitás': 'Productivity',
    'Fejlesztés': 'Development', 'Kommunikáció': 'Communication', 'Rendszer': 'System', 'Vendor': 'Vendor',
    'Külső projektek': 'External projects', 'GitHub repok': 'GitHub repos', 'Környezeti változók': 'Environment variables',
    'Env': 'Env', '+ Változó hozzáadása': '+ Add variable', 'Kornyezeti változó neve': 'Environment variable name',
    'Kulcs neve': 'Key name', 'Kulcs nev (pl. OPENAI_API_KEY)': 'Key name (e.g. OPENAI_API_KEY)', 'pl. API_KEY': 'e.g. API_KEY',
    'pl. OPENAI_API_KEY': 'e.g. OPENAI_API_KEY', 'pl. OpenAI production key': 'e.g. OpenAI production key',
    'Uj kulcs': 'New key', 'Uj kulcs hozzaadasa': 'Add new key', 'API kulcs': 'API key', 'API kulcs hozzáadása': 'Add API key',
    'API kulcsok megadasa': 'Enter API keys', 'API kulcsok megadása szükséges...': 'API keys required...',
    'DeepSeek API kulcs hozzáadása': 'Add DeepSeek API key', 'DeepSeek-V4-Pro nincs konfigurálva.': 'DeepSeek-V4-Pro is not configured.',
    'Tarolt kulcs': 'Stored key', 'Meg nincs tarolt kulcs': 'No stored key yet', 'Adj hozza egyet az "Uj kulcs" gombbal': 'Add one with the "New key" button',
    'Vault kulcs': 'Vault key', 'Vault kulcs hozzarendelese MCP szerverhez': 'Assign vault key to MCP server', 'Kulcs hozzarendelese': 'Assign key',
    'Mentés a Vault-ba': 'Save to Vault', 'Vault (titkositott kulcsok)': 'Vault (encrypted keys)', 'Titkositas': 'Encryption',
    'Titkositott kulcsok es API tokenek': 'Encrypted keys and API tokens', 'Kotes': 'Binding', 'Ertek': 'Value', 'Tarolas': 'Storage',
    'Utvonalak': 'Paths', 'Kivalasztottak importalasa': 'Import selected', 'Kihagyas': 'Skip',
    'MCP konfigok atvizsgalasa erzekeny kulcsokert': 'Scan MCP configs for sensitive keys', 'MCP titkok keresese': 'Find MCP secrets',
    'Nem talaltam erzekeny erteket a konfiguraciokban.': 'No sensitive values found in the configurations.',
    'Vault ertekek szinkronizalasa a .mcp.json fajlokba': 'Sync Vault values to .mcp.json files',
    'titkositas · A kulcsok kizarolag a helyi gepen tarolodnak, soha nem hagyjak el a rendszert. MCP szerverek telepitesekor a szukseges API kulcsokat itt tarolhatod biztonsagosan.':
      'encryption · Keys are stored only on the local machine and never leave the system. When installing MCP servers you can securely store the required API keys here.',
    'Ez az MCP szerver az alabbi env változókat igényli. Az ertekek titkositva a Vault-ba kerulnek.': 'This MCP server requires the following env variables. Values are stored encrypted in the Vault.',
    'Ez az MCP szerver az alabbi env változókat igenyeli. Az ertekek titkositva a Vault-ba kerulnek.': 'This MCP server requires the following env variables. Values are stored encrypted in the Vault.',
    'A rendszer atvizsgalja az osszes .mcp.json fajlt es megkeresi az erzekeny konfiguracios ertekeket (API kulcsok, tokenek, jelszo-szeru ertekek).':
      'The system scans all .mcp.json files and finds sensitive configuration values (API keys, tokens, password-like values).',
    'Az itt listázott MCP szerverek a te Claude Code előfizetésedben bekapcsoltak (claude.ai OAuth connectorok, marketplace pluginok, lokális konfig). Minden sub-agent automatikusan látja őket, mert ugyanabban a HOME-ban fut, mint a fő session. Ha egy MCP már bekapcsolva van claude.ai-n,':
      'The MCP servers listed here are enabled in your Claude Code subscription (claude.ai OAuth connectors, marketplace plugins, local config). Every sub-agent sees them automatically because it runs in the same HOME as the main session. If an MCP is already enabled on claude.ai,',
    'ne vedd fel még egyszer lokálisan': 'do not add it again locally',
    ': duplikálódik, és a Claude CLI "local wins" üzenetet ad rá. A lista a dashboard indulásakor töltődik be, explicit frissítés a "Frissítés" gombbal.':
      ': it gets duplicated and the Claude CLI reports "local wins". The list loads when the dashboard starts; refresh it explicitly with the "Refresh" button.',
    'NAV, Billingo, Wise, fal.ai: egyetlen MCP-ből, vagy token-hatékony CLI-vel. Magyar fókusz, nemzetközi lefedettség.':
      'NAV, Billingo, Wise, fal.ai: from a single MCP, or with a token-efficient CLI. Hungarian focus, international coverage.',
    'connectors.hu, egy MCP mind fölött': 'connectors.hu, one MCP above all', 'connectors.hu CLI telepítve': 'connectors.hu CLI installed',
    'connectors.hu token (dashboardról)': 'connectors.hu token (from the dashboard)',
    'A Chrome integráció lehetővé teszi a böngészőautomatizálást. A Marveen sub-agentek indítása jelenleg nem adja át ezt a flaget, így csak a manuálisan indított fő session használhatja.':
      'The Chrome integration enables browser automation. Starting Marveen sub-agents currently does not pass this flag, so only the manually started main session can use it.',
    'A Claude in Chrome egy indítás-idejű flag a Claude Code CLI-n, nem egy bekapcsolható MCP szerver. Ezért nem jelenik meg a':
      'Claude in Chrome is a launch-time flag on the Claude Code CLI, not an MCP server you can toggle. That is why it does not appear in the',
    'A Computer Use egy natív Claude képesség, amit nem a Marveen kezel, hanem maga a Claude Code CLI / Claude alkalmazás. Nem jelenik meg a':
      'Computer Use is a native Claude capability that is not managed by Marveen but by the Claude Code CLI / Claude app itself. It does not appear in the',
    'kimenetében, ezért a dashboard sem tudja automatikusan detektálni.': 'output, so the dashboard cannot detect it automatically either.',
    'kimenetében, és a dashboard sem tudja automatikusan detektálni.': 'output, and the dashboard cannot detect it automatically either.',
    'Ez a képesség engedélyt ad az ügynöknek a képernyő vezérlésére és kattintásra, ezért csak megbízható környezetben használd.':
      'This capability allows the agent to control the screen and click, so use it only in a trusted environment.',
    'Bekapcsolás:': 'To enable:', 'indítsd a Claude-ot a': 'start Claude with the', 'flaggel:': 'flag:', 'paranccsal': 'command',
    'Mi ez?': 'What is this?', 'vagy': 'or', 'Menj a': 'Go to', 'Nyisd meg a': 'Open the', 'Nyisd meg a bongeszodben:': 'Open in your browser:',
    'a Vault oldalon.': 'on the Vault page.', 'repón.': 'repo.', 'Illeszd be az alábbi': 'Paste the following',
    'Illeszd be az alábbi YAML manifestet a Slack App létrehozásakor. Ez automatikusan beállítja az összes szükséges scope-ot, eseményt és a Socket Mode-ot.':
      'Paste the YAML manifest below when creating the Slack App. It automatically configures all required scopes, events and Socket Mode.',
    'Illeszd be az alábbi YAML manifestet': 'Paste the YAML manifest below',
    // --- token monitor ---
    'Token Monitor': 'Token Monitor', 'FELHASZNÁLT': 'USED', 'CSÚCSIDŐ': 'PEAK HOURS', 'Legnagyobb hívások': 'Largest calls',
    'Nincs ilyen hívás a szűrt időszakban': 'No such call in the filtered period', 'kumulatív az aktuális ablakban': 'cumulative in the current window',
    'Min token:': 'Min tokens:', '24 óra': '24 hours', '7 nap': '7 days', '30 nap': '30 days', '1 óra': '1 hour', 'hét': 'week',
    // --- channels (Telegram / Slack / Discord) ---
    'Csatorna': 'Channel', 'Csatorna provider': 'Channel provider', 'Csatorna-kérések': 'Channel requests', 'Csatorna engedélyezése': 'Enable channel',
    'Csatorna leszakadt. Automatikus újracsatlakozás folyamatban, vagy használd a gombot lent.': 'Channel disconnected. Automatic reconnect is in progress, or use the button below.',
    'Channel-MCP reconnect': 'Channel-MCP reconnect', 'Channels restart': 'Channels restart',
    'Bot API Token': 'Bot API Token', 'Masold be a Bot Token-t ide': 'Paste the Bot Token here', 'Másold be ide és hagyd jóvá. Ezután az ügynök fog tudni írni a csoportba és olvasni a tagok üzeneteit.':
      'Paste it here and approve. After that the agent can write to the group and read members\' messages.',
    'Masold be az API tokent ide': 'Paste the API token here', 'Token beállítva': 'Token set',
    'Telegram bot bekotese': 'Connect Telegram bot', 'Hozz letre egy uj botot a': 'Create a new bot with', 'Hozz letre egy uj Application-t es Bot-ot': 'Create a new Application and Bot',
    'Egyéni Claude bot': 'Custom Claude bot', 'Bekötött chat-ek és csoportok': 'Connected chats and groups',
    'Még nincs bekötött chat. Lent add hozzá az elsőt.': 'No chats connected yet. Add the first one below.',
    'Új ember vagy csoport hozzáadása': 'Add a new person or group', '1. Új ember (privát chat) hozzáadása:': '1. Add a new person (private chat):',
    '2. Telegram csoport hozzáadása:': '2. Add a Telegram group:', 'Meghívó link (egy kattintásos hozzáadás)': 'Invite link (one-click add)',
    'Új meghívó link': 'New invite link', 'Nincs aktív meghívó link.': 'No active invite link.',
    'Generálj egy egyedi linket. Aki rákattint, automatikusan elindítja a botot, és Te a UI-n láthatóan azonnal jóváhagyhatod. Egy link csak egyszer használható.':
      'Generate a unique link. Whoever clicks it starts the bot automatically and you can approve them right away in the UI. A link can be used only once.',
    'Hogyan adj hozzá több embert vagy csoportot? ▼': 'How do you add more people or groups? ▼',
    'Add meg az illetőnek a bot felhasználónevét (lent látható).': 'Give the person the bot\'s username (shown below).',
    'Az illető indítsd el a botot a Telegramban (': 'The person should start the bot in Telegram (',
    'Az illető indítsa el a botot a Telegramban (': 'The person should start the bot in Telegram (',
    ') és írjon neki egy üzenetet.': ') and send it a message.', 'A bot válaszol egy 6-jegyű párosítási kóddal.': 'The bot replies with a 6-digit pairing code.',
    'Az illető elküldi neked a kódot, te ide írod be és jóváhagyod.': 'The person sends you the code, you enter it here and approve it.',
    'Hívd meg a botot egy meglévő Telegram csoportba (csoport beállítások → Tagok → Hozzáadás).': 'Invite the bot to an existing Telegram group (group settings → Members → Add).',
    'A csoportban írj': 'In the group, write', 'Megjelenik egy párosítási kód a csoportban.': 'A pairing code appears in the group.',
    'Ha valaki ír a botnak, a plugin egy kódot küld neki. Ide írd be a kódot a jóváhagyáshoz.': 'When someone messages the bot, the plugin sends them a code. Enter the code here to approve.',
    'Párosítási kód': 'Pairing code', 'Párosítás jóváhagyva!': 'Pairing approved!', 'Jóváhagyás': 'Approve', 'Jóváhagyási hiba': 'Approval error',
    'Elutasítás': 'Reject', 'Kérés elutasítva': 'Request rejected', 'Nincs várakozó párosítás': 'No pending pairing', 'Várakozók frissítése': 'Refresh pending',
    'Kész, újrapróbálom': 'Done, retrying', 'Busy cél-session, a rendszer tovább próbálkozik. Nyilvánvaló hibánál visszavonhatod.': 'Target session busy, the system keeps retrying. You can cancel in case of an obvious error.',
    'Az ügynök ide tud üzenetet küldeni és innen fogad üzenetet. Egy ügynök tetszőleges számú emberhez (DM) és csoporthoz köthető.':
      'The agent can send messages here and receive messages from here. An agent can be linked to any number of people (DMs) and groups.',
    'Az ügynök fut, a bot aktívan figyel. A chat ID-d előre engedélyezve van, nem kell pairing kód.': 'The agent is running and the bot is actively listening. Your chat ID is pre-approved; no pairing code is needed.',
    'A bot csak akkor fogad üzeneteket, ha az ügynök fut. Indítsd el az Áttekintés tab-on az "Indítás" gombbal.': 'The bot only receives messages while the agent is running. Start it on the Overview tab with the "Start" button.',
    'Az ügynök csak @-tagelt üzenetekre reagál': 'The agent only reacts to @-mentions', 'Csak @-tageléskor figyeljen': 'Listen only when @-mentioned',
    'Bárkitől fogadjon': 'Accept from anyone', 'Ha ki van kapcsolva, csak a kérést indító felhasználótól fogad': 'If turned off, it only accepts from the user who initiated the request',
    'Az agent tmux session-jében elindítja a': 'Starts, in the agent\'s tmux session, the', 'parancsot és visszaadja az auth URL-t.': 'command and returns the auth URL.',
    'Újraindítja az agentet a host hitelesítésével. Nincs külön bejelentkezés.': 'Restarts the agent with the host authentication. No separate sign-in.',
    'A host OAuth hitelesítését használja (alapértelmezett)': 'Uses the host OAuth authentication (default)', 'Host OAuth alkalmazása': 'Apply host OAuth',
    'Hitelesítési mód': 'Authentication mode', 'Külön Anthropic Team login saját OAuth-tal': 'Separate Anthropic Team login with its own OAuth', 'Saját Team login': 'Own Team login',
    'Slack app bekötése': 'Connect Slack app', 'Slack App létrehozása': 'Create Slack App', 'Slack App létrehozása (manifest)': 'Create Slack App (manifest)',
    'Hozz létre egy Slack App-ot, vagy használd a manifest gombot lent': 'Create a Slack App, or use the manifest button below',
    'Még nincs Slack App-od? Kattints ide!': 'Don\'t have a Slack App yet? Click here!',
    'Slack csatornák, amelyekben megemlítették a botot, de még nincsenek engedélyezve.': 'Slack channels where the bot was mentioned but which are not enabled yet.',
    'Slack csatorna smoke-test': 'Slack channel smoke test', 'Slack smoke-test eredmény': 'Slack smoke test result', 'Kapcsolat tesztelése': 'Test connection',
    'Teljes ellenőrzés': 'Full check', 'Ellenőrzés': 'Check', 'Nem sikerült ellenőrizni:': 'Failed to verify:', 'Lépések': 'Steps', '1. Forrás megadása': '1. Specify source',
    '2. Találatok': '2. Results', '3. Eredmény': '3. Result', 'Scan & Import': 'Scan & Import', 'Gyűjtés': 'Collecting', 'Gyűjtés...': 'Collecting...', 'Feltérképezés': 'Mapping',
    'Workspace / mappa útvonala': 'Workspace / folder path', 'Nem található migrálható tartalom': 'No migratable content found',
    'Rendszerszintű beállítás szükséges': 'System-level setting required',
    'A Claude Code megköveteli, hogy a Slack channel plugin engedélyezve legyen a rendszerszintű managed-settings.json fájlban. Futtasd az alábbi parancsot a Terminálban:':
      'Claude Code requires the Slack channel plugin to be enabled in the system-level managed-settings.json file. Run the command below in the Terminal:',
    'Mentés...': 'Saving...', 'A legfrissebb verzión vagy': 'You are on the latest version', 'Marveen verzió ellenőrzés': 'Marveen version check',
    'Nincs változás.': 'No changes.', 'Változások': 'Changes', 'Legfrissebb:': 'Latest:', '→ Legfrissebb:': '→ Latest:',
    'Utolsó módosítás: ': 'Last modified: ', 'Utolsó módosítás:': 'Last modified:', '(opcionális)': '(optional)', '(rövid)': '(short)', '(szigorú)': '(strict)',
    '(betűk, számok, kötőjel, aláhúzás — szóköz nem!)': '(letters, numbers, hyphen, underscore — no spaces!)',
    ' (kérő: ${escapeHtml(userId)})': ' (requested by: ${escapeHtml(userId)})', 'Üresen hagyva automatikusan a főügynöknek.': 'If left empty, it goes to the main agent automatically.',
    '-- Nincs --': '-- None --', '-- nincs --': '-- none --', 'nincs URL': 'no URL', 'Válassz': 'Select',
    'Válassz ütemezést': 'Choose a schedule', 'Válaszolj legalább egy kérdésre': 'Answer at least one question',
    '-- vagy szólj az agent-nek Telegramon, hogy módosítsa.': '-- or tell the agent on Telegram to change it.',
    'Eltávolításhoz használd a Bekötött chat-ek listájában az X gombot.': 'To remove, use the X button in the Connected chats list.',
    'Bele': 'In',
    'Aktív (bekerül a napi scanbe)': 'Active (included in the daily scan)', 'Összekapcsolás': 'Connect', 'Leválasztás': 'Disconnect',
    '-t (vagy a bot által megadott parancsot).': ' (or the command given by the bot).',
  }

  // Regex rules for interpolated strings: [pattern, replacement]
  const EN_RULES = [
    [/^(\d+) hívás, out: (.*)$/, '$1 calls, out: $2'],
    [/^(\d+) bejegyzés$/, '$1 entries'],
    [/^(\d+) emlék$/, '$1 memories'],
    [/^(\d+) ügynök$/, '$1 agents'],
    [/^(\d+) hívás$/, '$1 calls'],
    [/^(\d+) perc$/, '$1 min'],
    [/^(\d+) napja$/, '$1 days ago'],
    [/^(\d+) órája$/, '$1 hours ago'],
    [/^(\d+) perce$/, '$1 minutes ago'],
    [/^ebből (\d+) ma$/, '$1 today'],
    [/^Hiba: (.*)$/, 'Error: $1'],
    [/^Betöltés hiba: (.*)$/, 'Load error: $1'],
    [/^Sikertelen: (.*)$/, 'Failed: $1'],
  ]

  const dictLookup = new Map(Object.entries(EN_DICT).map(([k, v]) => [k.replace(/\s+/g, ' ').trim(), v]))
  // Longest keys first, for prefix matching of "label: dynamic value" strings.
  const prefixKeys = [...dictLookup.keys()].filter(k => /[:] ?$/.test(k) || k.endsWith(' ')).sort((a, b) => b.length - a.length)

  function translateString(s) {
    const lead = s.match(/^\s*/)[0]
    const trail = s.match(/\s*$/)[0]
    const core = s.trim().replace(/\s+/g, ' ')
    if (!core) return s
    let out = dictLookup.get(core)
    if (out === undefined) {
      for (const [re, rep] of EN_RULES) {
        if (re.test(core)) { out = core.replace(re, rep); break }
      }
    }
    if (out === undefined) {
      for (const k of prefixKeys) {
        const kk = k.trim()
        if (core.startsWith(kk) && core.length > kk.length) {
          out = dictLookup.get(k) + core.slice(kk.length)
          break
        }
      }
    }
    return out === undefined ? s : lead + out + trail
  }

  let lang = 'hu'
  try { lang = localStorage.getItem(LANG_KEY) === 'en' ? 'en' : 'hu' } catch { /* ignore */ }

  const origText = new WeakMap() // Text node -> Hungarian original
  const origAttr = new WeakMap() // Element -> { attr: original }
  let applying = false

  function translateTextNode(node) {
    const cur = node.nodeValue
    if (!cur || !cur.trim()) return
    if (lang === 'en') {
      const known = origText.get(node)
      // Skip nodes we already translated (value is our own output).
      if (known && known.en === cur) return
      const en = translateString(cur)
      if (en !== cur) { origText.set(node, { hu: cur, en }); node.nodeValue = en }
    }
  }

  function translateAttrs(el) {
    if (!el.getAttribute) return
    for (const a of ATTRS) {
      if (!el.hasAttribute(a)) continue
      const cur = el.getAttribute(a)
      const rec = origAttr.get(el) || {}
      if (rec[a] && rec[a].en === cur) continue
      if (lang === 'en') {
        const en = translateString(cur)
        if (en !== cur) { rec[a] = { hu: cur, en }; origAttr.set(el, rec); el.setAttribute(a, en) }
      }
    }
  }

  const SKIP_TAGS = new Set(['SCRIPT', 'STYLE', 'TEXTAREA', 'CODE', 'PRE'])
  function walk(root) {
    if (root.nodeType === Node.TEXT_NODE) {
      if (!root.parentNode || !SKIP_TAGS.has(root.parentNode.tagName)) translateTextNode(root)
      return
    }
    if (root.nodeType !== Node.ELEMENT_NODE && root.nodeType !== Node.DOCUMENT_NODE) return
    if (root.nodeType === Node.ELEMENT_NODE) {
      translateAttrs(root)
      if (SKIP_TAGS.has(root.tagName)) return
    }
    const tw = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
    let n
    while ((n = tw.nextNode())) {
      if (n.nodeType === Node.TEXT_NODE) {
        if (!SKIP_TAGS.has(n.parentNode.tagName)) translateTextNode(n)
      } else translateAttrs(n)
    }
  }

  function restoreAll() {
    const tw = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT)
    let n
    while ((n = tw.nextNode())) {
      if (n.nodeType === Node.TEXT_NODE) {
        const rec = origText.get(n)
        if (rec && n.nodeValue === rec.en) n.nodeValue = rec.hu
        origText.delete(n)
      } else {
        const rec = origAttr.get(n)
        if (rec) {
          for (const a of Object.keys(rec)) if (n.getAttribute(a) === rec[a].en) n.setAttribute(a, rec[a].hu)
          origAttr.delete(n)
        }
      }
    }
  }

  const observer = new MutationObserver(muts => {
    if (applying || lang !== 'en') return
    applying = true
    try {
      for (const m of muts) {
        if (m.type === 'childList') m.addedNodes.forEach(walk)
        else if (m.type === 'characterData') translateTextNode(m.target)
        else if (m.type === 'attributes') translateAttrs(m.target)
      }
    } finally { applying = false }
  })

  function setLang(next) {
    lang = next === 'en' ? 'en' : 'hu'
    try { localStorage.setItem(LANG_KEY, lang) } catch { /* ignore */ }
    document.documentElement.lang = lang
    applying = true
    try {
      restoreAll()
      if (lang === 'en') walk(document.body)
    } finally { applying = false }
    updateSwitcher()
    document.dispatchEvent(new CustomEvent('marveen-lang-change', { detail: { lang } }))
  }

  function updateSwitcher() {
    document.querySelectorAll('.lang-btn').forEach(b => {
      const on = b.dataset.lang === lang
      b.classList.toggle('active', on)
      b.setAttribute('aria-pressed', on ? 'true' : 'false')
    })
  }

  // alert/confirm/prompt carry Hungarian strings from app.js.
  for (const fn of ['alert', 'confirm', 'prompt']) {
    const orig = window[fn].bind(window)
    window[fn] = (msg, ...rest) => orig(lang === 'en' && typeof msg === 'string' ? translateString(msg) : msg, ...rest)
  }

  window.i18n = { t: translateString, getLang: () => lang, setLang }
  window.APP_LOCALE = () => (lang === 'en' ? 'en-GB' : 'hu-HU')

  function init() {
    document.documentElement.lang = lang
    document.querySelectorAll('.lang-btn').forEach(b => b.addEventListener('click', () => setLang(b.dataset.lang)))
    updateSwitcher()
    observer.observe(document.body, {
      childList: true, subtree: true, characterData: true,
      attributes: true, attributeFilter: ATTRS,
    })
    if (lang === 'en') { applying = true; try { walk(document.body) } finally { applying = false } }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init)
  else init()
})()
