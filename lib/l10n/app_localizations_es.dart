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
}
