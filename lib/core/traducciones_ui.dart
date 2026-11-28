/// Diccionario curado de traducciones de interfaz para evitar traducciones
/// literales fuera de contexto (p. ej. "Cola" -> "Tail", "Letra" -> "Letter",
/// "Claro" -> "Of course", "Reproducir" -> "Reproduce").
String? buscarTraduccionUiFijada(String idioma, String texto) {
  final exacto = _diccionarioPorIdioma[idioma]?[texto];
  if (exacto != null) return exacto;
  return _traducirPatron(idioma, texto);
}

const Map<String, Map<String, String>> _diccionarioPorIdioma = {
  'en': {
    // Navegación y secciones principales
    'Inicio': 'Home',
    'Buscar': 'Search',
    'Biblioteca': 'Library',
    'Cola': 'Queue',
    'Abrir cola': 'Open queue',
    'Añadir a la cola': 'Add to queue',
    'Añadida a la cola': 'Added to queue',
    'La cola está vacía.': 'Queue is empty.',
    'Pódcast': 'Podcast',
    'Pódcasts': 'Podcasts',
    'Canciones que te gustan': 'Liked Songs',
    'Artistas seguidos': 'Followed Artists',
    'TUS ARTISTAS SEGUIDOS': 'FOLLOWED ARTISTS',
    'Playlists': 'Playlists',
    'TUS PLAYLISTS': 'YOUR PLAYLISTS',
    'Playlist': 'Playlist',
    'Lista de reproducción': 'Playlist',
    'Volver al contenido': 'Back to content',

    // Reproducción y barra de estado
    'Reproducir': 'Play',
    'Reproducir aquí': 'Play here',
    'Reproduciendo': 'Now Playing',
    'Reproducción Actual': 'Now Playing',
    'Nada sonando': 'Nothing playing',
    'SONANDO AHORA': 'NOW PLAYING',
    'A continuación': 'Next up',
    'A CONTINUACIÓN': 'NEXT UP',
    'A continuación en la cola': 'Next in queue',
    'Recientes': 'Recently played',
    'Aún no hay escuchas recientes.': 'No recently played tracks yet.',
    'Última escucha': 'Recently played',
    'Aleatorio': 'Shuffle',
    'Reproduce una canción para ver sus detalles.':
        'Play a song to see its details.',

    // Letra y sincronización
    'Letra': 'Lyrics',
    'Seguir letra': 'Follow lyrics',
    'Vista previa de la letra': 'Lyrics preview',
    'Por letras': 'By lines',
    'Por palabras': 'By words',
    'Pista instrumental': 'Instrumental track',
    'No hay letra disponible en LRCLIB.': 'No lyrics available on LRCLIB.',
    'No se pudo conectar con LRCLIB.': 'Could not connect to LRCLIB.',
    'No se pudo guardar la sincronización.': 'Could not save lyrics sync.',
    'Resaltado': 'Highlight',
    'Sincronización de esta canción': 'Lyrics sync for this track',
    'Sincronizar con voz': 'Sync with voice',

    // Artistas, álbumes, pódcasts y seguimiento
    'Seguir': 'Follow',
    'Siguiendo': 'Following',
    'Créditos': 'Credits',
    'Ver créditos': 'Show credits',
    'De gira': 'On tour',
    'Información sobre el artista': 'About the artist',
    'Ir al artista': 'Go to artist',
    'Ir al álbum': 'Go to album',
    'Ir a radio de la canción': 'Go to song radio',
    'Inicia sesión de nuevo para sincronizar tus artistas seguidos.':
        'Log in again to sync your followed artists.',
    'Los artistas que sigas en Spotify aparecerán aquí.':
        'Artists you follow on Spotify will appear here.',
    'No se pudieron cargar tus artistas seguidos.':
        'Could not load your followed artists.',
    'Canciones más escuchadas': 'Popular',
    'Singles y EPs': 'Singles & EPs',
    'Destacado en': 'Appears on',
    'Puede que también te guste': 'Fans also like',
    'Este artista no tiene canciones que enseñar.':
        'This artist has no songs to display.',
    'Sin canciones que enseñar aquí.': 'No songs to display here.',
    'Este disco no tiene canciones que enseñar.':
        'This album has no songs to display.',
    'Episodios': 'Episodes',
    'Más episodios': 'More episodes',
    'No hay episodios disponibles.': 'No episodes available.',
    'Abrir episodio en Spotify': 'Open episode in Spotify',
    'No se pudo abrir el episodio en Spotify.':
        'Could not open episode in Spotify.',

    // Inicio y búsqueda
    'Vuelve a escuchar': 'Jump back in',
    'Hecho para ti': 'Made for you',
    'Canciones de tus artistas top que no has escuchado hace poco':
        'Songs by your top artists you haven’t played recently',
    'Tus artistas': 'Your artists',
    'Novedades': 'New releases',
    'Lo último publicado en Spotify': 'Latest releases on Spotify',
    'Lo que más escuchas': 'Your top tracks',
    'De las últimas semanas': 'From the last few weeks',
    'Todavía no hay historial que enseñar. Pon algo de música y vuelve por aquí.':
        'No listening history yet. Play some music and check back here.',
    'Todo': 'All',
    'Artistas': 'Artists',
    'Canciones': 'Songs',
    'Más escuchadas': 'Top tracks',
    'Lo más escuchado en tu idioma': 'Top tracks in your region',
    'Ver más resultados': 'Show more results',
    'Buscando…': 'Searching…',
    'Sin resultados.': 'No results.',
    'Escribe para buscar en NeoFy.': 'Type to search in NeoFy.',

    // Listas, carpetas y acciones de pista
    'Añadir a lista': 'Add to playlist',
    'Añadir a una playlist': 'Add to a playlist',
    'Quitar de esta playlist': 'Remove from this playlist',
    'Quitar de tu biblioteca': 'Remove from your library',
    'Guardar en Canciones que te gustan': 'Save to Liked Songs',
    'Eliminar de Canciones que te gustan': 'Remove from Liked Songs',
    'No hay playlists cargadas.': 'No playlists loaded.',
    'Mover a carpeta': 'Move to folder',
    'Mover a carpeta...': 'Move to folder...',
    'Fuera de cualquier carpeta': 'Outside any folder',
    'Nueva carpeta': 'New folder',
    'Nombre de la carpeta': 'Folder name',
    'Mi carpeta': 'My folder',
    'Renombrar carpeta': 'Rename folder',
    'Eliminar carpeta': 'Delete folder',
    'Nueva playlist': 'New playlist',
    'Renombrar': 'Rename',
    'Quitar': 'Remove',
    'Canción': 'Track',
    'Álbum': 'Album',
    'Álbumes': 'Albums',
    'Duración': 'Duration',
    'Compartir': 'Share',
    'Copiar enlace de Spotify': 'Copy Spotify link',
    'Copiar título y artista': 'Copy title and artist',
    'Abrir en Spotify': 'Open in Spotify',

    // Temporizador
    'Temporizador de apagado': 'Sleep timer',
    'Desactivar temporizador': 'Turn off timer',
    'Al final de la canción': 'End of track',

    // Ajustes, temas, idioma y soporte
    'Ajustes': 'Settings',
    'Apariencia e idioma': 'Appearance & language',
    'Temas': 'Themes',
    'Tema': 'Theme',
    'Automático': 'Automatic',
    'Claro': 'Light',
    'Oscuro': 'Dark',
    'Elige entre NeoFy Claro, NeoFy Nocturno o seguir la apariencia del sistema.':
        'Choose between NeoFy Light, NeoFy Dark, or match your system appearance.',
    'Menús dentro del elemento': 'Inline menus',
    'Los menús se despliegan ocupando el hueco del propio elemento en vez de flotar encima.':
        'Menus expand inside the item row instead of floating over it.',
    'Idioma': 'Language',
    'Idioma de Spotify': 'Spotify language',
    'Buscar idioma o código (es_ES, en_US…)':
        'Search language or code (es_ES, en_US…)',
    'Formato de la API de Spotify: idioma_PAÍS. Si no hay traducción, Spotify responde en inglés americano.':
        'Spotify API format: language_COUNTRY. If unavailable, Spotify falls back to US English.',
    'Audio': 'Audio',
    'Calidad de streaming': 'Streaming quality',
    'Si deja de escucharse, vuelve a abrir la salida.':
        'If audio stops playing, reopen the audio output.',
    'Reabriendo la salida…': 'Reopening audio output…',
    'Modo rendimiento': 'Performance mode',
    'Elimina las portadas por cuadrados de color':
        'Replaces cover art with solid color tiles',
    'Rich Presence': 'Rich Presence',
    'Muestra en tu perfil de Discord la canción que estás escuchando.':
        'Displays the song you are listening to on your Discord profile.',
    'Client ID de Discord': 'Discord Client ID',
    'Pega aquí el Client ID de tu aplicación':
        'Paste your application Client ID here',
    'Crea una app en el Discord Developer Portal con un asset llamado "logo"':
        'Create an app in the Discord Developer Portal with an asset named "logo"',
    'Rama de actualizaciones': 'Update channel',
    'Estable': 'Stable',
    'Las novedades llegan primero a Preview y después a Estable. Puedes cambiar en cualquier momento.':
        'New features land in Preview first and then in Stable. You can switch at any time.',
    'Sin versiones preview más recientes': 'No newer preview releases',
    'Estás al día': 'You are up to date',
    'Instalando; NeoFy se reiniciará': 'Installing; NeoFy will restart',
    'No se pudo comprobar': 'Could not check for updates',
    'Comprobar si hay novedades': 'Check for updates',
    'Soporte': 'Support',
    'Enviar un reporte': 'Send a report',

    // Cuenta, permisos y login
    'Cuenta': 'Account',
    'Cuenta conectada': 'Connected account',
    'Cuenta de Spotify': 'Spotify account',
    'Sesión conectada': 'Signed in',
    'Cerrar sesión': 'Log out',
    'Iniciar sesión': 'Log in',
    'Volver a iniciar sesión': 'Log in again',
    'Salir': 'Log out',
    'Conectar con Spotify': 'Connect to Spotify',
    'Gestionar cuenta en Spotify': 'Manage Spotify account',
    'Enlazar tu cuenta': 'Link your account',
    'Tu app de Spotify': 'Your Spotify app',
    'Abrir el panel': 'Open dashboard',
    'Guardar y continuar': 'Save and continue',
    'Olvidar el Client ID guardado': 'Forget saved Client ID',
    'Esperando al navegador…': 'Waiting for browser…',
    'Iniciar sesión con Spotify': 'Log in with Spotify',
    'Solo la primera vez pide enlazar dos veces.':
        'Only the first time requires linking twice.',
    'Guarda el Client ID antes de continuar.':
        'Save your Client ID before continuing.',
    'Hace falta una cuenta Spotify Premium: es la propia API la que exige Premium para controlar la reproducción.':
        'A Spotify Premium account is required: Spotify’s Web API restricts playback control to Premium.',
    'Toda tu música de Spotify en un cliente nativo y optimizado para el día a día sin perder funciones por el camino':
        'All your Spotify music in a native client optimized for everyday listening without sacrificing features',
    'Por cómo funciona Spotify, cada usuario necesita crear su propia app y autorizarla: NeoFy no viene configurada. No te preocupes, es rápido y solo hay que hacerlo una vez.':
        'Due to how Spotify works, each user needs to create and authorize their own app—NeoFy does not ship preconfigured. Don’t worry, it’s quick and only needed once.',
    'Crea una app en el panel de Spotify y marca «Web API».':
        'Create an app in the Spotify Dashboard and check “Web API”.',
    'Pon este Redirect URI, exactamente así: 127.0.0.1.':
        'Set this exact Redirect URI: 127.0.0.1.',
    'Copia el Client ID de tu app y pégalo aquí.':
        'Copy your app’s Client ID and paste it here.',
    '¿Sin Premium?': 'No Premium?',
    'Esperando el login…': 'Waiting for login…',
    'Volver a conectar YouTube Music': 'Reconnect YouTube Music',
    'Conectar YouTube Music': 'Connect YouTube Music',
    'YouTube Music está conectado. Si tu cuenta de Spotify no es Premium, la música sonará desde aquí.':
        'YouTube Music is connected. If your Spotify account isn’t Premium, playback will stream from here.',
    'La API de Spotify exige Premium para controlar la reproducción. Si tu cuenta es gratuita, conecta tu cuenta de YouTube Music para escuchar tu música en NeoFy.':
        'Spotify’s API requires Premium for playback control. If you have a free account, connect YouTube Music to listen in NeoFy.',
    'Falta un permiso para la portada': 'Missing permission for Home',
    'Hace falta un permiso más': 'One more permission is needed',
    'Para ver tus canciones guardadas necesitas dar el permiso «user-library-read».\n\nSolo tienes que volver a iniciar sesión en Spotify. No perderás nada.':
        'To view your saved songs, you need to grant the “user-library-read” permission.\n\nJust log in to Spotify again. You won’t lose anything.',
    'Tu sesión se inició sin permiso para seguir artistas en Spotify. Hay que volver a pasar por Spotify otra vez.':
        'Your session doesn’t have permission to follow artists on Spotify. Please sign in with Spotify again.',
    'Tu sesión se inició sin permiso para editar favoritos. Hay que volver a pasar por Spotify otra vez.':
        'Your session doesn’t have permission to edit your library. Please sign in with Spotify again.',
    'Tu sesión se inició sin permiso para editar tus playlists. Hay que volver a pasar por Spotify otra vez.':
        'Your session doesn’t have permission to edit your playlists. Please sign in with Spotify again.',

    // Botones genéricos
    'Cancelar': 'Cancel',
    'Confirmar': 'Confirm',
    'Guardar': 'Save',
    'Cerrar': 'Close',
    'Reintentar': 'Retry',
    'Cambiar': 'Change',
    'Restablecer': 'Reset',
    'Actualizar': 'Update',
    'Instalar': 'Install',
    'Reiniciar': 'Restart',
    'Mostrar todos': 'Show all',
    'Mostrar menos': 'Show less',
  },
  'fr': {
    'Inicio': 'Accueil',
    'Buscar': 'Rechercher',
    'Biblioteca': 'Bibliothèque',
    'Cola': 'File d’attente',
    'Abrir cola': 'Ouvrir la file d’attente',
    'Añadir a la cola': 'Ajouter à la file d’attente',
    'Añadida a la cola': 'Ajouté à la file d’attente',
    'La cola está vacía.': 'La file d’attente est vide.',
    'Letra': 'Paroles',
    'Seguir letra': 'Suivre les paroles',
    'Vista previa de la letra': 'Aperçu des paroles',
    'Por letras': 'Par ligne',
    'Por palabras': 'Mot à mot',
    'Pista instrumental': 'Titre instrumental',
    'Reproducir': 'Lecture',
    'Reproducir aquí': 'Lire ici',
    'Reproduciendo': 'Lecture en cours',
    'Reproducción Actual': 'Lecture en cours',
    'Nada sonando': 'Aucune lecture en cours',
    'SONANDO AHORA': 'EN COURS DE LECTURE',
    'A continuación': 'À suivre',
    'A CONTINUACIÓN': 'À SUIVRE',
    'A continuación en la cola': 'À suivre dans la file d’attente',
    'Recientes': 'Écoutes récentes',
    'Última escucha': 'Écouté récemment',
    'Aleatorio': 'Aléatoire',
    'Canciones que te gustan': 'Titres likés',
    'Artistas seguidos': 'Artistes suivis',
    'TUS ARTISTAS SEGUIDOS': 'ARTISTES SUIVIS',
    'Playlists': 'Playlists',
    'TUS PLAYLISTS': 'VOS PLAYLISTS',
    'Seguir': 'Suivre',
    'Siguiendo': 'Abonné',
    'Tema': 'Thème',
    'Temas': 'Thèmes',
    'Automático': 'Automatique',
    'Claro': 'Clair',
    'Oscuro': 'Sombre',
    'Ajustes': 'Paramètres',
    'Apariencia e idioma': 'Apparence et langue',
    'Cuenta': 'Compte',
    'Cuenta conectada': 'Compte connecté',
    'Cuenta de Spotify': 'Compte Spotify',
    'Sesión conectada': 'Connecté',
    'Cerrar sesión': 'Déconnexion',
    'Iniciar sesión': 'Connexion',
    'Volver a iniciar sesión': 'Se reconnecter',
    'Salir': 'Déconnexion',
    'Temporizador de apagado': 'Minuteur de veille',
    'Desactivar temporizador': 'Désactiver le minuteur',
    'Al final de la canción': 'À la fin du titre',
    'Modo rendimiento': 'Mode performance',
    'Calidad de streaming': 'Qualité de streaming',
    'Rama de actualizaciones': 'Canal de mise à jour',
    'Estable': 'Stable',
    'Menús dentro del elemento': 'Menus intégrés',
    'Enviar un reporte': 'Envoyer un rapport',
    'Créditos': 'Crédits',
    'Ver créditos': 'Afficher les crédits',
    'De gira': 'En tournée',
    'Información sobre el artista': 'À propos de l’artiste',
    'Ir al artista': 'Aller à l’artiste',
    'Ir al álbum': 'Aller à l’album',
    'Ir a radio de la canción': 'Aller à la radio du titre',
    'Añadir a lista': 'Ajouter à la playlist',
    'Añadir a una playlist': 'Ajouter à une playlist',
    'Mover a carpeta': 'Déplacer vers un dossier',
    'Nueva carpeta': 'Nouveau dossier',
    'Nueva playlist': 'Nouvelle playlist',
    'Cancelar': 'Annuler',
    'Confirmar': 'Confirmer',
    'Guardar': 'Enregistrer',
    'Cerrar': 'Fermer',
    'Reintentar': 'Réessayer',
    'Cambiar': 'Changer',
    'Restablecer': 'Réinitialiser',
    'Actualizar': 'Mettre à jour',
    'Instalar': 'Installer',
    'Reiniciar': 'Redémarrer',
    'Mostrar todos': 'Tout afficher',
    'Mostrar menos': 'Afficher moins',
    'Canción': 'Titre',
    'Álbum': 'Album',
    'Duración': 'Durée',
  },
  'de': {
    'Inicio': 'Start',
    'Buscar': 'Suchen',
    'Biblioteca': 'Bibliothek',
    'Cola': 'Warteschlange',
    'Abrir cola': 'Warteschlange öffnen',
    'Añadir a la cola': 'Zur Warteschlange hinzufügen',
    'Añadida a la cola': 'Zur Warteschlange hinzugefügt',
    'La cola está vacía.': 'Die Warteschlange ist leer.',
    'Letra': 'Songtext',
    'Seguir letra': 'Songtext folgen',
    'Vista previa de la letra': 'Songtext-Vorschau',
    'Por letras': 'Zeilenweise',
    'Por palabras': 'Wortweise',
    'Pista instrumental': 'Instrumentalstück',
    'Reproducir': 'Abspielen',
    'Reproducir aquí': 'Hier abspielen',
    'Reproduciendo': 'Aktuelle Wiedergabe',
    'Reproducción Actual': 'Aktuelle Wiedergabe',
    'Nada sonando': 'Keine Wiedergabe',
    'SONANDO AHORA': 'AKTUELL LÄUFT',
    'A continuación': 'Als Nächstes',
    'A CONTINUACIÓN': 'ALS NÄCHSTES',
    'A continuación en la cola': 'Als Nächstes in der Warteschlange',
    'Recientes': 'Zuletzt gehört',
    'Última escucha': 'Zuletzt gehört',
    'Aleatorio': 'Zufallswiedergabe',
    'Canciones que te gustan': 'Lieblingssongs',
    'Artistas seguidos': 'Gefolgte Künstler',
    'TUS ARTISTAS SEGUIDOS': 'GEFOLGTE KÜNSTLER',
    'Playlists': 'Playlists',
    'TUS PLAYLISTS': 'DEINE PLAYLISTS',
    'Seguir': 'Folgen',
    'Siguiendo': 'Folge ich',
    'Tema': 'Design',
    'Temas': 'Designs',
    'Automático': 'Automatisch',
    'Claro': 'Hell',
    'Oscuro': 'Dunkel',
    'Ajustes': 'Einstellungen',
    'Apariencia e idioma': 'Erscheinungsbild & Sprache',
    'Cuenta': 'Konto',
    'Cuenta conectada': 'Verbundenes Konto',
    'Cuenta de Spotify': 'Spotify-Konto',
    'Sesión conectada': 'Angemeldet',
    'Cerrar sesión': 'Abmelden',
    'Iniciar sesión': 'Anmelden',
    'Volver a iniciar sesión': 'Erneut anmelden',
    'Salir': 'Abmelden',
    'Temporizador de apagado': 'Sleep-Timer',
    'Desactivar temporizador': 'Timer ausschalten',
    'Al final de la canción': 'Am Ende des Titels',
    'Modo rendimiento': 'Leistungsmodus',
    'Calidad de streaming': 'Streaming-Qualität',
    'Rama de actualizaciones': 'Update-Kanal',
    'Estable': 'Stabil',
    'Menús dentro del elemento': 'Inline-Menüs',
    'Enviar un reporte': 'Bericht senden',
    'Créditos': 'Mitwirkende',
    'Ver créditos': 'Mitwirkende anzeigen',
    'De gira': 'Auf Tour',
    'Información sobre el artista': 'Über den Künstler',
    'Ir al artista': 'Zum Künstler',
    'Ir al álbum': 'Zum Album',
    'Ir a radio de la canción': 'Zum Song-Radio',
    'Añadir a lista': 'Zur Playlist hinzufügen',
    'Añadir a una playlist': 'Zu einer Playlist hinzufügen',
    'Mover a carpeta': 'In Ordner verschieben',
    'Nueva carpeta': 'Neuer Ordner',
    'Nueva playlist': 'Neue Playlist',
    'Cancelar': 'Abbrechen',
    'Confirmar': 'Bestätigen',
    'Guardar': 'Speichern',
    'Cerrar': 'Schließen',
    'Reintentar': 'Erneut versuchen',
    'Cambiar': 'Ändern',
    'Restablecer': 'Zurücksetzen',
    'Actualizar': 'Aktualisieren',
    'Instalar': 'Installieren',
    'Reiniciar': 'Neu starten',
    'Mostrar todos': 'Alle anzeigen',
    'Mostrar menos': 'Weniger anzeigen',
    'Canción': 'Titel',
    'Álbum': 'Album',
    'Duración': 'Dauer',
  },
  'pt': {
    'Inicio': 'Início',
    'Buscar': 'Buscar',
    'Biblioteca': 'Biblioteca',
    'Cola': 'Fila',
    'Abrir cola': 'Abrir fila',
    'Añadir a la cola': 'Adicionar à fila',
    'Añadida a la cola': 'Adicionada à fila',
    'La cola está vacía.': 'A fila está vazia.',
    'Letra': 'Letra',
    'Seguir letra': 'Seguir letra',
    'Vista previa de la letra': 'Prévia da letra',
    'Por letras': 'Por linhas',
    'Por palabras': 'Por palavras',
    'Pista instrumental': 'Faixa instrumental',
    'Reproducir': 'Reproduzir',
    'Reproducir aquí': 'Reproduzir aqui',
    'Reproduciendo': 'Tocando agora',
    'Reproducción Actual': 'Tocando agora',
    'Nada sonando': 'Nada tocando',
    'SONANDO AHORA': 'TOCANDO AGORA',
    'A continuación': 'A seguir',
    'A CONTINUACIÓN': 'A SEGUIR',
    'A continuación en la cola': 'A seguir na fila',
    'Recientes': 'Tocados recentemente',
    'Última escucha': 'Tocado recentemente',
    'Aleatorio': 'Aleatório',
    'Canciones que te gustan': 'Músicas curtidas',
    'Artistas seguidos': 'Artistas seguidos',
    'TUS ARTISTAS SEGUIDOS': 'ARTISTAS SEGUIDOS',
    'Playlists': 'Playlists',
    'TUS PLAYLISTS': 'SUAS PLAYLISTS',
    'Seguir': 'Seguir',
    'Siguiendo': 'Seguindo',
    'Tema': 'Tema',
    'Temas': 'Temas',
    'Automático': 'Automático',
    'Claro': 'Claro',
    'Oscuro': 'Escuro',
    'Ajustes': 'Configurações',
    'Apariencia e idioma': 'Aparência e idioma',
    'Cuenta': 'Conta',
    'Cuenta conectada': 'Conta conectada',
    'Cuenta de Spotify': 'Conta do Spotify',
    'Sesión conectada': 'Conectado',
    'Cerrar sesión': 'Sair',
    'Iniciar sesión': 'Entrar',
    'Volver a iniciar sesión': 'Entrar novamente',
    'Salir': 'Sair',
    'Temporizador de apagado': 'Temporizador',
    'Desactivar temporizador': 'Desativar temporizador',
    'Al final de la canción': 'No fim da música',
    'Modo rendimiento': 'Modo de desempenho',
    'Calidad de streaming': 'Qualidade de streaming',
    'Rama de actualizaciones': 'Canal de atualizações',
    'Estable': 'Estável',
    'Menús dentro del elemento': 'Menus integrados',
    'Enviar un reporte': 'Enviar um relatório',
    'Créditos': 'Créditos',
    'Ver créditos': 'Mostrar créditos',
    'De gira': 'Em turnê',
    'Información sobre el artista': 'Sobre o artista',
    'Ir al artista': 'Ir para o artista',
    'Ir al álbum': 'Ir para o álbum',
    'Ir a radio de la canción': 'Ir para a rádio da música',
    'Añadir a lista': 'Adicionar à playlist',
    'Añadir a una playlist': 'Adicionar a uma playlist',
    'Mover a carpeta': 'Mover para pasta',
    'Nueva carpeta': 'Nova pasta',
    'Nueva playlist': 'Nova playlist',
    'Cancelar': 'Cancelar',
    'Confirmar': 'Confirmar',
    'Guardar': 'Salvar',
    'Cerrar': 'Fechar',
    'Reintentar': 'Tentar novamente',
    'Cambiar': 'Alterar',
    'Restablecer': 'Redefinir',
    'Actualizar': 'Atualizar',
    'Instalar': 'Instalar',
    'Reiniciar': 'Reiniciar',
    'Mostrar todos': 'Mostrar tudo',
    'Mostrar menos': 'Mostrar menos',
    'Canción': 'Música',
    'Álbum': 'Álbum',
    'Duración': 'Duração',
  },
  'it': {
    'Inicio': 'Home',
    'Buscar': 'Cerca',
    'Biblioteca': 'Libreria',
    'Cola': 'Coda',
    'Abrir cola': 'Apri coda',
    'Añadir a la cola': 'Aggiungi alla coda',
    'Añadida a la cola': 'Aggiunto alla coda',
    'La cola está vacía.': 'La coda è vuota.',
    'Letra': 'Testo',
    'Seguir letra': 'Segui testo',
    'Vista previa de la letra': 'Anteprima testo',
    'Por letras': 'Per righe',
    'Por palabras': 'Per parole',
    'Pista instrumental': 'Traccia strumentale',
    'Reproducir': 'Riproduci',
    'Reproducir aquí': 'Riproduci qui',
    'Reproduciendo': 'In riproduzione',
    'Reproducción Actual': 'In riproduzione',
    'Nada sonando': 'Nessuna riproduzione',
    'SONANDO AHORA': 'IN RIPRODUZIONE',
    'A continuación': 'Successivi',
    'A CONTINUACIÓN': 'SUCCESSIVI',
    'A continuación en la cola': 'Prossimo in coda',
    'Recientes': 'Ascoltati di recente',
    'Última escucha': 'Ascoltato di recente',
    'Aleatorio': 'Casuale',
    'Canciones que te gustan': 'Brani che ti piacciono',
    'Artistas seguidos': 'Artisti seguiti',
    'TUS ARTISTAS SEGUIDOS': 'ARTISTI SEGUITI',
    'Playlists': 'Playlist',
    'TUS PLAYLISTS': 'LE TUE PLAYLIST',
    'Seguir': 'Segui',
    'Siguiendo': 'Segui già',
    'Tema': 'Tema',
    'Temas': 'Temi',
    'Automático': 'Automatico',
    'Claro': 'Chiaro',
    'Oscuro': 'Scuro',
    'Ajustes': 'Impostazioni',
    'Apariencia e idioma': 'Aspetto e lingua',
    'Cuenta': 'Account',
    'Cuenta conectada': 'Account collegato',
    'Cuenta de Spotify': 'Account Spotify',
    'Sesión conectada': 'Accesso effettuato',
    'Cerrar sesión': 'Esci',
    'Iniciar sesión': 'Accedi',
    'Volver a iniciar sesión': 'Accedi di nuovo',
    'Salir': 'Esci',
    'Temporizador de apagado': 'Timer di spegnimento',
    'Desactivar temporizador': 'Disattiva timer',
    'Al final de la canción': 'Alla fine del brano',
    'Modo rendimiento': 'Modalità prestazioni',
    'Calidad de streaming': 'Qualità streaming',
    'Rama de actualizaciones': 'Canale di aggiornamento',
    'Estable': 'Stabile',
    'Menús dentro del elemento': 'Menu integrati',
    'Enviar un reporte': 'Invia segnalazione',
    'Créditos': 'Crediti',
    'Ver créditos': 'Mostra crediti',
    'De gira': 'In tour',
    'Información sobre el artista': 'Informazioni sull’artista',
    'Ir al artista': 'Vai all’artista',
    'Ir al álbum': 'Vai all’album',
    'Ir a radio de la canción': 'Vai alla radio del brano',
    'Añadir a lista': 'Aggiungi alla playlist',
    'Añadir a una playlist': 'Aggiungi a una playlist',
    'Mover a carpeta': 'Sposta nella cartella',
    'Nueva carpeta': 'Nuova cartella',
    'Nueva playlist': 'Nuova playlist',
    'Cancelar': 'Annulla',
    'Confirmar': 'Conferma',
    'Guardar': 'Salva',
    'Cerrar': 'Chiudi',
    'Reintentar': 'Riprova',
    'Cambiar': 'Cambia',
    'Restablecer': 'Ripristina',
    'Actualizar': 'Aggiorna',
    'Instalar': 'Installa',
    'Reiniciar': 'Riavvia',
    'Mostrar todos': 'Mostra tutto',
    'Mostrar menos': 'Mostra meno',
    'Canción': 'Brano',
    'Álbum': 'Album',
    'Duración': 'Durata',
  },
};

