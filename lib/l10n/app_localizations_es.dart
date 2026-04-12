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
