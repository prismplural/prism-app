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
      'Compartir brillo, estilo y color de acento via sincronización';

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
      'Controla qué configuraciones se comparten entre tus dispositivos via sincronización.';

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
  String get devicesRevokeDevice => 'Revocar dispositivo';

  @override
  String get devicesDeviceCopied => 'ID de dispositivo copiado';

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
  String get voiceMicPermissionDenied =>
      'Se necesita permiso de micrófono para grabar notas de voz.';

  @override
  String get voiceMicPermissionBlocked =>
      'El acceso al micrófono está bloqueado. Actívalo en Configuración.';

  @override
  String get voiceRecordingFailed => 'No se pudo iniciar la grabación.';
}
