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
  String get notesTitle => 'Notas';

  @override
  String get notesNewNoteTooltip => 'Nueva nota';

  @override
  String get notesEmptyTitle => 'Aún no hay notas';

  @override
  String get notesEmptySubtitle =>
      'Crea notas para llevar un registro de pensamientos y observaciones';

  @override
  String get notesNewNoteAction => 'Nueva nota';

  @override
  String get notesUntitled => 'Sin título';

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
      'Trae tus datos existentes a Prism. Elige cómo te gustaría importar tus datos de Simply Plural.';

  @override
  String get migrationConnectWithApi => 'Conectar con API';

  @override
  String get migrationConnectWithApiSubtitle =>
      'Sin necesidad de exportar archivos — importa directamente desde tu cuenta';

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
  String get migrationSupportedMembers => 'Integrantes';

  @override
  String get migrationSupportedCustomFronts => 'Frentes personalizados';

  @override
  String get migrationSupportedFrontingHistory => 'Historial al frente';

  @override
  String get migrationSupportedChatChannels => 'Canales y mensajes de chat';

  @override
  String get migrationSupportedPolls => 'Encuestas';

  @override
  String get migrationSupportedMemberColors => 'Colores de integrantes';

  @override
  String get migrationSupportedMemberDescriptions =>
      'Descripciones de integrantes';

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
  String get migrationConnectToSimplyPlural => 'Conectar a Simply Plural';

  @override
  String get migrationEnterTokenDescription =>
      'Ingresa tu token de API para importar datos directamente.';

  @override
  String get migrationApiTokenLabel => 'Token de API';

  @override
  String get migrationPasteTokenHint => 'Pega tu token aquí';

  @override
  String get migrationShowToken => 'Mostrar token';

  @override
  String get migrationHideToken => 'Ocultar token';

  @override
  String get migrationPasteFromClipboard => 'Pegar del portapapeles';

  @override
  String get migrationWhereDoIFindThis => '¿Dónde lo encuentro?';

  @override
  String get migrationTokenHelpText =>
      'En Simply Plural, ve a Configuración → Cuenta → Tokens. Crea un nuevo token con permiso de lectura y cópialo.';

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
      'Los datos importados se agregarán junto con los datos existentes. Nada se sobreescribirá.';

  @override
  String get migrationRemindersApiNote =>
      'Los recordatorios no están disponibles a través de la API. Para importar recordatorios, usa un archivo de exportación.';

  @override
  String get migrationImportAllAddToExisting =>
      'Importar todo (agregar a los existentes)';

  @override
  String get migrationStartFresh =>
      'Empezar de nuevo (reemplazar todos los datos)';

  @override
  String get migrationImportAll => 'Importar todo';

  @override
  String get migrationReplaceAllTitle => '¿Reemplazar todos los datos?';

  @override
  String get migrationReplaceAllMessage =>
      'Esto eliminará todos los integrantes, el historial al frente, las conversaciones y otros datos antes de importar. Esta acción no se puede deshacer.\n\nSi tienes sincronización configurada, los demás dispositivos emparejados también deben restablecerse para evitar conflictos.';

  @override
  String get migrationReplaceAll => 'Reemplazar todo';

  @override
  String get migrationImporting => 'Importando…';

  @override
  String get migrationImportComplete => 'Importación completa';

  @override
  String migrationImportSuccess(int total, int seconds) {
    return 'Se importaron $total elementos correctamente en ${seconds}s.';
  }

  @override
  String get migrationSummary => 'Resumen';

  @override
  String get migrationResultMembers => 'Integrantes';

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
  String get migrationImportFailed => 'Error en la importación';

  @override
  String get migrationTryFileImport => 'Intentar importación de archivo';

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
      'Esto eliminará tu token y desconectará de PluralKit. Tus datos importados permanecerán en la app.';

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
      'Para obtener tu token, envía un mensaje al bot de PluralKit en Discord con \"pk;token\" y pega el resultado aquí.';

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
  String get pluralkitPull => 'Recibir';

  @override
  String get pluralkitBoth => 'Ambos';

  @override
  String get pluralkitPush => 'Enviar';

  @override
  String get pluralkitLastSyncSummary => 'Resumen de la última sincronización';

  @override
  String get pluralkitUpToDate => 'Todo está actualizado.';

  @override
  String pluralkitMembersPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count integrantes recibidos',
      one: '1 integrante recibido',
    );
    return '$_temp0';
  }

  @override
  String pluralkitMembersPushed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count integrantes enviados',
      one: '1 integrante enviado',
    );
    return '$_temp0';
  }

  @override
  String pluralkitSwitchesPulled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios al frente recibidos',
      one: '1 cambio al frente recibido',
    );
    return '$_temp0';
  }

  @override
  String pluralkitSwitchesPushed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cambios al frente enviados',
      one: '1 cambio al frente enviado',
    );
    return '$_temp0';
  }

  @override
  String pluralkitMembersUnchanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count integrantes sin cambios',
      one: '1 integrante sin cambios',
    );
    return '$_temp0';
  }

  @override
  String get pluralkitInfoSync =>
      'Compatible con sincronización de recepción, envío o bidireccional. Elige tu dirección preferida arriba.';

  @override
  String get pluralkitInfoToken =>
      'Tu token se almacena de forma segura en el llavero del dispositivo y nunca sale de tu dispositivo.';

  @override
  String get pluralkitInfoMembers =>
      'Los integrantes se asocian por UUID de PluralKit. Los existentes se actualizan y los nuevos se crean.';

  @override
  String get pluralkitInfoSwitches =>
      'Los cambios al frente se importan como sesiones al frente. Los duplicados se omiten automáticamente.';

  @override
  String get pluralkitJustNow => 'Justo ahora';

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
  String get dataManagementImportFromOtherApps => 'Importar desde otras apps';

  @override
  String get dataManagementExportRowTitle => 'Exportar datos';

  @override
  String get dataManagementExportRowSubtitle =>
      'Crear una copia de seguridad protegida con contraseña';

  @override
  String get dataManagementImportRowTitle => 'Importar datos';

  @override
  String get dataManagementImportRowSubtitle =>
      'Restaurar datos desde un archivo de exportación de Prism (.json o .prism)';

  @override
  String get dataManagementPluralKitRowSubtitle =>
      'Importar integrantes y sesiones al frente con token de API';

  @override
  String get dataManagementSimplyPluralRowTitle => 'Simply Plural';

  @override
  String get dataManagementSimplyPluralRowSubtitle =>
      'Importar desde un archivo de exportación de Simply Plural';

  @override
  String get dataManagementExportYourData => 'Exportar tus datos';

  @override
  String get dataManagementExportDescription =>
      'Crea una copia de seguridad protegida con contraseña de todos tus datos, incluidos integrantes, sesiones al frente, mensajes, encuestas y configuración.';

  @override
  String get dataManagementExportButton => 'Exportar datos';

  @override
  String get dataManagementEncryptExport => 'Cifrar exportación';

  @override
  String get dataManagementEncryptDescription =>
      'Establece una contraseña para cifrar tu archivo de exportación. Necesitarás esta contraseña para importar los datos más adelante.';

  @override
  String get dataManagementUnencryptedWarning =>
      'Las exportaciones sin cifrar son JSON simple. Cualquier persona que abra el archivo puede leer su contenido.';

  @override
  String get dataManagementPasswordLabel => 'Contraseña';

  @override
  String get dataManagementPasswordHint =>
      'Usa una frase de contraseña de 15+ palabras para mayor seguridad';

  @override
  String get dataManagementShowPassword => 'Mostrar contraseña';

  @override
  String get dataManagementHidePassword => 'Ocultar contraseña';

  @override
  String get dataManagementConfirmPasswordLabel => 'Confirmar contraseña';

  @override
  String get dataManagementExportUnencrypted => 'Exportar sin cifrado';

  @override
  String get dataManagementEncrypt => 'Cifrar';

  @override
  String get dataManagementExporting => 'Exportando tus datos…';

  @override
  String get dataManagementMayTakeMoment => 'Esto puede tardar un momento.';

  @override
  String get dataManagementExportFailed => 'Error al exportar';

  @override
  String get dataManagementRetry => 'Reintentar';

  @override
  String get dataManagementExportComplete => 'Exportación completa';

  @override
  String get dataManagementExportWithoutEncryptionTitle =>
      '¿Exportar sin cifrado?';

  @override
  String get dataManagementExportWithoutEncryptionMessage =>
      'Esto creará un archivo JSON simple que cualquier persona que lo abra puede leer. Usa la exportación cifrada a menos que necesites específicamente una copia de seguridad insegura.';

  @override
  String get dataManagementExportUnencryptedConfirm => 'Exportar sin cifrado';

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
      'Selecciona un archivo de exportación de Prism (.json o .prism) para restaurar tus datos. Los datos existentes no se sobreescribirán.';

  @override
  String get dataManagementEncryptedFile => 'Archivo cifrado';

  @override
  String get dataManagementEncryptedFileDescription =>
      'Este archivo de exportación está cifrado. Ingresa la contraseña que se usó al crear la exportación.';

  @override
  String get dataManagementDecrypt => 'Descifrar';

  @override
  String get dataManagementImportPreview => 'Vista previa de importación';

  @override
  String dataManagementExportedDate(String date) {
    return 'Exportado: $date';
  }

  @override
  String get dataManagementPreviewMembers => 'Integrantes';

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
  String get dataManagementPreviewSettings => 'Configuración';

  @override
  String get dataManagementPreviewHabits => 'Hábitos';

  @override
  String get dataManagementPreviewHabitCompletions => 'Completados de hábitos';

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
      'Esto puede tardar un momento. No cierres la app.';

  @override
  String get dataManagementImportComplete => 'Importación completa';

  @override
  String get dataManagementImportFailed => 'Error al importar';

  @override
  String get dataManagementImportFailedNote =>
      'No se importaron datos. La base de datos no fue modificada.';

  @override
  String get dataManagementIncorrectPassword => 'Contraseña incorrecta';

  @override
  String dataManagementDecryptionFailed(String error) {
    return 'Error de descifrado: $error';
  }

  @override
  String get dataManagementPasswordEmptyImport =>
      'La contraseña no puede estar vacía';

  @override
  String get sharingTitle => 'Compartir';

  @override
  String get sharingRefreshInbox => 'Actualizar bandeja';

  @override
  String get sharingUseSharingCodeTooltip => 'Usar código de compartición';

  @override
  String get sharingShareYourCodeTooltip => 'Compartir tu código';

  @override
  String get sharingPendingRequests => 'Solicitudes pendientes';

  @override
  String get sharingTrustedPeople => 'Personas de confianza';

  @override
  String get sharingEmptyTitle => 'Aún no hay relaciones de compartición';

  @override
  String get sharingEmptySubtitle =>
      'Comparte tu código para que alguien pueda enviarte una solicitud, o usa el código de otra persona para conectarte.';

  @override
  String get sharingShareMyCode => 'Compartir mi código';

  @override
  String get sharingUseACode => 'Usar un código';

  @override
  String get sharingRequestSent =>
      'Solicitud de compartición enviada. La verán la próxima vez que revisen compartir.';

  @override
  String get sharingNoNewRequests =>
      'No hay nuevas solicitudes de compartición';

  @override
  String get sharingUnableToRefresh =>
      'No se pudo actualizar la bandeja de compartición';

  @override
  String get sharingSyncNotConfigured =>
      'La sincronización no está configurada';

  @override
  String get sharingRequestAccepted => 'Solicitud de compartición aceptada';

  @override
  String get sharingUnableToAccept => 'No se pudo aceptar la solicitud';

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
  String get sharingNoScopesGranted => 'Sin permisos otorgados';

  @override
  String get sharingJustNow => 'Justo ahora';

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
  String get sharingYourDisplayName => 'Tu nombre visible';

  @override
  String get sharingDisplayNameHint => 'Cómo te verán';

  @override
  String get sharingWhatToShare => 'Qué compartir';

  @override
  String get sharingSending => 'Enviando…';

  @override
  String get sharingSendRequest => 'Enviar solicitud';

  @override
  String get sharingInvalidCode => 'Código de compartición no válido';

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
      'La compartición usa un código estable en lugar de un intercambio de claves. Cualquier persona con este código puede enviarte una solicitud de compartición.';

  @override
  String get sharingDisplayNameOptionalLabel => 'Nombre visible (opcional)';

  @override
  String get sharingDisplayNameOptionalHint =>
      'Se muestra a la persona que abre tu código';

  @override
  String get sharingSharingCodeTitle => 'Código de compartición';

  @override
  String get sharingCodeValidNote =>
      'Este código sigue siendo válido hasta que desactives la compartición.';

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
  String get sharingFriend => 'Amigo';

  @override
  String get sharingFriendNotFound => 'Amigo no encontrado';

  @override
  String get sharingGrantedScopes => 'Permisos otorgados';

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
    return 'Agregado $date';
  }

  @override
  String get sharingVerificationRecommended => 'Verificación recomendada';

  @override
  String sharingVerificationDescription(String name) {
    return 'Compara las huellas digitales con $name fuera del sistema antes de marcar esta relación como verificada.';
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
    return '¿Revocar todo el acceso de $name? Las claves de recursos se rotarán.';
  }

  @override
  String get sharingRevoke => 'Revocar';

  @override
  String get sharingUnableToComputeFingerprint =>
      'No se pudo calcular la huella digital';

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
}