final _reSoloCanciones = RegExp(r'^(\d+) canciones$');
final _reDetallePlaylist = RegExp(r'^(.+) · (\d+) canciones$');
final _reSeguidores = RegExp(r'^(.+) seguidores$');
final _reVolverA = RegExp(r'^Volver a (.+)$');
final _rePlaylistsDe = RegExp(r'^Listas de reproducción de (.+)$');
final _rePodcastDe = RegExp(r'^Pódcast · (.+)$');
final _reSinIdioma = RegExp(r'^Ningún idioma coincide con «(.+)»\.$');
final _reClientId = RegExp(r'^Client ID guardado: (.+)$');
final _reProgresoPlaylists = RegExp(r'^(\d+) de (\d+) playlists$');
final _reTotalPlaylists = RegExp(r'^(\d+) playlists$');
final _reDescargando = RegExp(r'^Descargando… (\d+) %$');
final _reEstableDisp = RegExp(r'^Versión estable disponible: (.+)$');
final _rePreviewDisp = RegExp(r'^Hay una versión preview nueva: (.+)$');
final _reNuevaDisp = RegExp(r'^Hay una versión nueva: (.+)$');

String _etiquetaCanciones(String idioma, int n) => switch (idioma) {
  'en' => n == 1 ? '1 song' : '$n songs',
  'fr' => n == 1 ? '1 titre' : '$n titres',
  'de' => n == 1 ? '1 Titel' : '$n Titel',
  'pt' => n == 1 ? '1 música' : '$n músicas',
  'it' => n == 1 ? '1 brano' : '$n brani',
  _ => '$n canciones',
};

