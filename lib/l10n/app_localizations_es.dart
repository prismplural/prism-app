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
  String get noResults => 'Sin resultados';

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
  String get selectMember => 'Seleccionar integrante';

  @override
  String get selectMembers => 'Seleccionar integrantes';

  @override
  String get selectAMember => 'Seleccionar un integrante';

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
  String get searchMembers => 'Buscar integrantes...';

  @override
  String get noMembersFound => 'No se encontraron integrantes';

  @override
  String get moreOptions => 'Más opciones';

  @override
  String get settingsSectionSystem => 'Sistema';

  @override
  String get settingsSectionApp => 'App';

  @override
  String get settingsSectionData => 'Datos';

  @override
  String get settingsSectionAbout => 'Acerca de';

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
  String get settingsSync => 'Sincronización';

  @override
  String get settingsSharing => 'Compartir';

  @override
  String get settingsImportExport => 'Importar y exportar';

  @override
  String get settingsResetData => 'Restablecer datos';

  @override
  String get settingsAbout => 'Acerca de';

  @override
  String get settingsEncryptionPrivacy => 'Cifrado y privacidad';

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
  String get appearanceAccentColor => 'Color de acento';

  @override
  String get appearancePerMemberColors => 'Colores por integrante';

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
  String get appearancePreview => 'Vista previa';

  @override
  String get appearanceSamplePronouns => 'ella';

  @override
  String get appearanceFronting => 'Al frente';

  @override
  String get appearanceUsingSystemPalette =>
      'Usando la paleta de colores del sistema';

  @override
  String get syncTitle => 'Sincronización';

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
  String get syncChangePassword => 'Cambiar contraseña';

  @override
  String get syncChangePasswordSubtitle =>
      'Actualizar tu contraseña de cifrado de sincronización';

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
    return '$count entidades';
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
  String get syncSetupPasswordTitle => 'Crear contraseña';

  @override
  String get syncSetupSecretKeyTitle => 'Tu clave secreta';

  @override
  String get syncSetupIntroHeadline =>
      'Mantén tus datos sincronizados en todos tus dispositivos.';

  @override
  String get syncSetupIntroBody =>
      'Todo está cifrado de extremo a extremo — el servidor nunca ve tus datos. Crearás una contraseña y recibirás una clave de recuperación para guardar.';

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
  String get syncSetupPasswordIntro =>
      'Crea una contraseña para proteger tus claves de cifrado.';

  @override
  String get syncSetupPasswordHelp =>
      'Necesitarás esta contraseña cada vez que configures un nuevo dispositivo.';

  @override
  String get syncSetupPasswordLabel => 'Contraseña';

  @override
  String get syncSetupConfirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get syncSetupContinueButton => 'Continuar';

  @override
  String get syncSetupCompleteButton => 'Completar configuración';

  @override
  String get syncSetupPasswordTooShort =>
      'La contraseña debe tener al menos 8 caracteres';

  @override
  String get syncSetupPasswordMismatch => 'Las contraseñas no coinciden';

  @override
  String get syncSetupProgressCreatingGroup =>
      'Creando grupo de sincronización...';

  @override
  String get syncSetupProgressConfiguringEngine => 'Configurando cifrado...';

  @override
  String get syncSetupProgressCachingKeys => 'Asegurando claves...';

  @override
  String get syncSetupProgressBootstrapping => 'Subiendo tus datos...';

  @override
  String get syncSetupProgressSyncing => 'Sincronizando...';

  @override
  String get syncSecretKeyTitle => 'Clave secreta';

  @override
  String get syncVerifyPasswordTitle => 'Verificar contraseña';

  @override
  String get syncVerifyPasswordPrompt =>
      'Ingresa tu contraseña de sincronización para revelar tu frase de recuperación de 12 palabras.';

  @override
  String get syncPasswordHint => 'Contraseña de sincronización';

  @override
  String get syncShowPassword => 'Mostrar contraseña';

  @override
  String get syncHidePassword => 'Ocultar contraseña';

  @override
  String get syncRevealSecretKey => 'Revelar clave secreta';

  @override
  String get syncSecretKeyNotFound =>
      'Clave secreta no encontrada en el llavero.';

  @override
  String get syncEngineNotAvailable => 'Motor de sincronización no disponible.';

  @override
  String get syncIncorrectPassword =>
      'Contraseña incorrecta. Inténtalo de nuevo.';

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
  String get resetDataConfirmAll =>
      'Esto eliminará permanentemente todos tus datos, incluidos integrantes, sesiones de frente, mensajes, encuestas, hábitos, datos de sueño y configuración. Esta acción no se puede deshacer.';

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
  String get statisticsTotalMembers => 'Total de integrantes';

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
    return '$count sesiones';
  }

  @override
  String statisticsActiveMembersBreakdown(int active, int inactive) {
    return '$active activos, $inactive inactivos';
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
  String get debugTimelineSanitization => 'Saneamiento de cronología';

  @override
  String get debugTimelineSanitizationSubtitle =>
      'Buscar y corregir problemas de cronología';

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
  String get debugResetDatabaseConfirm2Message =>
      'Esto borrará permanentemente todos los integrantes, sesiones, conversaciones, mensajes y encuestas. No hay forma de deshacer.';

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
  String get systemInfoRemoveAvatar => 'Eliminar avatar';

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
  String get devicesThisDevicePill => 'Este dispositivo';

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
      'Resolución de Problemas de Sincronización';

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
  String get syncTroubleshootingOpenEventLog => 'Abrir Registro de Eventos';

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
  String get featureChatDescription =>
      'Mensajería interna entre los miembros del sistema.';

  @override
  String get featureChatGeneral => 'General';

  @override
  String get featureChatEnable => 'Activar Chat';

  @override
  String get featureChatEnableSubtitle => 'Mensajería interna entre miembros';

  @override
  String get featureChatOptions => 'Opciones';

  @override
  String get featureChatLogFront => 'Registrar Frente al Cambiar';

  @override
  String get featureChatLogFrontSubtitle =>
      'Cambiar quién habla en el chat también registra un frente';

  @override
  String get featureChatGifSearch => 'Búsqueda de GIF';

  @override
  String get featureChatGifSearchSubtitle => 'Buscar y enviar GIFs en el chat';

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
  String get featureHabitsDescription =>
      'Realiza un seguimiento de tareas recurrentes y construye rachas con los miembros del sistema.';

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
  String get featureNotesDescription =>
      'Un diario personal para los miembros del sistema. Desactivar oculta las notas de la navegación pero conserva las entradas existentes.';

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
  String get frontingTimelineIssuesFound =>
      'Problemas de cronología encontrados';

  @override
  String frontingTimelineIssuesBannerMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count problemas de cronología encontrados. Toca para revisar.',
      one: '1 problema de cronología encontrado. Toca para revisar.',
    );
    return '$_temp0';
  }

  @override
  String get frontingTimelineIssuesReview => 'Revisar';

  @override
  String get frontingMenuWakeUpAs => 'Despertar como...';

  @override
  String get frontingMenuLogFront => 'Registrar frente';

  @override
  String get frontingMenuNewPoll => 'Nueva encuesta';

  @override
  String get frontingMenuStartSleep => 'Empezar a dormir';

  @override
  String get frontingWakeUpAsTitle => 'Despertar como...';

  @override
  String frontingErrorWakingUp(Object error) {
    return 'Error al despertar: $error';
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
      '¿Estás seguro/a de que quieres eliminar esta sesión de sueño?';

  @override
  String get frontingSleeping => 'Sueño';

  @override
  String frontingSleepSessionSemantics(String duration, String timeRange) {
    return 'Sesión de sueño, $duration, $timeRange';
  }

  @override
  String get frontingWelcomeTitle => 'Bienvenido/a a Prism';

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
  String get frontingAddCoFronterTitle => 'Agregar co-frontador';

  @override
  String get frontingSelectFronter => 'Seleccionar quien está al frente';

  @override
  String get frontingSelectMember => 'Seleccionar miembro';

  @override
  String get frontingCoFrontToggle => 'Co-frente';

  @override
  String get frontingCoFronters => 'Co-frontadores';

  @override
  String get frontingNoOtherMembers => 'No hay otros miembros disponibles';

  @override
  String get frontingCoFrontHint =>
      'Toca un miembro para agregarlo como co-frontador a la sesión actual.';

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
  String get frontingSearchMembersHint => 'Buscar miembros...';

  @override
  String frontingNoMembersMatching(String query) {
    return 'Sin miembros que coincidan con \"$query\"';
  }

  @override
  String get frontingFronting => 'Al frente';

  @override
  String frontingErrorAddingCoFronter(Object error) {
    return 'Error al agregar co-frontador: $error';
  }

  @override
  String frontingErrorCreatingSession(Object error) {
    return 'Error al crear la sesión: $error';
  }

  @override
  String get frontingAddCoFrontersTitle => 'Agregar co-frontadores';

  @override
  String frontingErrorAddingCoFronters(Object error) {
    return 'Error al agregar co-frontadores: $error';
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
  String get frontingCoFrontersSection => 'Co-frontadores';

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
  String get frontingSanitizationTitle => 'Saneamiento de cronología';

  @override
  String get frontingSanitizationScanning => 'Escaneando cronología…';

  @override
  String get frontingSanitizationIntroTitle => 'Saneamiento de cronología';

  @override
  String get frontingSanitizationIntroBody =>
      'Escanea tu historial de frente en busca de sesiones superpuestas, duplicadas o inválidas, y aplica correcciones automáticas.';

  @override
  String get frontingSanitizationScanButton => 'Escanear cronología';

  @override
  String get frontingSanitizationCleanTitle => '¡La cronología está limpia!';

  @override
  String get frontingSanitizationCleanSubtitle =>
      'No se encontraron superposiciones, duplicados ni sesiones inválidas.';

  @override
  String get frontingSanitizationScanAgain => 'Escanear de nuevo';

  @override
  String frontingSanitizationIssuesFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Se encontraron $count problemas en tu cronología.',
      one: 'Se encontró 1 problema en tu cronología.',
    );
    return '$_temp0';
  }

  @override
  String frontingSanitizationFixesApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count correcciones aplicadas correctamente.',
      one: '1 corrección aplicada correctamente.',
    );
    return '$_temp0';
  }

  @override
  String frontingSanitizationScanFailed(Object error) {
    return 'Error al escanear: $error';
  }

  @override
  String frontingSanitizationFixFailed(Object error) {
    return 'Error al aplicar la corrección: $error';
  }

  @override
  String frontingSanitizationLoadFixFailed(Object error) {
    return 'No se pudieron cargar las opciones de corrección: $error';
  }

  @override
  String get frontingSanitizationFixOptionsTitle => 'Opciones de corrección';

  @override
  String get frontingSanitizationNoAutoFix =>
      'No hay correcciones automáticas disponibles para este problema.\nRevisa y resuélvelo manualmente.';

  @override
  String get frontingSanitizationPreview => 'Vista previa';

  @override
  String get frontingSanitizationHidePreview => 'Ocultar vista previa';

  @override
  String get frontingSanitizationApply => 'Aplicar';

  @override
  String get frontingIssueTypeOverlap => 'Superposición';

  @override
  String get frontingIssueTypeGap => 'Brecha';

  @override
  String get frontingIssueTypeDuplicate => 'Duplicado';

  @override
  String get frontingIssueTypeMergeable => 'Fusionable';

  @override
  String get frontingIssueTypeInvalidRange => 'Rango inválido';

  @override
  String get frontingIssueTypeFutureSession => 'Sesión futura';

  @override
  String get frontingIssueSectionOverlap => 'Sesiones superpuestas';

  @override
  String get frontingIssueSectionGap => 'Brechas';

  @override
  String get frontingIssueSectionDuplicate => 'Duplicados';

  @override
  String get frontingIssueSectionMergeable => 'Adyacentes fusionables';

  @override
  String get frontingIssueSectionInvalidRange => 'Rangos inválidos';

  @override
  String get frontingIssueSectionFutureSession => 'Sesiones futuras';

  @override
  String frontingIssueSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesiones',
      one: '1 sesión',
    );
    return '$_temp0';
  }

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
  String get frontingGapFillWithUnknown => 'Rellenar con fronter desconocido';

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
  String get memberSectionBio => 'Notas';

  @override
  String get memberEditTooltip => 'Editar integrante';

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
  String get memberAdded => 'Integrante agregado';

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
    return '$name activado/a';
  }

  @override
  String memberDeactivated(String name) {
    return '$name archivado/a';
  }

  @override
  String memberRemoved(String name) {
    return '$name eliminado/a';
  }

  @override
  String get memberRemoveFromGroupTitle => 'Eliminar integrante';

  @override
  String memberRemoveFromGroupMessage(String name) {
    return '¿Eliminar a $name de este grupo? El integrante no será eliminado.';
  }

  @override
  String get memberEmptyList => 'Aún no hay integrantes';

  @override
  String get memberGroupEmptyList => 'Aún no hay grupos';

  @override
  String get memberGroupEmptySubtitle =>
      'Crea grupos para organizar a los integrantes del sistema';

  @override
  String get memberGroupNoMembers => 'Sin integrantes';

  @override
  String get memberGroupNoMembersSubtitle => 'Agrega integrantes a este grupo';

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
    return 'Hace $count días';
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
  String get memberSetAsFronter => 'Establecer como fronter';

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
  String get memberNoteAddHeadmate => 'Agregar headmate';

  @override
  String get memberNoteDiscardTitle => '¿Descartar cambios?';

  @override
  String get memberNoteDiscardMessage =>
      'Tienes cambios sin guardar. ¿Seguro que quieres descartarlos?';

  @override
  String get memberNoteDiscardConfirm => 'Descartar';

  @override
  String get memberNoteChooseHeadmate => 'Elegir Headmate';

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
  String get memberGroupSectionMembers => 'Integrantes';

  @override
  String get memberGroupAddMember => 'Agregar integrante';

  @override
  String get memberGroupDeleteTitle => 'Eliminar grupo';

  @override
  String memberGroupDeleteMessage(String name) {
    return '¿Seguro que quieres eliminar \"$name\"? Los integrantes no serán eliminados.';
  }

  @override
  String get memberGroupDeleteConfirm => 'Eliminar';

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
  String get memberGroupColorLabel => 'Color (hex)';

  @override
  String memberGroupErrorSaving(Object error) {
    return 'Error al guardar el grupo: $error';
  }

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
  String get memberMarkdownTitle => 'Formatear bio en markdown';

  @override
  String get memberMarkdownSubtitle => 'Mostrar el texto con formato markdown';

  @override
  String get memberAdminTitle => 'Admin';

  @override
  String get memberAdminSubtitle =>
      'Los admins pueden gestionar la configuración del sistema';

  @override
  String get memberCustomColorTitle => 'Color personalizado';

  @override
  String get memberCustomColorSubtitle =>
      'Usar un color personal para este integrante';

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
    return '$count seleccionado(s)';
  }

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
  String get chatConversationFallback => 'Conversación';

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
  String get chatChooseSpeakingMember => 'Elegir integrante';

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
  String get chatInfoAddMembers => 'Agregar integrantes';

  @override
  String get chatInfoOwner => 'Propietario';

  @override
  String get chatInfoAdmin => 'Admin';

  @override
  String get chatInfoUnknownMember => 'Integrante desconocido';

  @override
  String get chatInfoErrorLoadingMember => 'Error al cargar integrante';

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
  String get chatInfoLeaveConversation => 'Salir de la conversación';

  @override
  String get chatInfoDeleteConversation => 'Eliminar conversación';

  @override
  String get chatInfoConversationArchived => 'Conversación archivada';

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
  String get chatAddMembersTitle => 'Agregar integrantes';

  @override
  String get chatAddMembersAllAdded =>
      'Todos los integrantes activos ya están en esta conversación.';

  @override
  String chatAddMembersFailed(Object error) {
    return 'Error al agregar integrantes: $error';
  }

  @override
  String get chatCreateTitle => 'Nueva conversación';

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
  String get chatCreateNoMembers =>
      'No hay integrantes disponibles. Crea integrantes primero.';

  @override
  String get chatCreateFronting => 'Fronting';

  @override
  String chatCreateFronterDeselectedWarning(String name) {
    return '$name está en frente actualmente pero no está en este chat. No podrás ver ni enviar mensajes.';
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
  String get chatNoMembersAvailable => 'No hay integrantes disponibles';

  @override
  String get chatErrorLoadingMembersShort => 'Error al cargar integrantes';

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
  String chatGifsFound(int count) {
    return '$count GIFs encontrados';
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
  String get onboardingAddMembersSkylarsDefaults => 'Defaults de Skylar';

  @override
  String get onboardingAddMembersNoMembers =>
      'Aún no hay integrantes.\nToca «Agregar integrante» o usa los predeterminados.';

  @override
  String get onboardingAddMembersRemoveMember => 'Eliminar integrante';

  @override
  String get onboardingAddMembersAddMember => 'Agregar integrante';

  @override
  String get onboardingAddMemberSheetTitle => 'Agregar integrante';

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
  String get onboardingFeaturesChatDescription =>
      'Mensajería interna entre integrantes del sistema';

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
  String get onboardingPluralKitImportButton => 'Importar integrantes';

  @override
  String onboardingPluralKitImportSuccess(int count) {
    return '¡Se importaron $count integrantes desde PluralKit!';
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
  String get onboardingWhosFrontingSelectHint =>
      'Toca para seleccionar quién está al frente ahora';

  @override
  String get onboardingWhosFrontingNoMembers =>
      'Aún no hay integrantes.\nVuelve atrás para agregar integrantes primero.';

  @override
  String get onboardingChatSuggestedChannels => 'Canales sugeridos';

  @override
  String get onboardingChatCustomChannel => 'Canal personalizado';

  @override
  String get onboardingChatChannelNameHint => 'Nombre del canal';

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
  String get onboardingPreferencesPerMemberColors => 'Colores por integrante';

  @override
  String get onboardingPreferencesPerMemberColorsSubtitle =>
      'Permite que cada integrante tenga su propio color de acento';

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
  String get onboardingSyncEnterPassword => 'Ingresa tu contraseña';

  @override
  String get onboardingSyncEnterPasswordDescription =>
      'Ingresa tu contraseña de sincronización para terminar de registrar este dispositivo.';

  @override
  String get onboardingSyncPasswordHint => 'Contraseña';

  @override
  String get onboardingSyncFinishPairing => 'Finalizar emparejamiento';

  @override
  String get onboardingSyncEnterPasswordPrompt =>
      'Por favor ingresa tu contraseña.';

  @override
  String get onboardingSyncConnecting => 'Emparejando y sincronizando...';

  @override
  String get onboardingSyncConnectingSubtitle =>
      'Esto puede tardar un momento mientras se registra el dispositivo.';

  @override
  String get onboardingSyncDataStillSyncing =>
      'Algunos datos aún se están sincronizando y aparecerán en breve.';

  @override
  String get onboardingSyncWelcomeBackTitle => '¡Bienvenido de vuelta!';

  @override
  String get onboardingSyncWelcomeBackDescription =>
      'Tu dispositivo ha sido emparejado y tus datos están listos.';

  @override
  String get onboardingSyncPairingFailed => 'Error de emparejamiento';

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
  String get habitsCustomMessageField => 'Mensaje personalizado (opcional)';

  @override
  String get habitsSectionAssignment => 'ASIGNACIÓN';

  @override
  String get habitsAssignedMember => 'Integrante asignado';

  @override
  String get habitsAssignedMemberAnyone => 'Cualquiera';

  @override
  String get habitsOnlyNotifyWhenFronting =>
      'Notificar solo cuando esté al frente';

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
    return '$count opciones';
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
  String get pollsDetailSelectToVoteAs => 'para votar como';

  @override
  String get pollsDetailNoMembers => 'No hay integrantes disponibles';

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
}
