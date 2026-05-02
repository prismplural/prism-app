// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get cancel => 'Cancelar';

  @override
  String get save => 'Guardar';

  @override
  String get delete => 'Eliminar';

  @override
  String get edit => 'Editar';

  @override
  String get add => 'Agregar';

  @override
  String get done => 'Listo';

  @override
  String get close => 'Cerrar';

  @override
  String get confirm => 'Confirmar';

  @override
  String get back => 'Atrás';

  @override
  String get options => 'Opciones';

  @override
  String get activate => 'Activar';

  @override
  String get deactivate => 'Desactivar';

  @override
  String get loading => 'Cargando…';

  @override
  String get tryAgain => 'Intentar de nuevo';

  @override
  String get search => 'Buscar';

  @override
  String get error => 'Error';

  @override
  String get suggestions => 'Sugerencias:';

  @override
  String get unknown => 'Desconocido';

  @override
  String get tapToSet => 'Toca para establecer';

  @override
  String get navigationBar => 'Barra de navegación';

  @override
  String get mainNavigation => 'Navegación principal';

  @override
  String get closeMenu => 'Cerrar menú';

  @override
  String get moreTabs => 'Más pestañas';

  @override
  String navUnreadCount(String label, int count) {
    return '$label, $count sin leer';
  }

  @override
  String errorLoadingMembers(String members, Object error) {
    return 'Error al cargar $members: $error';
  }

  @override
  String selectMember(String term) {
    return 'Seleccionar $term';
  }

  @override
  String selectMembers(String termPlural) {
    return 'Seleccionar $termPlural';
  }

  @override
  String selectAMember(String termLower) {
    return 'Seleccionar $termLower';
  }

  @override
  String errorWithDetail(Object detail) {
    return 'Error: $detail';
  }

  @override
  String get segmentedControl => 'Control segmentado';

  @override
  String get dismissNotification => 'Descartar notificación';

  @override
  String get searchEmoji => 'Buscar emoji...';

  @override
  String get dismiss => 'Descartar';

  @override
  String get destructiveAction => 'Acción destructiva';

  @override
  String noMembersFound(String termPlural) {
    return 'No se encontraron $termPlural';
  }

  @override
  String get moreOptions => 'Más opciones';

  @override
  String get settingsSectionSystem => 'Sistema';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionData => 'Datos';

  @override
  String get settingsSystemInformation => 'Información del sistema';

  @override
  String get settingsGroups => 'Grupos';

  @override
  String get settingsCustomFields => 'Campos personalizados';

  @override
  String get settingsStatistics => 'Estadísticas';

  @override
  String get settingsAppearance => 'Apariencia';

  @override
  String get settingsNavigation => 'Navegación';

  @override
  String get settingsFeatures => 'Funciones';

  @override
  String get settingsPrivacySecurity => 'Privacidad y seguridad';

  @override
  String get settingsNotifications => 'Notificaciones';

  @override
  String get settingsSync => 'Prism Sync';

  @override
  String get settingsSharing => 'Compartir';

  @override
  String get settingsImportExport => 'Importar y exportar';

  @override
  String get settingsResetData => 'Restablecer datos';

  @override
  String get settingsAbout => 'Sobre Prism';

  @override
  String get settingsDebug => 'Depuración';

  @override
  String get settingsFallbackSystemName => 'Mi sistema';

  @override
  String get settingsLanguageTitle => 'Idioma';

  @override
  String get settingsLanguageSubtitle =>
      'Sigue la configuración de tu dispositivo';

  @override
  String get appearanceTitle => 'Apariencia';

  @override
  String get appearanceBrightness => 'Brillo';

  @override
  String get appearanceStyle => 'Estilo';

  @override
  String get appearanceUsesSystemPalette =>
      'Usa la paleta de colores del sistema';

  @override
  String get appearanceCornerStyleTitle => 'Estilo de esquinas';

  @override
  String get appearanceCornerStyleRounded => 'Redondeadas';

  @override
  String get appearanceCornerStyleAngular => 'Angulares';

  @override
  String get appearanceCornerStyleDescription =>
      'Elige entre esquinas redondeadas o angulares en toda la app.';

  @override
  String get appearanceAccentColor => 'Color de acento';

  @override
  String appearancePerMemberColors(String term) {
    return 'Colores por $term';
  }

  @override
  String appearancePerMemberColorsSwitchTitle(String term) {
    return 'Colores de acento por $term';
  }

  @override
  String appearancePerMemberColorsSwitchSubtitle(String term) {
    return 'Permite que cada $term tenga su propio color';
  }

  @override
  String get appearanceSyncSection => 'Sincronización';

  @override
  String get appearanceSyncThemeTitle => 'Sincronizar tema entre dispositivos';

  @override
  String get appearanceSyncThemeSubtitle =>
      'Compartir brillo, estilo y color de acento vía sincronización';

  @override
  String get appearanceTerminology => 'Terminología';

  @override
  String get appearanceLanguage => 'Idioma';

  @override
  String get appearanceLanguageSystem => 'Predeterminado del sistema';

  @override
  String get appearanceLanguageFooter => 'Más idiomas próximamente';

  @override
  String get appearancePreview => 'Vista previa';

  @override
  String get appearanceSamplePronouns => 'ella';

  @override
  String appearanceSampleMember(String term) {
    return '$term de ejemplo';
  }

  @override
  String get appearanceFronting => 'Al frente';

  @override
  String get syncTitle => 'Prism Sync';

  @override
  String get syncDisconnectedTitle => 'La sincronización fue desconectada';

  @override
  String get syncDisconnectedMessage =>
      'Configura la sincronización de nuevo para reconectar tus dispositivos.';

  @override
  String get syncSetUpSyncButton => 'Configurar sincronización';

  @override
  String get syncUnableToLoad =>
      'No se pudo cargar la configuración de sincronización';

  @override
  String get syncNotSetUp => 'La sincronización no está configurada';

  @override
  String get syncNotSetUpDescription =>
      'Configura la sincronización cifrada de extremo a extremo para mantener tus datos sincronizados en todos tus dispositivos.';

  @override
  String get syncSetupButton => 'Configurar sincronización';

  @override
  String get syncNowTitle => 'Sincronizar ahora';

  @override
  String get syncNowSubtitle =>
      'Verificar cambios y enviar actualizaciones locales';

  @override
  String get syncInProgress => 'Sincronizando…';

  @override
  String get syncSetUpAnotherDevice => 'Configurar otro dispositivo';

  @override
  String get syncSetUpAnotherDeviceSubtitle =>
      'Generar un código QR de emparejamiento';

  @override
  String get syncManageDevices => 'Administrar dispositivos';

  @override
  String get syncManageDevicesSubtitle =>
      'Ver y revocar dispositivos vinculados';

  @override
  String get syncChangePassword => 'Cambiar PIN';

  @override
  String get syncChangePasswordSubtitle =>
      'Actualizar tu PIN de cifrado de sincronización';

  @override
  String get syncViewSecretKey => 'Ver clave secreta';

  @override
  String get syncViewSecretKeySubtitle =>
      'Mostrar tu frase de recuperación de 12 palabras';

  @override
  String get syncPreferencesSection => 'Preferencias de sincronización';

  @override
  String get syncPreferencesDescription =>
      'Controla qué configuraciones se comparten entre tus dispositivos vía sincronización.';

  @override
  String get syncNavigationLayoutTitle => 'Sincronizar diseño de navegación';

  @override
  String get syncNavigationLayoutSubtitle =>
      'Compartir disposición de pestañas entre dispositivos';

  @override
  String get syncAppearanceToggleTitle =>
      'Sincronizar apariencia entre dispositivos';

  @override
  String get syncAppearanceToggleDescription =>
      'Comparte el tema, el color de acento y el estilo de esquinas entre tus dispositivos vinculados.';

  @override
  String get syncIgnoreAppearanceTitle =>
      'Ignorar apariencia sincronizada en este dispositivo';

  @override
  String get syncIgnoreAppearanceDescription =>
      'Usa la configuración de apariencia local en este dispositivo. Los cambios aquí se siguen sincronizando con otros dispositivos si el uso compartido está activo.';

  @override
  String get navigationShowViewToggleTitle =>
      'Mostrar botón de vista en Inicio';

  @override
  String get navigationShowViewToggleSubtitle =>
      'Mostrar el botón para alternar entre cronología y lista en la barra superior de la pestaña Inicio.';

  @override
  String get syncIssuesSection => 'Problemas de sincronización';

  @override
  String get syncIssuesDescription =>
      'Estos registros no se pudieron aplicar por incompatibilidad de tipos. Limpiarlos elimina el indicador de advertencia.';

  @override
  String get syncClearAll => 'Limpiar todo';

  @override
  String get syncDetailsSection => 'Detalles';

  @override
  String get syncRelayLabel => 'Relay';

  @override
  String get syncIdLabel => 'ID de sincronización';

  @override
  String get syncNodeIdLabel => 'ID de nodo';

  @override
  String get syncNodeIdNotInitialised => 'No inicializado';

  @override
  String get syncTroubleshootingLink => 'Solución de problemas';

  @override
  String get syncLast24h => 'Sincronizado últimas 24h';

  @override
  String get syncTotal => 'Total sincronizado';

  @override
  String syncEntitiesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entidades',
      one: '1 entidad',
    );
    return '$_temp0';
  }

  @override
  String get syncFinished => 'Sincronización finalizada';

  @override
  String syncFailed(Object error) {
    return 'Error de sincronización: $error';
  }

  @override
  String get syncStatusError => 'Error de sincronización';

  @override
  String get syncStatusSyncing => 'Sincronizando';

  @override
  String get syncStatusSyncInProgress => 'Sincronización en curso…';

  @override
  String get syncStatusSyncedWithIssues => 'Sincronizado con problemas';

  @override
  String get syncStatusLastSynced => 'Última sincronización';

  @override
  String get syncStatusReadyToSync => 'Listo para sincronizar';

  @override
  String get syncStatusWaiting => 'Esperando cambios.';

  @override
  String get syncStatusNeedsReconnect => 'Necesita reconexión';

  @override
  String get syncStatusTapToReconnect =>
      'Toca Sincronizar ahora para reconectar.';

  @override
  String get syncRealTimeConnected => 'Tiempo real conectado';

  @override
  String get syncRealTimeDisconnected => 'Tiempo real desconectado';

  @override
  String get syncJustNow => 'Ahora mismo';

  @override
  String syncMinutesAgo(int count) {
    return 'hace ${count}m';
  }

  @override
  String syncHoursAgo(int count) {
    return 'hace ${count}h';
  }

  @override
  String syncDaysAgo(int count) {
    return 'hace ${count}d';
  }

  @override
  String get syncSetupIntroTitle => 'Configurar sincronización';

  @override
  String get syncSetupSecretKeyTitle => 'Tu clave secreta';

  @override
  String get syncSetupIntroHeadline =>
      'Mantén tus datos sincronizados en todos tus dispositivos.';

  @override
  String get syncSetupIntroBody =>
      'Todo está cifrado de extremo a extremo — el servidor nunca ve tus datos. Crearás una contraseña y recibirás una clave de recuperación para guardar. Necesitarás tu frase de recuperación de 12 palabras para continuar. Tenla a mano.';

  @override
  String get syncSetupSelfHosted => '¿Relay propio?';

  @override
  String get syncSetupRelayUrlLabel => 'URL del relay';

  @override
  String get syncSetupRegistrationToken => 'Token de registro';

  @override
  String get syncSetupRegistrationTokenHint => 'Opcional';

  @override
  String get syncSetupRegistrationTokenHelp =>
      'Requerido si tu relay tiene habilitado el control de registro.';

  @override
  String get syncSetupRelayUrlError =>
      'La URL del relay debe comenzar con https://';

  @override
  String get syncSetupCompleteButton => 'Completar configuración';

  @override
  String get syncSetupPinLabel => 'PIN de la app';

  @override
  String get syncSetupProgressCreatingGroup =>
      'Creando grupo de sincronización...';

  @override
  String get syncSetupProgressConfiguringEngine => 'Configurando cifrado...';

  @override
  String get syncSetupProgressCachingKeys => 'Asegurando claves...';

  @override
  String get syncSetupProgressBootstrapping =>
      'Preparando tus datos para sincronizar';

  @override
  String get syncSetupProgressMeasuringSnapshot =>
      'Comprobando el tamaño de los datos';

  @override
  String get syncSecretKeyTitle => 'Clave secreta';

  @override
  String get syncSecretKeyNotStoredTitle =>
      'Frase de recuperación no almacenada';

  @override
  String get syncSecretKeyNotStoredBody =>
      'Tu frase de recuperación no se guarda en este dispositivo — se mostró una sola vez durante la configuración.\n\nSi la guardaste (por ejemplo, en un gestor de contraseñas o en un papel), búscala allí.\n\nSi no puedes encontrarla, desconecta este dispositivo y vuelve a emparejarlo para generar una nueva frase.';

  @override
  String get syncVerifyPasswordTitle => 'Verificar PIN';

  @override
  String get syncVerifyPasswordPrompt =>
      'Ingresa tu PIN de la app para revelar tu frase de recuperación de 12 palabras.';

  @override
  String get syncPasswordHint => 'PIN';

  @override
  String get syncRevealSecretKey => 'Revelar clave secreta';

  @override
  String get syncSecretKeyNotFound =>
      'Clave secreta no encontrada en el llavero.';

  @override
  String get syncEngineNotAvailable => 'Motor de sincronización no disponible.';

  @override
  String get syncIncorrectPassword => 'PIN incorrecto. Inténtalo de nuevo.';

  @override
  String syncAnErrorOccurred(Object error) {
    return 'Ocurrió un error: $error';
  }

  @override
  String get privacySecurityTitle => 'Privacidad y seguridad';

  @override
  String get pinLockSection => 'Bloqueo por PIN';

  @override
  String get pinLockEnableTitle => 'Activar bloqueo por PIN';

  @override
  String get pinLockEnableSubtitle => 'Requerir un PIN para abrir la app';

  @override
  String get pinLockBiometricSection => 'Biométrico';

  @override
  String get pinLockBiometricTitle => 'Desbloqueo biométrico';

  @override
  String get pinLockBiometricSubtitle =>
      'Usa Face ID o huella digital para desbloquear';

  @override
  String get pinLockBiometricDisabledSubtitle =>
      'Activa el bloqueo por PIN para usar el desbloqueo biométrico';

  @override
  String get pinLockUnlockOptionsSection => 'Opciones de desbloqueo';

  @override
  String get pinLockHardSyncLockTitle =>
      'Requerir recuperación para sincronizar';

  @override
  String get pinLockHardSyncLockSubtitle =>
      'Cuando la app se bloquee, olvida la clave de desbloqueo rápido de sincronización. La sincronización en segundo plano se pausa hasta que ingreses tu PIN y frase de recuperación.';

  @override
  String get pinLockHardSyncLockDisabledSubtitle =>
      'Activa el bloqueo por PIN para requerir recuperación después del bloqueo de la app.';

  @override
  String get pinLockAutoLockSection => 'Bloqueo automático';

  @override
  String get pinLockAfterLeaving => 'Bloquear al salir de la app';

  @override
  String get pinLockManageSection => 'Administrar';

  @override
  String get pinLockChange => 'Cambiar PIN';

  @override
  String get pinLockRemove => 'Eliminar PIN';

  @override
  String get pinLockSetTitle => 'Establecer PIN';

  @override
  String get pinLockConfirmTitle => 'Confirmar PIN';

  @override
  String get pinLockEnterTitle => 'Ingresar PIN';

  @override
  String get pinLockSetSubtitle => 'Elige un PIN de 6 dígitos';

  @override
  String get pinLockConfirmSubtitle =>
      'Vuelve a ingresar tu PIN para confirmar';

  @override
  String get pinLockUnlockSubtitle => 'Ingresa tu PIN para desbloquear';

  @override
  String get pinLockInstant => 'Inmediato';

  @override
  String get pinLock15s => '15s';

  @override
  String get pinLock1m => '1m';

  @override
  String get pinLock5m => '5m';

  @override
  String get pinLock15m => '15m';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsFrontingRemindersTitle => 'Recordatorios de frente';

  @override
  String get notificationsFrontingRemindersSubtitle =>
      'Recibe recordatorios para registrar cambios de frente';

  @override
  String get notificationsReminderIntervalTitle => 'Intervalo de recordatorio';

  @override
  String get notificationsReminderIntervalSubtitle =>
      'Con qué frecuencia enviar recordatorios';

  @override
  String get notificationsChatSection => 'Notificaciones de chat';

  @override
  String get notificationsBadgeAllMessages =>
      'Insignia para todos los mensajes';

  @override
  String notificationsBadgeMentionsOnly(String member) {
    return 'Solo las @menciones mostrarán insignia para $member';
  }

  @override
  String notificationsBadgeAllFor(String member) {
    return 'Todos los mensajes nuevos mostrarán insignia para $member';
  }

  @override
  String get notificationsPermissionStatus => 'Estado del permiso';

  @override
  String get notificationsCouldNotCheck =>
      'No se pudieron verificar los permisos';

  @override
  String get notificationsEnabled => 'Notificaciones activadas';

  @override
  String get notificationsPermissionGranted => 'Permiso concedido';

  @override
  String get notificationsNotEnabled => 'Notificaciones no activadas';

  @override
  String get notificationsPermissionRequired =>
      'Se requiere permiso para los recordatorios';

  @override
  String get notificationsRequest => 'Solicitar';

  @override
  String get notificationsAboutText =>
      'Los recordatorios de frente envían notificaciones periódicas para ayudarte a estar al tanto de quién está al frente. Esto puede ser útil para registrar cambios y mantener la conciencia durante el día.';

  @override
  String get notificationsAndroidFootnote =>
      'En Android, los recordatorios pueden llegar unos minutos tarde.';

  @override
  String get notificationsInterval15m => '15 minutos';

  @override
  String get notificationsInterval30m => '30 minutos';

  @override
  String get notificationsInterval1h => '1 hora';

  @override
  String get notificationsInterval2h => '2 horas';

  @override
  String get notificationsInterval4h => '4 horas';

  @override
  String get notificationsInterval8h => '8 horas';

  @override
  String get resetDataTitle => 'Restablecer datos';

  @override
  String get resetDataCategoriesSection => 'Categorías';

  @override
  String get resetDataCategoriesDescription =>
      'Restablece categorías específicas de datos en este dispositivo. El restablecimiento del sistema de sincronización elimina la configuración de sincronización sin borrar los datos de la app.';

  @override
  String get resetDataDangerZone => 'Zona de peligro';

  @override
  String resetDataConfirmTitle(String category) {
    return '¿Restablecer $category?';
  }

  @override
  String resetDataConfirmAll(String termPluralLower) {
    return 'Esto eliminará permanentemente todos tus datos, incluidos $termPluralLower, sesiones de frente, mensajes, encuestas, hábitos, datos de sueño y configuración. Esta acción no se puede deshacer.';
  }

  @override
  String get resetDataConfirmSync =>
      'Esto conserva los datos locales de la app, pero elimina las claves de sincronización, la configuración del relay, la identidad del dispositivo y el historial de sincronización de este dispositivo. Deberás configurar la sincronización de nuevo.';

  @override
  String resetDataConfirmCategory(String category) {
    return 'Esto eliminará permanentemente todos los datos de $category en este dispositivo. Esta acción no se puede deshacer.';
  }

  @override
  String get resetDataConfirmEverything => 'Restablecer todo';

  @override
  String get resetDataConfirmSync2 => 'Restablecer sincronización';

  @override
  String resetDataSuccess(String category) {
    return '$category restablecido correctamente';
  }

  @override
  String resetDataFailed(Object error) {
    return 'Error al restablecer: $error';
  }

  @override
  String get navigationSettingsTitle => 'Navegación';

  @override
  String get navigationPreferences => 'Preferencias';

  @override
  String get navigationLayoutSection => 'Diseño';

  @override
  String get navigationNavBar => 'Barra de navegación';

  @override
  String get navigationMoreMenu => 'Menú de más';

  @override
  String get navigationAvailable => 'Disponible';

  @override
  String get navigationDisabledFeatures => 'Funciones desactivadas';

  @override
  String get navigationEnableInFeatures => 'Activar en Funciones';

  @override
  String get navigationMoveToNavBar => 'Mover a barra de navegación';

  @override
  String get navigationMoveToMoreMenu => 'Mover al menú de más';

  @override
  String get navigationRemove => 'Eliminar de la navegación';

  @override
  String get navigationAddToNavBar => 'Agregar a la barra de navegación';

  @override
  String get navigationAddToMoreMenu => 'Agregar al menú de más';

  @override
  String get featuresTitle => 'Funciones';

  @override
  String get featuresDisablingHint =>
      'Desactivar una función la oculta de la navegación sin eliminar datos.';

  @override
  String get featuresEnabled => 'Activada';

  @override
  String get featuresDisabled => 'Desactivada';

  @override
  String get featureChatTitle => 'Chat';

  @override
  String get featureFrontingTitle => 'Frente';

  @override
  String get featureHabitsTitle => 'Hábitos';

  @override
  String get featureSleepTitle => 'Sueño';

  @override
  String get featurePollsTitle => 'Encuestas';

  @override
  String get featureNotesTitle => 'Notas';

  @override
  String get featureRemindersTitle => 'Recordatorios';

  @override
  String get statisticsTitle => 'Estadísticas';

  @override
  String get statisticsOverview => 'Resumen';

  @override
  String statisticsTotalMembers(String termPlural) {
    return 'Total de $termPlural';
  }

  @override
  String get statisticsTotalSessions => 'Total de sesiones';

  @override
  String get statisticsConversations => 'Conversaciones';

  @override
  String get statisticsPolls => 'Encuestas';

  @override
  String get statisticsMostFrequentFronters =>
      'Integrantes al frente más frecuentes';

  @override
  String get statisticsAverageSessionDuration => 'Duración promedio de sesión';

  @override
  String get statisticsNoFrontingData => 'Sin datos de frente aún';

  @override
  String get statisticsNoCompletedSessions => 'Sin sesiones completadas aún';

  @override
  String statisticsSessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
    );
    return '$_temp0';
  }

  @override
  String get statisticsDurationStats => 'Estadísticas de duración';

  @override
  String get statisticsDurationSessions => 'Sesiones';

  @override
  String get statisticsDurationTotal => 'Total';

  @override
  String get statisticsDurationAverage => 'Promedio';

  @override
  String get statisticsDurationMedian => 'Mediana';

  @override
  String get statisticsDurationShortest => 'Más corta';

  @override
  String get statisticsDurationLongest => 'Más larga';

  @override
  String statisticsFrontingTimeByMember(String term) {
    return 'Minutos por $term';
  }

  @override
  String statisticsMemberMinutesAxisHint(String term) {
    return '% de los minutos por $term del sistema';
  }

  @override
  String get statisticsMedianSessionLabel => 'Sesión mediana';

  @override
  String get statisticsGapTimeLabel => 'Tiempo sin frente';

  @override
  String get statisticsSwitchesPerDayLabel => 'Cambios/día';

  @override
  String statisticsUniqueFrontersLabel(String termPlural) {
    return '$termPlural únicos';
  }

  @override
  String statisticsActiveMembersBreakdown(int active, int inactive) {
    return '$active activos, $inactive inactivos';
  }

  @override
  String get timeOfDayMorning => 'Mañana';

  @override
  String get timeOfDayAfternoon => 'Tarde';

  @override
  String get timeOfDayEvening => 'Noche';

  @override
  String get timeOfDayNight => 'Madrugada';

  @override
  String get timeOfDayChartNoData => 'No hay datos de hora del día';

  @override
  String timeOfDayChartSemantics(String parts) {
    return 'Hora del día: $parts';
  }

  @override
  String get debugTitle => 'Depuración';

  @override
  String get debugDangerZone => 'Zona de peligro';

  @override
  String get debugResetDatabase => 'Restablecer base de datos';

  @override
  String get debugExportData => 'Exportar datos';

  @override
  String get debugComingSoon => 'Próximamente';

  @override
  String get debugStressTestingTitle => 'Pruebas de estrés';

  @override
  String get debugStressTestingDescription =>
      'Generar grandes conjuntos de datos para pruebas de rendimiento';

  @override
  String get debugGenerateStressData => 'Generar datos de estrés';

  @override
  String get debugClearingStressData => 'Limpiando...';

  @override
  String get debugClearStressData => 'Limpiar datos de estrés';

  @override
  String get debugSyncState => 'Estado de sincronización';

  @override
  String get debugPendingChanges => 'Cambios pendientes';

  @override
  String get debugLastSync => 'Última sincronización';

  @override
  String get debugNeverSynced => 'Nunca';

  @override
  String get debugOpenSyncLog => 'Abrir registro de sincronización';

  @override
  String get debugBuildInfo => 'Información de compilación';

  @override
  String get debugCopyBuildInfo => 'Copiar información de compilación';

  @override
  String get debugBuildInfoCopied => 'Información de compilación copiada';

  @override
  String get debugAppVersion => 'Versión de la app';

  @override
  String get debugGit => 'Git';

  @override
  String get debugBranch => 'Rama';

  @override
  String get debugBuilt => 'Compilado';

  @override
  String get debugPackage => 'Paquete';

  @override
  String get debugTools => 'Herramientas';

  @override
  String get debugDevice => 'Dispositivo';

  @override
  String get debugNodeId => 'ID de nodo';

  @override
  String get debugNodeIdUnavailable => 'No disponible — aún no emparejado';

  @override
  String get debugCopyNodeId => 'Copiar ID de nodo';

  @override
  String get debugNodeIdCopied => 'ID de nodo copiado al portapapeles';

  @override
  String get debugResetDatabaseConfirm1Title => 'Restablecer base de datos';

  @override
  String get debugResetDatabaseConfirm1Message =>
      '¿Estás seguro de que quieres eliminar todos los datos? Esta acción no se puede deshacer.';

  @override
  String get debugResetDatabaseConfirm2Title =>
      '¿Realmente eliminar todos los datos?';

  @override
  String debugResetDatabaseConfirm2Message(String termPluralLower) {
    return 'Esto borrará permanentemente $termPluralLower, sesiones, conversaciones, mensajes y encuestas. No hay forma de deshacer.';
  }

  @override
  String get debugDeleteEverything => 'Eliminar todo';

  @override
  String get debugDatabaseResetSuccess =>
      'Base de datos restablecida correctamente';

  @override
  String debugFailedToReset(Object error) {
    return 'Error al restablecer: $error';
  }

  @override
  String get debugSelectPreset => 'Seleccionar perfil';

  @override
  String get debugDatabaseNotEmpty => 'Base de datos no vacía';

  @override
  String get debugDatabaseNotEmptyMessage =>
      'Tu base de datos ya tiene datos. Los datos de estrés se agregarán junto a ellos. ¿Continuar?';

  @override
  String get debugNoStressData => 'No hay datos de estrés para limpiar';

  @override
  String get debugClearStressDataTitle => 'Limpiar datos de estrés';

  @override
  String get debugClearStressDataMessage =>
      'Esto eliminará todos los datos de prueba de estrés generados. Tus datos reales no se verán afectados.';

  @override
  String get debugStressDataCleared => 'Datos de estrés limpiados';

  @override
  String debugFailedToClearStress(Object error) {
    return 'Error al limpiar datos de estrés: $error';
  }

  @override
  String debugStressGenerated(String preset) {
    return 'Datos de estrés $preset generados';
  }

  @override
  String debugGenerationFailed(Object error) {
    return 'Error de generación: $error';
  }

  @override
  String get errorHistoryTitle => 'Historial de errores';

  @override
  String get errorHistoryClear => 'Limpiar historial';

  @override
  String get errorHistoryEmpty => 'No hay errores registrados';

  @override
  String get errorHistoryEmptySubtitle =>
      'Los errores aparecerán aquí cuando ocurran';

  @override
  String get errorHistoryCopyTooltip => 'Copiar detalles del error';

  @override
  String get errorHistoryCopied => 'Detalles del error copiados';

  @override
  String get systemInfoTitle => 'Información del sistema';

  @override
  String get systemInfoChangeAvatar => 'Cambiar avatar';

  @override
  String memberChangeAvatar(String termSingularLower) {
    return 'Cambiar avatar de $termSingularLower';
  }

  @override
  String get avatarCropTitle => 'Recortar avatar';

  @override
  String get systemInfoRemoveAvatar => 'Eliminar avatar';

  @override
  String get memberRemoveAvatar => 'Eliminar foto';

  @override
  String get memberProfileHeaderSectionTitle => 'Encabezado del perfil';

  @override
  String get memberProfileHeaderSectionDescription =>
      'Elige el origen de la imagen y el diseño de este perfil.';

  @override
  String get memberProfileHeaderVisibleTitle => 'Mostrar encabezado del perfil';

  @override
  String get memberProfileHeaderVisibleSubtitle =>
      'Conserva la imagen y el origen guardados mientras oculta el encabezado.';

  @override
  String get memberProfileHeaderSourcePluralKit => 'PluralKit';

  @override
  String get memberProfileHeaderSourcePrism => 'Prism';

  @override
  String get memberProfileHeaderSourcePluralKitHelper =>
      'Se actualiza desde PluralKit cuando Prism sincroniza.';

  @override
  String get memberProfileHeaderSourcePrismHelper =>
      'Privado para Prism. No actualiza PluralKit.';

  @override
  String get memberProfileHeaderPluralKitUnavailable =>
      'PluralKit aparece cuando este miembro tiene un encabezado vinculado o guardado en cache.';

  @override
  String get memberProfileHeaderAddImage => 'Añadir foto';

  @override
  String get memberProfileHeaderChangeImage => 'Cambiar foto';

  @override
  String get memberProfileHeaderRemoveImage => 'Eliminar';

  @override
  String get memberProfileHeaderHideTitle => 'Ocultar encabezado del perfil';

  @override
  String get memberProfileHeaderLayoutLabel => 'Diseño';

  @override
  String get memberProfileHeaderLayoutCompact => 'Compacto';

  @override
  String get memberProfileHeaderLayoutClassic => 'Clásico';

  @override
  String get memberProfileHeaderCropTitle => 'Recortar encabezado del perfil';

  @override
  String get memberProfileHeaderProcessingError =>
      'No se pudo procesar esa imagen.';

  @override
  String get memberNameStyleTooltip => 'Editar estilo del nombre';

  @override
  String get memberNameStyleDialogTitle => 'Estilo del nombre';

  @override
  String get memberNameStyleFontLabel => 'Fuente';

  @override
  String get memberNameStyleFontDefault => 'Predeterminada';

  @override
  String get memberNameStyleFontDisplay => 'Display';

  @override
  String get memberNameStyleFontSerif => 'Serif';

  @override
  String get memberNameStyleFontMono => 'Mono';

  @override
  String get memberNameStyleFontRounded => 'Redondeada';

  @override
  String get memberNameStyleStyleLabel => 'Estilo';

  @override
  String get memberNameStyleBold => 'Negrita';

  @override
  String get memberNameStyleItalic => 'Cursiva';

  @override
  String get memberNameStyleColorLabel => 'Color';

  @override
  String get memberNameStyleColorDefault => 'Predeterminado';

  @override
  String get memberNameStyleColorAccent => 'Acento';

  @override
  String get memberNameStyleColorCustom => 'Personalizado';

  @override
  String get memberNameStyleReset => 'Restablecer';

  @override
  String get systemInfoNameLabel => 'Nombre';

  @override
  String get systemInfoSystemNameHint => 'Nombre del sistema';

  @override
  String get systemInfoSaveSystemName => 'Guardar nombre del sistema';

  @override
  String get systemInfoCancelEditing => 'Cancelar edición';

  @override
  String get systemInfoDescriptionLabel => 'Descripción';

  @override
  String get systemInfoDescriptionHint => 'Descripción del sistema';

  @override
  String get systemInfoAddDescription => 'Agregar una descripción...';

  @override
  String get systemInfoSaveDescription => 'Guardar descripción';

  @override
  String get systemInfoTagLabel => 'Etiqueta del sistema';

  @override
  String get systemInfoTagHint => 'p. ej. | Skylars';

  @override
  String get systemInfoTagHelper => 'Se añade a los mensajes proxificados';

  @override
  String get systemInfoColorLabel => 'Color del sistema';

  @override
  String get systemInfoColorPickAction => 'Elegir color';

  @override
  String get systemInfoColorClearAction => 'Borrar color';

  @override
  String get systemInfoColorNoneSet => 'Sin color';

  @override
  String get devicesTitle => 'Administrar dispositivos';

  @override
  String get devicesThisDevice => 'Este dispositivo';

  @override
  String get devicesOtherDevices => 'Otros dispositivos';

  @override
  String get devicesFailedToLoad => 'Error al cargar dispositivos';

  @override
  String get devicesNoOtherDevices => 'No hay otros dispositivos';

  @override
  String get devicesNoOtherDevicesSubtitle =>
      'Solo este dispositivo está registrado en el grupo de sincronización.';

  @override
  String get devicesStatusActive => 'Activo';

  @override
  String get devicesStatusStale => 'Obsoleto';

  @override
  String get devicesStatusRevoked => 'Revocado';

  @override
  String get devicesRotateKey => 'Rotar clave de firma';

  @override
  String get devicesRotateKeyTitle => '¿Rotar clave de firma?';

  @override
  String get devicesRotateKeyMessage =>
      'Esto genera una nueva clave de firma post-cuántica para este dispositivo. Los demás dispositivos aceptarán la nueva clave automáticamente. La clave anterior sigue siendo válida por 30 días.';

  @override
  String get devicesRotate => 'Rotar';

  @override
  String devicesKeyRotated(int gen) {
    return 'Clave rotada a generación $gen';
  }

  @override
  String devicesKeyRotationFailed(Object error) {
    return 'Error al rotar la clave: $error';
  }

  @override
  String get devicesRevokeTitle => '¿Revocar dispositivo?';

  @override
  String devicesRevokeMessage(String shortId) {
    return 'El dispositivo $shortId será eliminado del grupo de sincronización y ya no podrá sincronizar. Esto no se puede deshacer.';
  }

  @override
  String get devicesRequestWipeTitle => 'Solicitar borrado remoto de datos';

  @override
  String get devicesRequestWipeSubtitle =>
      'Pide al dispositivo que borre sus datos de sincronización. Esta es una solicitud — si el dispositivo está desconectado o comprometido, puede no ser atendida.';

  @override
  String get devicesRevoke => 'Revocar';

  @override
  String devicesRevoked(String shortId) {
    return 'Dispositivo $shortId revocado';
  }

  @override
  String devicesFailedToRevoke(Object error) {
    return 'Error al revocar: $error';
  }

  @override
  String devicesSemanticLabel(String shortId, String status, int gen) {
    return 'Dispositivo $shortId, $status, generación de clave $gen';
  }

  @override
  String devicesSemanticLabelCurrent(String shortId, String status, int gen) {
    return 'Dispositivo $shortId, $status, generación de clave $gen, este dispositivo';
  }

  @override
  String get continueLabel => 'Continuar';

  @override
  String devicesEpochKeyGen(int epoch, int gen) {
    return 'Época $epoch · Gen clave $gen';
  }

  @override
  String get devicesRotateKeyTooltip => 'Rotar clave de firma';

  @override
  String get devicesRevokeTooltip => 'Revocar dispositivo';

  @override
  String get devicesIdCopied => 'ID del dispositivo copiado';

  @override
  String get syncTroubleshootingTitle =>
      'Resolución de Problemas de Prism Sync';

  @override
  String get syncTroubleshootingConnectionStatus => 'Estado de Conexión';

  @override
  String get syncTroubleshootingNotConfigured => 'No configurado';

  @override
  String get syncTroubleshootingConnected => 'Conectado';

  @override
  String get syncTroubleshootingConfiguredLocally => 'Configurado localmente';

  @override
  String get syncTroubleshootingNotConfiguredSubtitle =>
      'Este dispositivo no tiene sincronización configurada actualmente.';

  @override
  String get syncTroubleshootingConnectedSubtitle =>
      'El motor de sincronización está activo y listo';

  @override
  String get syncTroubleshootingConfiguredLocallySubtitle =>
      'La configuración está almacenada. El motor se reconectará en la próxima sincronización.';

  @override
  String get syncTroubleshootingLastSync => 'Última Sincronización';

  @override
  String get syncTroubleshootingLastSuccessful =>
      'Última sincronización exitosa';

  @override
  String get syncTroubleshootingNeverSynced => 'Nunca sincronizado';

  @override
  String get syncTroubleshootingLastError => 'Último error de sincronización';

  @override
  String get syncTroubleshootingCurrentState =>
      'Estado de sincronización actual';

  @override
  String get syncTroubleshootingSyncing => 'Sincronizando…';

  @override
  String get syncTroubleshootingIdle => 'Inactivo';

  @override
  String get syncTroubleshootingPendingOps => 'Operaciones pendientes';

  @override
  String syncTroubleshootingPendingOpsValue(int count) {
    return '$count operaciones esperando sincronización';
  }

  @override
  String get syncTroubleshootingSyncId => 'ID de Sincronización';

  @override
  String get syncTroubleshootingRelayUrl => 'URL del Relay';

  @override
  String get syncTroubleshootingActions => 'Acciones';

  @override
  String get syncTroubleshootingForceSync => 'Forzar Sincronización';

  @override
  String get syncTroubleshootingOpenEventLog =>
      'Abrir Registro de Eventos de Prism Sync';

  @override
  String get syncTroubleshootingResetSync =>
      'Restablecer Sistema de Sincronización';

  @override
  String get syncTroubleshootingRepair => 'Reemparejar Dispositivo';

  @override
  String get syncTroubleshootingCommonIssues => 'Problemas Comunes';

  @override
  String get syncTroubleshootingIssue1Title =>
      '¿La sincronización no funciona?';

  @override
  String get syncTroubleshootingIssue1Description =>
      'Comprueba que la URL del relay y el ID de sincronización estén correctamente configurados. Ambos dispositivos deben usar el mismo ID de sincronización.';

  @override
  String get syncTroubleshootingIssue2Title => '¿Datos duplicados?';

  @override
  String get syncTroubleshootingIssue2Description =>
      'Intenta restablecer el sistema de sincronización con el botón de arriba. Esto borra la configuración local y te permite emparejar de nuevo.';

  @override
  String get syncTroubleshootingIssue3Title => '¿Errores de conexión?';

  @override
  String get syncTroubleshootingIssue3Description =>
      'Verifica que el dispositivo tenga acceso a la red y que el servidor relay esté en línea. Revisa la URL del relay.';

  @override
  String get syncTroubleshootingIssue4Title => '¿Sincronización lenta?';

  @override
  String get syncTroubleshootingIssue4Description =>
      'La sincronización inicial puede tardar más con grandes conjuntos de datos. Las sincronizaciones posteriores son incrementales y más rápidas.';

  @override
  String get syncTroubleshootingIssue5Title =>
      'Discrepancia de Identidad del Dispositivo';

  @override
  String get syncTroubleshootingIssue5Description =>
      'Si el emparejamiento falló a la mitad, la identidad del dispositivo puede ser inconsistente. Usa \'Reemparejar Dispositivo\' para generar una identidad nueva.';

  @override
  String get syncTroubleshootingFinished => 'Sincronización completada';

  @override
  String syncTroubleshootingFailed(Object error) {
    return 'Error de sincronización: $error';
  }

  @override
  String get syncTroubleshootingResetTitle =>
      '¿Restablecer sistema de sincronización?';

  @override
  String get syncTroubleshootingResetMessage =>
      'Esto conserva los datos locales, pero borra claves de sincronización, configuración del relay, identidad del dispositivo e historial de sincronización. Deberás configurar la sincronización de nuevo.';

  @override
  String get syncTroubleshootingResetConfirm => 'Restablecer';

  @override
  String get syncTroubleshootingResetSuccess =>
      'Sistema de sincronización restablecido';

  @override
  String get syncTroubleshootingRepairTitle => '¿Reemparejar Dispositivo?';

  @override
  String get syncTroubleshootingRepairMessage =>
      'Esto borrará tus credenciales de sincronización y requerirá que emparejes de nuevo. Los cambios locales no sincronizados se perderán.\n\nRecomendamos exportar los datos primero como medida de seguridad.';

  @override
  String get syncTroubleshootingRepairNow => 'Reemparejar ahora';

  @override
  String get syncTroubleshootingExportFirst => 'Exportar datos primero';

  @override
  String get syncTroubleshootingCredentialsCleared =>
      'Credenciales de sincronización borradas';

  @override
  String get syncTroubleshootingPluralKitSection => 'PluralKit';

  @override
  String get syncTroubleshootingPkRepairTitle =>
      'Abrir reparación de grupos de PluralKit';

  @override
  String get syncTroubleshootingPkRepairSubtitle =>
      'Usa la pantalla de configuración de PluralKit para ejecutar la reparación de grupos y revisar coincidencias de grupos PK suprimidas.';

  @override
  String featureChatDescription(String term) {
    return 'Mensajería interna entre los $term del sistema.';
  }

  @override
  String get featureChatGeneral => 'General';

  @override
  String get featureChatEnable => 'Activar Chat';

  @override
  String featureChatEnableSubtitle(String term) {
    return 'Mensajería interna entre $term';
  }

  @override
  String get featureChatOptions => 'Opciones';

  @override
  String get featureChatLogFront => 'Registrar Frente al Cambiar';

  @override
  String get featureChatLogFrontSubtitle =>
      'Cambiar quién habla en el chat también registra un frente';

  @override
  String get featureChatProxyTagAuthoring =>
      'Usar etiquetas de proxy para firmar mensajes';

  @override
  String featureChatProxyTagAuthoringSubtitle(String termSingularLower) {
    return 'Escribe una etiqueta de proxy (p. ej. A:) para firmar un solo mensaje como $termSingularLower. Distingue mayúsculas y minúsculas.';
  }

  @override
  String chatPostingAsProxy(String name) {
    return 'Publicando como $name';
  }

  @override
  String get chatPostingAsProxyDismiss => 'No publicar como proxy';

  @override
  String get featureChatGifSearch => 'Búsqueda de GIF';

  @override
  String get featureChatGifSearchSubtitle => 'Buscar y enviar GIFs en el chat';

  @override
  String get featureChatGifSearchUndecidedSubtitle =>
      'Desactivado hasta que revises los detalles de privacidad';

  @override
  String get featureChatGifSearchEnabledSubtitle =>
      'Activado en este dispositivo';

  @override
  String get featureChatGifSearchDeclinedSubtitle =>
      'Oculto después de rechazarlo en este dispositivo';

  @override
  String get featureChatGifSearchSyncRequiredSubtitle =>
      'Debes activar la sincronización para usar GIFs';

  @override
  String get featureChatGifSearchSyncRequiredDialogTitle =>
      'Se requiere sincronización para los GIFs';

  @override
  String get featureChatGifSearchSyncRequiredDialogBody =>
      'La búsqueda de GIFs se realiza a través de tu relé de sincronización para mantener el servicio privado. Activa la sincronización para usar GIFs en este dispositivo.';

  @override
  String get featureChatGifSearchSyncRequiredDialogAction =>
      'Activar sincronización';

  @override
  String get featureChatVoiceNotes => 'Notas de voz';

  @override
  String get featureChatVoiceNotesSubtitle =>
      'Enviar mensajes de voz en el chat';

  @override
  String get featureFrontingDescription =>
      'Configura cómo funcionan las sesiones de frente.';

  @override
  String get featureFrontingOptions => 'Opciones';

  @override
  String get featureFrontingQuickSwitch => 'Cambio Rápido';

  @override
  String get featureFrontingQuickSwitchOff => 'Desactivado';

  @override
  String featureFrontingQuickSwitchSeconds(int seconds) {
    return 'Ventana de corrección de ${seconds}s';
  }

  @override
  String featureFrontingQuickSwitchMinutes(int minutes) {
    return 'Ventana de corrección de ${minutes}m';
  }

  @override
  String get featureFrontingQuickSwitchTitle => 'Ventana de Cambio Rápido';

  @override
  String get featureFrontingQuickSwitchMessage =>
      'Si cambias de frente dentro de esta ventana, corrige la sesión actual en lugar de crear una nueva.';

  @override
  String get featureFrontingShowQuickFront => 'Front Rápido';

  @override
  String featureFrontingShowQuickFrontSubtitle(String termPluralLower) {
    return 'Muestra $termPluralLower que frentan frecuentemente como accesos rápidos de mantener pulsado';
  }

  @override
  String featureHabitsDescription(String term) {
    return 'Realiza un seguimiento de tareas recurrentes y construye rachas con los $term del sistema.';
  }

  @override
  String get featureHabitsGeneral => 'General';

  @override
  String get featureHabitsEnable => 'Activar Hábitos';

  @override
  String get featureHabitsEnableSubtitle =>
      'Seguimiento de rutinas y objetivos diarios';

  @override
  String get featureHabitsOptions => 'Opciones';

  @override
  String get featureHabitsDueBadge => 'Insignia de Hábitos Pendientes';

  @override
  String get featureHabitsDueBadgeSubtitle =>
      'Mostrar el número de hábitos pendientes en el icono de la pestaña';

  @override
  String get featureSleepDescription =>
      'Las sesiones de sueño ayudan a seguir los patrones de descanso junto con las sesiones de frente. Puedes iniciar una sesión de sueño desde el icono de luna en la pantalla de frente.';

  @override
  String get featureSleepGeneral => 'General';

  @override
  String get featureSleepEnable => 'Activar Sueño';

  @override
  String get featureSleepEnableSubtitle =>
      'Registrar y monitorear sesiones de sueño';

  @override
  String get featureSleepOptions => 'Opciones';

  @override
  String get featureSleepDefaultQuality => 'Calidad Predeterminada';

  @override
  String get featureSleepDefaultQualityTitle => 'Calidad Predeterminada';

  @override
  String get featureSleepDefaultQualityMessage =>
      'Elige la calificación de calidad predeterminada para las nuevas sesiones de sueño.';

  @override
  String get featurePollsDescription =>
      'Permite que tu sistema vote en decisiones juntos. Desactivar oculta las encuestas de la navegación pero conserva los datos existentes.';

  @override
  String get featurePollsEnable => 'Activar Encuestas';

  @override
  String get featurePollsEnableSubtitle =>
      'Crear encuestas para decisiones del sistema';

  @override
  String featureNotesDescription(String term) {
    return 'Un diario personal para los $term del sistema. Desactivar oculta las notas de la navegación pero conserva las entradas existentes.';
  }

  @override
  String get featureNotesEnable => 'Activar Notas';

  @override
  String get featureNotesEnableSubtitle =>
      'Escribir notas y entradas de diario';

  @override
  String get featureRemindersDescription =>
      'Recibe recordatorios en horarios programados o cuando los frentes cambien. Desactivar oculta los recordatorios de la navegación pero conserva los existentes.';

  @override
  String get featureRemindersGeneral => 'General';

  @override
  String get featureRemindersEnable => 'Activar Recordatorios';

  @override
  String get featureRemindersEnableSubtitle =>
      'Recordatorios programados y de cambio de frente';

  @override
  String get featureRemindersOptions => 'Opciones';

  @override
  String get featureRemindersManage => 'Gestionar Recordatorios';

  @override
  String get featureRemindersManageSubtitle =>
      'Crear y editar tus recordatorios';

  @override
  String get voicePreparingNote => 'Preparando nota de voz...';

  @override
  String get voiceRecordingStartedAnnouncement => 'Grabación iniciada.';

  @override
  String get voiceRecordingReadyAnnouncement =>
      'Nota de voz lista para enviar.';

  @override
  String get voiceMicPermissionDenied =>
      'Se necesita permiso de micrófono para grabar notas de voz.';

  @override
  String get voiceMicPermissionBlocked =>
      'El acceso al micrófono está bloqueado. Actívalo en Configuración.';

  @override
  String get voiceRecordingFailed => 'No se pudo iniciar la grabación.';

  @override
  String get openSettings => 'Abrir Configuración';

  @override
  String get frontingListView => 'Vista de lista';

  @override
  String get frontingTimelineView => 'Vista de cronología';

  @override
  String get frontingAddEntry => 'Agregar registro de frente';

  @override
  String get frontingLoadingOlderSessions => 'Cargando sesiones anteriores';

  @override
  String frontingAlwaysPresentLabel(String duration) {
    return 'Siempre presente · $duration';
  }

  @override
  String frontingAlwaysPresentSemantics(String names, String duration) {
    return 'Siempre al frente: $names, $duration';
  }

  @override
  String frontingAlwaysPresentDurationWeeks(int weeks) {
    String _temp0 = intl.Intl.pluralLogic(
      weeks,
      locale: localeName,
      other: '$weeks semanas',
      one: '1 semana',
    );
    return '$_temp0';
  }

  @override
  String frontingAlwaysPresentDurationDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String frontingAlwaysPresentDurationHours(int hours) {
    String _temp0 = intl.Intl.pluralLogic(
      hours,
      locale: localeName,
      other: '$hours horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String get frontingMenuWakeUpAs => 'Despertar como...';

  @override
  String get frontingMenuLogFront => 'Registrar frente';

  @override
  String get frontingMenuNewPoll => 'Nueva encuesta';

  @override
  String get frontingMenuStartSleep => 'Empezar a dormir';

  @override
  String get frontingMenuSyncPluralKit => 'Sincronizar con PluralKit';

  @override
  String get frontingPluralKitSyncingToast => 'Sincronizando con PluralKit…';

  @override
  String get frontingPluralKitSyncDoneToast =>
      'Sincronización de PluralKit completa';

  @override
  String frontingPluralKitSyncFailedToast(Object error) {
    return 'Error de sincronización de PluralKit: $error';
  }

  @override
  String get frontingWakeUpAsTitle => 'Despertar como...';

  @override
  String frontingErrorWakingUp(Object error) {
    return 'Error al despertar: $error';
  }

  @override
  String frontingErrorSwitchingFronter(Object error) {
    return 'Error al cambiar de frente: $error';
  }

  @override
  String get frontingNoSessionHistory => 'Sin historial de sesiones aún';

  @override
  String frontingErrorLoadingHistory(Object error) {
    return 'Error al cargar el historial: $error';
  }

  @override
  String get frontingDeleteSleepTitle => 'Eliminar sesión de sueño';

  @override
  String get frontingDeleteSleepMessage =>
      '¿Estás segure de que quieres eliminar esta sesión de sueño?';

  @override
  String get frontingSleeping => 'Sueño';

  @override
  String frontingSleepSessionSemantics(String duration, String timeRange) {
    return 'Sesión de sueño, $duration, $timeRange';
  }

  @override
  String get frontingWelcomeTitle => 'Bienvenide a Prism';

  @override
  String frontingWelcomeSubtitle(String member) {
    return 'Agrega tu primer $member del sistema para comenzar';
  }

  @override
  String frontingQuickFrontLabel(String name) {
    return 'Frente rápido de $name';
  }

  @override
  String get frontingQuickFrontHoldHint =>
      'Mantén presionado para estar al frente';

  @override
  String get frontingNewSession => 'Nueva sesión';

  @override
  String get frontingAddCoFronterTitle => 'Agregar al co-frente';

  @override
  String get frontingStartSessionTooltip => 'Iniciar sesión';

  @override
  String get frontingAddCoFronterTooltip => 'Agregar cofronter';

  @override
  String get frontingSelectFronter => 'Seleccionar quien está al frente';

  @override
  String get frontingAddFrontModeAdditive => 'Agregar al co-frente';

  @override
  String get frontingAddFrontModeReplace => 'Reemplazar actual';

  @override
  String frontingSelectMember(String term) {
    return 'Seleccionar $term';
  }

  @override
  String get frontingCoFrontToggle => 'Co-frente';

  @override
  String get frontingCoFronters => 'Co-frente';

  @override
  String frontingNoOtherMembers(String term) {
    return 'No hay otros $term disponibles';
  }

  @override
  String frontingCoFrontHint(String term) {
    return 'Toca un $term para agregarlo al co-frente de la sesión actual.';
  }

  @override
  String get frontingConfidenceLevel => 'Nivel de confianza';

  @override
  String get frontingConfidenceUnsure => 'Inseguro';

  @override
  String get frontingConfidenceStrong => 'Fuerte';

  @override
  String get frontingConfidenceCertain => 'Seguro';

  @override
  String get frontingNotes => 'Notas';

  @override
  String get frontingNotesHint => 'Notas opcionales sobre esta sesión...';

  @override
  String get frontingNotesHintEdit => 'Notas opcionales...';

  @override
  String frontingSearchMembersHint(String term) {
    return 'Buscar $term...';
  }

  @override
  String frontingNoMembersMatching(String term, String query) {
    return 'Sin $term que coincidan con \"$query\"';
  }

  @override
  String get frontingFronting => 'Al frente';

  @override
  String frontingErrorAddingCoFronter(Object error) {
    return 'Error al agregar al co-frente: $error';
  }

  @override
  String frontingErrorCreatingSession(Object error) {
    return 'Error al crear la sesión: $error';
  }

  @override
  String get frontingAddCoFrontersTitle => 'Agregar al co-frente';

  @override
  String frontingErrorAddingCoFronters(Object error) {
    return 'Error al agregar al co-frente: $error';
  }

  @override
  String get frontingEditSessionTitle => 'Editar sesión';

  @override
  String get frontingSaveSession => 'Guardar sesión';

  @override
  String get frontingSessionNotFound => 'Sesión no encontrada';

  @override
  String get frontingStillActive => 'Aún activo';

  @override
  String get frontingStart => 'Inicio';

  @override
  String get frontingEnd => 'Fin';

  @override
  String get frontingFronter => 'Al frente';

  @override
  String get frontingShortSessionTitle => 'Sesión corta';

  @override
  String get frontingShortSessionMessage =>
      'Esta sesión dura menos de un minuto. ¿Guardar de todas formas?';

  @override
  String get frontingDuplicateSessionTitle => 'Sesión duplicada';

  @override
  String frontingDuplicateSessionMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Esta sesión parece ser un duplicado de $count otras sesiones. ¿Guardar de todas formas?',
      one:
          'Esta sesión parece ser un duplicado de 1 otra sesión. ¿Guardar de todas formas?',
    );
    return '$_temp0';
  }

  @override
  String get frontingSaveAnyway => 'Guardar de todas formas';

  @override
  String frontingErrorSavingSession(Object error) {
    return 'Error al guardar la sesión: $error';
  }

  @override
  String get frontingEndSessionButton => 'Terminar sesión';

  @override
  String frontingEndSessionEndedToast(String member) {
    return 'Sesión de $member terminada';
  }

  @override
  String get frontingNextFronterTitle => '¿Quién está al frente ahora?';

  @override
  String get frontingNextFronterBody =>
      'Después de esto no habrá nadie al frente.';

  @override
  String get frontingNextFronterPick => 'Elegir quién al frente';

  @override
  String get frontingNextFronterUnknown => 'Desconocido';

  @override
  String get frontingNextFronterEnd => 'Terminar sin nadie al frente';

  @override
  String get frontingSessionDetailEditTooltip => 'Editar';

  @override
  String get frontingSessionDetailDeleteTooltip => 'Eliminar';

  @override
  String get frontingSleepingNow => 'Durmiendo ahora';

  @override
  String get frontingSleepSession => 'Sesión de sueño';

  @override
  String get frontingInfoStarted => 'Inicio';

  @override
  String get frontingInfoEnded => 'Fin';

  @override
  String get frontingInfoDuration => 'Duración';

  @override
  String get frontingInfoActive => 'Activo';

  @override
  String get frontingInfoQuality => 'Calidad';

  @override
  String get frontingInfoQualityUnrated => 'Sin calificar';

  @override
  String get frontingTimeSection => 'Tiempo';

  @override
  String get frontingConfidenceSection => 'Confianza';

  @override
  String get frontingNotesSection => 'Notas';

  @override
  String get frontingCoFrontersSection => 'Co-frente';

  @override
  String get frontingSleepingLabel => 'Durmiendo';

  @override
  String frontingSleepSince(String time) {
    return 'Desde las $time';
  }

  @override
  String get frontingWakeUp => 'Despertar';

  @override
  String get frontingSleepQualityUnrated => 'Calidad del sueño: Sin calificar';

  @override
  String frontingSleepQualityRated(String label) {
    return 'Calidad del sueño: $label';
  }

  @override
  String frontingRateSleepAs(String label) {
    return 'Calificar sueño como $label';
  }

  @override
  String get sleepQualityNotRated => 'Sin calificar';

  @override
  String get sleepQualityVeryPoor => 'Muy mala';

  @override
  String get sleepQualityPoor => 'Mala';

  @override
  String get sleepQualityFair => 'Regular';

  @override
  String get sleepQualityGood => 'Buena';

  @override
  String get sleepQualityExcellent => 'Excelente';

  @override
  String get sleepSuggestionBedtimeDismiss => 'Descartar hasta mañana';

  @override
  String get frontingStartSleepTitle => 'Empezar a dormir';

  @override
  String get frontingStartButton => 'Empezar';

  @override
  String get frontingStartSleepNotesHint =>
      'Notas opcionales sobre este sueño...';

  @override
  String frontingErrorStartingSleep(Object error) {
    return 'Error al iniciar el sueño: $error';
  }

  @override
  String get frontingEditSleepTitle => 'Editar sueño';

  @override
  String get frontingEditSleepLabel => 'Sesión de sueño';

  @override
  String get frontingStillSleeping => 'Aún durmiendo';

  @override
  String get frontingStillSleepingSubtitle => 'Dejar la sesión abierta';

  @override
  String get frontingSleepQualityLabel => 'Calidad del sueño';

  @override
  String get frontingEditSleepNotesHint =>
      'Notas opcionales sobre este sueño...';

  @override
  String get frontingEndTimeMustBeAfterStart =>
      'La hora de fin debe ser posterior a la de inicio.';

  @override
  String frontingErrorSavingSleepSession(Object error) {
    return 'Error al guardar la sesión de sueño: $error';
  }

  @override
  String get frontingCommentsTitle => 'Comentarios';

  @override
  String get frontingAddCommentTooltip => 'Agregar comentario';

  @override
  String get frontingNoCommentsYet => 'Sin comentarios aún';

  @override
  String get frontingAddCommentTitle => 'Agregar comentario';

  @override
  String get frontingEditCommentTitle => 'Editar comentario';

  @override
  String get frontingCommentHint => 'Escribe tu comentario...';

  @override
  String get frontingDeleteCommentTitle => '¿Eliminar comentario?';

  @override
  String get frontingDeleteCommentMessage =>
      'Esta acción no se puede deshacer.';

  @override
  String get frontingTimelineJumpToDate => 'Ir a fecha';

  @override
  String get frontingTimelineJumpToNow => 'Ir a ahora';

  @override
  String get frontingTimelineZoomOut => 'Alejar';

  @override
  String get frontingTimelineZoomIn => 'Acercar';

  @override
  String get frontingTimelineNoHistory => 'Sin historial de frente';

  @override
  String get frontingTimelineNoHistorySubtitle =>
      'Inicia una sesión de frente para verla en la cronología.';

  @override
  String get frontingDeleteStrategyTitle => '¿Qué debe pasar con este tiempo?';

  @override
  String get frontingDeleteStrategyRecommended => 'Recomendado';

  @override
  String frontingGapDetectedTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Brechas detectadas',
      one: 'Brecha detectada',
    );
    return '$_temp0';
  }

  @override
  String frontingGapDetectedMessage(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Esta edición crearía $count brechas de $total en total.',
      one: 'Esta edición crearía una brecha de $total en total.',
    );
    return '$_temp0';
  }

  @override
  String get frontingGapFillWithUnknown =>
      'Rellenar con integrante desconocido';

  @override
  String get frontingGapFillWithUnknownSubtitle =>
      'Crear sesiones desconocidas para cubrir las brechas.';

  @override
  String get frontingGapLeaveGaps => 'Dejar brechas';

  @override
  String get frontingGapLeaveGapsSubtitle =>
      'Guardar sin rellenar las brechas.';

  @override
  String frontingOverlapTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Superposición con $count sesiones',
      one: 'Superposición con 1 sesión',
    );
    return '$_temp0';
  }

  @override
  String get frontingOverlapTrimOption => 'Recortar sesiones superpuestas';

  @override
  String get frontingOverlapTrimSubtitle =>
      'Acortar o eliminar sesiones que entran en conflicto con tu edición.';

  @override
  String get frontingOverlapCoFrontOption => 'Crear sesión de co-frente';

  @override
  String get frontingOverlapCoFrontSubtitle =>
      'Dividir el tiempo superpuesto en segmentos compartidos de co-frente.';

  @override
  String get frontingOverlapRemoveSessionTitle => 'Eliminar sesión';

  @override
  String get frontingOverlapRemoveSessionMessage =>
      'Esto eliminaría completamente una sesión. ¿Continuar?';

  @override
  String get frontingOverlapContinue => 'Continuar';

  @override
  String get frontingTimingModeTitle => 'Modo de tiempo';

  @override
  String get frontingTimingModeFlexible => 'Flexible';

  @override
  String get frontingTimingModeStrict => 'Estricto';

  @override
  String get frontingTimingModeFlexibleSubtitle =>
      'Se permiten pequeñas brechas (menos de 5 minutos) entre sesiones.';

  @override
  String get frontingTimingModeStrictSubtitle =>
      'Las sesiones deben ser continuas sin brechas en la cronología.';

  @override
  String get memberSectionCustomFields => 'Campos personalizados';

  @override
  String get memberSectionFrontingStats => 'Estadísticas de frente';

  @override
  String get memberSectionRecentSessions => 'Sesiones recientes';

  @override
  String get memberSectionConversations => 'Conversaciones';

  @override
  String get memberSectionNotes => 'Notas';

  @override
  String get memberSectionBio => 'Biografía';

  @override
  String get memberSectionProxyTags => 'Etiquetas de proxy';

  @override
  String get memberProxyTagsManagedOnPk =>
      'Las etiquetas de proxy se gestionan en PluralKit.';

  @override
  String get memberProxyTagsEditOnPk => 'Editar en PluralKit';

  @override
  String get memberProxyTagsLocalDescription =>
      'Se guardan en Prism para firmar mensajes de chat con etiquetas de proxy. Los miembros vinculados se sincronizan con PluralKit cuando la sincronización de subida está activada.';

  @override
  String get memberProxyTagsEditInPrism => 'Editar etiquetas de proxy';

  @override
  String get memberProxyTagsAdd => 'Agregar etiqueta de proxy';

  @override
  String get memberProxyTagsRemove => 'Quitar etiqueta de proxy';

  @override
  String get memberProxyTagPrefixLabel => 'Prefijo';

  @override
  String get memberProxyTagPrefixHint => 'A:';

  @override
  String get memberProxyTagSuffixLabel => 'Sufijo';

  @override
  String get memberProxyTagSuffixHint => '-a';

  @override
  String get memberProxyTagsEmpty => 'No hay etiquetas de proxy.';

  @override
  String memberEditTooltip(String termSingularLower) {
    return 'Editar $termSingularLower';
  }

  @override
  String get memberMoreOptionsTooltip => 'Más opciones';

  @override
  String get memberAddNoteTooltip => 'Agregar nota';

  @override
  String get memberSaveNoteTooltip => 'Guardar nota';

  @override
  String get memberCancelSelectionTooltip => 'Cancelar selección';

  @override
  String get memberClearDateTooltip => 'Borrar fecha';

  @override
  String get memberNewGroupTooltip => 'Nuevo grupo';

  @override
  String memberAdded(String term) {
    return '$term añadide';
  }

  @override
  String memberIsFronting(String name) {
    return '$name está al frente';
  }

  @override
  String memberGroupDeleted(String name) {
    return '$name eliminado';
  }

  @override
  String memberActivated(String name) {
    return '$name activade';
  }

  @override
  String memberDeactivated(String name) {
    return '$name archivade';
  }

  @override
  String memberRemoved(String name) {
    return '$name eliminade';
  }

  @override
  String memberRemoveFromGroupTitle(String term) {
    return 'Eliminar $term';
  }

  @override
  String memberRemoveFromGroupMessage(String name, String termLower) {
    return '¿Eliminar a $name de este grupo? $termLower no será eliminade.';
  }

  @override
  String get memberGroupEmptyList => 'Aún no hay grupos';

  @override
  String memberGroupEmptySubtitle(String termPlural) {
    return 'Crea grupos para organizar les $termPlural de tu sistema';
  }

  @override
  String memberGroupNoMembers(String termPlural) {
    return 'Sin $termPlural';
  }

  @override
  String memberGroupNoMembersSubtitle(String termPlural) {
    return 'Añadir $termPlural a este grupo';
  }

  @override
  String get memberArchived => 'Inactivo';

  @override
  String get memberActive => 'Activo';

  @override
  String get memberOrderUpdated => 'Orden actualizado';

  @override
  String get memberReorderBy => 'Reordenar por';

  @override
  String get memberSortNameAZ => 'Nombre A–Z';

  @override
  String get memberSortNameZA => 'Nombre Z–A';

  @override
  String get memberSortRecentlyCreated => 'Creados recientemente';

  @override
  String get memberSortMostFronting => 'Más tiempo al frente';

  @override
  String get memberSortLeastFronting => 'Menos tiempo al frente';

  @override
  String get memberShowInactive => 'Mostrar inactivos';

  @override
  String get memberHideInactive => 'Ocultar inactivos';

  @override
  String get memberStatsTotalSessions => 'Total de sesiones';

  @override
  String get memberStatsTotalTime => 'Tiempo total';

  @override
  String get memberStatsLastFronted => 'Último frente';

  @override
  String get memberStatsToday => 'Hoy';

  @override
  String get memberStatsYesterday => 'Ayer';

  @override
  String memberStatsDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Hace $count días',
      one: 'Hace 1 día',
    );
    return '$_temp0';
  }

  @override
  String memberStatsWeeksAgo(int count) {
    return 'Hace $count semanas';
  }

  @override
  String get memberSessionActive => 'Activo';

  @override
  String memberSessionTodayAt(String time) {
    return 'Hoy a las $time';
  }

  @override
  String get memberFrontingChip => 'Al frente';

  @override
  String get memberAdminChip => 'Admin';

  @override
  String get memberInactiveChip => 'Inactivo';

  @override
  String get memberSetAsFronter => 'Poner al frente';

  @override
  String get memberNoteTitle => 'Nota';

  @override
  String get memberNoteUntitled => 'Sin título';

  @override
  String get memberNoteNotFound => 'Nota no encontrada';

  @override
  String get memberNoteDeleteTitle => '¿Eliminar nota?';

  @override
  String memberNoteDeleteMessage(String title) {
    return '¿Seguro que quieres eliminar \"$title\"? Esta acción no se puede deshacer.';
  }

  @override
  String get memberNoteNoNotesYet => 'Aún no hay notas';

  @override
  String get memberNoteEmptySubtitle =>
      'Crea notas para registrar pensamientos y observaciones';

  @override
  String get memberNoteTitleHint => 'Título';

  @override
  String get memberNoteBodyHint => 'Empieza a escribir...';

  @override
  String memberNoteAddHeadmate(String termLower) {
    return 'Añadir $termLower';
  }

  @override
  String get memberNoteDiscardTitle => '¿Descartar cambios?';

  @override
  String get memberNoteDiscardMessage =>
      'Tienes cambios sin guardar. ¿Seguro que quieres descartarlos?';

  @override
  String get memberNoteDiscardConfirm => 'Descartar';

  @override
  String memberNoteChooseHeadmate(String termSingular) {
    return 'Elegir $termSingular';
  }

  @override
  String memberNoteDateSemantics(String date) {
    return 'Fecha de la nota, $date. Toca para cambiar';
  }

  @override
  String memberNoteMemberSemantics(String termSingular, String name) {
    return '$termSingular: $name. Toca para cambiar';
  }

  @override
  String memberNoteNoHeadmateSemantics(String termLower) {
    return 'No hay $termLower seleccionado. Toca para elegir';
  }

  @override
  String get memberSelectNone => 'Ninguno';

  @override
  String get memberGroupsTitle => 'Grupos';

  @override
  String memberGroupErrorLoading(Object error) {
    return 'Error al cargar grupos: $error';
  }

  @override
  String memberGroupErrorLoadingDetail(Object error) {
    return 'Error al cargar el grupo: $error';
  }

  @override
  String get memberGroupNotFound => 'Grupo no encontrado';

  @override
  String get memberGroupSubGroupsLabel => 'Sub-grupos';

  @override
  String memberGroupSectionMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get memberGroupStartChat => 'Iniciar chat';

  @override
  String memberGroupAddMember(String termSingularLower) {
    return 'Agregar $termSingularLower';
  }

  @override
  String get memberGroupAddSubGroup => 'Agregar subgrupo';

  @override
  String get memberGroupAddToGroup => 'Añadir a grupo';

  @override
  String memberGroupAddToGroupSemantics(String name) {
    return 'Añadir $name a un grupo';
  }

  @override
  String get memberGroupDeleteTitle => 'Eliminar grupo';

  @override
  String memberGroupDeleteMessage(String name, String termPlural) {
    return '¿Seguro que quieres eliminar \"$name\"? $termPlural no serán eliminados.';
  }

  @override
  String get memberGroupDeleteConfirm => 'Eliminar';

  @override
  String get memberGroupDeleteCascadeSubtitle =>
      'Este grupo tiene subgrupos. ¿Qué debería pasar con ellos?';

  @override
  String get memberGroupDeletePromote => 'Mover subgrupos al nivel superior';

  @override
  String get memberGroupDeletePromoteSubtitle =>
      'Los subgrupos se mantienen, solo sin un padre';

  @override
  String get memberGroupDeleteAll => 'Eliminar todo';

  @override
  String get memberGroupDeleteAllSubtitle =>
      'También se eliminarán todos los subgrupos';

  @override
  String get memberGroupDeleteAllConfirmTitle => '¿Eliminar subgrupos también?';

  @override
  String memberGroupDeleteAllConfirmMessage(String name, String termPlural) {
    return 'Esto eliminará permanentemente \"$name\" y todos sus subgrupos. $termPlural no serán eliminados.';
  }

  @override
  String get memberGroupPromoted => 'Subgrupos movidos al nivel superior';

  @override
  String get memberGroupEditTitle => 'Editar Grupo';

  @override
  String get memberGroupNewTitle => 'Nuevo Grupo';

  @override
  String get memberGroupNameLabel => 'Nombre';

  @override
  String get memberGroupNameRequired => 'El nombre es obligatorio';

  @override
  String get memberGroupDescriptionLabel => 'Descripción';

  @override
  String get memberGroupColorLabel => 'Color';

  @override
  String get memberGroupColorNone => 'Sin color';

  @override
  String memberGroupErrorSaving(Object error) {
    return 'Error al guardar el grupo: $error';
  }

  @override
  String get memberGroupParentLabel => 'Grupo padre';

  @override
  String get memberGroupParentNone => 'Ninguno (nivel superior)';

  @override
  String get memberGroupParentDepthLimit => 'No se puede anidar más';

  @override
  String get memberGroupFilterAll => 'Todos';

  @override
  String get memberGroupFilterBarLabel => 'Filtrar por grupo';

  @override
  String get memberGroupFilterUngrouped => 'Sin grupo';

  @override
  String memberGroupFrontAllAlreadyFronting(
    String termPluralLower,
    Object termPlural,
  ) {
    return '$termPlural ya están al frente';
  }

  @override
  String memberGroupFrontAllInactive(String name, String termPluralLower) {
    return '$termPluralLower de $name están inactivos. ¿Frente de todos modos?';
  }

  @override
  String get memberGroupFrontGroup => 'Frente como grupo';

  @override
  String memberGroupFrontGroupConfirmTitle(String name) {
    return '¿Frente como $name?';
  }

  @override
  String memberGroupFrontGroupConfirmMessage(int count, String termForCount) {
    return 'Se iniciará una sesión de co-frente con $count $termForCount.';
  }

  @override
  String memberGroupFrontGroupSemantics(String name, String termPluralLower) {
    return 'Frente a $termPluralLower de $name';
  }

  @override
  String memberGroupFrontSomeAlreadyFronting(
    int count,
    String termForCount,
    int remaining,
  ) {
    return '$count $termForCount ya al frente. ¿Añadir les $remaining restantes?';
  }

  @override
  String get memberGroupManageNoGroups => 'Aún no hay grupos';

  @override
  String get memberGroupManageNoGroupsAction => 'Crear un grupo';

  @override
  String get memberGroupManageTitle => 'Grupos';

  @override
  String get memberNameLabel => 'Nombre *';

  @override
  String get memberNameHint => 'Ingresar nombre';

  @override
  String get memberNameRequired => 'El nombre es obligatorio';

  @override
  String get memberPronounsLabel => 'Pronombres';

  @override
  String get memberPronounsHint => 'p. ej. ella, elle, él';

  @override
  String get memberAgeLabel => 'Edad';

  @override
  String get memberAgeHint => 'Opcional';

  @override
  String get memberBioLabel => 'Bio';

  @override
  String get memberBioHint => 'Una breve descripción...';

  @override
  String get memberBioEditorTooltip => 'Editar bio';

  @override
  String get memberDisplayNameLabel => 'Nombre mostrado';

  @override
  String get memberDisplayNameHint => 'Alias opcional junto al nombre';

  @override
  String get memberBirthdayLabel => 'Cumpleaños';

  @override
  String get memberBirthdayHint => 'Toca para elegir una fecha';

  @override
  String get memberBirthdayHideYear => 'Ocultar año';

  @override
  String get memberBirthdayHideYearSubtitle => 'Mostrar solo mes y día';

  @override
  String get memberBirthdayClear => 'Borrar cumpleaños';

  @override
  String get memberSectionBirthday => 'Cumpleaños';

  @override
  String get memberMarkdownTitle => 'Formatear bio en markdown';

  @override
  String get memberMarkdownSubtitle => 'Mostrar el texto con formato markdown';

  @override
  String get memberAdminTitle => 'Admin';

  @override
  String get memberAdminSubtitle =>
      'Los admins pueden gestionar la configuración del sistema';

  @override
  String get memberAccentColorSectionTitle => 'Color de acento';

  @override
  String get memberCustomColorTitle => 'Color personalizado';

  @override
  String memberCustomColorSubtitle(String termSingularLower) {
    return 'Usar un color personal para $termSingularLower';
  }

  @override
  String get memberColorHexLabel => 'Color hex';

  @override
  String memberErrorSaving(String term, Object error) {
    return 'Error al guardar $term: $error';
  }

  @override
  String memberAgeDisplay(int age) {
    return 'Edad $age';
  }

  @override
  String memberSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count seleccionados',
      one: '1 seleccionado',
    );
    return '$_temp0';
  }

  @override
  String memberSearchConfirmSelectionTooltip(String termPluralLower) {
    return 'Confirmar $termPluralLower seleccionados';
  }

  @override
  String memberSaveTooltip(String termSingularLower) {
    return 'Guardar $termSingularLower';
  }

  @override
  String get memberEditTabEdit => 'Editar';

  @override
  String get memberEditTabStyle => 'Estilo';

  @override
  String get memberEditSectionAbout => 'Acerca de';

  @override
  String get memberEditSectionSettings => 'Ajustes';

  @override
  String get memberBulkActivate => 'Activar';

  @override
  String get memberBulkDeactivate => 'Desactivar';

  @override
  String memberNoInactive(String terms) {
    return 'Sin $terms inactivos';
  }

  @override
  String memberNoActive(String terms) {
    return 'Sin $terms activos';
  }

  @override
  String get memberConversationFallback => 'Conversación';

  @override
  String get memberCustomFieldSelectDate => 'Seleccionar fecha';

  @override
  String memberCustomFieldEnterHint(String fieldName) {
    return 'Ingresar $fieldName';
  }

  @override
  String get chatTitle => 'Mensajes';

  @override
  String get chatNewConversation => 'Nueva conversación';

  @override
  String get chatManageCategories => 'Gestionar categorías';

  @override
  String get chatSearchMessages => 'Buscar mensajes';

  @override
  String get chatNoConversations => 'Sin conversaciones';

  @override
  String get chatNoConversationsSubtitle => 'Empieza a chatear con tu sistema';

  @override
  String get chatErrorLoadingConversations => 'Error al cargar conversaciones';

  @override
  String get chatUncategorized => 'Sin categoría';

  @override
  String get chatMarkAsRead => 'Marcar como leído';

  @override
  String get chatMarkAllAsRead => 'Marcar todo como leído';

  @override
  String get chatMute => 'Silenciar';

  @override
  String get chatUnmute => 'Activar';

  @override
  String get chatDeleteConversationTitle => 'Eliminar conversación';

  @override
  String get chatDeleteConversationMessage =>
      '¿Seguro que quieres eliminar esta conversación? Todos los mensajes se eliminarán permanentemente.';

  @override
  String get chatDeleteConversationFullMessage =>
      '¿Seguro que quieres eliminar esta conversación? Todos los mensajes se eliminarán permanentemente. Esto no se puede deshacer.';

  @override
  String get chatBadgeMentionsOnly => 'Notificación: solo menciones';

  @override
  String get chatBadgeAllMessages => 'Notificación: todos los mensajes';

  @override
  String get chatHideArchived => 'Ocultar archivados';

  @override
  String get chatShowArchived => 'Mostrar archivados';

  @override
  String get chatConversationNotFound => 'Conversación no encontrada';

  @override
  String get chatConversationInfo => 'Información de la conversación';

  @override
  String get chatNoMessages => 'Aún no hay mensajes';

  @override
  String get chatStartConversation => '¡Inicia la conversación!';

  @override
  String chatErrorLoadingMessages(Object error) {
    return 'Error al cargar mensajes: $error';
  }

  @override
  String get chatLoadingOlderMessages => 'Cargando mensajes anteriores';

  @override
  String get chatSearchPlaceholder => 'Buscar mensajes...';

  @override
  String get chatSearchHint => 'Busca mensajes en todas tus conversaciones';

  @override
  String get chatSearchKeepTyping => 'Sigue escribiendo para buscar...';

  @override
  String chatSearchNoResults(String query) {
    return 'No se encontraron mensajes para \'$query\'';
  }

  @override
  String get chatSearchTryDifferent => 'Prueba con menos palabras o diferentes';

  @override
  String chatSearchError(Object error) {
    return 'Error: $error';
  }

  @override
  String get chatMessagePlaceholder => 'Mensaje';

  @override
  String get chatSendMessage => 'Enviar mensaje';

  @override
  String get chatSendMessageDisabled => 'Enviar mensaje, desactivado';

  @override
  String get chatRecordVoiceNote => 'Grabar nota de voz';

  @override
  String chatSpeakingAs(String name) {
    return 'Hablando como $name. Toca dos veces para cambiar.';
  }

  @override
  String chatChooseSpeakingMember(String termSingularLower) {
    return 'Elegir $termSingularLower hablante';
  }

  @override
  String get chatCancelReply => 'Cancelar respuesta';

  @override
  String get chatAddAttachment => 'Agregar archivo adjunto';

  @override
  String get chatCamera => 'Cámara';

  @override
  String get chatPhotoLibrary => 'Biblioteca de fotos';

  @override
  String get chatContextReply => 'Responder';

  @override
  String get chatContextCopyText => 'Copiar texto';

  @override
  String get chatContextEditMessage => 'Editar mensaje';

  @override
  String get chatContextDelete => 'Eliminar';

  @override
  String get chatCopied => 'Copiado';

  @override
  String get chatEditMessageTitle => 'Editar mensaje';

  @override
  String get chatMessageContentHint => 'Contenido del mensaje';

  @override
  String get chatDeleteMessageTitle => 'Eliminar mensaje';

  @override
  String get chatDeleteMessageMessage =>
      'Este mensaje se eliminará permanentemente.';

  @override
  String get chatReplyQuoteDeleted => 'Mensaje original eliminado';

  @override
  String chatReplyQuoteSemantics(String authorName, String content) {
    return 'Respondiendo a $authorName: $content. Toca dos veces para ir al mensaje.';
  }

  @override
  String get chatReplyQuoteDeletedSemantics => 'Mensaje original eliminado';

  @override
  String get chatMessageEdited => 'editado';

  @override
  String get chatInfoTitle => 'Info';

  @override
  String get chatInfoConversationTitle => 'Título de la conversación';

  @override
  String chatInfoCreatedAt(String date) {
    return 'Creado el $date';
  }

  @override
  String chatInfoParticipants(int count) {
    return 'Participantes ($count)';
  }

  @override
  String chatInfoAddMembers(String termPluralLower) {
    return 'Agregar $termPluralLower';
  }

  @override
  String get chatInfoOwner => 'Propietario';

  @override
  String get chatInfoAdmin => 'Admin';

  @override
  String chatInfoUnknownMember(String termSingular) {
    return '$termSingular desconocido';
  }

  @override
  String chatInfoErrorLoadingMember(String termSingularLower) {
    return 'Error al cargar $termSingularLower';
  }

  @override
  String get chatInfoCategory => 'Categoría';

  @override
  String get chatInfoCategoryNone => 'Ninguna';

  @override
  String chatInfoCategorySemantics(String name) {
    return 'Categoría: $name';
  }

  @override
  String get chatInfoDirectMessage => 'Mensaje directo';

  @override
  String get chatInfoGroupChat => 'Chat grupal';

  @override
  String chatInfoCannotManage(String memberName) {
    return '$memberName no puede gestionar esta conversación';
  }

  @override
  String get chatInfoArchiveConversation => 'Archivar conversación';

  @override
  String get chatInfoUnarchiveConversation => 'Desarchivar conversación';

  @override
  String get chatInfoLeaveConversation => 'Salir de la conversación';

  @override
  String get chatInfoDeleteConversation => 'Eliminar conversación';

  @override
  String get chatInfoConversationArchived => 'Conversación archivada';

  @override
  String get chatInfoConversationUnarchived => 'Conversación desarchivada';

  @override
  String chatInfoFailedSaveTitle(Object error) {
    return 'Error al guardar el título: $error';
  }

  @override
  String chatInfoFailedSaveEmoji(Object error) {
    return 'Error al guardar el emoji: $error';
  }

  @override
  String get chatLeaveConversationTitle => 'Salir de la conversación';

  @override
  String get chatLeaveConversationMessage =>
      '¿Salir de esta conversación? Tus mensajes anteriores permanecerán.';

  @override
  String get chatLeaveConversationConfirm => 'Salir';

  @override
  String get chatSelectNewOwner =>
      'Selecciona el nuevo propietario de la conversación';

  @override
  String chatAddMembersTitle(String termPlural) {
    return 'Agregar $termPlural';
  }

  @override
  String chatAddMembersAllAdded(String termPluralLower, Object termPlural) {
    return '$termPlural activos ya están en esta conversación.';
  }

  @override
  String chatAddMembersFailed(String termPluralLower, Object error) {
    return 'Error al agregar $termPluralLower: $error';
  }

  @override
  String get chatCreateTitle => 'Nueva conversación';

  @override
  String get chatCreateConversationTooltip => 'Crear conversación';

  @override
  String get chatCreateGroupTab => 'Grupo';

  @override
  String get chatCreateDirectMessageTab => 'Mensaje directo';

  @override
  String get chatCreateGroupName => 'Nombre del grupo';

  @override
  String get chatCreateGroupNameHint => 'p. ej., Discusión del sistema';

  @override
  String get chatCreateSelectParticipants => 'Seleccionar participantes (2+)';

  @override
  String chatCreateMessageAs(String name) {
    return 'Mensaje como $name con:';
  }

  @override
  String get chatCreateSelectAll => 'Seleccionar todo';

  @override
  String get chatCreateDeselectAll => 'Deseleccionar todo';

  @override
  String chatCreateNoMembers(String termPluralLower) {
    return 'No hay $termPluralLower disponibles. Crea $termPluralLower primero.';
  }

  @override
  String get chatCreateFronting => 'Al frente';

  @override
  String chatCreateFronterDeselectedWarning(String name) {
    return '$name está al frente actualmente pero no está en este chat. No podrás ver ni enviar mensajes.';
  }

  @override
  String chatCreateFailed(Object error) {
    return 'Error al crear la conversación: $error';
  }

  @override
  String get chatCategoriesTitle => 'Gestionar categorías';

  @override
  String get chatCategoriesNone => 'Aún no hay categorías';

  @override
  String get chatCategoriesNewHint => 'Nombre de nueva categoría';

  @override
  String get chatCategoriesCategoryNameHint => 'Nombre de categoría';

  @override
  String get chatCategoriesAddTooltip => 'Agregar categoría';

  @override
  String chatCategoriesDeleteTitle(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get chatCategoriesDeleteMessage =>
      'Las conversaciones en esta categoría quedarán sin categoría.';

  @override
  String chatCategoriesCreateFailed(Object error) {
    return 'Error al crear la categoría: $error';
  }

  @override
  String chatCategoriesRenameFailed(Object error) {
    return 'Error al renombrar la categoría: $error';
  }

  @override
  String chatCategoriesDeleteFailed(Object error) {
    return 'Error al eliminar la categoría: $error';
  }

  @override
  String chatNoMembersAvailable(String termPluralLower) {
    return 'No hay $termPluralLower disponibles';
  }

  @override
  String chatErrorLoadingMembersShort(String termPluralLower) {
    return 'Error al cargar $termPluralLower';
  }

  @override
  String get chatGifsTitle => 'GIFs';

  @override
  String get chatGifsSearchHint => 'Buscar GIFs';

  @override
  String get chatGifsPoweredBy => 'Funciona con KLIPY';

  @override
  String get chatGifsLoadFailed => 'Error al cargar GIFs';

  @override
  String get chatGifsNotFound => 'No se encontraron GIFs';

  @override
  String get chatGifsNotFoundSubtitle =>
      'Prueba con otros términos de búsqueda';

  @override
  String get chatGifConsentTitle => '¿Activar GIFs?';

  @override
  String get chatGifConsentIntro =>
      'Los GIFs usan un servicio de Klipy detrás del relay. Esto es lo que cada parte puede y no puede ver.';

  @override
  String get chatGifConsentRelayTitle => 'Lo que puede ver el relay de Prism';

  @override
  String get chatGifConsentRelayBody =>
      'Tu relay puede ver las búsquedas de GIF que envías a través de él y los metadatos de red de tu dispositivo. No puede ver tus chats cifrados.';

  @override
  String get chatGifConsentKlipyTitle => 'Lo que puede ver Klipy';

  @override
  String get chatGifConsentKlipyBody =>
      'Klipy recibe la solicitud de búsqueda desde el relay y puede ver los términos de búsqueda junto con la identidad de red del relay, no la tuya directamente.';

  @override
  String get chatGifConsentMediaTitle => 'Qué pasa cuando abres un GIF';

  @override
  String get chatGifConsentMediaBody =>
      'Las vistas previas y la reproducción del GIF siguen cargándose desde el host multimedia de Klipy, así que abrir un GIF puede conectar tu dispositivo directamente con Klipy.';

  @override
  String get chatGifConsentDecline => 'No, gracias';

  @override
  String get chatGifConsentEnable => 'Activar GIFs';

  @override
  String chatGifsFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count GIFs encontrados',
      one: '1 GIF encontrado',
    );
    return '$_temp0';
  }

  @override
  String get chatGifSendButton => 'Enviar';

  @override
  String chatGifPreviewSemantics(String description) {
    return 'Vista previa del GIF: $description. Botón Enviar abajo.';
  }

  @override
  String chatGifCellSemantics(String description) {
    return 'GIF: $description';
  }

  @override
  String get chatGifCellSemanticsDefault => 'GIF: resultado de búsqueda';

  @override
  String get chatMediaNoLongerAvailable => 'Contenido multimedia no disponible';

  @override
  String get chatAttachedImagePreview => 'Vista previa de imagen adjunta';

  @override
  String get chatRemoveAttachment => 'Eliminar archivo adjunto';

  @override
  String get chatSearchClear => 'Borrar búsqueda';

  @override
  String get chatInfoEditEmoji => 'Editar emoji de la conversación';

  @override
  String get chatInfoEditTitle => 'Editar título de la conversación';

  @override
  String get chatImageAttachment => 'Adjunto de imagen';

  @override
  String get chatImageLoading => 'Cargando adjunto de imagen.';

  @override
  String get chatImageOpenFullScreen =>
      'Adjunto de imagen. Toca dos veces para ver en pantalla completa.';

  @override
  String chatMessageToggleReaction(String emoji) {
    return 'Alternar reacción $emoji';
  }

  @override
  String get chatMessageAddCustomReaction => 'Agregar reacción personalizada';

  @override
  String get chatMessageToggleTimeFormat => 'Cambiar formato de hora';

  @override
  String chatReactionAdd(String emoji) {
    return 'Agregar reacción $emoji';
  }

  @override
  String chatReactionSheetTitle(String emoji) {
    return 'Reacciones $emoji';
  }

  @override
  String chatVoiceNoteSemantics(String duration) {
    return 'Nota de voz del mensaje, $duration';
  }

  @override
  String chatVoiceNoteLoading(String duration) {
    return 'Cargando nota de voz, $duration';
  }

  @override
  String chatVoiceNotePause(String duration) {
    return 'Pausar nota de voz, $duration';
  }

  @override
  String chatVoiceNotePlay(String duration) {
    return 'Reproducir nota de voz, $duration';
  }

  @override
  String chatVoiceNoteSpeed(String speed) {
    return 'Velocidad de reproducción ${speed}x. Toca dos veces para cambiar.';
  }

  @override
  String get chatVoiceNoteError =>
      'Error al cargar la nota de voz. Toca para reintentar.';

  @override
  String get chatImageError =>
      'Error al cargar la imagen. Toca para reintentar.';

  @override
  String get chatImageUploadFailed => 'Error al enviar la imagen';

  @override
  String get chatVoiceNoteUploadFailed => 'Error al enviar la nota de voz';

  @override
  String get chatVoiceRecorderCancel => 'Cancelar grabación';

  @override
  String get chatVoiceRecorderSend => 'Enviar nota de voz';

  @override
  String chatImageViewerSemantics(String caption) {
    return 'Visor de imagen a pantalla completa. $caption. Pellizca para hacer zoom, desliza hacia abajo para cerrar.';
  }

  @override
  String get chatImageViewerClose => 'Cerrar visor';

  @override
  String get chatImageViewerShare => 'Compartir imagen';

  @override
  String get chatConversationNoTitle => 'Conversación';

  @override
  String memberSelectLoadFailed(String termPlural) {
    return 'Error al cargar $termPlural';
  }

  @override
  String get onboardingPermissionsNotGranted => 'No concedido';

  @override
  String get syncSetupConnectingToJoiner =>
      'Conectando con el dispositivo que se une...';

  @override
  String get syncSetupCompletingPairing => 'Completando emparejamiento...';

  @override
  String get syncSetupScanJoinerPrompt =>
      'El nuevo dispositivo puede generar un código QR de solicitud de emparejamiento. Escanéalo aquí para aprobar el dispositivo y compartir tus credenciales de sincronización.';

  @override
  String get setupDeviceEnterMnemonicTitle =>
      'Introduce tu frase de recuperación';

  @override
  String get setupDeviceEnterMnemonicSubtitle =>
      'Se necesita para configurar este nuevo dispositivo. Tu frase de recuperación no se guarda en este dispositivo: escríbela desde tu copia de seguridad.';

  @override
  String get setupDeviceMnemonicContinue => 'Continuar';

  @override
  String get syncSetupScanJoinerButton =>
      'Escanear QR del dispositivo que se une';

  @override
  String get syncSetupScanJoinerDescription =>
      'Escanea el código QR de emparejamiento del dispositivo que se une.';

  @override
  String get syncSetupInvalidPairingQr =>
      'Código QR de emparejamiento no válido.';

  @override
  String get syncSetupVerifyDescription =>
      'Confirma que estas palabras coincidan en el dispositivo que se une.';

  @override
  String get syncSetupPairingComplete =>
      '¡Emparejamiento completo! El nuevo dispositivo ya se está sincronizando.';

  @override
  String get syncSetupSnapshotNotice =>
      'Se subió una instantánea cifrada y se eliminará automáticamente después de que se conecte el nuevo dispositivo (o tras 24 horas).';

  @override
  String get syncSetupPairingFailed => 'Falló el emparejamiento';

  @override
  String get syncSetupSnapshotUploadingTitle =>
      'Subiendo tu sistema al nuevo dispositivo';

  @override
  String syncSetupSnapshotUploadProgress(String sent, String total) {
    return '$sent de $total';
  }

  @override
  String get syncSetupSnapshotUploadStarting => 'Preparando la subida...';

  @override
  String get syncSetupSnapshotUploadFailedTitle =>
      'No se pudo subir tu sistema';

  @override
  String get syncSetupSnapshotUploadRetry => 'Reintentar subida';

  @override
  String get syncSetupPairingReadyTitle => 'Emparejamiento listo';

  @override
  String get syncSetupPairingReadyWaiting =>
      'Esperando a que el otro dispositivo termine la configuración.';

  @override
  String memberAvatarSemantics(String name) {
    return 'Avatar de $name';
  }

  @override
  String memberAvatarSemanticsUnnamed(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Avatar de $termSingularLower';
  }

  @override
  String groupMemberAvatarSemantics(String termSingularLower) {
    return 'Avatar de $termSingularLower del grupo';
  }

  @override
  String get habitsReminderNotificationTitle => 'Recordatorio de hábito';

  @override
  String habitsReminderNotificationBody(String habitName) {
    return 'Hora de completar: $habitName';
  }

  @override
  String get chatTileNoMessages => 'Aún no hay mensajes';

  @override
  String get showPassword => 'Mostrar contraseña';

  @override
  String get hidePassword => 'Ocultar contraseña';

  @override
  String get showToken => 'Mostrar token';

  @override
  String get hideToken => 'Ocultar token';

  @override
  String get onboardingCloseOnboarding => 'Cerrar introducción';

  @override
  String onboardingProgressStep(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get onboardingGetStarted => 'Comenzar';

  @override
  String get onboardingContinue => 'Continuar';

  @override
  String onboardingErrorCompletingSetup(Object error) {
    return 'Error al completar la configuración: $error';
  }

  @override
  String get onboardingImportCompleteTitle => 'Importación completa';

  @override
  String get onboardingImportCompleteDescription =>
      'Tu exportación de Prism ha sido restaurada y este dispositivo está listo.';

  @override
  String get onboardingImportedDataLabel => 'Datos importados';

  @override
  String get onboardingWelcomePrivateTitle => 'Privado por defecto';

  @override
  String get onboardingWelcomePrivateDescription =>
      'Ni siquiera nosotros podemos leer tus datos. Todo permanece en tu dispositivo a menos que elijas sincronizar.';

  @override
  String get onboardingWelcomeSyncTitle => 'Sincroniza entre dispositivos';

  @override
  String get onboardingWelcomeSyncDescription =>
      'Cifrado de extremo a extremo. El servidor solo ve ruido.';

  @override
  String get onboardingWelcomeBuiltForYouTitle => 'Hecho para ti';

  @override
  String get onboardingWelcomeBuiltForYouDescription =>
      'Tus palabras, tus colores, tus funciones. Prism se adapta a cómo funciona tu sistema.';

  @override
  String onboardingAddMembersNoMembers(
    String termPluralLower,
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Aún no hay $termPluralLower.\nToca «Agregar $termSingularLower» para empezar.';
  }

  @override
  String onboardingAddMembersRemoveMember(String termSingularLower) {
    return 'Eliminar $termSingularLower';
  }

  @override
  String onboardingAddMembersAddMember(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Agregar $termSingularLower';
  }

  @override
  String onboardingAddMemberSheetTitle(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Agregar $termSingularLower';
  }

  @override
  String get onboardingAddMemberFieldEmoji => 'Emoji';

  @override
  String get onboardingAddMemberFieldName => 'Nombre *';

  @override
  String get onboardingAddMemberPronounSheHer => 'Ella/La';

  @override
  String get onboardingAddMemberPronounHeHim => 'Él/Lo';

  @override
  String get onboardingAddMemberPronounTheyThem => 'Elle/Le';

  @override
  String get onboardingAddMemberFieldPronounsCustom =>
      'Pronombres (personalizados)';

  @override
  String get onboardingAddMemberFieldAge => 'Edad (opcional)';

  @override
  String get onboardingAddMemberFieldBio => 'Bio (opcional)';

  @override
  String get onboardingAddMemberSaveButton => 'Agregar';

  @override
  String get onboardingFeaturesChat => 'Chat';

  @override
  String onboardingFeaturesChatDescription(String termPluralLower) {
    return 'Mensajería interna entre $termPluralLower del sistema';
  }

  @override
  String get onboardingFeaturesPolls => 'Encuestas';

  @override
  String get onboardingFeaturesPollsDescription =>
      'Crea encuestas para decisiones del sistema';

  @override
  String get onboardingFeaturesHabits => 'Hábitos';

  @override
  String get onboardingFeaturesHabitsDescription =>
      'Registra hábitos y rutinas diarias';

  @override
  String get onboardingFeaturesSleepTracking => 'Seguimiento del sueño';

  @override
  String get onboardingFeaturesSleepTrackingDescription =>
      'Monitorea patrones y calidad del sueño';

  @override
  String get onboardingFeaturesNotes => 'Notas';

  @override
  String get onboardingFeaturesNotesDescription =>
      'Un diario personal y espacio de escritura para tu sistema';

  @override
  String get onboardingFeaturesBoards => 'Tableros de Mensajes';

  @override
  String get onboardingFeaturesBoardsDescription =>
      'Mensajes cortos entre compañeros del sistema — línea de tiempo pública más bandeja de entrada privada.';

  @override
  String get onboardingFeaturesReminders => 'Recordatorios';

  @override
  String onboardingFeaturesRemindersDescription(String termPluralLower) {
    return 'Configura recordatorios para ti o $termPluralLower del sistema';
  }

  @override
  String get onboardingCompleteTrackFrontingTitle =>
      'Registra quién está al frente';

  @override
  String get onboardingCompleteTrackFrontingDescription =>
      'Anota quién está presente y revisa patrones con el tiempo.';

  @override
  String get onboardingCompleteChatTitle => 'Habla entre ustedes';

  @override
  String get onboardingCompleteChatDescription =>
      'Deja mensajes para quien esté al frente después, o chatea en tiempo real.';

  @override
  String get onboardingCompletePollsTitle => 'Decide juntos';

  @override
  String get onboardingCompletePollsDescription =>
      'Encuestas, votos — la democracia que tu sistema merece.';

  @override
  String get onboardingImportDataSourcePickerIntro =>
      'Puedes importar tus datos existentes o saltarte este paso para comenzar desde cero.';

  @override
  String get onboardingImportSyncWithDevice =>
      'Sincronizar con dispositivo existente';

  @override
  String get onboardingImportSyncWithDeviceDescription =>
      'Escanea un código QR de emparejamiento para sincronizar datos desde otro dispositivo';

  @override
  String get onboardingImportPluralKit => 'PluralKit';

  @override
  String get onboardingImportPluralKitDescription =>
      'Importa integrantes e historial de turnos desde PluralKit mediante token de API';

  @override
  String get onboardingImportPrismExport => 'Exportación de Prism';

  @override
  String get onboardingImportPrismExportDescription =>
      'Importa desde un archivo .json o .prism cifrado de Prism';

  @override
  String get onboardingImportSimplyPlural => 'Simply Plural';

  @override
  String get onboardingImportSimplyPluralDescription =>
      'Importa desde un archivo JSON exportado de Simply Plural';

  @override
  String get onboardingImportLaterHint =>
      'Siempre puedes importar datos más tarde desde Ajustes.';

  @override
  String get onboardingImportOtherOptions => 'Otras opciones de importación';

  @override
  String get onboardingPluralKitHowToGetToken => 'Cómo obtener tu token:';

  @override
  String get onboardingPluralKitStep1 => 'Abre Discord';

  @override
  String get onboardingPluralKitStep2 =>
      'Envía un DM al bot PluralKit: pk;token';

  @override
  String get onboardingPluralKitStep3 => 'Copia el token y pégalo abajo';

  @override
  String get onboardingPluralKitTokenHint => 'Pega tu token de PluralKit';

  @override
  String get onboardingPluralKitImportButton => 'Importar datos de PluralKit';

  @override
  String get onboardingPluralKitConnecting => 'Conectando a PluralKit…';

  @override
  String get onboardingPluralKitImportingMembers => 'Importando integrantes…';

  @override
  String get onboardingPluralKitImportingHistory =>
      'Importando historial de cambios…';

  @override
  String onboardingPluralKitImportSuccess(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '¡Se importaron $count integrantes desde PluralKit!',
      one: '¡Se importó 1 integrante desde PluralKit!',
    );
    return '$_temp0';
  }

  @override
  String get onboardingPluralKitErrorEnterToken =>
      'Por favor ingresa tu token de PluralKit.';

  @override
  String get onboardingPluralKitErrorCouldNotConnect =>
      'No se pudo conectar. Por favor verifica tu token.';

  @override
  String onboardingImportError(Object error) {
    return 'Error al importar: $error';
  }

  @override
  String onboardingImportReadFileFailed(Object error) {
    return 'Error al leer el archivo: $error';
  }

  @override
  String get onboardingImportPasswordEmpty =>
      'La contraseña no puede estar vacía';

  @override
  String get onboardingImportIncorrectPassword => 'Contraseña incorrecta';

  @override
  String onboardingImportDecryptionFailed(Object error) {
    return 'Error al descifrar: $error';
  }

  @override
  String get onboardingImportUnencryptedBackup =>
      'Esta copia de seguridad no está cifrada. Vuelve a exportar desde la app para obtener un archivo .prism seguro.';

  @override
  String get onboardingPrismExportHowToExport => 'Cómo exportar desde Prism:';

  @override
  String get onboardingPrismExportStep1 => 'Abre Prism en tu otro dispositivo';

  @override
  String get onboardingPrismExportStep2 =>
      'Ve a Ajustes → Importar y exportar → Exportar datos';

  @override
  String get onboardingPrismExportStep3 =>
      'Guarda el archivo .json o .prism y selecciónalo abajo';

  @override
  String get onboardingPrismExportSelectFile =>
      'Seleccionar archivo de exportación';

  @override
  String get onboardingPrismExportEncryptedTitle => 'Exportación cifrada';

  @override
  String get onboardingPrismExportEncryptedDescription =>
      'Ingresa la contraseña de exportación para desbloquear este respaldo de Prism.';

  @override
  String get onboardingPrismExportPasswordHint => 'Contraseña de exportación';

  @override
  String get onboardingPrismExportUnlockButton => 'Desbloquear exportación';

  @override
  String get onboardingPrismExportReadyToImport => 'Listo para importar';

  @override
  String get onboardingPrismExportPreviewDescription =>
      'Esto restaurará tu sistema de Prism exportado y completará la configuración en este dispositivo.';

  @override
  String get onboardingPrismExportImportButton => 'Importar y continuar';

  @override
  String get onboardingPrismExportImporting =>
      'Importando tu exportación de Prism...';

  @override
  String get onboardingSimplyPluralHowToExport =>
      'Cómo exportar desde Simply Plural:';

  @override
  String get onboardingSimplyPluralStep1 => 'Abre la app Simply Plural';

  @override
  String get onboardingSimplyPluralStep2 => 'Ve a Ajustes → Exportar datos';

  @override
  String get onboardingSimplyPluralStep3 =>
      'Guarda el archivo JSON y selecciónalo abajo';

  @override
  String get onboardingSimplyPluralSelectFile =>
      'Seleccionar archivo de exportación';

  @override
  String get onboardingSimplyPluralReadingFile => 'Leyendo archivo...';

  @override
  String get onboardingSimplyPluralFoundData => 'Datos encontrados:';

  @override
  String get onboardingSimplyPluralImportButton => 'Importar datos';

  @override
  String get onboardingSimplyPluralImportComplete =>
      '¡Importación completa! Tus datos están listos.';

  @override
  String get onboardingImportPreviewMembers => 'Integrantes';

  @override
  String get onboardingImportPreviewFrontingSessions => 'Sesiones al frente';

  @override
  String get onboardingImportPreviewConversations => 'Conversaciones';

  @override
  String get onboardingImportPreviewMessages => 'Mensajes';

  @override
  String get onboardingImportPreviewHabits => 'Hábitos';

  @override
  String get onboardingImportPreviewNotes => 'Notas';

  @override
  String get onboardingImportPreviewTotalRecords => 'Total de registros';

  @override
  String get onboardingImportPreviewCustomFronts => 'Fronts personalizados';

  @override
  String get onboardingImportPreviewGroups => 'Grupos';

  @override
  String get onboardingImportPreviewPolls => 'Encuestas';

  @override
  String get onboardingImportPreviewCustomFields => 'Campos personalizados';

  @override
  String get onboardingImportPreviewComments => 'Comentarios';

  @override
  String get onboardingImportPreviewReminders => 'Recordatorios';

  @override
  String get onboardingImportPreviewSleepSessions => 'Sesiones de sueño';

  @override
  String get onboardingImportPreviewFriends => 'Amigos';

  @override
  String get onboardingImportPreviewMediaAttachments => 'Archivos adjuntos';

  @override
  String get onboardingDataReadyMembers => 'Integrantes';

  @override
  String get onboardingDataReadyFrontingSessions => 'Sesiones al frente';

  @override
  String get onboardingDataReadyConversations => 'Conversaciones';

  @override
  String get onboardingDataReadyMessages => 'Mensajes';

  @override
  String get onboardingDataReadyHabits => 'Hábitos';

  @override
  String get onboardingDataReadyNotes => 'Notas';

  @override
  String get onboardingDataReadySyncedData => 'Datos sincronizados';

  @override
  String get onboardingSystemNameHint => 'Ingresa el nombre del sistema';

  @override
  String get onboardingSystemNameHelperText =>
      'Así se identificará tu sistema en la app.';

  @override
  String get onboardingSystemNameHelperTextImported =>
      'Lo sacamos de tu importación — edítalo si prefieres algo distinto.';

  @override
  String get onboardingWhosFrontingSelectHint =>
      'Toca para seleccionar quién está al frente ahora';

  @override
  String onboardingWhosFrontingNoMembers(String termPluralLower) {
    return 'Aún no hay $termPluralLower.\nVuelve atrás para agregar $termPluralLower primero.';
  }

  @override
  String get onboardingChatSuggestedChannels => 'Canales sugeridos';

  @override
  String get onboardingChatCustomChannel => 'Canal personalizado';

  @override
  String get onboardingChatChannelNameHint => 'Nombre del canal';

  @override
  String onboardingChatChannelAllMembers(
    String termPlural,
    Object termPluralLower,
  ) {
    return 'Todos $termPluralLower';
  }

  @override
  String get onboardingChatChannelVenting => 'Desahogo';

  @override
  String get onboardingChatChannelPlanning => 'Planificación';

  @override
  String get onboardingChatChannelJournal => 'Diario';

  @override
  String get onboardingChatChannelUpdates => 'Actualizaciones';

  @override
  String get onboardingChatChannelRandom => 'Aleatorio';

  @override
  String get onboardingPreferencesTerminology => 'Terminología';

  @override
  String get onboardingPreferencesCustomTerminology => 'Personalizado';

  @override
  String get onboardingPreferencesSingularHint => 'Singular (p. ej. Alter)';

  @override
  String get onboardingPreferencesPluralHint => 'Plural (p. ej. Alters)';

  @override
  String get onboardingPreferencesAccentColor => 'Color de acento';

  @override
  String onboardingPreferencesPerMemberColors(
    String termSingular,
    Object termSingularLower,
  ) {
    return 'Colores por $termSingularLower';
  }

  @override
  String onboardingPreferencesPerMemberColorsSubtitle(
    String termSingularLower,
  ) {
    return 'Permite que cada $termSingularLower tenga su propio color de acento';
  }

  @override
  String get onboardingSyncJoinYourGroup =>
      'Únete a tu grupo de sincronización';

  @override
  String get onboardingSyncJoinDescription =>
      'Crea una solicitud de emparejamiento en este dispositivo y pide a un dispositivo existente que la apruebe.';

  @override
  String get onboardingSyncRequestToJoin => 'Solicitar unirse';

  @override
  String get onboardingSyncRequestToJoinHint =>
      'Muestra un código QR para que tu dispositivo existente lo escanee y apruebe.';

  @override
  String get onboardingSyncShowToExistingDevice =>
      'Muestra esto a tu dispositivo existente';

  @override
  String get onboardingSyncScanInstructions =>
      'En tu dispositivo existente, abre «Configurar otro dispositivo» y escanea este código.';

  @override
  String get onboardingSyncWaitingForScan =>
      'Esperando que el otro dispositivo escanee...';

  @override
  String get onboardingSyncWaitingForVerification =>
      'Esperando verificación de seguridad...';

  @override
  String get onboardingSyncWaitingForVerificationSubtitle =>
      'El otro dispositivo se está conectando. Los códigos de seguridad aparecerán en breve.';

  @override
  String get onboardingSyncVerifySecurityCode =>
      'Verificar código de seguridad';

  @override
  String get onboardingSyncVerifyDescription =>
      'Confirma que estas palabras coinciden con las que se muestran en tu dispositivo existente.';

  @override
  String get onboardingSyncTheyMatch => 'Coinciden';

  @override
  String get onboardingSyncTheyDontMatch => 'No coinciden';

  @override
  String get onboardingSyncEnterPassword => 'Ingresa tu PIN de sincronización';

  @override
  String get onboardingSyncEnterPasswordDescription =>
      'Ingresa el PIN de 6 dígitos del dispositivo con el que te estás sincronizando.';

  @override
  String get onboardingSyncConnecting => 'Emparejando y sincronizando...';

  @override
  String get onboardingSyncConnectingSubtitle =>
      'Esto puede tardar un momento mientras se registra el dispositivo.';

  @override
  String get onboardingSyncDataStillSyncing =>
      'Algunos datos aún se están sincronizando y aparecerán en breve.';

  @override
  String get onboardingSyncWelcomeBackTitle => '¡Bienvenide de vuelta!';

  @override
  String get onboardingSyncWelcomeBackDescription =>
      'Tu dispositivo ha sido emparejado y tus datos están listos.';

  @override
  String get onboardingSyncUnknownError => 'Ocurrió un error desconocido.';

  @override
  String get habitsNewHabit => 'Nuevo hábito';

  @override
  String get habitsEditHabit => 'Editar hábito';

  @override
  String get habitsSectionBasicInfo => 'INFORMACIÓN BÁSICA';

  @override
  String get habitsFieldName => 'Nombre';

  @override
  String get habitsFieldNameHint => 'p. ej., Meditación matutina';

  @override
  String get habitsFieldDescription => 'Descripción (opcional)';

  @override
  String get habitsSectionSchedule => 'HORARIO';

  @override
  String get habitsIntervalEvery => 'Cada ';

  @override
  String get habitsIntervalDays => ' días';

  @override
  String get habitsIntervalDecrease => 'Reducir intervalo';

  @override
  String get habitsIntervalIncrease => 'Aumentar intervalo';

  @override
  String get habitsSectionNotifications => 'NOTIFICACIONES';

  @override
  String get habitsEnableReminders => 'Activar recordatorios';

  @override
  String get habitsReminderTime => 'Hora del recordatorio';

  @override
  String get habitsReminderTimeNotSet => 'No establecida';

  @override
  String habitsReminderSetFor(String time) {
    return 'Recordatorio establecido para $time';
  }

  @override
  String get habitsCustomMessageField => 'Mensaje personalizado (opcional)';

  @override
  String get habitsSectionAssignment => 'ASIGNACIÓN';

  @override
  String habitsAssignedMember(String termSingular) {
    return '$termSingular asignado';
  }

  @override
  String get habitsAssignedMemberAnyone => 'Cualquiera';

  @override
  String get habitsOnlyNotifyWhenFronting =>
      'Notificar solo cuando esté al frente';

  @override
  String habitsOnlyFrontingCaveat(String termSingularLower) {
    return 'Los recordatorios se enviarán aunque $termSingularLower no esté al frente — la entrega consciente del frente requiere acceso en segundo plano.';
  }

  @override
  String get habitsPrivate => 'Privado';

  @override
  String get habitsPrivateSubtitle => 'Ocultar en vistas compartidas';

  @override
  String get habitsCompleteHabit => 'Completar hábito';

  @override
  String get habitsCompletedAt => 'Completado a las';

  @override
  String get habitsCompletedBy => 'Completado por';

  @override
  String get habitsSectionRating => 'VALORACIÓN';

  @override
  String habitsRateNStars(int n) {
    return 'Valorar $n de 5 estrellas';
  }

  @override
  String habitsRateNStarsTooltip(int n) {
    return 'Valorar $n estrellas';
  }

  @override
  String get habitsNotesField => 'Notas (opcional)';

  @override
  String get habitsDetailDeleteTitle => 'Eliminar hábito';

  @override
  String get habitsDetailDeleteMessage =>
      'Esto eliminará permanentemente este hábito y todas sus completaciones. Esta acción no se puede deshacer.';

  @override
  String get habitsDetailMoreOptions => 'Más opciones';

  @override
  String habitsDetailFrequencyEveryNDays(int n) {
    return 'Cada $n días';
  }

  @override
  String get habitsDetailSectionRecentCompletions => 'Completaciones recientes';

  @override
  String get habitsDetailNoCompletions => 'Aún no hay completaciones';

  @override
  String get habitsDetailNoCompletionsSubtitle =>
      'Completa este hábito para comenzar a registrar el progreso.';

  @override
  String get habitsStatCompletions => 'Completaciones';

  @override
  String get habitsStatCompletionRate => 'Tasa de completación';

  @override
  String habitsStatCurrentStreak(int count) {
    return '$count de racha';
  }

  @override
  String habitsStatBestStreak(int count) {
    return '$count mejor';
  }

  @override
  String habitsStatsSemanticsLabel(int completions, String rate) {
    return '$completions completaciones, $rate% de tasa de completación';
  }

  @override
  String habitsCompletionRatedNStars(int n) {
    return 'Valorado con $n de 5 estrellas';
  }

  @override
  String habitsCompletionTileToday(String time) {
    return 'Hoy $time';
  }

  @override
  String habitsCompletionTileYesterday(String time) {
    return 'Ayer $time';
  }

  @override
  String get habitsAlreadyCompleted => 'Hábito ya completado para este período';

  @override
  String get habitsCompleteButtonLabel => 'Completar hábito';

  @override
  String get habitsCompleted => 'Completado';

  @override
  String get habitsComplete => 'Completar';

  @override
  String get habitsListTitle => 'Hábitos';

  @override
  String get habitsCreateHabitTooltip => 'Crear hábito';

  @override
  String get habitsEmptyTitle => 'Aún no hay hábitos';

  @override
  String get habitsEmptySubtitle =>
      'Crea hábitos para registrar rutinas diarias, autocuidado o cualquier cosa que tu sistema quiera mantener.';

  @override
  String get habitsEmptyCreateLabel => 'Crear hábito';

  @override
  String get habitsSectionUpcoming => 'Próximos';

  @override
  String get habitsSectionInactive => 'Inactivos';

  @override
  String habitsWeeklyProgressSemantics(int completed, int total) {
    return '$completed de $total días completados esta semana';
  }

  @override
  String get habitsTodayAllDone => 'todo listo';

  @override
  String get habitsTodaySemantics => 'Hoy';

  @override
  String get habitsTodayAllDoneSemantics =>
      'Hoy, todos los hábitos completados';

  @override
  String get habitsTodayHeader => 'Hoy';

  @override
  String get habitsSectionComplete => 'Completados';

  @override
  String habitsChipCompletedSemantics(String name) {
    return '$name, completado';
  }

  @override
  String habitsChipCompleteSemantics(String name) {
    return 'Completar $name';
  }

  @override
  String habitsColorSemantics(String hex, String selected) {
    return 'Color #$hex$selected';
  }

  @override
  String get habitsColorSelected => ', seleccionado';

  @override
  String get pollsNewPoll => 'Nueva encuesta';

  @override
  String get pollsQuestionLabel => 'Pregunta';

  @override
  String get pollsQuestionHint => '¿Qué quieres preguntar?';

  @override
  String get pollsDescriptionLabel => 'Descripción (opcional)';

  @override
  String get pollsDescriptionHint => 'Añade contexto o detalles...';

  @override
  String get pollsOptionsHeader => 'Opciones';

  @override
  String pollsOptionLabel(int n) {
    return 'Opción $n';
  }

  @override
  String get pollsRemoveOptionTooltip => 'Eliminar opción';

  @override
  String get pollsAddOption => 'Agregar opción';

  @override
  String get pollsAddOtherOption => 'Agregar opción «Otro»';

  @override
  String get pollsAddOtherOptionSubtitle => 'Permite respuestas de texto libre';

  @override
  String get pollsAnonymousVoting => 'Votación anónima';

  @override
  String get pollsAnonymousVotingSubtitle => 'Ocultar quién votó qué';

  @override
  String get pollsAllowMultipleVotes => 'Permitir múltiples votos';

  @override
  String pollsAllowMultipleVotesSubtitle(String plural) {
    return '$plural pueden votar por más de una opción';
  }

  @override
  String get pollsSetExpiration => 'Establecer vencimiento';

  @override
  String get pollsNoExpiration =>
      'La encuesta permanece abierta hasta que se cierre manualmente';

  @override
  String get pollsPickDateTime => 'Elegir fecha y hora';

  @override
  String pollsChangeDateTime(String datetime) {
    return 'Cambiar: $datetime';
  }

  @override
  String pollsCreateError(Object error) {
    return 'Error al crear la encuesta: $error';
  }

  @override
  String get pollsListTitle => 'Encuestas';

  @override
  String get pollsCreateTooltip => 'Crear encuesta';

  @override
  String get pollsFilterActive => 'Activas';

  @override
  String get pollsFilterClosed => 'Cerradas';

  @override
  String get pollsFilterAll => 'Todas';

  @override
  String get pollsEmptyActiveTitle => 'No hay encuestas activas';

  @override
  String get pollsEmptyActiveSubtitle =>
      'Crea una encuesta para que tu sistema vote';

  @override
  String get pollsEmptyClosedTitle => 'No hay encuestas cerradas';

  @override
  String get pollsEmptyClosedSubtitle =>
      'Las encuestas cerradas y vencidas aparecerán aquí';

  @override
  String get pollsEmptyAllTitle => 'Aún no hay encuestas';

  @override
  String get pollsEmptyAllSubtitle => 'Crea tu primera encuesta para comenzar';

  @override
  String get pollsEmptyCreateLabel => 'Crear encuesta';

  @override
  String get pollsLoadError => 'Error al cargar las encuestas';

  @override
  String pollsVoteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count votos',
      one: '1 voto',
    );
    return '$_temp0';
  }

  @override
  String pollsOptionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count opciones',
      one: '1 opción',
    );
    return '$_temp0';
  }

  @override
  String get pollsExpired => 'Vencida';

  @override
  String get pollsClosed => 'Cerrada';

  @override
  String pollsCountdownDays(int n) {
    return '${n}d restantes';
  }

  @override
  String pollsCountdownHours(int n) {
    return '${n}h restantes';
  }

  @override
  String pollsCountdownMinutes(int n) {
    return '${n}min restantes';
  }

  @override
  String get pollsCountdownEndingSoon => 'Terminando pronto';

  @override
  String get pollsAnonymous => 'Anónima';

  @override
  String get pollsMultiVote => 'Multivoto';

  @override
  String pollsDetailLoadError(Object error) {
    return 'Error al cargar la encuesta: $error';
  }

  @override
  String get pollsDetailNotFound => 'Encuesta no encontrada';

  @override
  String get pollsDetailClosePollTooltip => 'Cerrar encuesta';

  @override
  String get pollsDetailMoreOptions => 'Más opciones';

  @override
  String get pollsDetailResultsLabel => 'Resultados';

  @override
  String get pollsDetailOptionsLabel => 'Opciones';

  @override
  String get pollsDetailVoteAs => 'Votar como';

  @override
  String pollsDetailNoMembers(String termPluralLower) {
    return 'No hay $termPluralLower disponibles';
  }

  @override
  String get pollsDetailSubmitVote => 'Enviar voto';

  @override
  String get pollsDetailVoteSubmitted => 'Voto enviado';

  @override
  String pollsDetailVoteError(Object error) {
    return 'Error al votar: $error';
  }

  @override
  String get pollsDetailClosePollTitle => '¿Cerrar encuesta?';

  @override
  String get pollsDetailClosePollMessage =>
      'No se podrán emitir más votos una vez que la encuesta esté cerrada. Esto no se puede deshacer.';

  @override
  String get pollsDetailClosePollConfirm => 'Cerrar encuesta';

  @override
  String get pollsDetailDeleteTitle => '¿Eliminar encuesta?';

  @override
  String get pollsDetailDeleteMessage =>
      'Esto eliminará permanentemente la encuesta y todos los votos. Esta acción no se puede deshacer.';

  @override
  String get pollsDetailExpired => 'Vencida';

  @override
  String pollsDetailExpiresLabel(String date) {
    return 'Vence $date';
  }

  @override
  String get pollsDetailOtherResponseHint => 'Ingresa tu respuesta...';

  @override
  String pollsNotificationBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count encuestas necesitan',
      one: '1 encuesta necesita',
    );
    return '$_temp0 tu voto';
  }

  @override
  String get migrationImportData => 'Importar datos';

  @override
  String get migrationReadingFile => 'Leyendo archivo…';

  @override
  String get migrationVerifyingToken => 'Verificando token…';

  @override
  String get migrationImportFromSimplyPlural => 'Importar desde Simply Plural';

  @override
  String get migrationImportDescription =>
      'Trae tus datos existentes a Prism. Elige cómo importar tus datos de Simply Plural.';

  @override
  String get migrationConnectWithApi => 'Conectar con API';

  @override
  String get migrationConnectWithApiSubtitle =>
      'No necesitas exportar un archivo — importa directamente desde tu cuenta';

  @override
  String get migrationRecommended => 'Recomendado';

  @override
  String get migrationImportFromFile => 'Importar desde archivo';

  @override
  String get migrationImportFromFileSubtitle =>
      'Usa un archivo de exportación JSON de Simply Plural';

  @override
  String get migrationSupportedDataTypes => 'Tipos de datos compatibles';

  @override
  String migrationSupportedMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get migrationSupportedCustomFronts => 'Frentes personalizados';

  @override
  String get migrationSupportedFrontingHistory => 'Historial al frente';

  @override
  String get migrationSupportedChatChannels => 'Canales de chat y mensajes';

  @override
  String get migrationSupportedPolls => 'Encuestas';

  @override
  String migrationSupportedMemberColors(String termSingular) {
    return 'Colores de $termSingular';
  }

  @override
  String migrationSupportedMemberDescriptions(String termSingular) {
    return 'Descripciones de $termSingular';
  }

  @override
  String get migrationSupportedAvatarImages => 'Imágenes de avatar';

  @override
  String get migrationSupportedNotes => 'Notas';

  @override
  String get migrationSupportedCustomFields => 'Campos personalizados';

  @override
  String get migrationSupportedGroups => 'Grupos';

  @override
  String get migrationSupportedComments => 'Comentarios en sesiones al frente';

  @override
  String get migrationSupportedReminders => 'Recordatorios';

  @override
  String get migrationConnectToSimplyPlural => 'Conectar con Simply Plural';

  @override
  String get migrationEnterTokenDescription =>
      'Introduce tu token de API para importar datos directamente.';

  @override
  String get migrationApiTokenLabel => 'Token de API';

  @override
  String get migrationPasteTokenHint => 'Pega tu token aquí';

  @override
  String get migrationShowToken => 'Mostrar token';

  @override
  String get migrationHideToken => 'Ocultar token';

  @override
  String get migrationPasteFromClipboard => 'Pegar desde portapapeles';

  @override
  String get migrationWhereDoIFindThis => '¿Dónde encuentro esto?';

  @override
  String get migrationTokenHelpText =>
      'En Simply Plural, ve a Ajustes → Cuenta → Tokens. Crea un nuevo token con permiso de Lectura y cópialo.';

  @override
  String get migrationVerifyToken => 'Verificar token';

  @override
  String get migrationConnected => 'Conectado';

  @override
  String migrationSignedInAs(String username) {
    return 'Sesión iniciada como $username';
  }

  @override
  String get migrationContinue => 'Continuar';

  @override
  String get migrationFetchingData => 'Obteniendo datos de Simply Plural…';

  @override
  String get migrationPreviewImport => 'Vista previa de importación';

  @override
  String get migrationPreviewDescription =>
      'Revisa lo que se encontró antes de importar.';

  @override
  String get migrationImportInfoNote =>
      'Los datos importados se añadirán junto a los datos existentes. Nada será sobreescrito.';

  @override
  String get migrationRemindersApiNote =>
      'Los recordatorios no están disponibles vía API. Para importar recordatorios, usa una exportación de archivo.';

  @override
  String get migrationImportAllAddToExisting =>
      'Importar todo (añadir a lo existente)';

  @override
  String get migrationStartFresh =>
      'Empezar de cero (reemplazar todos los datos)';

  @override
  String get migrationImportAll => 'Importar todo';

  @override
  String get migrationReplaceAllTitle => '¿Reemplazar todos los datos?';

  @override
  String migrationReplaceAllMessage(String termPluralLower) {
    return 'Esto eliminará $termPluralLower, historial al frente, conversaciones y otros datos existentes antes de importar. Esta acción no se puede deshacer.\n\nSi tienes la sincronización configurada, los otros dispositivos emparejados también deberían reiniciarse para evitar conflictos.';
  }

  @override
  String get migrationReplaceAll => 'Reemplazar todo';

  @override
  String get migrationImporting => 'Importando…';

  @override
  String get migrationImportComplete => 'Importación completa';

  @override
  String migrationImportSuccess(int total, int seconds) {
    return 'Se importaron $total elementos en ${seconds}s.';
  }

  @override
  String get migrationSummary => 'Resumen';

  @override
  String migrationResultMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get migrationResultFrontSessions => 'Sesiones al frente';

  @override
  String get migrationResultConversations => 'Conversaciones';

  @override
  String get migrationResultMessages => 'Mensajes';

  @override
  String get migrationResultPolls => 'Encuestas';

  @override
  String get migrationResultNotes => 'Notas';

  @override
  String get migrationResultComments => 'Comentarios';

  @override
  String get migrationResultCustomFields => 'Campos personalizados';

  @override
  String get migrationResultGroups => 'Grupos';

  @override
  String get migrationResultReminders => 'Recordatorios';

  @override
  String get migrationResultAvatarsDownloaded => 'Avatares descargados';

  @override
  String migrationWarnings(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count advertencias',
      one: '1 advertencia',
    );
    return '$_temp0';
  }

  @override
  String get migrationNotImportedTitle => 'What didn\'t come over';

  @override
  String get migrationNotImportedFriendsTitle => 'Friends';

  @override
  String get migrationNotImportedFriendsDetail =>
      'SP friends are separate accounts on another system. Prism doesn\'t have a cross-system friends concept yet.';

  @override
  String get migrationNotImportedBoardMetaTitle => 'Board message metadata';

  @override
  String get migrationNotImportedBoardMetaDetail =>
      'Message categories and bucket assignments aren\'t part of the export format.';

  @override
  String get migrationNotImportedNotifTitle => 'Notification preferences';

  @override
  String get migrationNotImportedNotifDetail =>
      'These are stored on your device in SP and aren\'t included in the export.';

  @override
  String get migrationNotImportedFrontRulesTitle =>
      'Custom front display rules';

  @override
  String get migrationNotImportedFrontRulesDetail =>
      'Display rules and front conditions don\'t map to Prism\'s system.';

  @override
  String get migrationImportFailed => 'Fallo en la importación';

  @override
  String get migrationTryFileImport => 'Probar importación desde archivo';

  @override
  String get migrationUnknownError => 'Ocurrió un error desconocido.';

  @override
  String migrationPreviewSystem(String name) {
    return 'Sistema: $name';
  }

  @override
  String get migrationPreviewDataFound => 'Datos encontrados';

  @override
  String get migrationPreviewFrontHistoryEntries =>
      'Entradas del historial al frente';

  @override
  String get migrationPreviewChatChannels => 'Canales de chat';

  @override
  String get migrationPreviewMessages => 'Mensajes';

  @override
  String get migrationPreviewTotalEntities => 'Total de entidades';

  @override
  String get migrationPreviewWarnings => 'Advertencias';

  @override
  String get migrationPreviewCustomFronts => 'Frentes personalizados';

  @override
  String get migrationPreviewGroups => 'Grupos';

  @override
  String get migrationPreviewPolls => 'Encuestas';

  @override
  String get pluralkitTitle => 'PluralKit';

  @override
  String get pluralkitAccount => 'Cuenta de PluralKit';

  @override
  String get pluralkitSyncDirection => 'Dirección de sincronización';

  @override
  String get pluralkitSyncActions => 'Acciones de sincronización';

  @override
  String get pluralkitHowItWorks => 'Cómo funciona';

  @override
  String get pluralkitDisconnectTitle => '¿Desconectar PluralKit?';

  @override
  String get pluralkitDisconnectMessage =>
      'Esto eliminará tu token y te desconectará de PluralKit. Los datos importados permanecerán en la aplicación.';

  @override
  String get pluralkitDisconnect => 'Desconectar';

  @override
  String get pluralkitConnected => 'Conectado';

  @override
  String pluralkitLastSync(String when) {
    return 'Última sincronización: $when';
  }

  @override
  String pluralkitLastManualSync(String when) {
    return 'Última sincronización manual: $when';
  }

  @override
  String get pluralkitTokenLabel => 'Token de PluralKit';

  @override
  String get pluralkitPasteTokenHint => 'Pega tu token aquí';

  @override
  String get pluralkitConnect => 'Conectar';

  @override
  String get pluralkitTokenHelp =>
      'Para obtener tu token, envía un mensaje directo al bot de PluralKit en Discord con \"pk;token\" y pega el resultado aquí.';

  @override
  String get pluralkitFileImportHelp =>
      'Recupera el historial anterior de fronts de PluralKit con un archivo pk;export y un token. El archivo aporta el historial de cambios; el token permite que Prism lo vincule de forma segura.';

  @override
  String get pluralkitImportButton => 'Importar desde PluralKit';

  @override
  String get pluralkitSyncRecent => 'Sincronizar cambios recientes';

  @override
  String pluralkitSyncRecentCooldown(int seconds) {
    return 'Sincronizar cambios recientes (${seconds}s)';
  }

  @override
  String get pluralkitSyncDirectionDescription =>
      'Elige cómo fluyen los datos entre Prism y PluralKit.';

  @override
  String get pluralkitPull => 'Descargar';

  @override
  String get pluralkitBoth => 'Ambos';

  @override
  String get pluralkitPush => 'Subir';

  @override
  String get pluralkitLastSyncSummary => 'Resumen de última sincronización';

  @override
  String get pluralkitUpToDate => 'Todo está actualizado.';

  @override
  String pluralkitMembersPulled(int count, String termForCount) {
    return 'Descargados: $count $termForCount';
  }

  @override
  String pluralkitMembersPushed(int count, String termForCount) {
    return 'Subidos: $count $termForCount';
  }

  @override
  String pluralkitSwitchesPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios descargados',
      one: '1 cambio descargado',
    );
    return '$_temp0';
  }

  @override
  String pluralkitSwitchesPushed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios subidos',
      one: '1 cambio subido',
    );
    return '$_temp0';
  }

  @override
  String pluralkitMembersUnchanged(int count, String termForCount) {
    return 'Sin cambios: $count $termForCount';
  }

  @override
  String get pluralkitInfoSync =>
      'Compatible con sincronización en modo entrada, salida o bidireccional. Elige tu dirección preferida arriba.';

  @override
  String get pluralkitInfoToken =>
      'Tu token se almacena de forma segura en el llavero del dispositivo y nunca sale de él.';

  @override
  String pluralkitInfoMembers(String termPluralLower) {
    return 'Después de conectar, vincula tus miembros de PluralKit con $termPluralLower de Prism — o impórtalos como nuevos — para evitar duplicados.';
  }

  @override
  String get pluralkitInfoSwitches =>
      'La recuperación del historial de fronts usa un archivo pk;export más un token para que Prism pueda vincular los cambios del archivo con los ID de cambios de PluralKit.';

  @override
  String get pluralkitJustNow => 'Ahora mismo';

  @override
  String get pluralkitRepairThisGroup => 'Este grupo';

  @override
  String get pluralkitRepairPkGroup => 'Grupo PK';

  @override
  String get pluralkitRepairPluralKitGroup => 'Grupo de PluralKit';

  @override
  String get pluralkitRepairReconnectForComparison =>
      'Reconecta PluralKit para ver los detalles de comparación';

  @override
  String pluralkitRepairSharedPkMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $termPluralLower PK compartidos',
      one: '1 $termSingularLower PK compartido',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairLocalOnlyMembers(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $termPluralLower solo locales',
      one: '1 $termSingularLower solo local',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairOnlyInPkMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count solo en PK',
      one: '1 solo en PK',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSuspectedPkUuid(String uuid) {
    return 'UUID PK sospechado: $uuid';
  }

  @override
  String pluralkitRepairMergeActionPreview(String summary) {
    return 'Usar esta coincidencia va a $summary.';
  }

  @override
  String get pluralkitRepairPreviewLinkLocalGroup =>
      'vincular este grupo local con el grupo PK sospechado';

  @override
  String pluralkitRepairPreviewPreserveShared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membresías PK compartidas',
      one: '1 membresía PK compartida',
    );
    return 'conservar $_temp0';
  }

  @override
  String pluralkitRepairPreviewKeepLocalOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count membresías solo locales',
      one: '1 membresía solo local',
    );
    return 'mantener $_temp0';
  }

  @override
  String pluralkitRepairPreviewLeavePkOnly(
    int count,
    String termSingularLower,
    String termPluralLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count $termPluralLower solo en PK',
      one: '1 $termSingularLower solo en PK',
    );
    return 'dejar $_temp0 sin vincular';
  }

  @override
  String get pluralkitRepairUsePluralKitMatch =>
      'Usar esta coincidencia de PluralKit';

  @override
  String get pluralkitRepairKeepMyPrismGroup => 'Mantener mi grupo de Prism';

  @override
  String get pluralkitRepairDismissFalsePositive => 'Descartar falso positivo';

  @override
  String get pluralkitRepairSection => 'Reparación de grupos';

  @override
  String get pluralkitRepairTemporaryTokenTitle =>
      'Token temporal de PluralKit';

  @override
  String get pluralkitRepairTemporaryTokenBody =>
      'Usa un token de un solo uso solo para esta reparación. Prism no lo guardará.';

  @override
  String get pluralkitRepairTokenLabel => 'Token de PluralKit';

  @override
  String get pluralkitRepairTokenHint => 'Pega un token temporal';

  @override
  String get pluralkitRepairTemporaryTokenHelp =>
      'Este token solo se usa para comparar tus grupos locales con datos actuales de grupos de PluralKit durante una reparación.';

  @override
  String get pluralkitRepairRunTokenBacked => 'Ejecutar reparación con token';

  @override
  String get pluralkitRepairLoadingStatus => 'Cargando estado de reparación...';

  @override
  String get pluralkitRepairCardTitle => 'Reparación de grupos de PluralKit';

  @override
  String get pluralkitRepairRunLocal => 'Ejecutar reparación local';

  @override
  String get pluralkitRepairRun => 'Ejecutar reparación';

  @override
  String get pluralkitRepairResetAndReimport =>
      'Restablecer grupos PK y reimportar';

  @override
  String get pluralkitRepairResetOnly => 'Restablecer solo grupos PK';

  @override
  String get pluralkitRepairCurrentStatus => 'Estado actual';

  @override
  String get pluralkitRepairPendingReview => 'Revisión pendiente';

  @override
  String get pluralkitRepairLastRun => 'Última ejecución';

  @override
  String get pluralkitRepairWhatChanged => 'Qué cambió';

  @override
  String get pluralkitRepairUseTemporaryToken => 'Usar token temporal';

  @override
  String get pluralkitRepairCutoverTitle => 'Cambio a sync v2 de grupos PK';

  @override
  String get pluralkitRepairSharedEnablement => 'Activación compartida';

  @override
  String get pluralkitRepairEnablePkGroupSync => 'Activar sync de grupos PK';

  @override
  String get pluralkitRepairHeadlineRunning =>
      'Escaneando grupos vinculados, reparando duplicados obvios y verificando grupos PK actuales cuando hay un token disponible.';

  @override
  String get pluralkitRepairHeadlinePending =>
      'Los grupos importados ambiguos están suprimidos por ahora para que Prism no cree enlaces de sincronización duplicados.';

  @override
  String get pluralkitRepairHeadlineReconnectRequired =>
      'La reparación local aún puede restaurar enlaces PK directamente comprobables, pero todavía debes reconectar PluralKit para reconstruir automáticamente la identidad faltante de grupos PK.';

  @override
  String get pluralkitRepairHeadlineChanged =>
      'La última ejecución hizo cambios locales concretos de reparación. Revisa el resumen antes de activar sync de grupos respaldados por PK.';

  @override
  String get pluralkitRepairHeadlineCompleted =>
      'La última ejecución terminó. Puedes volver a ejecutar la reparación después de reconectar o importar más datos de PluralKit.';

  @override
  String get pluralkitRepairHeadlineDefault =>
      'Corrige localmente duplicados obvios de grupos PK y marca coincidencias ambiguas para revisión.';

  @override
  String get pluralkitRepairStatusRunning => 'Reparación en curso';

  @override
  String get pluralkitRepairStatusRetryNeeded => 'Reintento necesario';

  @override
  String pluralkitRepairStatusPendingReview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pendientes de revisión',
      one: '1 pendiente de revisión',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairStatusLastRunComplete =>
      'Última ejecución completa';

  @override
  String get pluralkitRepairStatusReadyToRun => 'Lista para ejecutar';

  @override
  String get pluralkitRepairTokenBackedReady => 'Lista con token';

  @override
  String get pluralkitRepairLocalOnlyUntilToken =>
      'Solo local hasta tener token';

  @override
  String get pluralkitRepairCheckingTokenAccess =>
      'Verificando acceso al token';

  @override
  String get pluralkitRepairCutoverEnabledChip => 'Sync v2 PK activado';

  @override
  String get pluralkitRepairCutoverOffChip => 'Sync v2 PK desactivado';

  @override
  String get pluralkitRepairCheckingCutover => 'Verificando cambio';

  @override
  String get pluralkitRepairCurrentRunning =>
      'La reparación se está ejecutando ahora.';

  @override
  String get pluralkitRepairCurrentError =>
      'La última ejecución manual falló. Reintenta abajo cuando estés listo.';

  @override
  String pluralkitRepairCurrentPending(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count grupos todavía necesitan revisión antes de poder vincularse o limpiarse.',
      one:
          '1 grupo todavía necesita revisión antes de poder vincularse o limpiarse.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairCurrentNoRun =>
      'Aún no se ha registrado ninguna reparación en esta sesión de la app.';

  @override
  String get pluralkitRepairCurrentReconnectRequired =>
      'La última ejecución terminó la reparación local segura, pero la identidad faltante de grupos PK todavía necesita una fuente de referencia activa de PluralKit para reconstruirse automáticamente.';

  @override
  String get pluralkitRepairCurrentChanged =>
      'La última ejecución cambió datos locales de grupos PK. Revisa el resumen de la última ejecución para ver las reparaciones aplicadas.';

  @override
  String get pluralkitRepairCurrentNoChanges =>
      'La última ejecución no encontró reparaciones nuevas de grupos PK para aplicar.';

  @override
  String get pluralkitRepairCutoverHeadlineEnabled =>
      'La sincronización de grupos respaldados por PK está activada para este grupo de sync. Los grupos manuales o solo locales siguen siendo locales.';

  @override
  String get pluralkitRepairCutoverHeadlineReady =>
      'Los requisitos de reparación local están completos. El límite de seguridad restante es la confirmación explícita del cambio.';

  @override
  String get pluralkitRepairCutoverHeadlineBlocked =>
      'La sincronización de grupos respaldados por PK permanece desactivada hasta que la reparación termine y confirmes explícitamente que ya no hay dispositivos heredados emparejados.';

  @override
  String get pluralkitRepairCutoverStatusLoading =>
      'Cargando la configuración compartida de cambio para este grupo de sync.';

  @override
  String get pluralkitRepairCutoverStatusEnabled =>
      'Activado para este grupo de sync después de confirmación explícita.';

  @override
  String get pluralkitRepairCutoverStatusRunning =>
      'No disponible mientras la reparación sigue en curso.';

  @override
  String get pluralkitRepairCutoverStatusNoRun =>
      'No disponible hasta que una reparación termine en esta sesión de la app.';

  @override
  String get pluralkitRepairCutoverStatusPending =>
      'No disponible hasta resolver los elementos pendientes o mantenerlos solo locales.';

  @override
  String get pluralkitRepairCutoverStatusReady =>
      'Listo para activar después de confirmar explícitamente el cambio.';

  @override
  String get pluralkitRepairCutoverRecommendationEnabled =>
      'Esto solo afecta la sincronización de grupos respaldados por PK. Los grupos manuales o solo locales no cambian.';

  @override
  String get pluralkitRepairCutoverRecommendationRunFirst =>
      'Ejecuta la reparación primero. Prism mantiene sync v2 de grupos PK desactivado hasta que este cliente complete una reparación.';

  @override
  String get pluralkitRepairCutoverRecommendationPending =>
      'Resuelve cada elemento pendiente o mantenlo explícitamente solo local antes de activar el cambio.';

  @override
  String get pluralkitRepairCutoverRecommendationReady =>
      'Actívalo solo después de que todos los dispositivos heredados de la era 0.4.0+1 en este grupo de sync se hayan actualizado, restablecido/reemparejado, eliminado, o después de mover las pruebas a un grupo de sync nuevo.';

  @override
  String get pluralkitRepairPendingNone =>
      'No hay coincidencias ambiguas de grupos PK esperando revisión.';

  @override
  String pluralkitRepairPendingCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count grupos todavía necesitan revisión de seguimiento.',
      one: '1 grupo todavía necesita revisión de seguimiento.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairModeLocalOnlyRun => 'Ejecución solo local';

  @override
  String get pluralkitRepairModeStoredTokenRun =>
      'Ejecución con token guardado';

  @override
  String get pluralkitRepairModeTemporaryTokenRun =>
      'Ejecución con token temporal';

  @override
  String get pluralkitRepairLastRunPrefixLocal => 'La ejecución local';

  @override
  String get pluralkitRepairLastRunPrefixStoredToken =>
      'La ejecución con token guardado';

  @override
  String get pluralkitRepairLastRunPrefixTemporaryToken =>
      'La ejecución con token temporal';

  @override
  String pluralkitRepairLastRunNoChanges(Object prefix) {
    return '$prefix no encontró cambios nuevos de grupos PK para aplicar.';
  }

  @override
  String pluralkitRepairLastRunChanged(Object prefix, Object summary) {
    return '$prefix $summary.';
  }

  @override
  String pluralkitRepairJoinPair(Object first, Object second) {
    return '$first y $second';
  }

  @override
  String pluralkitRepairJoinSerial(Object last, Object leading) {
    return '$leading y $last';
  }

  @override
  String pluralkitRepairSummaryUpdatedParentLinks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'actualizó $count enlaces de grupo padre',
      one: 'actualizó 1 enlace de grupo padre',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryMovedMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'movió $count membresías de grupo',
      one: 'movió 1 membresía de grupo',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRemovedDuplicateGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'eliminó $count grupos locales duplicados',
      one: 'eliminó 1 grupo local duplicado',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRemovedConflictingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'eliminó $count membresías de grupo conflictivas',
      one: 'eliminó 1 membresía de grupo conflictiva',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummarySuppressedAmbiguousGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'suprimió $count grupos ambiguos para revisión',
      one: 'suprimió 1 grupo ambiguo para revisión',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRestoredMissingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'restauró $count enlaces de membresía PK faltantes',
      one: 'restauró 1 enlace de membresía PK faltante',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairSummaryRecordedLegacyAliases(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'registró $count alias heredados de grupo',
      one: 'registró 1 alias heredado de grupo',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailUpdatedParentLinks(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Actualizó $count enlaces de grupo padre para apuntar al grupo sobreviviente.',
      one:
          'Actualizó 1 enlace de grupo padre para apuntar al grupo sobreviviente.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailMovedMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Movió $count membresías de grupo al grupo sobreviviente.',
      one: 'Movió 1 membresía de grupo al grupo sobreviviente.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRemovedDuplicateGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Eliminó $count grupos locales duplicados.',
      one: 'Eliminó 1 grupo local duplicado.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRemovedConflictingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Eliminó $count membresías de grupo conflictivas al fusionar duplicados.',
      one: 'Eliminó 1 membresía de grupo conflictiva al fusionar duplicados.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailSuppressedAmbiguousGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Suprimió $count grupos ambiguos para revisión antes de continuar la sincronización.',
      one:
          'Suprimió 1 grupo ambiguo para revisión antes de continuar la sincronización.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRestoredMissingMemberships(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Restauró $count enlaces de membresía PK faltantes.',
      one: 'Restauró 1 enlace de membresía PK faltante.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairDetailRecordedLegacyAliases(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Registró $count alias heredados de grupo para que los ID antiguos aún se resuelvan.',
      one:
          'Registró 1 alias heredado de grupo para que los ID antiguos aún se resuelvan.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairReferenceImportOnly =>
      'Esto parece datos PK solo importados, sin grupos locales vinculados a PK que sirvan como referencias de reparación. Prism aún puede reparar filas vinculadas directamente de forma local, pero reconectar PluralKit o usar un token temporal es la única forma de reconstruir automáticamente la identidad faltante de grupos PK.';

  @override
  String get pluralkitRepairReferenceStoredTokenFailed =>
      'Existe un token guardado, pero falló la última consulta de referencia en vivo. Reconecta PluralKit o usa un token temporal si quieres una reparación completa respaldada por token.';

  @override
  String get pluralkitRepairReferenceReconnectOrToken =>
      'Reconecta PluralKit arriba o usa un token temporal para una reparación más completa. La reparación local aún maneja los duplicados obvios.';

  @override
  String get pluralkitRepairReferenceTokenRecommended =>
      'Se recomienda una reparación respaldada por token cuando puedas proporcionar uno. Hasta entonces, Prism solo ejecutará la reparación local segura.';

  @override
  String get pluralkitRepairReferenceLocalNow =>
      'La reparación puede ejecutarse localmente ahora. Las verificaciones PK en vivo aparecen cuando se confirme el acceso al token.';

  @override
  String pluralkitRepairReferenceError(Object error) {
    return 'La consulta PK en vivo falló en la última ejecución, así que Prism volvió a la reparación local. $error';
  }

  @override
  String pluralkitRepairError(Object error) {
    return 'La reparación falló: $error';
  }

  @override
  String get pluralkitRepairConfirmEnableTitle => '¿Activar sync v2 PK?';

  @override
  String get pluralkitRepairConfirmEnableBody =>
      'Activa esto solo después de que todos los dispositivos heredados de la era 0.4.0+1 se hayan actualizado, restablecido/reemparejado, eliminado, o después de moverte a un grupo de sync nuevo.';

  @override
  String get pluralkitRepairConfirmEnableFootnote =>
      'Si falta confirmar algún dispositivo, déjalo desactivado. Los grupos manuales o solo locales siguen siendo locales de cualquier forma.';

  @override
  String get pluralkitRepairConfirmEnableAction => 'Activar sync v2 PK';

  @override
  String get pluralkitRepairConfirmResetTitle => '¿Restablecer solo grupos PK?';

  @override
  String get pluralkitRepairConfirmResetConnectedBody =>
      'Prism eliminará grupos vinculados a PK y suprimidos por reparación, conservará grupos manuales o solo locales, limpiará operaciones diferidas de membresía PK y luego reimportará tus grupos PK actuales.';

  @override
  String get pluralkitRepairConfirmResetDisconnectedBody =>
      'Prism eliminará grupos vinculados a PK y suprimidos por reparación, conservará grupos manuales o solo locales y limpiará operaciones diferidas de membresía PK. Reconecta PluralKit o importa de nuevo después para reconstruirlos.';

  @override
  String get pluralkitRepairConfirmResetExportHint =>
      'Exporta los datos primero si quieres una copia completa antes del restablecimiento.';

  @override
  String get pluralkitRepairConfirmResetExportFirst => 'Exportar datos primero';

  @override
  String get pluralkitRepairConfirmResetActionConnected =>
      'Restablecer y reimportar';

  @override
  String get pluralkitRepairConfirmResetActionDisconnected =>
      'Restablecer grupos PK';

  @override
  String pluralkitRepairFailedToast(Object error) {
    return 'La reparación de grupos de PluralKit falló: $error';
  }

  @override
  String get pluralkitRepairReviewDismissed =>
      'Revisión de grupo descartada. Se limpió la supresión de sync.';

  @override
  String get pluralkitRepairKeepLocalOnlySuccess =>
      'Grupo mantenido solo local. Quedará fuera de sync.';

  @override
  String get pluralkitRepairMergedSuccess =>
      'Grupo vinculado con la coincidencia de PluralKit.';

  @override
  String pluralkitRepairDismissReviewFailed(Object error) {
    return 'No se pudo descartar este elemento de revisión: $error';
  }

  @override
  String pluralkitRepairKeepLocalOnlyFailed(Object error) {
    return 'No se pudo mantener este grupo solo local: $error';
  }

  @override
  String pluralkitRepairMergeFailed(Object error) {
    return 'No se pudo usar esta coincidencia de PluralKit: $error';
  }

  @override
  String get pluralkitRepairCutoverSettingsLoadingError =>
      'Aún no se pudo verificar la configuración compartida de cambio. Espera a que termine de cargar el estado de reparación e inténtalo de nuevo.';

  @override
  String get pluralkitRepairCutoverAlreadyEnabled =>
      'Sync v2 de grupos PK ya está activado para este grupo de sync.';

  @override
  String get pluralkitRepairCutoverRepairLoadingError =>
      'El estado de reparación todavía está cargando o ejecutándose. Espera a que termine antes de activar sync v2 de grupos PK.';

  @override
  String get pluralkitRepairCutoverRunRepairFirstError =>
      'Ejecuta primero la reparación de grupos de PluralKit. Sync v2 de grupos PK permanece desactivado hasta que este cliente complete una reparación.';

  @override
  String pluralkitRepairCutoverPendingReviewError(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Resuelve o mantén solo locales los $count elementos pendientes antes de activar sync v2 de grupos PK.',
      one:
          'Resuelve o mantén solo local el 1 elemento pendiente antes de activar sync v2 de grupos PK.',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairCutoverEnabledSuccess =>
      'Sync v2 de grupos PK activado para este grupo de sync. Los grupos manuales o solo locales no cambian.';

  @override
  String pluralkitRepairCutoverEnableFailed(Object error) {
    return 'No se pudo activar sync v2 de grupos PK: $error';
  }

  @override
  String get pluralkitRepairResetNoGroupsNeeded =>
      'Ningún grupo respaldado por PK o suprimido por reparación necesitaba restablecerse en este dispositivo.';

  @override
  String pluralkitRepairResetFinishedReconnect(Object summary) {
    return 'Restablecimiento de grupos PK terminado. $summary Reconecta PluralKit o importa desde un archivo para reconstruirlos.';
  }

  @override
  String pluralkitRepairResetFinishedReimported(Object summary) {
    return 'Restablecimiento de grupos PK terminado. $summary Se reimportaron los grupos PK actuales.';
  }

  @override
  String pluralkitRepairResetFinishedReimportFailed(
    Object error,
    Object summary,
  ) {
    return 'Restablecimiento de grupos PK terminado, pero falló la reimportación: $error. $summary';
  }

  @override
  String pluralkitRepairResetFailed(Object error) {
    return 'No se pudieron restablecer los grupos PK: $error';
  }

  @override
  String get pluralkitRepairNoNewNeeded =>
      'No se necesitaban reparaciones nuevas de grupos PK.';

  @override
  String pluralkitRepairSuccessLocalLookupFailed(Object detail) {
    return 'Reparación local terminada. $detail La consulta PK en vivo falló, así que todavía se recomienda volver a ejecutar con token.';
  }

  @override
  String pluralkitRepairSuccessLocalLookupFailedWithFollowUp(
    Object detail,
    Object followUp,
  ) {
    return 'Reparación local terminada. $detail $followUp La consulta PK en vivo falló, así que todavía se recomienda volver a ejecutar con token.';
  }

  @override
  String pluralkitRepairSuccessWithFollowUp(Object detail, Object followUp) {
    return 'Reparación terminada. $detail $followUp';
  }

  @override
  String pluralkitRepairSuccess(Object detail) {
    return 'Reparación terminada. $detail';
  }

  @override
  String pluralkitRepairFollowUpPendingReview(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count grupos suprimidos todavía necesitan revisión de seguimiento.',
      one: '1 grupo suprimido todavía necesita revisión de seguimiento.',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairStatusLoadFailed(Object error) {
    return 'No se pudo cargar el estado de reparación: $error';
  }

  @override
  String pluralkitRepairResetSummaryRemovedGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'eliminó $count grupos respaldados por PK o suprimidos',
      one: 'eliminó 1 grupo respaldado por PK o suprimido',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairResetSummaryPromotedChildGroups(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'promovió $count grupos locales hijos a raíz',
      one: 'promovió 1 grupo local hijo a raíz',
    );
    return '$_temp0';
  }

  @override
  String pluralkitRepairResetSummaryClearedDeferredOps(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'limpió $count operaciones diferidas de membresía PK',
      one: 'limpió 1 operación diferida de membresía PK',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitRepairResetSummaryNoGroupsNeeded =>
      'Ningún grupo respaldado por PK necesitaba restablecerse.';

  @override
  String pluralkitMinutesAgo(int minutes) {
    return 'hace ${minutes}m';
  }

  @override
  String pluralkitHoursAgo(int hours) {
    return 'hace ${hours}h';
  }

  @override
  String pluralkitDaysAgo(int days) {
    return 'hace ${days}d';
  }

  @override
  String get dataManagementExportTitle => 'Exportar datos';

  @override
  String get dataManagementImportTitle => 'Importar datos';

  @override
  String get dataManagementImportExportTitle => 'Importar y exportar';

  @override
  String get dataManagementExportSectionTitle => 'Exportar';

  @override
  String get dataManagementImportSectionTitle => 'Importar';

  @override
  String get dataManagementImportFromOtherApps =>
      'Importar desde otras aplicaciones';

  @override
  String get dataManagementExportRowTitle => 'Exportar datos';

  @override
  String get dataManagementExportRowSubtitle =>
      'Crea una copia de seguridad protegida por contraseña';

  @override
  String get dataManagementImportRowTitle => 'Importar datos';

  @override
  String get dataManagementImportRowSubtitle =>
      'Restaura datos desde un archivo de exportación de Prism (.json o .prism)';

  @override
  String dataManagementPluralKitRowSubtitle(String termPluralLower) {
    return 'Importa $termPluralLower y sesiones al frente mediante token de API';
  }

  @override
  String get dataManagementSimplyPluralRowTitle => 'Simply Plural';

  @override
  String get dataManagementSimplyPluralRowSubtitle =>
      'Importa desde un archivo de exportación de Simply Plural';

  @override
  String get dataManagementExportYourData => 'Exportar tus datos';

  @override
  String dataManagementExportDescription(String termPluralLower) {
    return 'Crea una copia de seguridad protegida por contraseña de todos tus datos, incluyendo $termPluralLower, sesiones al frente, mensajes, encuestas y ajustes.';
  }

  @override
  String get dataManagementExportButton => 'Exportar datos';

  @override
  String get dataManagementEncryptExport => 'Cifrar exportación';

  @override
  String get dataManagementEncryptDescription =>
      'Establece una contraseña para cifrar tu archivo de exportación. Necesitarás esta contraseña para importar los datos más adelante.';

  @override
  String get dataManagementUnencryptedWarning =>
      'Las exportaciones sin cifrar son JSON en texto plano. Cualquiera que abra el archivo puede leer su contenido.';

  @override
  String get dataManagementPasswordLabel => 'Contraseña';

  @override
  String get dataManagementPasswordHint =>
      'Al menos 12 caracteres — una frase larga es mejor';

  @override
  String get dataManagementShowPassword => 'Mostrar contraseña';

  @override
  String get dataManagementHidePassword => 'Ocultar contraseña';

  @override
  String get dataManagementConfirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get dataManagementExportUnencrypted => 'Exportar sin cifrar';

  @override
  String get dataManagementEncrypt => 'Cifrar';

  @override
  String get dataManagementExporting => 'Exportando tus datos…';

  @override
  String get dataManagementMayTakeMoment => 'Esto puede tardar un momento.';

  @override
  String get dataManagementExportFailed => 'Fallo en la exportación';

  @override
  String get dataManagementRetry => 'Reintentar';

  @override
  String get dataManagementExportComplete => 'Exportación completa';

  @override
  String get dataManagementExportWithoutEncryptionTitle =>
      '¿Exportar sin cifrado?';

  @override
  String get dataManagementExportWithoutEncryptionMessage =>
      'Esto creará un archivo JSON en texto plano que cualquiera que lo abra podrá leer. Usa la exportación cifrada a menos que necesites específicamente una copia sin cifrar.';

  @override
  String get dataManagementExportUnencryptedConfirm => 'Exportar sin cifrar';

  @override
  String get dataManagementPasswordEmpty =>
      'La contraseña no puede estar vacía';

  @override
  String get dataManagementPasswordTooShort =>
      'La contraseña debe tener al menos 12 caracteres';

  @override
  String get dataManagementPasswordMismatch => 'Las contraseñas no coinciden';

  @override
  String get dataManagementSelectFile => 'Seleccionar archivo';

  @override
  String get dataManagementImportFileDescription =>
      'Selecciona un archivo de exportación de Prism (.json o .prism) para restaurar tus datos. Los datos existentes no serán sobreescritos.';

  @override
  String get dataManagementEncryptedFile => 'Archivo cifrado';

  @override
  String get dataManagementEncryptedFileDescription =>
      'Este archivo de exportación está cifrado. Introduce la contraseña que se usó al crear la exportación.';

  @override
  String get dataManagementDecrypt => 'Descifrar';

  @override
  String get dataManagementImportPreview => 'Vista previa de importación';

  @override
  String dataManagementExportedDate(String date) {
    return 'Exportado: $date';
  }

  @override
  String dataManagementPreviewMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get dataManagementPreviewFrontSessions => 'Sesiones al frente';

  @override
  String get dataManagementPreviewSleepSessions => 'Sesiones de sueño';

  @override
  String get dataManagementPreviewConversations => 'Conversaciones';

  @override
  String get dataManagementPreviewMessages => 'Mensajes';

  @override
  String get dataManagementPreviewPolls => 'Encuestas';

  @override
  String get dataManagementPreviewPollOptions => 'Opciones de encuesta';

  @override
  String get dataManagementPreviewSettings => 'Ajustes';

  @override
  String get dataManagementPreviewHabits => 'Hábitos';

  @override
  String get dataManagementPreviewHabitCompletions =>
      'Completaciones de hábitos';

  @override
  String get dataManagementPreviewTotal => 'Total';

  @override
  String get dataManagementPreviewTotalCreated => 'Total creado';

  @override
  String get dataManagementImport => 'Importar';

  @override
  String get dataManagementImporting => 'Importando tus datos…';

  @override
  String get dataManagementImportingMessage =>
      'Esto puede tardar un momento. No cierres la aplicación.';

  @override
  String get dataManagementImportComplete => 'Importación completa';

  @override
  String get dataManagementImportFailed => 'Fallo en la importación';

  @override
  String get dataManagementImportFailedNote =>
      'No se importaron datos. La base de datos no fue modificada.';

  @override
  String get dataManagementIncorrectPassword => 'Contraseña incorrecta';

  @override
  String dataManagementDecryptionFailed(String error) {
    return 'Fallo al descifrar: $error';
  }

  @override
  String get dataManagementUnencryptedBackup =>
      'Esta copia de seguridad no está cifrada. Vuelve a exportar desde la app para obtener un archivo .prism seguro.';

  @override
  String get dataManagementPasswordEmptyImport =>
      'La contraseña no puede estar vacía';

  @override
  String get sharingTitle => 'Compartición';

  @override
  String get sharingRefreshInbox => 'Actualizar bandeja de entrada';

  @override
  String get sharingUseSharingCodeTooltip => 'Usar código de compartición';

  @override
  String get sharingShareYourCodeTooltip => 'Comparte tu código';

  @override
  String get sharingPendingRequests => 'Solicitudes pendientes';

  @override
  String get sharingTrustedPeople => 'Personas de confianza';

  @override
  String get sharingEmptyTitle => 'Aún no hay relaciones de compartición';

  @override
  String get sharingEmptySubtitle =>
      'Comparte tu código para que alguien pueda enviarte una solicitud, o usa el código de otra persona para conectar.';

  @override
  String get sharingShareMyCode => 'Compartir mi código';

  @override
  String get sharingUseACode => 'Usar un código';

  @override
  String get sharingRequestSent =>
      'Solicitud de compartición enviada. La verá la próxima vez que revise la compartición.';

  @override
  String get sharingNoNewRequests =>
      'No hay nuevas solicitudes de compartición';

  @override
  String get sharingUnableToRefresh =>
      'No se puede actualizar la bandeja de compartición';

  @override
  String get sharingSyncNotConfigured =>
      'La sincronización no está configurada';

  @override
  String get sharingRequestAccepted => 'Solicitud de compartición aceptada';

  @override
  String get sharingUnableToAccept => 'No se puede aceptar la solicitud';

  @override
  String get sharingRequestDismissed => 'Solicitud descartada';

  @override
  String get sharingRemoveTitle => 'Eliminar relación';

  @override
  String sharingRemoveMessage(String name) {
    return '¿Eliminar a $name y revocar su acceso? Esta acción no se puede deshacer.';
  }

  @override
  String get sharingRemove => 'Eliminar';

  @override
  String get sharingNoScopesGranted => 'No se concedieron permisos';

  @override
  String get sharingJustNow => 'Ahora mismo';

  @override
  String sharingMinutesAgo(int minutes) {
    return 'hace ${minutes}m';
  }

  @override
  String sharingHoursAgo(int hours) {
    return 'hace ${hours}h';
  }

  @override
  String sharingDaysAgo(int days) {
    return 'hace ${days}d';
  }

  @override
  String get sharingIgnore => 'Ignorar';

  @override
  String get sharingDismiss => 'Descartar';

  @override
  String get sharingAccept => 'Aceptar';

  @override
  String get sharingUseSharingCode => 'Usar código de compartición';

  @override
  String get sharingSharingCodeLabel => 'Código de compartición';

  @override
  String get sharingSharingCodeHint => 'Pega el código que recibiste';

  @override
  String sharingConnectingWith(String name) {
    return 'Conectando con $name';
  }

  @override
  String get sharingReadyToSend =>
      'Listo para enviar una solicitud de compartición';

  @override
  String get sharingYourDisplayName => 'Tu nombre de pantalla';

  @override
  String get sharingDisplayNameHint => 'Cómo te verán';

  @override
  String get sharingWhatToShare => 'Qué compartir';

  @override
  String get sharingSending => 'Enviando…';

  @override
  String get sharingSendRequest => 'Enviar solicitud';

  @override
  String get sharingInvalidCode => 'Código de compartición inválido';

  @override
  String sharingFailedToSend(Object error) {
    return 'Error al enviar la solicitud de compartición: $error';
  }

  @override
  String get sharingShareYourCode => 'Comparte tu código';

  @override
  String get sharingEnableSharing => 'Activar compartición';

  @override
  String get sharingDescription =>
      'La compartición usa un código estable en lugar de un intercambio de claves en línea. Cualquier persona con este código puede enviarte una solicitud de compartición.';

  @override
  String get sharingDisplayNameOptionalLabel => 'Nombre de pantalla (opcional)';

  @override
  String get sharingDisplayNameOptionalHint =>
      'Se muestra a la persona que abre tu código';

  @override
  String get sharingSharingCodeTitle => 'Código de compartición';

  @override
  String get sharingCodeValidNote =>
      'Este código permanece válido hasta que desactives la compartición.';

  @override
  String get sharingCopy => 'Copiar';

  @override
  String sharingFailedToEnable(Object error) {
    return 'Error al activar la compartición: $error';
  }

  @override
  String get sharingCodeCopied =>
      'Código de compartición copiado (se borra automáticamente en 15s)';

  @override
  String get sharingFriend => 'Amigue';

  @override
  String get sharingFriendNotFound => 'Persona no encontrada';

  @override
  String get sharingGrantedScopes => 'Permisos concedidos';

  @override
  String get sharingSharingId => 'ID de compartición';

  @override
  String get sharingCopySharingId => 'Copiar ID de compartición';

  @override
  String get sharingSharingIdCopied => 'ID de compartición copiado';

  @override
  String get sharingLastSynced => 'Última sincronización';

  @override
  String get sharingRevokeAccess => 'Revocar acceso';

  @override
  String get sharingVerified => 'Verificado';

  @override
  String get sharingNotVerified => 'No verificado';

  @override
  String sharingAddedDate(String date) {
    return 'Añadido el $date';
  }

  @override
  String get sharingVerificationRecommended => 'Verificación recomendada';

  @override
  String sharingVerificationDescription(String name) {
    return 'Compara las huellas digitales con $name fuera de la aplicación antes de marcar esta relación como verificada.';
  }

  @override
  String get sharingCompareFingerprint => 'Comparar huella digital';

  @override
  String get sharingSecurityFingerprintTitle => 'Huella digital de seguridad';

  @override
  String sharingFingerprintCompareText(String name) {
    return 'Compara esta huella digital con $name. Solo márcala como verificada si ven el mismo valor.';
  }

  @override
  String get sharingFingerprintWarning =>
      'No verifiques si las huellas digitales difieren.';

  @override
  String get sharingMarkVerified => 'Marcar como verificado';

  @override
  String get sharingRevokeTitle => 'Revocar acceso';

  @override
  String sharingRevokeMessage(String name) {
    return '¿Revocar todo el acceso de $name? Se rotarán las claves de recurso.';
  }

  @override
  String get sharingRevoke => 'Revocar';

  @override
  String get sharingUnableToComputeFingerprint =>
      'No se puede calcular la huella digital';

  @override
  String sharingFingerprintCopied(String label) {
    return '$label copiado';
  }

  @override
  String sharingCopyLabel(String label) {
    return 'Copiar $label';
  }

  @override
  String get sharingFingerprint => 'Huella digital';

  @override
  String get sharingIdentity => 'Identidad';

  @override
  String get remindersTitle => 'Recordatorios';

  @override
  String remindersLoadError(String error) {
    return 'Error: $error';
  }

  @override
  String get remindersEmptyTitle => 'Sin recordatorios';

  @override
  String get remindersEmptySubtitle =>
      'Crea recordatorios para cambios de frente o tiempos programados';

  @override
  String get remindersEmptyAction => 'Agregar recordatorio';

  @override
  String remindersDeletedSnackbar(String name) {
    return 'Eliminado \"$name\"';
  }

  @override
  String get remindersUndoAction => 'Deshacer';

  @override
  String get remindersSubtitleOnFrontChange => 'Al cambio de frente';

  @override
  String remindersSubtitleOnFrontChangeDelay(int hours) {
    return 'Al cambio de frente (${hours}h de retraso)';
  }

  @override
  String get remindersSubtitleDaily => 'Diario';

  @override
  String remindersSubtitleEveryNDays(int days) {
    return 'Cada $days días';
  }

  @override
  String get remindersFrequencyWeekly => 'Semanal';

  @override
  String get remindersFrequencyInterval => 'Cada pocos días';

  @override
  String get remindersScheduleLabel => 'Horario';

  @override
  String get remindersWeeklyEmptyHelper => 'Selecciona al menos un día';

  @override
  String get remindersSubtitleEveryDay => 'Todos los días';

  @override
  String get remindersSubtitleWeekdays => 'Entre semana';

  @override
  String get remindersSubtitleWeekends => 'Fines de semana';

  @override
  String remindersSubtitleDaysPerWeek(int count) {
    return '$count días a la semana';
  }

  @override
  String get weekdayAbbreviationSun => 'Dom';

  @override
  String get weekdayAbbreviationMon => 'Lun';

  @override
  String get weekdayAbbreviationTue => 'Mar';

  @override
  String get weekdayAbbreviationWed => 'Mié';

  @override
  String get weekdayAbbreviationThu => 'Jue';

  @override
  String get weekdayAbbreviationFri => 'Vie';

  @override
  String get weekdayAbbreviationSat => 'Sáb';

  @override
  String get remindersScheduled => 'Programado';

  @override
  String get remindersEditTitle => 'Editar recordatorio';

  @override
  String get remindersNewTitle => 'Nuevo recordatorio';

  @override
  String get remindersNameLabel => 'Nombre del recordatorio';

  @override
  String get remindersMessageLabel => 'Mensaje de notificación';

  @override
  String get remindersTriggerLabel => 'Activador';

  @override
  String get remindersTriggerFrontChange => 'Cambio de frente';

  @override
  String get remindersRepeatEveryLabel => 'Repetir cada';

  @override
  String remindersIntervalDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count días',
      one: '1 día',
    );
    return '$_temp0';
  }

  @override
  String get remindersTimeLabel => 'Hora';

  @override
  String get remindersDelayLabel => 'Retraso tras el cambio de frente';

  @override
  String get remindersImmediately => 'Inmediatamente';

  @override
  String remindersDelayHours(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count horas',
      one: '1 hora',
    );
    return '$_temp0';
  }

  @override
  String get remindersTargetLabel => 'Destino';

  @override
  String get remindersTargetAny => 'Cualquier cambio de frente';

  @override
  String get remindersTargetDisclosure =>
      'Se activa cuando Prism está en ejecución y detecta el cambio. Los cambios externos registrados mientras Prism está cerrado pueden no activar este recordatorio.';

  @override
  String remindersSubtitleTargetPrefix(String name) {
    return 'Cuando $name está al frente';
  }

  @override
  String get settingsAboutAppName => 'Prism';

  @override
  String get settingsAboutTagline => 'Gestión de sistemas plurales';

  @override
  String settingsAboutVersion(String version) {
    return 'Versión $version';
  }

  @override
  String settingsAboutDescription(String termPluralLower) {
    return 'Una app centrada en la privacidad para gestionar sistemas plurales. Registra el frente, comunícate entre $termPluralLower y mantén tu sistema organizado.';
  }

  @override
  String get settingsAboutWebsite => 'Sitio web';

  @override
  String get settingsAboutGitHub => 'GitHub';

  @override
  String get settingsAboutDiscord => 'Discord';

  @override
  String get settingsAboutBluesky => 'Bluesky';

  @override
  String get settingsAboutTumblr => 'Tumblr';

  @override
  String get settingsAboutPrivacy => 'Privacidad';

  @override
  String get settingsAboutFeedback => 'Sugerencias';

  @override
  String get settingsAboutLinkOpenFailed => 'No se pudo abrir ese enlace';

  @override
  String get settingsAboutGitHubComingSoon => 'Enlace de GitHub próximamente';

  @override
  String get settingsAboutSecurity => 'Seguridad';

  @override
  String get settingsAboutFeedbackComingSoon =>
      'Formulario de sugerencias próximamente';

  @override
  String get settingsCustomFieldsTitle => 'Campos personalizados';

  @override
  String get settingsCustomFieldsAddTooltip => 'Agregar campo';

  @override
  String settingsCustomFieldsError(String error) {
    return 'Error: $error';
  }

  @override
  String get settingsCustomFieldsEmptyTitle => 'Sin campos personalizados';

  @override
  String settingsCustomFieldsEmptySubtitle(String termSingularLower) {
    return 'Agrega campos para registrar atributos personalizados de cada $termSingularLower';
  }

  @override
  String get settingsCustomFieldsAddAction => 'Agregar campo';

  @override
  String get settingsCustomFieldsDeleteTitle => 'Eliminar campo';

  @override
  String settingsCustomFieldsDeleteConfirm(String name) {
    return '¿Estás segure de que quieres eliminar \"$name\"? Se eliminará el campo y todos sus valores.';
  }

  @override
  String settingsCustomFieldsDeletedToast(String name) {
    return '$name eliminado';
  }

  @override
  String get settingsAccentColorPrismPurple => 'Morado Prism';

  @override
  String get settingsAccentColorBlue => 'Azul';

  @override
  String get settingsAccentColorGreen => 'Verde';

  @override
  String get settingsAccentColorRed => 'Rojo';

  @override
  String get settingsAccentColorOrange => 'Naranja';

  @override
  String get settingsAccentColorPink => 'Rosa';

  @override
  String get settingsAccentColorTeal => 'Verde azulado';

  @override
  String get settingsAccentColorAmber => 'Ámbar';

  @override
  String get settingsAccentColorIndigo => 'Índigo';

  @override
  String get settingsAccentColorGray => 'Gris';

  @override
  String get settingsAccentColorSystemColor => 'Color del sistema';

  @override
  String get settingsAccentColorCustom => 'Personalizado';

  @override
  String get settingsAccentColorPickerTitle => 'Elige un color';

  @override
  String get settingsAccentColorSelect => 'Seleccionar';

  @override
  String get settingsAccentColorSystemPaletteNote =>
      'Usando la paleta de colores del sistema';

  @override
  String get accentLegibilityTooDark =>
      'Este color es muy oscuro — puede ser difícil de ver en fondos oscuros.';

  @override
  String get accentLegibilityTooLight =>
      'Este color es muy claro — puede ser difícil de ver en fondos claros.';

  @override
  String get accentLegibilityTooDesaturated =>
      'Este color es muy gris — puede mezclarse con el fondo.';

  @override
  String get settingsChangePinTitle => 'Cambiar PIN';

  @override
  String get settingsChangePinVerifyBody =>
      'Ingresa tu PIN actual para continuar.';

  @override
  String get settingsChangePinCurrentLabel => 'PIN actual';

  @override
  String get settingsChangePinContinue => 'Continuar';

  @override
  String get settingsChangePinCurrentRequired => 'Ingresa tu PIN actual.';

  @override
  String get settingsChangePinNoSecretKey =>
      'Clave secreta no encontrada en este dispositivo. Vuelve a emparejar para restaurarla.';

  @override
  String get settingsChangePinEngineUnavailable =>
      'Motor de sincronización no disponible.';

  @override
  String get settingsChangePinIncorrect =>
      'PIN incorrecto. Inténtalo de nuevo.';

  @override
  String settingsChangePinVerifyFailed(String error) {
    return 'Error de verificación: $error';
  }

  @override
  String settingsChangePinGenericError(String error) {
    return 'Ocurrió un error: $error';
  }

  @override
  String get settingsChangePinSessionExpired =>
      'Sesión expirada — verifica de nuevo.';

  @override
  String get settingsChangePinWarnBody =>
      'Tus otros dispositivos necesitarán ingresar el nuevo PIN la próxima vez que abran Prism.';

  @override
  String get settingsChangePinAction => 'Cambiar PIN';

  @override
  String get settingsChangePinNewBody =>
      'Elige un nuevo PIN de sincronización.';

  @override
  String get settingsChangePinNewLabel => 'Nuevo PIN';

  @override
  String get settingsChangePinConfirmLabel => 'Confirmar nuevo PIN';

  @override
  String get settingsChangePinNewRequired => 'Ingresa un nuevo PIN.';

  @override
  String get settingsChangePinInvalidLength =>
      'El PIN debe tener exactamente 6 dígitos.';

  @override
  String get settingsChangePinSamePin =>
      'Tu PIN de sincronización ya está configurado con ese valor.';

  @override
  String get settingsChangePinMismatch => 'Los PINs no coinciden.';

  @override
  String get settingsChangePinGenerationConflict =>
      'Otro dispositivo cambió la configuración recientemente — inténtalo de nuevo.';

  @override
  String settingsChangePinFailed(String error) {
    return 'No se pudo cambiar el PIN: $error';
  }

  @override
  String get settingsChangePinSuccessTitle => 'PIN cambiado';

  @override
  String get settingsChangePinSuccessBody =>
      'Tu PIN de sincronización ha sido actualizado en este dispositivo.';

  @override
  String get changePinEnterMnemonicTitle =>
      'Introduce tu frase de recuperación';

  @override
  String get changePinEnterMnemonicSubtitle =>
      'Tu frase de 12 palabras no se guarda en este dispositivo. Escríbela desde tu copia de seguridad.';

  @override
  String get changePinMnemonicHint => '12 palabras separadas por espacios';

  @override
  String get changePinMnemonicInvalid =>
      'Esto no parece una frase de recuperación válida.';

  @override
  String get changePinMnemonicRequired =>
      'Introduce tu frase de recuperación de 12 palabras.';

  @override
  String get changePinVerifyButton => 'Continuar';

  @override
  String get changePinVerificationFailed =>
      'El PIN o la frase de recuperación son incorrectos.';

  @override
  String get settingsCreateEditFieldEditTitle => 'Editar campo';

  @override
  String get settingsCreateEditFieldNewTitle => 'Nuevo campo';

  @override
  String get settingsCreateEditFieldNameLabel => 'Nombre del campo';

  @override
  String get settingsCreateEditFieldNameHint =>
      'p. ej. Cumpleaños, Color favorito';

  @override
  String get settingsCreateEditFieldTypeHeading => 'Tipo';

  @override
  String get settingsCreateEditFieldTypeImmutable =>
      'El tipo no se puede cambiar después de la creación.';

  @override
  String get settingsCreateEditFieldDatePrecisionHeading =>
      'Precisión de fecha';

  @override
  String settingsCreateEditFieldSaveError(String error) {
    return 'Error al guardar el campo: $error';
  }

  @override
  String get settingsDataBrowserTitle => 'Visor de datos';

  @override
  String get settingsDataBrowserReloadTooltip => 'Recargar datos';

  @override
  String settingsDataBrowserTabMembers(String termPlural) {
    return '$termPlural';
  }

  @override
  String get settingsDataBrowserTabSessions => 'Sesiones';

  @override
  String get settingsDataBrowserTabChats => 'Chats';

  @override
  String get settingsDataBrowserTabMessages => 'Msgs';

  @override
  String get settingsDataBrowserTabPolls => 'Encuestas';

  @override
  String settingsDataBrowserError(String error) {
    return 'Error: $error';
  }

  @override
  String settingsDataBrowserNoMembers(String termPluralLower) {
    return 'Sin $termPluralLower';
  }

  @override
  String get settingsDataBrowserNoSessions => 'Sin sesiones';

  @override
  String get settingsDataBrowserNoConversations => 'Sin conversaciones';

  @override
  String get settingsDataBrowserNoMessages => 'Sin mensajes';

  @override
  String get settingsDataBrowserNoPolls => 'Sin encuestas';

  @override
  String get settingsDataBrowserSessionActive => 'Activo';

  @override
  String get settingsDataBrowserSessionEnded => 'Finalizado';

  @override
  String get settingsDataBrowserUntitled => 'Sin título';

  @override
  String settingsDataBrowserParticipantCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count participantes',
      one: '1 participante',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataBrowserSystemMessage => 'Sistema';

  @override
  String get settingsDataBrowserPollClosed => 'Cerrada';

  @override
  String get settingsDataBrowserPollActive => 'Activa';

  @override
  String get settingsDataBrowserNoMessagesInConversation =>
      'Sin mensajes en esta conversación.';

  @override
  String get settingsDataBrowserLoadError =>
      'Error al cargar — toca para reintentar';

  @override
  String settingsDataBrowserMessageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes',
      one: '1 mensaje',
    );
    return '$_temp0';
  }

  @override
  String get settingsDataBrowserTapToLoad => 'Toca para cargar mensajes';

  @override
  String get settingsDataBrowserSessionEndTimeActive => 'null (activo)';

  @override
  String get settingsSyncDebugTitle => 'Registro de eventos de Prism Sync';

  @override
  String settingsSyncDebugEventCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eventos',
      one: '1 evento',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncDebugCopyLogTooltip => 'Copiar registro';

  @override
  String get settingsSyncDebugClearLogTooltip => 'Limpiar registro';

  @override
  String get settingsSyncDebugCopiedToast =>
      'Registro de eventos de sincronización copiado';

  @override
  String get settingsSyncDebugEmptyTitle =>
      'Sin eventos de sincronización registrados';

  @override
  String get settingsSyncDebugEmptyBody =>
      'Los eventos de sincronización aparecerán aquí a medida que ocurran.';

  @override
  String get settingsTerminologyPickerLabel => 'Terminología';

  @override
  String get settingsTerminologyOptionMembers => 'Integrantes';

  @override
  String get settingsTerminologyOptionMembersSingular => 'integrante';

  @override
  String get settingsTerminologyOptionHeadmates => 'Compañeros de sistema';

  @override
  String get settingsTerminologyOptionHeadmatesSingular =>
      'compañero de sistema';

  @override
  String get settingsTerminologyOptionAlters => 'Alters';

  @override
  String get settingsTerminologyOptionAltersSingular => 'alter';

  @override
  String get settingsTerminologyOptionParts => 'Partes';

  @override
  String get settingsTerminologyOptionPartsSingular => 'parte';

  @override
  String get settingsTerminologyOptionFacets => 'Facetas';

  @override
  String get settingsTerminologyOptionFacetsSingular => 'faceta';

  @override
  String get settingsTerminologyOptionCustom => 'Personalizado';

  @override
  String get settingsTerminologyOptionCustomSingular => 'término personalizado';

  @override
  String get settingsTerminologyCustomSingularLabel =>
      'Término personalizado (singular)';

  @override
  String get settingsTerminologyCustomSingularHint => 'p. ej. fragmento';

  @override
  String get settingsTerminologyCustomPluralLabel =>
      'Término personalizado (plural)';

  @override
  String get settingsTerminologyCustomPluralHint => 'p. ej. fragmentos';

  @override
  String get settingsTerminologyPreviewLabel => 'Vista previa';

  @override
  String get terminologyEnglishOptionsLabel => 'En inglés';

  @override
  String get navHome => 'Inicio';

  @override
  String get navChat => 'Chat';

  @override
  String get navHabits => 'Hábitos';

  @override
  String get navPolls => 'Encuestas';

  @override
  String get navSettings => 'Ajustes';

  @override
  String get navMembers => 'Integrantes';

  @override
  String get navReminders => 'Recordatorios';

  @override
  String get navNotes => 'Notas';

  @override
  String get navStatistics => 'Estadísticas';

  @override
  String get navTimeline => 'Cronología';

  @override
  String get navSleep => 'Sueño';

  @override
  String get navBoards => 'Tableros';

  @override
  String get sleepScreenTitle => 'Sueño';

  @override
  String get sleepScreenAddTooltip => 'Registrar sueño';

  @override
  String get sleepScreenSettingsTooltip => 'Ajustes de sueño';

  @override
  String get sleepEmptyTitle => 'Aún no hay sesiones de sueño';

  @override
  String get sleepEmptyBody => 'Toca + para registrar la primera';

  @override
  String get sleepLastNightLabel => 'Anoche';

  @override
  String get sleepSevenDayAvgLabel => 'Prom. 7 días';

  @override
  String get sleepRecentSectionHeader => 'Reciente';

  @override
  String get sleepStatUnavailable => '—';

  @override
  String get sleepViewAllHistory => 'Ver historial de sueño';

  @override
  String sleepTrendVsPriorWeek(String delta) {
    return 'vs. semana anterior: $delta';
  }

  @override
  String get sleepDateLooksOff => 'La fecha parece incorrecta';

  @override
  String get sleepOverlapsExistingWarning =>
      'Se solapa con una sesión de sueño existente';

  @override
  String get logPastSleep => 'Registrar sueño pasado';

  @override
  String get cancelHistoricalSleep => 'Cancelar';

  @override
  String get onboardingWelcomeTitle => 'Bienvenide a Prism';

  @override
  String get onboardingWelcomeSubtitle => 'Tu sistema, a tu manera.';

  @override
  String get onboardingWelcomeSyncLink => 'Ya uso Prism en otro dispositivo';

  @override
  String get onboardingBiometricSetupTitle => 'Habilitar biometría';

  @override
  String get onboardingBiometricSetupSubtitle =>
      'Usa Face ID o Touch ID para desbloquear.';

  @override
  String get onboardingSyncDeviceTitle => 'Sincronizar desde dispositivo';

  @override
  String get onboardingSyncDeviceSubtitle =>
      'Emparejar con un dispositivo existente';

  @override
  String get onboardingImportedDataReadyTitle => 'Datos listos';

  @override
  String get onboardingImportedDataReadySubtitle =>
      'Tu sistema importado está listo para usar';

  @override
  String get onboardingImportDataTitle => '¿Ya tienes datos?';

  @override
  String get onboardingImportDataSubtitle => 'Trae tu sistema contigo.';

  @override
  String get onboardingSystemNameTitle => 'Nombra tu sistema';

  @override
  String get onboardingSystemNameSubtitle => 'Lo que se sienta bien.';

  @override
  String get onboardingAddMembersTitle => '¿Quién está aquí?';

  @override
  String get onboardingAddMembersSubtitle =>
      'Agrega a las personas en tu sistema.';

  @override
  String get onboardingFeaturesTitle => 'Elige tus herramientas';

  @override
  String get onboardingFeaturesSubtitle =>
      'Activa lo que necesitas. Cambia cuando quieras.';

  @override
  String get onboardingChatSetupTitle => 'Configura el chat';

  @override
  String get onboardingChatSetupSubtitle =>
      'Canales para que tu sistema pueda hablar.';

  @override
  String get onboardingPreferencesTitle => 'Hazlo tuyo';

  @override
  String get onboardingPreferencesSubtitle =>
      'Colores, idioma, los pequeños detalles.';

  @override
  String get onboardingPermissionsTitle => 'Una cosa más';

  @override
  String get onboardingPermissionsSubtitle =>
      'Permisos opcionales para la mejor experiencia.';

  @override
  String get onboardingPermissionsNotificationTitle => 'Notificaciones';

  @override
  String onboardingPermissionsNotificationRationale(String termPluralLower) {
    return 'Te avisaremos cuando $termPluralLower registren un cambio o sea hora de un recordatorio';
  }

  @override
  String get onboardingPermissionsMicrophoneTitle => 'Micrófono';

  @override
  String onboardingPermissionsMicrophoneRationale(String termPluralLower) {
    return 'Para que puedas grabar mensajes de voz para tus $termPluralLower';
  }

  @override
  String get onboardingPermissionsAllowed => 'Permitido';

  @override
  String get onboardingPermissionsAllow => 'Permitir';

  @override
  String get onboardingPermissionsOpenSettings => 'Cambiar en Ajustes';

  @override
  String get onboardingWhosFrontingTitle => '¿Quién está al frente?';

  @override
  String get onboardingWhosFrontingSubtitle =>
      'Toca a quienes están aquí ahora.';

  @override
  String get onboardingCompleteTitle => 'Listo cuando tú lo estés';

  @override
  String get onboardingCompleteSubtitle =>
      'Tu sistema está configurado. Esto es lo que puedes explorar.';

  @override
  String terminologyAddButton(String term) {
    return 'Agregar $term';
  }

  @override
  String terminologySearchHint(String term) {
    return 'Buscar $term...';
  }

  @override
  String terminologyEmptyTitle(String term) {
    return 'Sin $term aún';
  }

  @override
  String terminologyEmptyActiveTitle(String term) {
    return 'Sin $term activos aún';
  }

  @override
  String terminologyNewItem(String term) {
    return 'Nuevo $term';
  }

  @override
  String terminologyEditItem(String term) {
    return 'Editar $term';
  }

  @override
  String terminologyDeleteItem(String term) {
    return 'Eliminar $term';
  }

  @override
  String terminologyManage(String term) {
    return 'Gestionar $term';
  }

  @override
  String terminologyDeleteSelected(String term) {
    return 'Eliminar $term seleccionados';
  }

  @override
  String terminologySelectPrompt(String term) {
    return 'Selecciona un $term';
  }

  @override
  String terminologyNoFound(String term) {
    return 'No se encontraron $term';
  }

  @override
  String terminologyLoadError(String term, String error) {
    return 'Error al cargar $term: $error';
  }

  @override
  String terminologyAddFirstSubtitle(String term) {
    return 'Agrega tu primer $term del sistema para comenzar';
  }

  @override
  String pollsVotingAsSelectPrompt(String term) {
    return 'Selecciona un $term para votar';
  }

  @override
  String get onboardingPinSetupTitle => 'Establece tu PIN';

  @override
  String get onboardingPinSetupSubtitle =>
      'Usarás este PIN de 6 dígitos para bloquear Prism y recuperar el acceso si lo necesitas.';

  @override
  String get onboardingRecoveryPhraseTitle => 'Guarda tu frase de recuperación';

  @override
  String get onboardingRecoveryPhraseSubtitle =>
      'Anota estas 12 palabras en un lugar seguro. Las necesitarás para configurar la sincronización, agregar nuevos dispositivos o cambiar tu PIN.';

  @override
  String get onboardingConfirmPhraseTitle => 'Verifica tu frase';

  @override
  String get onboardingConfirmPhraseSubtitle =>
      'Selecciona la palabra correcta para cada posición.';

  @override
  String get syncPinSheetTitle => 'Ingresa tu PIN';

  @override
  String get syncPinSheetSubtitle =>
      'Tu PIN es necesario para desbloquear Prism.';

  @override
  String get syncPinSheetMnemonicSubtitle =>
      'Ingresa tu frase de recuperación de 12 palabras para continuar. No se guarda en este dispositivo.';

  @override
  String get syncPinSheetMnemonicInvalid =>
      'Esto no parece una frase de recuperación válida.';

  @override
  String get syncPinSheetUnlockFailed =>
      'No se pudo desbloquear con esta frase y PIN.';

  @override
  String get syncPinSheetLostPhrase => '¿Perdiste tu frase?';

  @override
  String get syncPinSheetLostPhraseBody =>
      'Tu frase de recuperación es la única forma de desbloquear la sincronización en este dispositivo. Si la perdiste, reinicia la app y restaura desde una copia de seguridad exportada.';

  @override
  String get syncPinSheetMnemonicContinue => 'Continuar';

  @override
  String get syncPinSheetBack => 'Atrás';

  @override
  String mnemonicFieldWordCounter(String filled) {
    return '$filled de 12 palabras';
  }

  @override
  String get mnemonicFieldPaste => 'Pegar frase';

  @override
  String get mnemonicFieldShowWords => 'Mostrar palabras';

  @override
  String get mnemonicFieldHideWords => 'Ocultar palabras';

  @override
  String mnemonicFieldWordSlotLabel(String n) {
    return 'Palabra $n';
  }

  @override
  String mnemonicFieldWordChipValid(String n, String word) {
    return 'Palabra $n: $word, válida';
  }

  @override
  String mnemonicFieldWordChipInvalid(String n, String word) {
    return 'Palabra $n: $word, no reconocida';
  }

  @override
  String get mnemonicFieldScanQrTooltip => 'Escanear código QR';

  @override
  String get mnemonicFieldShowQrTooltip => 'Mostrar código QR';

  @override
  String get mnemonicFieldQrTitle => 'QR de frase de recuperación';

  @override
  String get mnemonicFieldQrDescription =>
      'Escanea este código QR para rellenar la frase de recuperación de 12 palabras en otro dispositivo.';

  @override
  String get mnemonicFieldScanQrTitle => 'Escanear QR de recuperación';

  @override
  String get mnemonicFieldScanQrDescription =>
      'Escanea un código QR que contenga tu frase de recuperación de 12 palabras.';

  @override
  String get mnemonicFieldInvalidQr =>
      'Código QR no válido. Escanea una frase de recuperación de 12 palabras.';

  @override
  String get mnemonicFieldCameraPermissionTitle =>
      'Permiso de cámara necesario';

  @override
  String get mnemonicFieldCameraPermissionDeniedBody =>
      'Prism necesita la cámara para escanear tu código QR de recuperación. Intenta de nuevo y permite el acceso a la cámara cuando se solicite.';

  @override
  String get mnemonicFieldCameraPermissionPermanentlyDeniedBody =>
      'El acceso a la cámara está bloqueado. Abre Ajustes para conceder el permiso de cámara a Prism y vuelve a intentarlo.';

  @override
  String get mnemonicFieldCameraPermissionOpenSettings => 'Abrir Ajustes';

  @override
  String get pluralkitAutoSyncSection => 'Auto-sincronización';

  @override
  String get pluralkitAutoSyncTitle => 'Obtener cambios automáticamente';

  @override
  String get pluralkitAutoSyncDescription =>
      'Mientras Prism esté abierto, consulta PluralKit para ver nuevos cambios de frente cada cierto intervalo. Se pausa en segundo plano.';

  @override
  String get pluralkitAutoSyncIntervalLabel => 'Consultar cada';

  @override
  String get pluralkitAutoSyncLoadFailed =>
      'No se pudieron cargar los ajustes de auto-sincronización.';

  @override
  String get pluralkitRerunMemberMapping => 'Volver a vincular integrantes';

  @override
  String get pluralkitImportFromFile => 'Recuperar historial desde pk;export';

  @override
  String pluralkitMappingBannerTitle(String termPluralLower) {
    return 'Un paso más: vincula a tus $termPluralLower';
  }

  @override
  String pluralkitMappingBannerBody(String termSingularLower) {
    return 'Estás conectado. Antes de activar la sincronización, empareja cada miembro de PluralKit con $termSingularLower de Prism — o impórtalos como nuevos. Esto evita duplicados y mantiene el historial de fronts ligado a la persona correcta.';
  }

  @override
  String pluralkitMappingBannerButton(String termPluralLower) {
    return 'Vincular $termPluralLower';
  }

  @override
  String get sleepWakeUpMorning => '¡Buenos días!';

  @override
  String get sleepWakeUpAfternoon => '¡Buenas tardes!';

  @override
  String get sleepWakeUpEvening => '¡Buenas noches!';

  @override
  String get sleepWakeUpNight => '¡Arriba!';

  @override
  String sleepWakeUpSleptFor(String duration) {
    return 'Dormiste $duration';
  }

  @override
  String get sleepWakeUpQualityQuestion => '¿Cómo dormiste?';

  @override
  String get sleepWakeUpWhosFronting => '¿Quién está al frente ahora?';

  @override
  String get sleepWakeUpDone => 'Listo';

  @override
  String get sleepWakeUpSkip => 'Omitir';

  @override
  String get sleepWakeUpOthers => 'Otros...';

  @override
  String get sleepSuggestionBedtime => 'Es tu hora habitual de dormir';

  @override
  String get sleepSuggestionBedtimeAction => 'Iniciar Sueño';

  @override
  String sleepWakeSuggestionNudge(String duration) {
    return 'Has dormido por $duration';
  }

  @override
  String get featureSleepSuggestions => 'Sugerencias';

  @override
  String get featureSleepBedtimeReminder => 'Recordatorio de Hora de Dormir';

  @override
  String get featureSleepBedtimeReminderSubtitle =>
      'Mostrar un recordatorio a tu hora habitual de dormir';

  @override
  String get featureSleepBedtimeTime => 'Hora de Dormir';

  @override
  String get featureSleepWakeReminder => 'Recordatorio de Despertar';

  @override
  String get featureSleepWakeReminderSubtitle =>
      'Aviso para despertar después de cierta duración';

  @override
  String get featureSleepWakeAfter => 'Despertar Después de';

  @override
  String featureSleepWakeAfterHours(String hours) {
    return '$hours horas';
  }

  @override
  String get onboardingSyncMembersLabel => 'Integrantes del sistema';

  @override
  String get onboardingSyncPhaseConnectTitle => 'Conectando…';

  @override
  String get onboardingSyncPhaseConnectSubtitle =>
      'Saludando a tu otro dispositivo';

  @override
  String get onboardingSyncPhaseDownloadTitle => 'Descargando tu sistema';

  @override
  String get onboardingSyncPhaseDownloadSubtitle =>
      'Trayendo la instantánea cifrada';

  @override
  String get onboardingSyncPhaseRestoreTitle => 'Restaurando tus datos';

  @override
  String get onboardingSyncPhaseRestoreSubtitle =>
      'Desempaquetando miembros, mensajes y notas';

  @override
  String get onboardingSyncPhaseFinishTitle => 'Finalizando';

  @override
  String get onboardingSyncPhaseFinishSubtitle => 'Asegurando todo';

  @override
  String get onboardingSyncReassurance =>
      'Aún cargando — los sistemas grandes pueden tardar un momento en redes lentas.';

  @override
  String get onboardingSyncReconnecting => 'Reconectando al relay…';

  @override
  String get onboardingSyncNoDataToRestore =>
      'Sin datos previos para restaurar — empezando desde cero.';

  @override
  String get onboardingSyncStillPullingBackground =>
      'Aún descargando actualizaciones en segundo plano. Puedes continuar.';

  @override
  String onboardingSyncPhaseAnnouncement(String phase) {
    return 'Ahora: $phase';
  }

  @override
  String onboardingSyncRestoredSummary(int members, int messages) {
    return 'Se restauraron $members miembros y $messages mensajes.';
  }

  @override
  String onboardingPhaseSegmentsSemantics(int current, int total) {
    return 'Paso $current de $total';
  }

  @override
  String get pkProfileDisclosureTitle =>
      '¿Importar tu perfil de sistema desde PluralKit?';

  @override
  String get pkProfileDisclosureSubtitle => 'Solo copiaremos lo que marques.';

  @override
  String get pkProfileDisclosureImport => 'Importar selección';

  @override
  String get pkProfileDisclosureSkip => 'Omitir';

  @override
  String get pkProfileFieldName => 'Nombre del sistema';

  @override
  String get pkProfileFieldDescription => 'Descripción';

  @override
  String get pkProfileFieldTag => 'Etiqueta del sistema';

  @override
  String get pkProfileFieldAvatar => 'Avatar del sistema';

  @override
  String get pkProfileFieldOverwriteHint =>
      'Prism ya tiene un valor — marca para sobrescribir.';

  @override
  String get migrationCfStepTitle => 'Frentes personalizados';

  @override
  String get migrationCfStepExplainer =>
      'Simply Plural tiene frentes personalizados (Co-fronting, Dormido y otros). Prism no los maneja como estados de primera clase. Elige qué hacer con cada uno.';

  @override
  String get migrationCfResetDefaults => 'Restablecer valores predeterminados';

  @override
  String get migrationCfBack => 'Atrás';

  @override
  String get migrationCfContinue => 'Continuar';

  @override
  String migrationCfOptionMember(String termSingularLower) {
    return 'Importar como $termSingularLower';
  }

  @override
  String get migrationCfOptionNote => 'Fusionar en notas';

  @override
  String get migrationCfOptionSleep => 'Convertir en sueño';

  @override
  String get migrationCfOptionSkip => 'Omitir';

  @override
  String migrationCfOptionMemberDesc(String termSingularLower) {
    return 'Crea $termSingularLower con este nombre. Las entradas del historial al frente se guardan como sesiones de $termSingularLower.';
  }

  @override
  String get migrationCfOptionNoteDesc =>
      'No se crea ningún integrante. El nombre del frente personalizado se añade a las notas de las sesiones que lo mencionan.';

  @override
  String get migrationCfOptionSleepDesc =>
      'Las entradas del historial al frente en las que éste es el fronter principal se convierten en sesiones de sueño.';

  @override
  String get migrationCfOptionSkipDesc =>
      'Sin integrante y sin nota. Las sesiones sin otro fronter se descartan.';

  @override
  String get migrationCfReasonSleepName =>
      'El nombre coincide con palabras clave de sueño';

  @override
  String get migrationCfReasonZeroUsage =>
      'Nunca se usa en el historial al frente ni en temporizadores';

  @override
  String get migrationCfReasonCoFronterOnly => 'Solo se usa como co-fronter';

  @override
  String get migrationCfReasonPrimaryHeavy =>
      'Se usa principalmente como fronter primario';

  @override
  String get migrationCfReasonFallback =>
      'Uso variado — lo más seguro es conservarlo como nota';

  @override
  String migrationCfUsageSummary(int primary, int coFront, int timers) {
    String _temp0 = intl.Intl.pluralLogic(
      primary,
      locale: localeName,
      other: '$primary primarios',
      one: '1 primario',
      zero: 'Nunca primario',
    );
    String _temp1 = intl.Intl.pluralLogic(
      coFront,
      locale: localeName,
      other: '$coFront co-front',
      one: '1 co-front',
      zero: '0 co-front',
    );
    String _temp2 = intl.Intl.pluralLogic(
      timers,
      locale: localeName,
      other: '$timers temporizadores',
      one: '1 temporizador',
      zero: '0 temporizadores',
    );
    return '$_temp0 · $_temp1 · $_temp2';
  }

  @override
  String migrationCfPreviewBreakdown(
    int asMember,
    int asSleep,
    int asNote,
    int asSkip,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      asMember,
      locale: localeName,
      other: '$asMember como integrantes',
      one: '1 como integrante',
    );
    String _temp1 = intl.Intl.pluralLogic(
      asSleep,
      locale: localeName,
      other: '$asSleep como sueño',
      one: '1 como sueño',
    );
    String _temp2 = intl.Intl.pluralLogic(
      asNote,
      locale: localeName,
      other: '$asNote notas',
      one: '1 nota',
    );
    String _temp3 = intl.Intl.pluralLogic(
      asSkip,
      locale: localeName,
      other: '$asSkip omitidos',
      one: '1 omitido',
    );
    return '$_temp0 · $_temp1 · $_temp2 · $_temp3';
  }

  @override
  String migrationWarnCfDroppedEntries(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se descartaron $count entradas del historial al frente (el principal era un frente personalizado omitido sin co-fronters).',
      one:
          'Se descartó 1 entrada del historial al frente (el principal era un frente personalizado omitido sin co-fronters).',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepCoFrontersDiscarded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones en modo sueño tenían co-fronters que fueron descartados.',
      one: '1 sesión en modo sueño tenía co-fronters que fueron descartados.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepCoFronterAsNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones al frente tenían un frente personalizado de sueño como co-fronter; se conservaron solo como nota.',
      one:
          '1 sesión al frente tenía un frente personalizado de sueño como co-fronter; se conservó solo como nota.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepOverlap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones de sueño se solapan con otras sesiones en tu cronología — resuélvelo en la pestaña Al frente.',
      one:
          '1 sesión de sueño se solapa con otras sesiones en tu cronología — resuélvelo en la pestaña Al frente.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfCommentsDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se descartaron $count comentarios (adjuntos a sesiones de frentes personalizados omitidas).',
      one:
          'Se descartó 1 comentario (adjunto a sesiones de frentes personalizados omitidas).',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfStaleMembers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count frentes personalizados importados previamente ya no se importan como integrantes; los registros de integrantes existentes permanecen — elimínalos manualmente si quieres quitarlos.',
      one:
          '1 frente personalizado importado previamente ya no se importa como integrante; el registro del integrante existente permanece — elimínalo manualmente si quieres quitarlo.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfDeletedRefs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count referencias del historial al frente apuntaban a frentes personalizados eliminados en SP — se trataron como notas.',
      one:
          '1 referencia del historial al frente apuntaba a un frente personalizado eliminado en SP — se trató como nota.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepClamped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas de sueño abiertas en SP se limitaron a 24 h.',
      one: '1 entrada de sueño abierta en SP se limitó a 24 h.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfTimersAdjusted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count temporizadores apuntaban a frentes personalizados que no se importaron como integrantes — se descartó el objetivo o se eliminaron los temporizadores.',
      one:
          '1 temporizador apuntaba a un frente personalizado que no se importó como integrante — se descartó el objetivo o se eliminó el temporizador.',
    );
    return '$_temp0';
  }

  @override
  String migrationWarnCfSleepDedup(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count entradas de sueño duplicadas de SP se combinaron.',
      one: '1 entrada de sueño duplicada de SP se combinó.',
    );
    return '$_temp0';
  }

  @override
  String get frontingUpgradeTitle => 'Actualización del frente';

  @override
  String get frontingUpgradeIntroHeadline =>
      'Estamos actualizando cómo se guarda el frente';

  @override
  String frontingUpgradeIntroBody(String termSingularLower) {
    return 'El co-frente ahora usa un registro por $termSingularLower en lugar de un único registro compartido. Esto hace que los solapamientos, las ediciones y las estadísticas funcionen correctamente. Primero guardaremos una copia de seguridad de tus datos actuales y luego haremos la actualización.';
  }

  @override
  String get frontingUpgradeContinue => 'Continuar';

  @override
  String get frontingUpgradeRoleHeadline =>
      '¿Este es tu dispositivo principal?';

  @override
  String get frontingUpgradeRoleBody =>
      'Tu dispositivo principal conserva todo tu historial de frente. Los otros dispositivos tendrán que vincularse de nuevo después y descargar el historial migrado desde el dispositivo principal.';

  @override
  String get frontingUpgradeRolePrimary =>
      'Sí, este es mi dispositivo principal';

  @override
  String get frontingUpgradeRoleSecondary =>
      'No, este es un dispositivo secundario';

  @override
  String get frontingUpgradeModeHeadline =>
      '¿Cómo deberíamos hacer la actualización?';

  @override
  String get frontingUpgradeModeKeepTitle => 'Conservar mis datos';

  @override
  String get frontingUpgradeModeKeepBody =>
      'Tus frentes existentes se conservan. Los frentes importados desde PluralKit se volverán a importar con la nueva estructura en la próxima sincronización con PluralKit.';

  @override
  String get frontingUpgradeModeFreshTitle => 'Empezar desde cero';

  @override
  String get frontingUpgradeModeFreshBody =>
      'Se borran todos los frentes. Útil si tu historial de frente está desordenado y quieres partir de cero. De todas formas se crea un archivo de copia de seguridad.';

  @override
  String get frontingUpgradeRecommended => 'Recomendado';

  @override
  String get frontingUpgradePasswordHeadline => 'Protege tu copia de seguridad';

  @override
  String get frontingUpgradePasswordBody =>
      'Estamos a punto de hacer una copia de seguridad de tus datos de frente actuales y luego actualizarlos.';

  @override
  String get frontingUpgradePasswordNote =>
      'Esta contraseña protege tu archivo de copia de seguridad. Guárdala en un lugar seguro — sin ella, el archivo no se puede recuperar.';

  @override
  String get frontingUpgradePasswordSubmit =>
      'Hacer copia de seguridad y actualizar';

  @override
  String get frontingUpgradeRunning => 'Migrando tu historial de frente…';

  @override
  String get frontingUpgradeRunningSubtitle =>
      'Esto puede tardar un momento. No cierres la app.';

  @override
  String get frontingUpgradeExporting => 'Preparando tu copia de seguridad…';

  @override
  String get frontingUpgradeExportingSubtitle =>
      'Cifrando tus datos de frente para que puedas conservar una copia.';

  @override
  String get frontingUpgradeBackupReadyHeadline => 'Copia de seguridad lista';

  @override
  String get frontingUpgradeBackupReadyBody =>
      'Guarda esta copia de seguridad en un lugar donde puedas encontrarla más tarde — fuera de la app. Sin ella, no podrás recuperar tus datos antiguos si algo sale mal.';

  @override
  String get frontingUpgradeBackupSaveAs => 'Guardar copia de seguridad…';

  @override
  String get frontingUpgradeBackupShare => 'Compartir…';

  @override
  String get frontingUpgradeBackupAcknowledge =>
      'He guardado esta copia de seguridad en un lugar donde podré encontrarla más tarde';

  @override
  String get frontingUpgradeBackupContinue => 'Continuar';

  @override
  String get frontingUpgradeSuccessHeadline => '¡Migración completa!';

  @override
  String frontingUpgradeCountSpMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se migraron $count sesiones de Simply Plural.',
      one: 'Se migró 1 sesión de Simply Plural.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountNativeMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se migraron $count sesiones de frente.',
      one: 'Se migró 1 sesión de frente.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountNativeExpanded(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se expandieron $count periodos de co-frente en registros por $termSingularLower.',
      one:
          'Se expandió 1 periodo de co-frente en registros por $termSingularLower.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountPkDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se borró el historial de PluralKit del formato anterior ($count sesiones). Vuelve a importarlo desde un token de PluralKit o un archivo pk;export.',
      one:
          'Se borró el historial de PluralKit del formato anterior (1 sesión). Vuelve a importarlo desde un token de PluralKit o un archivo pk;export.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountCommentsMigrated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se migraron $count comentarios.',
      one: 'Se migró 1 comentario.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountOrphansAssigned(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se asignaron $count sesiones sin atribución a $termSingularLower desconocido.',
      one:
          'Se asignó 1 sesión sin atribución a $termSingularLower desconocido.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradeCountSentinelCreated(String termSingularLower) {
    return 'Se creó $termSingularLower desconocido para guardar las sesiones sin un frente claro.';
  }

  @override
  String frontingUpgradeCountCorruptCoFronters(
    int count,
    String termSingularLower,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count sesiones tenían datos de co-frente ilegibles y se migraron como de $termSingularLower único.',
      one:
          '1 sesión tenía datos de co-frente ilegibles y se migró como de $termSingularLower único.',
    );
    return '$_temp0';
  }

  @override
  String get frontingUpgradeIntroPendingSyncWarning =>
      'Si tienes cambios sin sincronizar por uso sin conexión, asegúrate de que tu dispositivo esté en línea y sincronizado antes de continuar. Las cargas pendientes tendrás que volver a hacerlas después de la actualización.';

  @override
  String frontingUpgradeAnalyticsNote(String term) {
    return 'Las estadísticas ahora se muestran como minutos por $term — si dos de ustedes están en co-frente durante una hora, eso son dos horas-$term. La misma cuenta de antes, con una etiqueta más clara.';
  }

  @override
  String get frontingUpgradeRepairPrimary =>
      'Tus otros dispositivos tienen que vincularse de nuevo para recibir el historial migrado. Abre Configuración → Sincronización en tus otros dispositivos y sigue el flujo de vinculación.';

  @override
  String get frontingUpgradeRepairSecondary =>
      'Vincula este dispositivo de nuevo con tu dispositivo principal para recibir el historial migrado.';

  @override
  String get frontingUpgradeRepairSolo =>
      'Todo listo. Tus datos de frente ya están en el nuevo formato.';

  @override
  String get frontingUpgradeOpenPluralKitImport =>
      'Abrir importación de PluralKit';

  @override
  String get frontingUpgradeFailureHeadline => 'La migración falló';

  @override
  String get frontingUpgradeFailureBackupNote =>
      'Tu archivo de copia de seguridad se guardó. Puedes encontrarlo en el historial de tu menú de compartir si necesitas recuperar los datos.';

  @override
  String get frontingUpgradeBannerTitle => 'Actualización del frente pendiente';

  @override
  String get frontingUpgradeBannerMessage =>
      'Toca para continuar con la actualización.';

  @override
  String get frontingUpgradeResumeCleanupHeadline => 'Terminar la migración';

  @override
  String get frontingUpgradeResumeCleanupBody =>
      'Un intento anterior terminó la migración de datos pero no pudo completar el restablecimiento de sincronización. Toca abajo para terminar — solo se actualizan las credenciales de sincronización, no se tocan tus datos.';

  @override
  String get frontingUpgradeResumeCleanupButton => 'Terminar la migración';

  @override
  String get frontingUpgradePkTokenDialogTitle => 'Token de PluralKit';

  @override
  String get frontingUpgradePkTokenDialogMessage =>
      'Importa el historial de fronts de PluralKit ahora. El token se usa una sola vez y no activa la sincronización con PluralKit.';

  @override
  String get frontingUpgradePkTokenLabel => 'Token de PluralKit';

  @override
  String get frontingUpgradePkTokenHint => 'Pega tu token de PluralKit';

  @override
  String get frontingUpgradePkTokenImport => 'Importar';

  @override
  String get frontingUpgradePkImportButton => 'Importar con token de PluralKit';

  @override
  String get frontingUpgradePkImportIdle =>
      'El historial de PluralKit se puede reimportar aquí con un token temporal. El token se usa una sola vez y la sincronización con PluralKit permanece desactivada.';

  @override
  String get frontingUpgradePkImportRunning =>
      'Reimportando el historial de PluralKit...';

  @override
  String get frontingUpgradePkImportImported =>
      'Se reimportó el historial de PluralKit.';

  @override
  String frontingUpgradePkImportTombstoneLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se conservaron $count registros eliminados para respetar la eliminación local.',
      one:
          'Se conservó 1 registro eliminado para respetar la eliminación local.',
    );
    return '$_temp0';
  }

  @override
  String frontingUpgradePkImportZeroLengthLine(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se omitieron $count cierres de duración cero (PluralKit registró entradas y salidas en el mismo instante).',
      one:
          'Se omitió 1 cierre de duración cero (PluralKit registró una entrada y una salida en el mismo instante).',
    );
    return '$_temp0';
  }

  @override
  String get frontingUpgradePkImportNeedsToken =>
      'No se encontró un token de PluralKit guardado. Puedes importar con un token temporal sin activar la sincronización con PluralKit.';

  @override
  String frontingUpgradePkImportFailed(String error) {
    return 'La reimportación de PluralKit falló: $error';
  }

  @override
  String pkFileImportMembersLabel(String termPlural) {
    return '$termPlural';
  }

  @override
  String get pkFileImportGroupsLabel => 'Grupos';

  @override
  String get pkFileImportFrontingSessionsLabel =>
      'Cambios encontrados (no importados)';

  @override
  String get pkFileImportSwitchesFoundLabel =>
      'Cambios encontrados (no importados)';

  @override
  String pkFileImportPreviewNote(String termPlural) {
    return 'Los/las $termPlural existentes con el mismo ID de PluralKit se actualizarán. Para importar el historial de fronts, agrega un token de PluralKit para que Prism pueda vincular los cambios antes de importarlos.';
  }

  @override
  String get pkFileImportImportButton => 'Importar';

  @override
  String get pkFileImportSwitchesMatchedLabel =>
      'Cambios vinculados con el token';

  @override
  String get pkFileImportNewerSwitchesLabel => 'Cambios nuevos desde PluralKit';

  @override
  String get pkFileImportFrontingImportedNote =>
      'El historial de fronts se importó por la ruta de PluralKit con token, así Prism puede seguir usando los IDs canónicos de los cambios.';

  @override
  String pkFileImportFrontingImportedNoteWithNewer(int count) {
    return 'El historial de fronts se importó por la ruta de PluralKit con token, así Prism puede seguir usando los IDs canónicos de los cambios. Prism también importó $count cambios nuevos desde PluralKit que no estaban en la exportación.';
  }

  @override
  String get pkFileImportFrontingNotImportedNote =>
      'El historial de fronts no se importó porque la exportación y la API de PluralKit no coincidieron de forma segura.';

  @override
  String get pkFileImportDoneButton => 'Listo';

  @override
  String get pkFileImportFailedHeadline => 'La importación falló';

  @override
  String get pkFileImportTryAgainButton => 'Intentar de nuevo';

  @override
  String get pkFileImportPickDifferentButton => 'Elegir otro archivo';

  @override
  String get pkFileImportCompleteHeading => 'Importación completa';

  @override
  String get pkFileImportSwitchesCreatedLabel => 'Cambios creados';

  @override
  String get pkFileImportSwitchesSkippedLabel =>
      'Cambios encontrados (no importados)';

  @override
  String get settingsFrontingSessionDisplaySectionTitle =>
      'Visualización de sesiones y comportamiento del frente';

  @override
  String get settingsFrontingListViewModeLabel =>
      'Vista de la lista de sesiones';

  @override
  String get settingsFrontingListViewModeCombinedPeriods =>
      'Períodos combinados';

  @override
  String get settingsFrontingListViewModeCombinedPeriodsDescription =>
      'Pilas de avatares para cada grupo único al frente';

  @override
  String settingsFrontingListViewModePerMemberRows(String term) {
    return 'Filas por $term';
  }

  @override
  String get settingsFrontingListViewModePerMemberRowsDescription =>
      'Una fila por sesión al frente, lado a lado';

  @override
  String get settingsFrontingListViewModeTimeline => 'Cronología';

  @override
  String get settingsFrontingListViewModeTimelineDescription =>
      'Vista de gráfico de barras del frente a lo largo del tiempo';

  @override
  String get settingsAddFrontDefaultBehaviorLabel =>
      'Al agregar un nuevo frente';

  @override
  String get settingsAddFrontDefaultBehaviorAdditive => 'Agregar al co-frente';

  @override
  String get settingsAddFrontDefaultBehaviorAdditiveDescription =>
      'Los nuevos frentes se suman a los existentes';

  @override
  String get settingsAddFrontDefaultBehaviorReplace =>
      'Reemplazar quienes están al frente';

  @override
  String get settingsAddFrontDefaultBehaviorReplaceDescription =>
      'Termina todos los frentes actuales antes de iniciar uno nuevo';

  @override
  String get settingsQuickFrontDefaultBehaviorLabel => 'Al usar frente rápido';

  @override
  String get settingsQuickFrontDefaultBehaviorAdditive =>
      'Agregar al co-frente';

  @override
  String get settingsQuickFrontDefaultBehaviorReplace =>
      'Reemplazar quienes están al frente';

  @override
  String get featureBoardsTitle => 'Tableros de Mensajes';

  @override
  String get featureBoardsDescription =>
      'Mensajes cortos entre los integrantes del sistema — línea de tiempo pública e inbox privado.';

  @override
  String get featureBoardsEnable => 'Activar Tableros de Mensajes';

  @override
  String get featureBoardsEnableSubtitle =>
      'Añade la pestaña Tableros a tu navegación.';

  @override
  String get navMenuToastBoardsAdded =>
      'Tableros de Mensajes añadido a tu menú de navegación — arrástralo donde quieras.';

  @override
  String get boardsTileEdited => 'editado';

  @override
  String get boardsTileToEveryone => 'para todos';

  @override
  String get boardsTileRemovedMember => 'Integrante eliminado';

  @override
  String get boardsDetailEdit => 'Editar';

  @override
  String get boardsDetailDelete => 'Eliminar';

  @override
  String get boardsDeleteConfirmTitle => '¿Eliminar esta publicación?';

  @override
  String get boardsDeleteConfirmBody => 'Esto no se puede deshacer.';

  @override
  String get memberBoardScreenTitle => 'Mensajes del tablero';

  @override
  String get memberBoardEmpty => 'Aún no hay publicaciones aquí.';

  @override
  String get boardsScreenTitle => 'Tableros';

  @override
  String get boardsTabPublic => 'Público';

  @override
  String get boardsTabInbox => 'Bandeja de entrada';

  @override
  String get boardsViewFilterAll => 'Todos los que están al frente';

  @override
  String boardsViewFilterMember(String name) {
    return '$name';
  }

  @override
  String get boardsEmptyPublic =>
      'Todavía no hay nada en la línea de tiempo pública.';

  @override
  String get boardsEmptyInbox => 'No hay mensajes privados en este momento.';

  @override
  String get boardsComposeNoFronterHint =>
      'Nadie está al frente ahora mismo — inicia una sesión para publicar.';

  @override
  String boardsToastFronterDeFronted(String name) {
    return '$name dejó el frente — mostrando todos';
  }

  @override
  String get boardsComposeRecipientPublicEveryone => 'Todos (público)';

  @override
  String boardsComposeRecipientPublicMember(String name) {
    return '$name (público)';
  }

  @override
  String boardsComposeRecipientPrivateMember(String name) {
    return '$name (privado)';
  }

  @override
  String get boardsComposeAddTitle => '+ Agregar título';

  @override
  String get boardsComposeTitlePlaceholder => 'Título (opcional)';

  @override
  String get boardsComposeBodyPlaceholder => 'Escribe algo...';

  @override
  String boardsComposeConsequencePrivate(String name) {
    return 'Solo $name verá esto en su Inbox.';
  }

  @override
  String boardsComposeConsequencePublicMember(String name) {
    return 'El perfil de $name y el feed público mostrarán esto.';
  }

  @override
  String get boardsComposeConsequencePublicEveryone =>
      'Todos en tu sistema verán esto en el feed público.';

  @override
  String get boardsComposeSave => 'Publicar';

  @override
  String get boardsComposeCancel => 'Cancelar';

  @override
  String get boardsComposeEditing => 'Editar publicación';

  @override
  String get boardsComposeNewPost => 'New post';

  @override
  String get boardsComposeAudienceEveryone => 'Everyone';

  @override
  String get boardsComposeAudiencePrivate => 'Private';

  @override
  String get boardsComposeToNoHeadmate => 'No headmate';

  @override
  String get boardsComposeFromLabel => 'From';

  @override
  String get boardsComposeToLabel => 'To';

  @override
  String get memberSectionBoardMessages => 'Mensajes del tablero';

  @override
  String memberBoardSeeAll(int count) {
    return 'Ver las $count publicaciones';
  }

  @override
  String memberBoardAddPost(String name) {
    return 'Publicar para $name';
  }

  @override
  String get importDisclosureBoardsEnabled =>
      'Tableros de mensajes activados — tus mensajes importados están en el Buzón.';

  @override
  String get boardsPostDetailTitle => 'Publicación';

  @override
  String get boardsPostDetailNotFound =>
      'Esta publicación ya no está disponible.';
}