String? _traducirPatron(String idioma, String texto) {
  if (!_diccionarioPorIdioma.containsKey(idioma)) return null;

  if (_reSoloCanciones.firstMatch(texto) case final m?) {
    final n = int.parse(m.group(1)!);
    return _etiquetaCanciones(idioma, n);
  }
  if (_reDetallePlaylist.firstMatch(texto) case final m?) {
    final autor = m.group(1)!;
    final n = int.parse(m.group(2)!);
    return '$autor · ${_etiquetaCanciones(idioma, n)}';
  }
  if (_reSeguidores.firstMatch(texto) case final m?) {
    final cuenta = m.group(1)!;
    return switch (idioma) {
      'en' => '$cuenta followers',
      'fr' => '$cuenta abonnés',
      'de' => '$cuenta Follower',
      'pt' => '$cuenta seguidores',
      'it' => '$cuenta follower',
      _ => null,
    };
  }
  if (_reVolverA.firstMatch(texto) case final m?) {
    final destino = m.group(1)!;
    return switch (idioma) {
      'en' => 'Back to $destino',
      'fr' => 'Retour à $destino',
      'de' => 'Zurück zu $destino',
      'pt' => 'Voltar para $destino',
      'it' => 'Torna a $destino',
      _ => null,
    };
  }
  if (_rePlaylistsDe.firstMatch(texto) case final m?) {
    final artista = m.group(1)!;
    return switch (idioma) {
      'en' => 'Playlists featuring $artista',
      'fr' => 'Playlists avec $artista',
      'de' => 'Playlists mit $artista',
      'pt' => 'Playlists com $artista',
      'it' => 'Playlist con $artista',
      _ => null,
    };
  }
  if (_rePodcastDe.firstMatch(texto) case final m?) {
    final autor = m.group(1)!;
    return switch (idioma) {
      'en' => 'Podcast · $autor',
      'fr' => 'Podcast · $autor',
      'de' => 'Podcast · $autor',
      'pt' => 'Podcast · $autor',
      'it' => 'Podcast · $autor',
      _ => null,
    };
  }
  if (_reSinIdioma.firstMatch(texto) case final m?) {
    final q = m.group(1)!;
    return switch (idioma) {
      'en' => 'No language matches “$q”.',
      'fr' => 'Aucune langue ne correspond à « $q ».',
      'de' => 'Keine Sprache entspricht „$q“.',
      'pt' => 'Nenhum idioma corresponde a “$q”.',
      'it' => 'Nessuna lingua corrisponde a “$q”.',
      _ => null,
    };
  }
  if (_reClientId.firstMatch(texto) case final m?) {
    final id = m.group(1)!;
    return switch (idioma) {
      'en' => 'Saved Client ID: $id',
      'fr' => 'Client ID enregistré : $id',
      'de' => 'Gespeicherte Client-ID: $id',
      'pt' => 'Client ID salvo: $id',
      'it' => 'Client ID salvato: $id',
      _ => null,
    };
  }
  if (_reProgresoPlaylists.firstMatch(texto) case final m?) {
    final a = m.group(1)!;
    final b = m.group(2)!;
    return switch (idioma) {
      'en' => '$a of $b playlists',
      'fr' => '$a sur $b playlists',
      'de' => '$a von $b Playlists',
      'pt' => '$a de $b playlists',
      'it' => '$a di $b playlist',
      _ => null,
    };
  }
  if (_reTotalPlaylists.firstMatch(texto) case final m?) {
    final n = m.group(1)!;
    return switch (idioma) {
      'en' => '$n playlists',
      'fr' => '$n playlists',
      'de' => '$n Playlists',
      'pt' => '$n playlists',
      'it' => '$n playlist',
      _ => null,
    };
  }
  if (_reDescargando.firstMatch(texto) case final m?) {
    final p = m.group(1)!;
    return switch (idioma) {
      'en' => 'Downloading… $p%',
      'fr' => 'Téléchargement… $p %',
      'de' => 'Wird heruntergeladen… $p %',
      'pt' => 'Baixando… $p%',
      'it' => 'Download in corso… $p%',
      _ => null,
    };
  }
  if (_reEstableDisp.firstMatch(texto) case final m?) {
    final v = m.group(1)!;
    return switch (idioma) {
      'en' => 'Stable version available: $v',
      'fr' => 'Version stable disponible : $v',
      'de' => 'Stabile Version verfügbar: $v',
      'pt' => 'Versão estável disponível: $v',
      'it' => 'Versione stabile disponibile: $v',
      _ => null,
    };
  }
  if (_rePreviewDisp.firstMatch(texto) case final m?) {
    final v = m.group(1)!;
    return switch (idioma) {
      'en' => 'New preview version available: $v',
      'fr' => 'Nouvelle version preview disponible : $v',
      'de' => 'Neue Preview-Version verfügbar: $v',
      'pt' => 'Nova versão preview disponível: $v',
      'it' => 'Nuova versione preview disponibile: $v',
      _ => null,
    };
  }
  if (_reNuevaDisp.firstMatch(texto) case final m?) {
    final v = m.group(1)!;
    return switch (idioma) {
      'en' => 'New version available: $v',
      'fr' => 'Nouvelle version disponible : $v',
      'de' => 'Neue Version verfügbar: $v',
      'pt' => 'Nova versão disponível: $v',
      'it' => 'Nuova versione disponibile: $v',
      _ => null,
    };
  }

  return null;
}
